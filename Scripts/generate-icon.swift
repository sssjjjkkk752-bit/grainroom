import AppKit
let size=1024
let space=CGColorSpace(name:CGColorSpace.sRGB)!
let c=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red:0.055,green:0.064,blue:0.061,alpha:1));c.fill(CGRect(x:0,y:0,width:size,height:size))
c.setShadow(offset:.zero,blur:80,color:CGColor(red:0.94,green:0.71,blue:0.4,alpha:0.12))
c.setFillColor(CGColor(red:0.12,green:0.14,blue:0.12,alpha:1));c.addPath(CGPath(roundedRect:CGRect(x:190,y:180,width:644,height:664),cornerWidth:35,cornerHeight:35,transform:nil));c.fillPath();c.setShadow(offset:.zero,blur:0,color:nil)
c.setStrokeColor(CGColor(red:0.94,green:0.71,blue:0.40,alpha:1));c.setLineWidth(14);c.stroke(CGRect(x:300,y:275,width:424,height:474))
for x in [225,755]{for y in stride(from:240,through:770,by:90){c.setFillColor(CGColor(red:0.94,green:0.71,blue:0.40,alpha:1));c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:44,height:57),cornerWidth:9,cornerHeight:9,transform:nil));c.fillPath()}}
c.setFillColor(CGColor(red:0.94,green:0.71,blue:0.40,alpha:1));c.fillEllipse(in:CGRect(x:374,y:374,width:276,height:276))
c.setFillColor(CGColor(red:0.055,green:0.064,blue:0.061,alpha:1));c.fill(CGRect(x:512,y:365,width:145,height:300))
c.setStrokeColor(CGColor(red:0.94,green:0.71,blue:0.40,alpha:1));c.setLineWidth(6);c.strokeEllipse(in:CGRect(x:374,y:374,width:276,height:276))
let image=c.makeImage()!
let rep=NSBitmapImageRep(cgImage:image)
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
