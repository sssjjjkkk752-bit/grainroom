// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import PhotosUI
import Photos

@MainActor
final class DarkroomModel: ObservableObject {
    @Published var recipe = FilmRecipe() { didSet { refresh() } }
    @Published private(set) var original: UIImage?
    @Published private(set) var preview: UIImage?
    @Published private(set) var cube: CubeLUT?
    @Published private(set) var loading = false
    @Published private(set) var rendering = false
    @Published private(set) var exporting = false
    @Published var error: String?
    @Published var notice: String?
    @Published var shareURL: URL?
    @Published private(set) var asset: PhotoAsset?
    @Published private(set) var exportProgress = 0.0
    @Published private(set) var bracketImages: [UIImage] = []
    @Published var sidecarURL: URL?
    @Published var preparingBracket = false
    private let fullExporter = FullResolutionExporter()
    private var sourceURL: URL?
    private var exportTask: Task<Void,Never>?
    private let renderer = FilmRenderer()
    private var previewTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var importID = UUID()
    private var revision = UUID()

    func load(_ selected:PhotoAsset,store:LibraryStore) {
        importTask?.cancel();previewTask?.cancel();revision=UUID()
        let id=UUID();importID=id;loading=true;rendering=false
        asset=selected;sourceURL=store.url(for:selected)
        original=nil;preview=nil
        recipe.printStyle.capturedAt=selected.createdAt
        let url=store.url(for:selected)
        importTask=Task {
            do {
                let data=try Data(contentsOf:url,options:.mappedIfSafe)
                let image=try await renderer.decode(data,maximum:768)
                try Task.checkCancellation();guard id==importID else{return}
                original=image;preview=image;loading=false;refresh()
            }catch{guard id==importID else{return};loading=false;if !(error is CancellationError){self.error=error.localizedDescription}}
        }
    }

    func randomize() {
        recipe.customBW=nil;recipe.scanFilm=false
        if let stock=Stock.allCases.filter({!$0.positive && !$0.note.contains("黑白")}).randomElement(){
            recipe.stock=stock
            recipe.paper=Paper.allCases.first(where:{$0.id==stock.targetPrint}) ?? .soft
        }
        recipe.grain=Double.random(in:0.5...1.5)
        recipe.warmth=Double.random(in:-0.3...0.3)
        recipe.halation=Double.random(in:0.2...1.3)
    }
    func apply(_ emulsion:BWEmulsion) {
        recipe.stock=Stock.allCases.first(where:{$0.id=="kodak_doublex"})!
        recipe.paper=Paper.allCases.first(where:{$0.id=="kodak_2302"})!
        recipe.scanFilm=false;recipe.customBW=emulsion
        recipe.grain=emulsion.grain;recipe.halation=emulsion.halation
    }
    func makeBracket() {
        guard let original,!preparingBracket else{return}
        preparingBracket=true;bracketImages=[]
        let snapshot=recipe,cube=cube
        Task {
            defer{preparingBracket=false}
            do{for ev in [-1.0,0,1.0]{var r=snapshot;r.exposure += ev;let image=try await renderer.render(original,recipe:r,cube:cube);bracketImages.append(image)}}
            catch{self.error=error.localizedDescription}
        }
    }

    func refresh() {
        previewTask?.cancel()
        let id = UUID()
        revision = id
        guard let original, !loading else { return }
        let recipe = recipe
        let cube = cube
        rendering = true
        previewTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                try Task.checkCancellation()
                let image = try await renderer.render(original, recipe: recipe, cube: cube)
                try Task.checkCancellation()
                guard revision == id else { return }
                preview = image
                rendering = false
            } catch {
                guard revision == id else { return }
                rendering = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func importCube(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 24_000_000 else { throw AppError.invalidCube }
            cube = try CubeLUT(text: String(contentsOf: url, encoding: .utf8), name: url.deletingPathExtension().lastPathComponent)
            refresh()
        } catch { self.error = error.localizedDescription }
    }

    func removeCube() { cube = nil; refresh() }
    func reset() {cube=nil;var next=FilmRecipe();next.printStyle.capturedAt=asset?.createdAt ?? Date();recipe=next}

    func export(saveToPhotos: Bool,format:ExportFormat = .jpeg,store:LibraryStore? = nil) {
        guard !exporting,!loading,let sourceURL else{return}
        exporting=true;exportProgress=0
        let recipe=recipe,cube=cube
        exportTask=Task {
            var url:URL?
            do{
                let result:URL
                if format == .original {
                    result=FileManager.default.temporaryDirectory.appendingPathComponent("Grainroom-original-\(UUID()).\(sourceURL.pathExtension)")
                    try FileManager.default.copyItem(at:sourceURL,to:result)
                    let sidecar=result.deletingPathExtension().appendingPathExtension("grainroom.json")
                    try JSONEncoder().encode(recipe).write(to:sidecar,options:.atomic)
                    sidecarURL=sidecar
                }else{
                    result=try await fullExporter.export(sourceURL:sourceURL,recipe:recipe,cube:cube,format:format){[weak owner = self] progress in
                        Task{@MainActor in owner?.exportProgress=progress}
                    }
                }
                url=result;try Task.checkCancellation()
                if let store,format != .original {
                    try await store.add(data:Data(contentsOf:result,options:.mappedIfSafe),label:recipe.customBW?.name ?? recipe.stock.name,preferredExtension:format.fileExtension)
                    try? FileManager.default.removeItem(at:result)
                    notice="已将成片放上观片台"
                }else if saveToPhotos {
                    let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
                    guard status == .authorized || status == .limited else{throw AppError.photoPermission}
                    try await PHPhotoLibrary.shared().performChanges {
                        let request=PHAssetCreationRequest.forAsset()
                        request.addResource(with:.photo,fileURL:result,options:nil)
                    }
                    try? FileManager.default.removeItem(at:result)
                    if let sidecarURL{try? FileManager.default.removeItem(at:sidecarURL);self.sidecarURL=nil}
                    notice="已按原始像素尺寸保存到照片图库"
                }else{shareURL=result}
            }catch{
                if let url{try? FileManager.default.removeItem(at:url)}
                if let sidecarURL{try? FileManager.default.removeItem(at:sidecarURL);self.sidecarURL=nil}
                if !(error is CancellationError){self.error=error.localizedDescription}
            }
            exporting=false
        }
    }
    func cancelExport(){exportTask?.cancel()}

    func cleanupShare() {
        if let shareURL { try? FileManager.default.removeItem(at: shareURL) }
        shareURL = nil
        if let sidecarURL {try? FileManager.default.removeItem(at:sidecarURL)}
        sidecarURL=nil
    }
}
