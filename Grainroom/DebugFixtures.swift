// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import UIKit
import SwiftUI

@MainActor
enum DebugFixtures {
    /// Generated illustrations for simulator layout QA only. Never inserted
    /// unless --studio-fixture is explicitly passed to the Debug build.
    static func populate(_ store:LibraryStore) async throws {
        guard store.assets.isEmpty else{return}
        for i in 0..<9{
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let image=UIGraphicsImageRenderer(size:CGSize(width:900,height:1200),format:format).image{r in
                let ctx=r.cgContext
                let skies:[UIColor]=[UIColor(red:0.74,green:0.67,blue:0.48,alpha:1),UIColor(red:0.38,green:0.50,blue:0.50,alpha:1),UIColor(red:0.82,green:0.48,blue:0.31,alpha:1)]
                skies[i%3].setFill();ctx.fill(CGRect(x:0,y:0,width:900,height:1200))
                UIColor(red:0.96,green:0.83,blue:0.57,alpha:1).setFill();ctx.fillEllipse(in:CGRect(x:CGFloat(420+i*19%220),y:140,width:180,height:180))
                for layer in 0..<4{
                    let path=UIBezierPath();let y=CGFloat(550+layer*140)
                    path.move(to:CGPoint(x:0,y:y));path.addLine(to:CGPoint(x:240,y:y-CGFloat(160+i*7)));path.addLine(to:CGPoint(x:460,y:y+90));path.addLine(to:CGPoint(x:720,y:y-CGFloat(240-i*8)));path.addLine(to:CGPoint(x:900,y:y-60));path.addLine(to:CGPoint(x:900,y:1200));path.addLine(to:CGPoint(x:0,y:1200));path.close()
                    UIColor(red:0.10+CGFloat(layer)*0.02,green:0.17+CGFloat(layer)*0.01,blue:0.14+CGFloat(layer)*0.02,alpha:1).setFill();path.fill()
                }
            }
            try await store.add(data:image.jpegData(compressionQuality:0.95)!,label:"布局测试 \(i+1)")
        }
    }
}
#endif
