// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct SharePanel:UIViewControllerRepresentable {
    var urls:[URL]
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:urls,applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
struct SectionEyebrow:View {
    let text:String
    var body:some View{Text(text).font(.system(size:10,weight:.medium,design:.monospaced)).tracking(3).foregroundStyle(StudioTheme.amber)}
}
struct StudioHeading:View {
    let number:String
    let title:String
    let subtitle:String
    var body:some View {
        HStack(alignment:.top){
            VStack(alignment:.leading,spacing:10){SectionEyebrow(text:subtitle);Text(title).font(.system(size:34,weight:.regular,design:.serif)).foregroundStyle(StudioTheme.cream)}
            Spacer();Text(number).font(.system(size:48,weight:.ultraLight,design:.monospaced)).foregroundStyle(StudioTheme.amber.opacity(0.6))
        }.padding(.vertical,12)
    }
}
struct FilmIllustration:View {
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:3).fill(StudioTheme.amber.opacity(0.03))
            ForEach(0..<3){i in
                HStack(spacing:4){
                    ForEach(0..<4){j in
                        ZStack{
                            Rectangle().fill(Color.black)
                            Rectangle().fill(LinearGradient(colors:[StudioTheme.mint.opacity(0.6),Color(red:0.39,green:0.29,blue:0.17)],startPoint:.topLeading,endPoint:.bottomTrailing)).padding(9)
                            Text("\(i*4+j+1)").font(.system(size:8,design:.monospaced)).foregroundStyle(StudioTheme.amber).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottomLeading).padding(3)
                        }.frame(width:58,height:83)
                    }
                }.rotationEffect(.degrees(Double(i-1) * (-7))).offset(x:CGFloat(i-1)*9,y:CGFloat(i-1)*48)
            }
        }.frame(height:225).accessibilityHidden(true)
    }
}

@MainActor
enum ContactSheet {
    static func render(images:[UIImage],labels:[String],negative:Bool=false)->URL? {
        guard !images.isEmpty else{return nil}
        let columns=images.count<=3 ? images.count:3
        let cell:CGFloat=660,gap:CGFloat=24,padding:CGFloat=72,header:CGFloat=160
        let rows=Int(ceil(Double(images.count)/Double(columns)))
        let size=CGSize(width:CGFloat(columns)*cell+CGFloat(columns-1)*gap+2*padding,height:header+CGFloat(rows)*(cell+110)+padding)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let image=UIGraphicsImageRenderer(size:size,format:format).image{r in
            UIColor(red:0.89,green:0.89,blue:0.82,alpha:1).setFill();r.fill(CGRect(origin:.zero,size:size))
            ("GRAINROOM / CONTACT SHEET" as NSString).draw(at:CGPoint(x:padding,y:45),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:28,weight:.medium),.foregroundColor:UIColor.black])
            ((negative ? "NEGATIVE VIEW · DIGITAL PROOF":"SELECTED FRAMES · DIGITAL PROOF") as NSString).draw(at:CGPoint(x:padding,y:92),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:18,weight:.regular),.foregroundColor:UIColor.darkGray])
            for (i,photo) in images.enumerated(){
                let x=padding+CGFloat(i%columns)*(cell+gap),y=header+CGFloat(i/columns)*(cell+110)
                UIColor.black.setFill();r.fill(CGRect(x:x,y:y,width:cell,height:cell+48))
                let scale=min((cell-28)/photo.size.width,(cell-28)/photo.size.height)
                let fit=CGSize(width:photo.size.width*scale,height:photo.size.height*scale)
                photo.draw(in:CGRect(x:x+(cell-fit.width)/2,y:y+(cell-fit.height)/2,width:fit.width,height:fit.height))
                let label=i<labels.count ? labels[i]:"FRAME \(i+1)"
                (String(label.prefix(70)) as NSString).draw(at:CGPoint(x:x+15,y:y+cell+12),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:15,weight:.medium),.foregroundColor:UIColor.orange])
            }
        }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("Grainroom-contact-\(UUID()).jpg")
        do{try image.jpegData(compressionQuality:0.95)?.write(to:url);return url}catch{return nil}
    }
}
