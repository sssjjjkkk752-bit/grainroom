// SPDX-License-Identifier: GPL-3.0-only
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

actor FilmRenderer {
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private lazy var context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])

    func decode(_ data: Data, maximum: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw AppError.unreadableImage }
        if let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String), type.conforms(to: .rawImage) {
            guard let filter = CIRAWFilter(imageData:data,identifierHint:typeID as String), let output=filter.outputImage else {throw AppError.rawUnsupported}
            let scale=min(1,CGFloat(maximum)/max(output.extent.width,output.extent.height))
            let small=output.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            guard let cg=context.createCGImage(small,from:small.extent,format:.RGBA8,colorSpace:colorSpace) else{throw AppError.rendering}
            return UIImage(cgImage:cg)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AppError.unreadableImage }
        return UIImage(cgImage: cg)
    }

    private var spectralSession: SpectralSession?
    private var spectralKey: String?

    func render(_ image: UIImage, recipe r: FilmRecipe, cube: CubeLUT?) throws -> UIImage {
        try Task.checkCancellation()
        guard let cg = image.cgImage else { throw AppError.rendering }
        let original = PrintComposer.crop(CIImage(cgImage: cg),style:r.printStyle)
        let extent = original.extent
        var result: CIImage
        if r.intensity == 0 { result = original } else if let cube {
            // Explicit alternate mode: a user LUT, never a spectral-engine fallback.
            result = original.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: r.exposure])
                .applyingFilter("CIColorCubeWithColorSpace", parameters: [
                    "inputCubeDimension": cube.dimension, "inputCubeData": cube.data, "inputColorSpace": colorSpace
                ])
        } else {
            let params = try r.spectralJSON()
            let key = r.stock.id + "|" + r.paper.id + "|" + params
            if key != spectralKey {
                spectralSession = nil // free old calibration before allocating a new one
                spectralKey = nil
                spectralSession = try SpectralSession(film: r.stock.id, paper: r.paper.id, params: params)
                spectralKey = key
            }
            guard let spectralSession else { throw AppError.rendering }
            let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            let flattened = original.composited(over: CIImage(color: .black).cropped(to: extent))
            let w=Int(extent.width),h=Int(extent.height)
            let count = w * h * 4
            var input = [Float](repeating: 0, count: count)
            input.withUnsafeMutableBytes { bytes in
                context.render(flattened, toBitmap: bytes.baseAddress!, rowBytes: w * 16,
                               bounds: extent, format: .RGBAf, colorSpace: linearSpace)
            }
            try Task.checkCancellation()
            let output = try spectralSession.render(input, width: w, height: h)
            try Task.checkCancellation()
            let data = output.withUnsafeBytes { Data($0) }
            result = CIImage(bitmapData: data, bytesPerRow: w * 16,
                             size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: colorSpace)
        }
        result = result.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": original, kCIInputTimeKey: 1 - r.intensity])
        result=PrintComposer.compose(result,style:r.printStyle,stock:r.customBW?.name ?? r.stock.name)
        guard let output = context.createCGImage(result, from: result.extent, format: .RGBA8, colorSpace: colorSpace) else { throw AppError.rendering }
        return UIImage(cgImage: output)
    }

    func export(_ image: UIImage) throws -> URL {
        guard let cg = image.cgImage else { throw AppError.rendering }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Grainroom-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw AppError.rendering }
        // No original GPS/EXIF copied. RGB output is explicitly tagged sRGB.
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.96] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppError.rendering }
        return url
    }
}
