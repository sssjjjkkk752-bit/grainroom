// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

import ImageIO
import CoreImage

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var emulsions: [BWEmulsion] = []
    @Published var error: String?
    @Published var importing = false
    let directory: URL
    private let manifest: URL
    private let filmsURL: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("GrainroomLibrary", isDirectory: true)
        manifest = self.directory.appendingPathComponent("library.json")
        filmsURL = self.directory.appendingPathComponent("emulsions.json")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifest.path) { assets = try JSONDecoder().decode([PhotoAsset].self, from: Data(contentsOf: manifest)) }
            if FileManager.default.fileExists(atPath: filmsURL.path) { emulsions = try JSONDecoder().decode([BWEmulsion].self, from: Data(contentsOf: filmsURL)) }
        } catch { self.error = "图库读取失败：\(error.localizedDescription)" }
    }

    func url(for asset: PhotoAsset) -> URL { directory.appendingPathComponent(asset.fileName) }
    func thumbnail(_ asset: PhotoAsset, negative: Bool = false) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(negative ? asset.negativeName : asset.thumbnailName).path)
    }

    @discardableResult
    func add(data: Data, label: String, date: Date = Date(), preferredExtension: String? = nil) async throws -> PhotoAsset {
        let target = directory
        let asset = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let typeID = CGImageSourceGetType(source) else { throw AppError.unreadableImage }
            let type = UTType(typeID as String)
            let raw = type?.conforms(to: .rawImage) == true || preferredExtension?.lowercased() == "dng"
            let ext = preferredExtension ?? type?.preferredFilenameExtension ?? "img"
            let id = UUID()
            let name = id.uuidString + "." + ext
            let thumb = id.uuidString + "-thumb.jpg"
            let neg = id.uuidString + "-negative.jpg"
            let opts: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:700]
            var cg = CGImageSourceCreateThumbnailAtIndex(source,0,opts as CFDictionary)
            if cg == nil, raw, let filter = CIRAWFilter(imageData: data, identifierHint: typeID as String), let output = filter.outputImage {
                let scale = 700 / max(output.extent.width, output.extent.height)
                let small = output.transformed(by: CGAffineTransform(scaleX: min(1,scale), y: min(1,scale)))
                cg = CIContext().createCGImage(small, from: small.extent)
            }
            guard let cg, let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.87) else { throw AppError.unreadableImage }
            let ci = CIImage(cgImage: cg).applyingFilter("CIColorInvert")
                .applyingFilter("CIColorMatrix", parameters:["inputRVector":CIVector(x:0.95,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.70,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:0.42,w:0)])
            guard let inverted = CIContext().createCGImage(ci,from:ci.extent), let negative = UIImage(cgImage:inverted).jpegData(compressionQuality:0.87) else { throw AppError.rendering }
            let files = [target.appendingPathComponent(name),target.appendingPathComponent(thumb),target.appendingPathComponent(neg)]
            do {
                try data.write(to:files[0], options:.atomic)
                try jpeg.write(to:files[1], options:.atomic)
                try negative.write(to:files[2], options:.atomic)
            } catch { for file in files { try? FileManager.default.removeItem(at:file) }; throw error }
            return PhotoAsset(id:id,fileName:name,thumbnailName:thumb,negativeName:neg,createdAt:date,
                width:props[kCGImagePropertyPixelWidth] as? Int ?? cg.width,
                height:props[kCGImagePropertyPixelHeight] as? Int ?? cg.height,label:label,isRAW:raw)
        }.value
        var updated = assets; updated.insert(asset,at:0)
        do { try persist(updated); assets=updated }
        catch { for name in [asset.fileName,asset.thumbnailName,asset.negativeName] { try? FileManager.default.removeItem(at:directory.appendingPathComponent(name)) }; throw error }
        return asset
    }

    func importPhotos(_ items: [PhotosPickerItem]) async {
        importing=true; defer { importing=false }
        for item in items {
            do {
                guard let data=try await item.loadTransferable(type:Data.self) else { throw AppError.unreadableImage }
                try await add(data:data,label:"相册原片")
            } catch { self.error=error.localizedDescription }
        }
    }

    func importFile(_ url: URL) async {
        let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { try await add(data:Data(contentsOf:url, options:.mappedIfSafe),label:"导入原片",preferredExtension:url.pathExtension) }
        catch { self.error=error.localizedDescription }
    }

    func rate(_ asset: PhotoAsset) {
        var list=assets
        guard let i=list.firstIndex(where:{$0.id==asset.id}) else{return}
        list[i].rating=(list[i].rating+1)%4
        do { try persist(list);assets=list } catch { self.error=error.localizedDescription }
    }

    func save(_ emulsion: BWEmulsion) throws {
        var list=emulsions
        if let i=list.firstIndex(where:{$0.id==emulsion.id}) {list[i]=emulsion} else {list.insert(emulsion,at:0)}
        try JSONEncoder().encode(list).write(to:filmsURL,options:.atomic);emulsions=list
    }

    func importEmulsion(_ url:URL) throws {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let e=try JSONDecoder().decode(BWEmulsion.self,from:Data(contentsOf:url))
        guard !e.name.isEmpty, e.name.count<=80, [e.red,e.green,e.blue,e.grain,e.halation].allSatisfy({$0.isFinite && (0...2).contains($0)}), e.contrast.isFinite,(0.4...2).contains(e.contrast) else {throw AppError.spectral("配方参数超出范围")}
        try save(e)
    }

    func emulsionFile(_ e:BWEmulsion) throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("Grainroom-Emulsion-\(e.id).json")
        try JSONEncoder().encode(e).write(to:url,options:.atomic);return url
    }
    private func persist(_ list:[PhotoAsset]) throws {try JSONEncoder().encode(list).write(to:manifest,options:.atomic)}
}
