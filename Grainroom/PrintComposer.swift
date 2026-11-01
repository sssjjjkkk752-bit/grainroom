// SPDX-License-Identifier: GPL-3.0-only
import UIKit
import CoreImage

/// Borders and date backs are creative overlays, composed after emulsion processing.
enum PrintComposer {
    static func crop(_ image: CIImage, style: PrintStyle) -> CIImage {
        guard let ratio=style.aspect.ratio else { return image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY)) }
        let e=image.extent
        let w=min(e.width,e.height*ratio),h=min(e.height,e.width/ratio)
        let rect=CGRect(x:e.midX-w/2,y:e.midY-h/2,width:w,height:h).integral
        return image.cropped(to:rect).transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY))
    }

    static func compose(_ image: CIImage, style: PrintStyle, stock: String) -> CIImage {
        let e=image.extent
        let unit=max(1,max(e.width,e.height)/1600)
        var photo=image
        if style.dateStyle != .none {
            let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yy MM dd"
            let text: String
            switch style.dateStyle {
            case .classic:text=formatter.string(from:style.capturedAt)
            case .cinema:text="SC. \(String(format:"%03d",style.frameNumber))  /  \(formatter.string(from:style.capturedAt))"
            case .custom:text=String(style.caption.prefix(80))
            case .none:text=""
            }
            let stamp=strip(size:CGSize(width:e.width,height:90*unit)) { ctx,size in
                let attrs:[NSAttributedString.Key:Any]=[.font:UIFont.monospacedDigitSystemFont(ofSize:24*unit,weight:.medium),.foregroundColor:UIColor(red:1,green:0.39,blue:0.12,alpha:0.92)]
                ctx.setShadow(offset:.zero,blur:7*unit,color:UIColor.orange.withAlphaComponent(0.6).cgColor)
                let label=text as NSString
                label.draw(at:CGPoint(x:max(18*unit,size.width-label.size(withAttributes:attrs).width-28*unit),y:30*unit),withAttributes:attrs)
            }
            photo=CIImage(cgImage:stamp).transformed(by:CGAffineTransform(translationX:0,y:18*unit)).composited(over:photo)
        }
        guard style.border != .none else{return photo.cropped(to:e)}
        let side=ceil(e.width*(style.border == .perforated ? 0.065:0.045))
        let top=ceil(e.height*0.045)
        let bottom=ceil(e.height*(style.border == .instant ? 0.20:0.06))
        let width=e.width+2*side,height=e.height+top+bottom
        let canvas=CGRect(x:0,y:0,width:width,height:height)
        let instant=style.border == .instant
        let color=instant ? CIColor(red:0.93,green:0.91,blue:0.85):CIColor(red:0.035,green:0.033,blue:0.028)
        var result=photo.transformed(by:CGAffineTransform(translationX:side,y:bottom)).composited(over:CIImage(color:color).cropped(to:canvas))
        if style.border == .perforated {
            let rail=strip(size:CGSize(width:side,height:height)) {ctx,size in
                ctx.setFillColor(UIColor(red:0.86,green:0.85,blue:0.79,alpha:1).cgColor)
                let pitch=max(16,size.width*0.95)
                var y=pitch/2
                while y<size.height {
                    ctx.addPath(UIBezierPath(roundedRect:CGRect(x:size.width*0.26,y:y,width:size.width*0.48,height:pitch*0.58),cornerRadius:size.width*0.08).cgPath);ctx.fillPath();y+=pitch
                }
            }
            let ci=CIImage(cgImage:rail)
            result=ci.composited(over:result)
            result=ci.transformed(by:CGAffineTransform(translationX:width-side,y:0)).composited(over:result)
        }
        let label=strip(size:CGSize(width:width,height:bottom)) {ctx,size in
            let ink=instant ? UIColor(white:0.18,alpha:1):UIColor(red:0.93,green:0.63,blue:0.23,alpha:1)
            let text=instant ? style.caption : "GRAINROOM  •  \(stock.uppercased())  /  \(String(format:"%02d",style.frameNumber))  ▸"
            let font=UIFont.monospacedSystemFont(ofSize:min(22*unit,bottom*0.30),weight:.medium)
            (String(text.prefix(100)) as NSString).draw(at:CGPoint(x:side,y:size.height*0.38),withAttributes:[.font:font,.foregroundColor:ink])
        }
        result=CIImage(cgImage:label).composited(over:result)
        if style.border == .cinema {
            let line=CIImage(color:CIColor(red:0.92,green:0.56,blue:0.19)).cropped(to:CGRect(x:side,y:height-top*0.55,width:e.width,height:max(1,unit)))
            result=line.composited(over:result)
        }
        return result.cropped(to:canvas)
    }

    private static func strip(size:CGSize,draw:(CGContext,CGSize)->Void)->CGImage {
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=false
        return UIGraphicsImageRenderer(size:size,format:format).image { draw($0.cgContext,size) }.cgImage!
    }
}
