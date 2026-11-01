// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import Grainroom

final class StudioTests:XCTestCase {
    func source(width:Int,height:Int) throws -> URL {
        let size=CGSize(width:width,height:height)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let image=UIGraphicsImageRenderer(size:size,format:format).image{r in
            UIColor.red.setFill();r.fill(CGRect(x:0,y:0,width:width/2,height:height/2))
            UIColor.green.setFill();r.fill(CGRect(x:width/2,y:0,width:width-width/2,height:height/2))
            UIColor.blue.setFill();r.fill(CGRect(x:0,y:height/2,width:width/2,height:height-height/2))
            UIColor.white.setFill();r.fill(CGRect(x:width/2,y:height/2,width:width-width/2,height:height-height/2))
        }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        try XCTUnwrap(image.pngData()).write(to:url);return url
    }
    func properties(_ url:URL) throws -> [CFString:Any] {
        let src=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any])
    }
    func pixels(_ url:URL) throws -> (Int,Int,[UInt8]) {
        let src=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil));let cg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(src,0,nil))
        var pixels=[UInt8](repeating:0,count:cg.width*cg.height*4)
        let context=try XCTUnwrap(CGContext(data:&pixels,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height));return(cg.width,cg.height,pixels)
    }
    func plain()->FilmRecipe{var recipe=FilmRecipe();recipe.intensity=0;recipe.printStyle.border = .none;return recipe}

    func testTileCoordinatesAndFullDimensions() async throws {
        let input=try source(width:1031,height:691);defer{try? FileManager.default.removeItem(at:input)}
        let exporter=FullResolutionExporter()
        let output=try await exporter.export(sourceURL:input,recipe:plain(),cube:nil,format:.png,progress:{_ in})
        defer{try? FileManager.default.removeItem(at:output)}
        let before=try pixels(input),after=try pixels(output)
        XCTAssertEqual(after.0,1031);XCTAssertEqual(after.1,691)
        for y in [15,200,510,520,675]{for x in [15,300,510,520,1015]{
            for c in 0..<3{let p=(y*1031+x)*4+c;XCTAssertLessThanOrEqual(abs(Int(before.2[p])-Int(after.2[p])),1,"Tile orientation or offset at \(x),\(y)")}
        }}
        XCTAssertEqual(try properties(output)[kCGImagePropertyDepth] as? Int,16)
    }

    func test48MPHEIFExportRetainsEveryPixel() async throws {
        let width=8064,height=6048
        let image=CIImage(color:CIColor(red:0.3,green:0.5,blue:0.7)).cropped(to:CGRect(x:0,y:0,width:width,height:height))
        let context=CIContext(options:[.cacheIntermediates:false])
        let cg=try XCTUnwrap(context.createCGImage(image,from:image.extent))
        let input=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        let destination=try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,cg,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        defer{try? FileManager.default.removeItem(at:input)}
        let out=try await FullResolutionExporter().export(sourceURL:input,recipe:plain(),cube:nil,format:.heif,progress:{_ in})
        defer{try? FileManager.default.removeItem(at:out)}
        let props=try properties(out)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int,width)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int,height)
    }

    func testPhysicalTilesMatchWholeFrameWithoutSpatialEffects() async throws {
        let input=try source(width:1100,height:700);defer{try? FileManager.default.removeItem(at:input)}
        var recipe=plain();recipe.intensity=1;recipe.grain=0;recipe.halation=0;recipe.dirCouplers=0;recipe.scannerSharpness=0
        let renderer=FilmRenderer()
        let image=try await renderer.decode(Data(contentsOf:input),maximum:1600)
        let whole=try await renderer.render(image,recipe:recipe,cube:nil)
        let wholeFile=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        try XCTUnwrap(whole.pngData()).write(to:wholeFile);defer{try? FileManager.default.removeItem(at:wholeFile)}
        let tiled=try await FullResolutionExporter().export(sourceURL:input,recipe:recipe,cube:nil,format:.png,progress:{_ in})
        defer{try? FileManager.default.removeItem(at:tiled)}
        for file in [wholeFile,tiled] {if let image=UIImage(contentsOfFile:file.path){let a=XCTAttachment(image:image);a.lifetime = .keepAlways;add(a)}}
        let a=try pixels(wholeFile),b=try pixels(tiled)
        XCTAssertEqual(a.0,b.0);XCTAssertEqual(a.1,b.1)
        for y in [100,350,600]{for x in [100,510,520,900]{for c in 0..<3{let p=(y*a.0+x)*4+c;XCTAssertLessThanOrEqual(abs(Int(a.2[p])-Int(b.2[p])),2)}}}
    }

    @MainActor
    func testPersistentLibraryAndUnmodifiedOriginalExport() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=LibraryStore(directory:dir)
        let source=try source(width:320,height:240)
        let bytes=try Data(contentsOf:source)
        let asset=try await store.add(data:bytes,label:"Test original")
        let second=LibraryStore(directory:dir)
        XCTAssertEqual(second.assets.count,1)
        XCTAssertEqual(try Data(contentsOf:second.url(for:asset)),bytes)
        let model=DarkroomModel();model.load(asset,store:store)
        for _ in 0..<100{if !model.loading{break};try await Task.sleep(nanoseconds:50_000_000)}
        model.export(saveToPhotos:false,format:.original)
        for _ in 0..<100{if !model.exporting{break};try await Task.sleep(nanoseconds:50_000_000)}
        XCTAssertNil(model.error)
        let exported=try XCTUnwrap(model.shareURL)
        XCTAssertEqual(try Data(contentsOf:exported),bytes)
        let sidecar=try XCTUnwrap(model.sidecarURL)
        _=try JSONDecoder().decode(FilmRecipe.self,from:Data(contentsOf:sidecar))
        model.cleanupShare()
    }

    func testCancelledExportStopsBeforeProducingOutput() async throws {
        let input=try source(width:100,height:100);defer{try? FileManager.default.removeItem(at:input)}
        let recipe=plain(),exporter=FullResolutionExporter()
        let work=Task{try await exporter.export(sourceURL:input,recipe:recipe,cube:nil,format:.jpeg,progress:{_ in})}
        work.cancel()
        do{_=try await work.value;XCTFail("Cancelled export should not complete")}catch is CancellationError{}catch{XCTFail("Unexpected error: \(error)")}
    }

    func testAllStillEncodersWithFilmBorderAndDate() async throws {
        let input=try source(width:320,height:240);defer{try? FileManager.default.removeItem(at:input)}
        var recipe=plain();recipe.printStyle.border = .perforated;recipe.printStyle.dateStyle = .classic
        for format in [ExportFormat.jpeg,.heif,.png,.tiff]{
            let out=try await FullResolutionExporter().export(sourceURL:input,recipe:recipe,cube:nil,format:format,progress:{_ in})
            defer{try? FileManager.default.removeItem(at:out)}
            let props=try properties(out)
            XCTAssertGreaterThan(props[kCGImagePropertyPixelWidth] as? Int ?? 0,320)
            XCTAssertGreaterThan(props[kCGImagePropertyPixelHeight] as? Int ?? 0,240)
            if format.sixteenBit{XCTAssertEqual(props[kCGImagePropertyDepth] as? Int,16)}
        }
    }

    func testPrintFormatsAndImprintsChangeCanvas() throws {
        let image=CIImage(color:.gray).cropped(to:CGRect(x:0,y:0,width:1000,height:800))
        var style=PrintStyle();style.border = .none;style.aspect = .square
        let square=PrintComposer.crop(image,style:style)
        XCTAssertEqual(square.extent.width,800);XCTAssertEqual(square.extent.height,800)
        style.border = .instant;style.dateStyle = .custom;style.caption="HELLO SILVER"
        let composed=PrintComposer.compose(square,style:style,stock:"Custom B&W")
        XCTAssertGreaterThan(composed.extent.height,composed.extent.width)
        XCTAssertNotNil(CIContext().createCGImage(composed,from:composed.extent))
    }

    func testCustomBWReallyChangesSpectralResponse() throws {
        var normal=FilmRecipe();normal.stock=Stock.allCases.first{$0.id=="kodak_doublex"}!;normal.paper=Paper.allCases.first{$0.id=="kodak_2302"}!
        normal.grain=0;normal.halation=0
        var red=BWEmulsion();red.red=2;red.green=0.2;red.blue=0.01
        var blue=red;blue.red=0.01;blue.blue=2
        let input:[Float]=[0.6,0.05,0.01,1, 0.01,0.05,0.6,1]
        normal.customBW=red
        let a=try SpectralSession(film:normal.stock.id,paper:normal.paper.id,params:normal.spectralJSON()).render(input,width:2,height:1)
        normal.customBW=blue
        let b=try SpectralSession(film:normal.stock.id,paper:normal.paper.id,params:normal.spectralJSON()).render(input,width:2,height:1)
        XCTAssertGreaterThan(abs(a[0]-b[0]),0.02)
        XCTAssertGreaterThan(abs(a[4]-b[4]),0.02)
    }
}
