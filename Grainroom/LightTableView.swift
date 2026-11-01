// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LightTableView:View {
    @ObservedObject var store:LibraryStore
    let open:(PhotoAsset)->Void
    @State private var picked:[PhotosPickerItem]=[]
    @State private var files=false
    @State private var negative=true
    @State private var selecting=false
    @State private var selection=Set<UUID>()
    @State private var comparing=false
    @State private var favorites=false
    @State private var shareURL:URL?
    private var visible:[PhotoAsset]{store.assets.filter{!favorites || $0.rating>0}}
    private var chosen:[PhotoAsset]{store.assets.filter{selection.contains($0.id)}}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:22){
                    HStack(alignment:.top){
                        VStack(alignment:.leading,spacing:9){Text("GRAINROOM / LIGHT TABLE").font(.system(size:10,design:.monospaced)).tracking(2);Text("观片台").font(.system(size:36,weight:.regular,design:.serif))}
                        Spacer();Text(String(format:"%03d",visible.count)).font(.system(size:45,weight:.ultraLight,design:.monospaced))
                    }.foregroundStyle(Color.black.opacity(0.82))
                    HStack{
                        Button{negative.toggle()}label:{Label(negative ? "负片预览":"正片预览",systemImage:"circle.lefthalf.filled")}
                        Spacer();Button{favorites.toggle()}label:{Image(systemName:favorites ? "star.fill":"star")}
                        Button{selecting.toggle();if !selecting{selection=[]}}label:{Text(selecting ? "完成":"选择")}
                    }.font(.caption.weight(.medium)).tint(.black)
                    if visible.isEmpty{
                        VStack(spacing:18){FilmIllustration();Text("每一张，都值得再看一遍。").font(.system(size:22,design:.serif));Text("导入照片或拍摄一卷，\n把底片摊开，挑出最喜欢的一格。").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.5))}.padding(.vertical,40).foregroundStyle(.black)
                    }else{
                        LazyVGrid(columns:[GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10),GridItem(.flexible())],spacing:20){
                            ForEach(visible){asset in
                                Button{
                                    if selecting{if selection.contains(asset.id){selection.remove(asset.id)}else if selection.count<12{selection.insert(asset.id)}}else{open(asset)}
                                }label:{
                                    VStack(alignment:.leading,spacing:7){
                                        ZStack(alignment:.topTrailing){
                                            ZStack{
                                                Color(white:0.05)
                                                if let image=store.thumbnail(asset,negative:negative){Image(uiImage:image).resizable().scaledToFit().padding(.horizontal,6).padding(.vertical,10)}
                                            }.aspectRatio(0.78,contentMode:.fit)
                                            if selecting{Image(systemName:selection.contains(asset.id) ? "checkmark.circle.fill":"circle").foregroundStyle(StudioTheme.amber).padding(5)}
                                        }.overlay(Rectangle().stroke(selection.contains(asset.id) ? Color.orange:Color.clear,lineWidth:2))
                                        HStack{Text(asset.isRAW ? "DNG":"FRAME");Spacer();Text(asset.sizeLabel)}.font(.system(size:8,design:.monospaced)).foregroundStyle(.black.opacity(0.58))
                                        HStack(spacing:2){ForEach(0..<asset.rating,id:\.self){_ in Image(systemName:"star.fill")}}.font(.system(size:8)).foregroundStyle(.black.opacity(0.7)).frame(height:8)
                                    }
                                }.buttonStyle(.plain).contextMenu{
                                    Button("在暗房打开"){open(asset)}
                                    Button("评级（0–3 星）",systemImage:"star"){store.rate(asset)}
                                    Button("分享原始文件",systemImage:"square.and.arrow.up"){shareURL=store.url(for:asset)}
                                }.accessibilityLabel("\(asset.label)，\(asset.sizeLabel)，\(asset.rating) 星")
                            }
                        }
                    }
                    Text("\(negative ? "NEGATIVE VIEW · DIGITAL PROOF":"POSITIVE VIEW · DIGITAL PROOF") / 本机图库").font(.system(size:8,design:.monospaced)).tracking(1).foregroundStyle(.black.opacity(0.4))
                }.padding(22)
            }.background(Color(red:0.87,green:0.88,blue:0.81))
            .toolbar{
                ToolbarItem(placement:.topBarTrailing){
                    Menu{
                        PhotosPicker(selection:$picked,maxSelectionCount:30,matching:.images,preferredItemEncoding:.current){Label("从照片导入",systemImage:"photo.badge.plus")}
                        Button("从文件导入 RAW / 图片",systemImage:"folder"){files=true}
                    }label:{Image(systemName:"plus").foregroundStyle(.black)}
                }
                ToolbarItem(placement:.topBarLeading){if store.importing{ProgressView().tint(.black)}}
            }
            .safeAreaInset(edge:.bottom){
                if selecting{
                    HStack{
                        Button("比较 \(chosen.count) 格"){comparing=true}.disabled(chosen.count<2)
                        Spacer();Button("分享接触印样"){shareContact()}.disabled(chosen.isEmpty)
                    }.font(.subheadline).tint(.black).padding(18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,18).padding(.bottom,8)
                }
            }
            .onChange(of:picked){_,items in Task{await store.importPhotos(items);picked=[]}}
            .fileImporter(isPresented:$files,allowedContentTypes:[.image,.rawImage],allowsMultipleSelection:true){result in
                if case .success(let urls)=result{Task{store.importing=true;for url in urls{await store.importFile(url)};store.importing=false}}
                if case .failure(let error)=result{store.error=error.localizedDescription}
            }
            .sheet(isPresented:$comparing){comparison}
            .sheet(isPresented:Binding(get:{shareURL != nil},set:{if !$0{shareURL=nil}})){if let shareURL{SharePanel(urls:[shareURL])}}
        }
    }
    private var comparison:some View{
        NavigationStack{
            ScrollView{
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:20){ForEach(chosen){asset in
                    VStack(alignment:.leading,spacing:10){if let image=store.thumbnail(asset,negative:negative){Image(uiImage:image).resizable().scaledToFit()};Text(asset.label+" / "+asset.sizeLabel).font(.caption.monospaced());Button("选这一格"){comparing=false;open(asset)}}
                }}}.padding(20).background(StudioTheme.background).navigationTitle("并排选片").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){comparing=false}}}
        }.tint(StudioTheme.amber)
    }
    private func shareContact(){
        let entries=chosen.compactMap{asset->(UIImage,String)? in guard let image=store.thumbnail(asset,negative:negative)else{return nil};return(image,asset.label+" / "+asset.sizeLabel)}
        shareURL=ContactSheet.render(images:entries.map{$0.0},labels:entries.map{$0.1},negative:negative)
    }
}
