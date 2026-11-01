// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct EmulsionStudio:View {
    @ObservedObject var store:LibraryStore
    @ObservedObject var model:DarkroomModel
    let openDarkroom:()->Void
    @State private var film=BWEmulsion()
    @State private var shareURL:URL?
    @State private var importing=false
    @State private var notice:String?
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:24){
                    StudioHeading(number:"04",title:"配一卷自己的银盐。",subtitle:"EMULSION / SMALL BATCH")
                    ZStack(alignment:.bottomLeading){
                        LinearGradient(colors:[Color(white:0.32),Color(white:0.08)],startPoint:.topLeading,endPoint:.bottomTrailing)
                        if let preview=model.preview,model.recipe.customBW != nil{Image(uiImage:preview).resizable().scaledToFit().padding(16)}
                        else{VStack(alignment:.leading,spacing:14){Image(systemName:"waveform.path").font(.system(size:54,weight:.ultraLight));Text("LIGHT → SILVER").font(.caption.monospaced()).tracking(3);Text("从感光响应开始，\n做一卷只属于你的黑白。").font(.system(size:21,design:.serif)).lineSpacing(6)}.padding(26)}
                        Text("EXPERIMENTAL EMULSION / BATCH 001").font(.system(size:8,design:.monospaced)).tracking(2).padding(16).foregroundStyle(.white.opacity(0.7))
                    }.frame(height:260).clipShape(RoundedRectangle(cornerRadius:5))
                    VStack(alignment:.leading,spacing:18){
                        TextField("给胶片起个名字",text:$film.name).font(.title3).padding(.bottom,6)
                        HStack(spacing:8){preset("全色",r:1,g:1,b:1);preset("正色",r:0.04,g:1,b:1.4);preset("红敏实验",r:1.9,g:0.4,b:0.05)}
                        knob("红光感度 · 620nm",value:$film.red,range:0...2)
                        knob("绿光感度 · 540nm",value:$film.green,range:0...2)
                        knob("蓝光感度 · 450nm",value:$film.blue,range:0...2)
                        knob("显影反差",value:$film.contrast,range:0.4...2)
                        knob("乳剂颗粒",value:$film.grain,range:0...2)
                        knob("光晕",value:$film.halation,range:0...2)
                    }.padding(20).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:14))
                    HStack(spacing:12){
                        Button{do{try store.save(film);notice="已保存到我的乳剂"}catch{store.error=error.localizedDescription}}label:{Label("保存乳剂",systemImage:"flask.fill").frame(maxWidth:.infinity).padding(16).background(StudioTheme.amber,in:Capsule()).foregroundStyle(.black)}
                        Button{do{shareURL=try store.emulsionFile(film)}catch{store.error=error.localizedDescription}}label:{Image(systemName:"square.and.arrow.up").padding(17).background(StudioTheme.surface,in:Circle())}
                    }
                    Button{model.apply(film);openDarkroom()}label:{HStack{Text("带这卷胶片去暗房");Spacer();Image(systemName:"arrow.up.right")}.padding(18).overlay(RoundedRectangle(cornerRadius:12).stroke(StudioTheme.amber.opacity(0.5)))}
                    if !store.emulsions.isEmpty{
                        SectionEyebrow(text:"YOUR FORMULAS / 我的乳剂")
                        ForEach(store.emulsions){e in
                            Button{film=e;model.apply(e)}label:{HStack{Image(systemName:"film");Text(e.name);Spacer();Text("B&W").font(.caption.monospaced())}.padding(16).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)
                        }
                    }
                    Button("导入朋友的乳剂配方"){importing=true}.font(.subheadline)
                    Text("基于 Double-X 测量数据改变光谱感度与显影反差。配方可保存、交换；实验结果不代表校准过的实体胶片。").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(22)
            }.background(StudioTheme.background).tint(StudioTheme.amber)
                .onChange(of:film){_,e in if model.original != nil{model.apply(e)}}
                .sheet(isPresented:Binding(get:{shareURL != nil},set:{if !$0{shareURL=nil}})){if let shareURL{SharePanel(urls:[shareURL])}}
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json]){result in
                    do{try store.importEmulsion(result.get());notice="配方已收入我的乳剂"}catch{store.error=error.localizedDescription}
                }
                .alert("制片室",isPresented:Binding(get:{notice != nil},set:{if !$0{notice=nil}})){Button("好"){notice=nil}}message:{Text(notice ?? "")}
        }
    }
    private func knob(_ title:String,value:Binding<Double>,range:ClosedRange<Double>)->some View{
        VStack(spacing:4){HStack{Text(title).font(.subheadline);Spacer();Text(String(format:"%.2f",value.wrappedValue)).font(.caption.monospaced()).foregroundStyle(StudioTheme.amber)};Slider(value:value,in:range).accessibilityLabel(title)}
    }
    private func preset(_ title:String,r:Double,g:Double,b:Double)->some View{
        Button{film.red=r;film.green=g;film.blue=b}label:{Text(title).font(.caption).padding(.horizontal,14).padding(.vertical,8).background(.white.opacity(0.07),in:Capsule())}.buttonStyle(.plain)
    }
}
