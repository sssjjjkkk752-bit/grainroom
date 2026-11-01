// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import PhotosUI

enum StudioTab:Hashable {case camera,darkroom,lightTable,emulsion}

struct StudioRootView:View {
    @StateObject private var library=LibraryStore()
    @StateObject private var darkroom=DarkroomModel()
    @StateObject private var camera=CameraModel()
    @State private var tab:StudioTab = .darkroom
    @State private var savingCapture=false
    @State private var prepared=false
    @AppStorage("Grainroom.rollFrame") private var frame=1
    @AppStorage("Grainroom.mysteryRoll") private var mystery=false
    var body:some View {
        TabView(selection:$tab){
            CameraPage(model:camera,frame:frame,mystery:$mystery,active:tab == .camera).tabItem{Label("相机",systemImage:"camera")}.tag(StudioTab.camera)
            DarkroomView(model:darkroom).tabItem{Label("暗房",systemImage:"slider.horizontal.3")}.tag(StudioTab.darkroom)
            LightTableView(store:library){asset in darkroom.load(asset,store:library);tab = .darkroom}
                .tabItem{Label("观片台",systemImage:"rectangle.split.3x3")}.tag(StudioTab.lightTable)
            EmulsionStudio(store:library,model:darkroom){tab = .darkroom}.tabItem{Label("制片室",systemImage:"flask")}.tag(StudioTab.emulsion)
        }.tint(tab == .lightTable ? Color(red:0.22,green:0.29,blue:0.23):StudioTheme.amber).environmentObject(library)
        .preferredColorScheme(tab == .lightTable ? .light:.dark)
        .task{
            #if DEBUG
            if !prepared,ProcessInfo.processInfo.arguments.contains("--studio-fixture"){
                prepared=true
                do{try await DebugFixtures.populate(library)}catch{library.error=error.localizedDescription}
                if let asset=library.assets.first{darkroom.load(asset,store:library)}
            }
            if ProcessInfo.processInfo.arguments.contains("--light-table"){tab = .lightTable}
            if ProcessInfo.processInfo.arguments.contains("--emulsion-studio"){tab = .emulsion}
            if ProcessInfo.processInfo.arguments.contains("--camera-page"){tab = .camera}
            #endif
        }
        .onAppear{camera.onFiles={files in
            savingCapture=true;camera.capturing=true
            Task{@MainActor in
                defer{savingCapture=false;camera.capturing=false}
                do{
                    var latest:PhotoAsset?
                    for file in files {let asset=try await library.add(data:file.data,label:file.label,preferredExtension:file.ext);if latest==nil || asset.isRAW{latest=asset}}
                    darkroom.recipe.printStyle.frameNumber=frame
                    frame = frame%36+1
                    if mystery{darkroom.randomize()}
                    if let latest{darkroom.load(latest,store:library)}
                }catch{library.error=error.localizedDescription}
            }
        }}
        .alert("图库提示",isPresented:Binding(get:{library.error != nil},set:{if !$0{library.error=nil}})){Button("知道了",role:.cancel){library.error=nil}}message:{Text(library.error ?? "")}
    }
}

struct CameraPage:View {
    @ObservedObject var model:CameraModel
    let frame:Int
    @Binding var mystery:Bool
    let active:Bool
    @Environment(\.scenePhase) private var scene
    var body:some View {
        NavigationStack {
            VStack(spacing:18){
                HStack{
                    SectionEyebrow(text:"GRAINROOM / CAMERA")
                    Spacer();Text(String(format:"%02d / 36",frame)).font(.caption.monospaced()).foregroundStyle(StudioTheme.amber)
                }.padding(.horizontal,22)
                ZStack{
                    RoundedRectangle(cornerRadius:6).fill(StudioTheme.surface)
                    if model.authorized{CameraPreview(session:model.service.session).clipShape(RoundedRectangle(cornerRadius:6))}
                    else{VStack(spacing:14){Image(systemName:"camera.aperture").font(.system(size:64,weight:.ultraLight));Text("等待光线，也等待一瞬间。").font(.subheadline)}}
                    VStack{HStack{
                        Text(model.maxResolution ? "MAX RES":"STANDARD").font(.caption2.monospaced()).padding(8).background(.black.opacity(0.4),in:Capsule())
                        Spacer();Image(systemName:"viewfinder").font(.title2)
                    };Spacer();HStack{Text((model.capabilities.lenses.first{$0.id==model.capabilities.selectedID}?.name ?? "镜头")+" · 原生").font(.caption.monospaced());Spacer();Text(model.format.rawValue).font(.caption.monospaced())}}.foregroundStyle(.white).padding(18)
                    Rectangle().stroke(.white.opacity(0.18),lineWidth:0.5).padding(.horizontal,65)
                    Rectangle().stroke(.white.opacity(0.18),lineWidth:0.5).padding(.vertical,100)
                }.aspectRatio(3/4,contentMode:.fit).padding(.horizontal,20)
                HStack(spacing:14){
                    Menu{ForEach(model.capabilities.lenses){lens in Button(lens.name){model.service.switchLens(lens.id)}}}label:{Label("镜头",systemImage:"camera.metering.center.weighted")}
                    Spacer()
                    Menu{ForEach(CaptureFormat.allCases){format in
                        Button(format.rawValue){model.format=format}.disabled(format == .heif && !model.capabilities.heif || format == .proRAW && !model.capabilities.proRAW || format == .bayerRAW && !model.capabilities.bayerRAW)
                    }}label:{Text(model.format.rawValue).font(.caption.weight(.semibold))}
                    Spacer()
                    Button{model.maxResolution.toggle()}label:{Text(model.maxResolution ? (model.capabilities.supports48MP ? "48MP MAX":"最高像素"):"标准像素").font(.caption.weight(.semibold))}
                }.padding(.horizontal,26).disabled(model.capturing)
                HStack(spacing:38){
                    Button{mystery.toggle()}label:{VStack(spacing:5){Image(systemName:mystery ? "sparkles":"dice");Text("盲盒胶卷").font(.system(size:9))}.foregroundStyle(mystery ? StudioTheme.amber:.secondary)}.accessibilityValue(mystery ? "开启":"关闭")
                    Button{model.shoot()}label:{ZStack{Circle().stroke(.white,lineWidth:2).frame(width:78,height:78);Circle().fill(model.capturing ? Color.gray:StudioTheme.cream).frame(width:64,height:64);if model.capturing{ProgressView().tint(.black)}}}.disabled(model.capturing || !model.authorized).accessibilityLabel("拍摄照片")
                    VStack(spacing:5){Text("AUTO").font(.caption.monospaced());Text("原片保留").font(.system(size:9))}.foregroundStyle(.secondary)
                }.padding(.top,2)
                Text(model.message.isEmpty ? "\(model.capabilities.maxWidth) × \(model.capabilities.maxHeight) 请求上限 · 实际尺寸以本次拍摄结果为准":model.message)
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal,26)
                Spacer(minLength:0)
            }.padding(.top,12).background(StudioTheme.background)
                .task{if active{await model.start()}}.onDisappear{model.service.stop()}
                .onChange(of:active){_,value in if value{Task{await model.start()}}else{model.service.stop()}}
                .onChange(of:scene){_,phase in if phase == .active && active{Task{await model.start()}}else{model.service.stop()}}
                .toolbar(.hidden,for:.navigationBar)
        }
    }
}
