// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

import Darwin

/// A disk-backed raster keeps 48MP output off the Swift heap while the f64
/// engine processes bounded overlapping regions at the original pixel pitch.
final class MappedRaster {
    let pointer: UnsafeMutableRawPointer
    let count: Int
    let url: URL
    init(count:Int) throws {
        self.count=count
        url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".raster")
        let fd=open(url.path,O_RDWR|O_CREAT|O_EXCL,S_IRUSR|S_IWUSR)
        guard fd>=0 else {throw AppError.rendering};defer{close(fd)}
        guard ftruncate(fd,off_t(count))==0 else {try? FileManager.default.removeItem(at:url);throw AppError.rendering}
        let mapped=mmap(nil,count,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0)
        guard mapped != MAP_FAILED,let mapped else {try? FileManager.default.removeItem(at:url);throw AppError.rendering}
        pointer=mapped
    }
    deinit {munmap(pointer,count);try? FileManager.default.removeItem(at:url)}
    func image(width:Int,height:Int,sixteenBit:Bool)->CGImage? {
        let owner=Unmanaged.passRetained(self).toOpaque()
        guard let provider=CGDataProvider(dataInfo:owner,data:pointer,size:count,releaseData:{info,_,_ in
            if let info {Unmanaged<MappedRaster>.fromOpaque(info).release()}
        }) else {Unmanaged<MappedRaster>.fromOpaque(owner).release();return nil}
        let bits=sixteenBit ? 16:8
        let alpha=CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue)
        let bitmap=sixteenBit ? alpha.union(.byteOrder16Little):alpha
        return CGImage(width:width,height:height,bitsPerComponent:bits,bitsPerPixel:bits*4,bytesPerRow:width*bits/8*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:bitmap,provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
}

actor FullResolutionExporter {
    private let context=CIContext(options:[.cacheIntermediates:false])
    func export(sourceURL:URL,recipe:FilmRecipe,cube:CubeLUT?,format:ExportFormat,
                progress:@escaping @Sendable(Double)->Void) throws -> URL {
        try Task.checkCancellation()
        guard format != .original else {throw AppError.rendering}
        let source=try Self.source(sourceURL)
        let cropped=PrintComposer.crop(source,style:recipe.printStyle)
        let width=Int(cropped.extent.width),height=Int(cropped.extent.height)
        guard width>0,height>0,width*height<=110_000_000 else {throw AppError.spectral("图片尺寸超出本版 1.1 亿像素的处理范围")}
        var localRecipe=recipe
        // Meter the complete frame once. Each tile must share the same exposure.
        if localRecipe.autoExposure {
            let scale=min(1,256/max(cropped.extent.width,cropped.extent.height))
            let sw=max(1,Int((cropped.extent.width*scale).rounded())),sh=max(1,Int((cropped.extent.height*scale).rounded()))
            let small=cropped.transformed(by:CGAffineTransform(scaleX:CGFloat(sw)/cropped.extent.width,y:CGFloat(sh)/cropped.extent.height))
            var pixels=[Float](repeating:0,count:sw*sh*4)
            pixels.withUnsafeMutableBytes{bytes in context.render(small,toBitmap:bytes.baseAddress!,rowBytes:sw*16,bounds:CGRect(x:0,y:0,width:sw,height:sh),format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB))}
            var sum=0.0,total=0.0
            let longest=Double(max(sw,sh))
            for y in 0..<sh{for x in 0..<sw{
                let nx=(Double(x)/Double(sw)-0.5)*Double(sw)/longest
                let ny=(Double(y)/Double(sh)-0.5)*Double(sh)/longest
                let weight=exp(-(nx*nx+ny*ny)/0.08)
                let i=(y*sw+x)*4
                let luma=Double(pixels[i])*0.2126+Double(pixels[i+1])*0.7152+Double(pixels[i+2])*0.0722
                sum+=luma*weight;total+=weight
            }}
            localRecipe.exposure += log2(0.184/max(1e-10,sum/total));localRecipe.autoExposure=false
        }
        let session=cube == nil && recipe.intensity>0 ? try SpectralSession(film:localRecipe.stock.id,paper:localRecipe.paper.id,params:localRecipe.spectralJSON()):nil
        let bpp=format.sixteenBit ? 8:4
        let required=Int64(width*height*bpp)*2+64_000_000
        let capacity=try? FileManager.default.temporaryDirectory.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
        if let free=capacity?.volumeAvailableCapacityForImportantUsage,free<required {
            throw AppError.spectral("存储空间不足，无法完成全尺寸显影；请至少留出约 \(required/1_000_000) MB 空间")
        }
        let mapped=try MappedRaster(count:width*height*bpp)
        let sRGB=CGColorSpace(name:CGColorSpace.sRGB)!
        let linear=CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!
        let core=512
        // DIR's largest diffusion tail and the repeated halation kernel need
        // overlap. Finite overlap approximates infinite IIR tails at boundaries.
        let pixelUM=localRecipe.filmFormat*1000/Double(max(width,height))
        let tail=max(localRecipe.dirCouplers>0 ? 1700.0:0,localRecipe.halation>0 ? 500.0:0)
        let halo=session == nil ? 0:Int(min(700,max(16,ceil(tail/pixelUM))))
        let total=Int(ceil(Double(width)/Double(core)))*Int(ceil(Double(height)/Double(core)))
        var completed=0
        for y in stride(from:0,to:height,by:core) {
            for x in stride(from:0,to:width,by:core) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let rect=CGRect(x:x,y:y,width:min(core,width-x),height:min(core,height-y))
                    let region=rect.insetBy(dx:-CGFloat(halo),dy:-CGFloat(halo)).intersection(cropped.extent).integral
                    let tw=Int(region.width),th=Int(region.height)
                    let tile=cropped.cropped(to:region).transformed(by:CGAffineTransform(translationX:-region.minX,y:-region.minY))
                    var processed=tile
                    if let session {
                        var input=[Float](repeating:0,count:tw*th*4)
                        input.withUnsafeMutableBytes {bytes in
                            context.render(tile.composited(over:CIImage(color:.black).cropped(to:tile.extent)),toBitmap:bytes.baseAddress!,rowBytes:tw*16,bounds:tile.extent,format:.RGBAf,colorSpace:linear)
                        }
                        let seed=UInt64(x)&*73856093 ^ UInt64(y)&*19349663
                        let output=try session.render(input,width:tw,height:th,fullLongEdge:max(width,height),seed:seed)
                        let data=output.withUnsafeBytes{Data($0)}
                        processed=CIImage(bitmapData:data,bytesPerRow:tw*16,size:CGSize(width:tw,height:th),format:.RGBAf,colorSpace:sRGB)
                    } else if let cube {
                        processed=tile.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:recipe.exposure])
                            .applyingFilter("CIColorCubeWithColorSpace",parameters:["inputCubeDimension":cube.dimension,"inputCubeData":cube.data,"inputColorSpace":sRGB])
                    }
                    if recipe.intensity<1 {processed=processed.applyingFilter("CIDissolveTransition",parameters:["inputTargetImage":tile,kCIInputTimeKey:1-recipe.intensity])}
                    processed=processed.transformed(by:CGAffineTransform(translationX:region.minX,y:region.minY))
                    // Bounds use CI's lower-left coordinates, while render's
                    // bitmap scanlines and CGImage providers are top-down.
                    // Reverse region placement only; never flip scanlines twice.
                    let destY=height-y-Int(rect.height)
                    context.render(processed,toBitmap:mapped.pointer.advanced(by:(destY*width+x)*bpp),rowBytes:width*bpp,bounds:rect,format:format.sixteenBit ? .RGBA16:.RGBA8,colorSpace:sRGB)
                }
                completed+=1;progress(Double(completed)/Double(total)*0.92)
            }
        }
        guard let raster=mapped.image(width:width,height:height,sixteenBit:format.sixteenBit) else {throw AppError.rendering}
        var composed=CIImage(cgImage:raster)
        composed=PrintComposer.compose(composed,style:recipe.printStyle,stock:recipe.customBW?.name ?? recipe.stock.name)
        context.clearCaches()
        guard let cg=context.createCGImage(composed,from:composed.extent,format:format.sixteenBit ? .RGBA16:.RGBA8,colorSpace:sRGB) else {throw AppError.rendering}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("Grainroom-\(UUID()).\(format.fileExtension)")
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,format.type.identifier as CFString,1,nil) else {throw AppError.spectral("此设备不能编码所选格式")}
        CGImageDestinationAddImage(destination,cg,[kCGImageDestinationLossyCompressionQuality:0.97] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {try? FileManager.default.removeItem(at:url);throw AppError.rendering}
        progress(1);return url
    }

    static func source(_ url:URL) throws -> CIImage {
        let options:[CIImageOption:Any]=[.applyOrientationProperty:true]
        if let source=CGImageSourceCreateWithURL(url as CFURL,nil),let id=CGImageSourceGetType(source),
           let type=UTType(id as String),type.conforms(to:.rawImage) {
            guard let filter=CIRAWFilter(imageURL:url),let image=filter.outputImage else {throw AppError.rawUnsupported}
            // RAW decoding stays linear; Core Image manages into the engine's sRGB.
            return image
        }
        guard let image=CIImage(contentsOf:url,options:options) else {throw AppError.unreadableImage}
        return image
    }
}
