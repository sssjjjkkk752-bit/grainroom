// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private let accent = Color(red: 0.90, green: 0.69, blue: 0.38)
private let panel = Color(red: 0.105, green: 0.11, blue: 0.105)

struct DarkroomView: View {
    @ObservedObject var model:DarkroomModel
    @EnvironmentObject private var library:LibraryStore
    @State private var showBracket=false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var comparing = false
    @State private var importingCube = false
    @State private var showAbout = false
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    photoStage
                    if model.original != nil {
                        HStack {
                            Label("照片暗房", systemImage: "circle.lefthalf.filled")
                            if let asset=model.asset{Text(asset.sizeLabel)}
                            Spacer()
                            Text(model.cube == nil ? "光谱引擎 · f64" : "自定义 LUT").foregroundStyle(accent)
                        }.font(.caption.monospaced()).foregroundStyle(.secondary)
                        engineSection
                        adjustments
                        printOptions
                        Button{model.makeBracket();showBracket=true}label:{
                            HStack{Image(systemName:"rectangle.split.3x1");Text("做一张曝光试条");Spacer();Text("−1 / 0 / +1").font(.caption.monospaced())}.padding(18).background(panel,in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain).foregroundStyle(accent)
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                            Text("全尺寸显影 · HEIF / JPEG / PNG / TIFF · 保留原始文件")
                        }.font(.caption2).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("把日常，留在胶片里。")
                                .font(.title2.weight(.medium))
                            Text("从照片开始，选择一种色彩，慢慢调出自己的暗房配方。")
                                .foregroundStyle(.secondary).font(.subheadline).lineSpacing(5)
                            Text("01 导入照片     02 选择风格     03 保存成片")
                                .font(.caption.monospaced()).foregroundStyle(accent).padding(.top, 8)
                        }
                    }
                }.padding(20).padding(.bottom, 24)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.055))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("关于应用与引擎")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu("保存到照片",systemImage:"square.and.arrow.down"){
                            ForEach(ExportFormat.allCases){format in Button(format.rawValue){model.export(saveToPhotos:true,format:format)}.disabled(model.original == nil && format != .original)}
                        }
                        Menu("导出与分享",systemImage:"square.and.arrow.up"){
                            ForEach(ExportFormat.allCases){format in Button(format.rawValue){model.export(saveToPhotos:false,format:format)}.disabled(model.original == nil && format != .original)}
                        }
                        Button("成片放上观片台",systemImage:"rectangle.split.3x3"){model.export(saveToPhotos:false,format:.heif,store:library)}.disabled(model.original == nil)
                        Text("原始文件导出保持原始字节；RAW 不包含胶片效果。")
                    } label: {
                        if model.exporting { ProgressView() } else { Text("导出").fontWeight(.semibold) }
                    }.disabled(model.asset == nil || model.loading || model.exporting)
                }
            }
            .tint(accent)
            .disabled(model.exporting)
            .overlay {
                if model.exporting {
                    VStack(spacing: 12) {
                        ProgressView(value:model.exportProgress).frame(width:180)
                        Text("全尺寸光谱显影 · \(Int(model.exportProgress*100))%").font(.subheadline)
                        Button("取消"){model.cancelExport()}.font(.caption).disabled(false)
                    }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .onChange(of:selectedPhoto){_,item in
                if let item{Task{do{guard let data=try await item.loadTransferable(type:Data.self) else{throw AppError.unreadableImage};let asset=try await library.add(data:data,label:"相册原片");model.load(asset,store:library)}catch{model.error=error.localizedDescription}}}
            }
            .fileImporter(isPresented: $importingCube, allowedContentTypes: [.init(filenameExtension: "cube") ?? .data]) { result in
                switch result {
                case .success(let url): model.importCube(url)
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .alert("未能完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("知道了", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .alert("已保存", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("好", role: .cancel) { model.notice = nil }
            } message: { Text(model.notice ?? "") }
            .confirmationDialog("恢复所有参数，并移除当前 LUT？", isPresented: $showReset, titleVisibility: .visible) {
                Button("恢复初始配方", role: .destructive) { model.reset() }
            }
            .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.cleanupShare() } })) {
                if let url = model.shareURL { SharePanel(urls:[url]+(model.sidecarURL.map{[$0]} ?? [])) }
            }
            .sheet(isPresented: $showAbout) { about }
            .sheet(isPresented:$showBracket){bracketSheet}
        }
    }

    private var header:some View {
        StudioHeading(number:"02",title:"把光，慢慢显影。",subtitle:"GRAINROOM / DARKROOM")
    }

    private var photoStage: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(Color.black)
                if let image = comparing ? model.original : model.preview {
                    Image(uiImage: image).resizable().scaledToFit().padding(12)
                        .accessibilityLabel(comparing ? "原始照片" : "处理后的照片")
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding:.current, photoLibrary: .shared()) {
                        VStack(spacing: 18) {
                            FilmIllustration().frame(width:260,height:190)
                            Text("装入第一张底片").font(.system(size:20,weight:.medium,design:.serif))
                            Text("开启你的第一张暗房作品").font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.disabled(model.loading)
                }
                if model.loading { ProgressView("正在读取照片").padding().background(.regularMaterial, in: Capsule()) }
                if model.rendering && !model.loading {
                    VStack { HStack { Spacer(); ProgressView().padding(12).background(.ultraThinMaterial, in: Circle()) }; Spacer() }.padding(10)
                }
                if comparing {
                    VStack { Spacer(); Text("原图").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6).background(.regularMaterial, in: Capsule()).padding(20) }
                }
            }.aspectRatio(0.88, contentMode: .fit).clipped()
            if model.original != nil {
                HStack {
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding:.current, photoLibrary: .shared()) {
                        Label("换一张", systemImage: "photo.on.rectangle")
                    }.disabled(model.loading)
                    Spacer()
                    Button { comparing.toggle() } label: {
                        Label(comparing ? "查看成片" : "对比原图", systemImage: "rectangle.on.rectangle")
                    }.accessibilityValue(comparing ? "正在显示原图" : "正在显示成片")
                }.font(.caption).padding(14).foregroundStyle(accent)
            }
        }.background(panel).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.recipe.customBW?.name ?? "胶片与印相").font(.headline)
                Spacer()
                Button("导入 LUT") { importingCube = true }.font(.caption)
            }
            if let cube = model.cube {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cube.name).font(.subheadline).lineLimit(2)
                        Text("自定义 LUT 模式 · sRGB → sRGB").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.removeCube() } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("返回光谱引擎")
                }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 12))
                Text("当前为独立 LUT 模式，曝光与混合强度有效；颗粒、光晕和显影参数仅适用于光谱模式。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    Picker("胶片", selection: $model.recipe.stock) {
                        ForEach(Stock.allCases) { stock in Text(stock.name).tag(stock) }
                    }
                    if !model.recipe.stock.positive && !model.recipe.scanFilm {
                        Picker("相纸 / 印片", selection: $model.recipe.paper) {
                            ForEach(Paper.allCases) { paper in Text(paper.rawValue).tag(paper) }
                        }
                    }
                    Toggle("直接扫描胶片", isOn: Binding(
                        get: { model.recipe.scanFilm || model.recipe.stock.positive },
                        set: { model.recipe.scanFilm = $0 }
                    )).disabled(model.recipe.stock.positive)
                    Text(model.recipe.stock.positive ? "反转片自动直接扫描，跳过印相。" : "关闭直接扫描时，执行底片 → 印相 → 扫描。")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.subheadline).padding(16).background(panel, in: RoundedRectangle(cornerRadius: 12))
                if model.recipe.customBW != nil {Button("返回原厂黑白配方"){model.recipe.customBW=nil}.font(.caption)}
                Text("spektrafilm 光谱模型 · 81 波长采样 · 原生 Rust CPU 双精度")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.recipe.stock) { _, stock in
            if stock.id != "kodak_doublex" {model.recipe.customBW=nil}
            if let paper = Paper.allCases.first(where: { $0.id == stock.targetPrint }) { model.recipe.paper = paper }
            model.recipe.scanFilm = stock.positive
        }
    }

    private var adjustments: some View {
        VStack(spacing: 18) {
            HStack {
                Text("暗房调校").font(.headline)
                Spacer()
                Button("重置") { showReset = true }.font(.caption)
            }
            control("曝光", symbol: "plusminus.circle", value: $model.recipe.exposure, range: -2...2, text: String(format: "%+.1f EV", model.recipe.exposure))
            Group {
            control("黄滤镜", symbol: "thermometer.medium", value: $model.recipe.warmth, range: -1...1, text: String(format: "%+.0f", model.recipe.warmth * 15))
            control("颗粒", symbol: "circle.dotted", value: $model.recipe.grain, range: 0...2, text: "\(Int(model.recipe.grain * 100))")
            control("光晕", symbol: "sun.haze", value: $model.recipe.halation, range: 0...2, text: "\(Int(model.recipe.halation * 100))")
                DisclosureGroup("更多物理参数") {
                    VStack(spacing: 18) {
                        Toggle("自动曝光", isOn: $model.recipe.autoExposure).font(.subheadline)
                        control("DIR 耦合剂", symbol: "circle.hexagongrid", value: $model.recipe.dirCouplers, range: 0...2, text: String(format: "%.2f", model.recipe.dirCouplers))
                        control("印相曝光", symbol: "lightbulb", value: $model.recipe.printExposure, range: -2...2, text: String(format: "%+.1f EV", model.recipe.printExposure))
                        control("品红滤镜", symbol: "camera.filters", value: $model.recipe.magenta, range: -30...30, text: String(format: "%+.0f", model.recipe.magenta))
                        control("胶片画幅", symbol: "rectangle", value: $model.recipe.filmFormat, range: 16...70, text: String(format: "%.0f mm", model.recipe.filmFormat))
                        control("相纸预闪", symbol: "bolt", value: $model.recipe.preflash, range: 0...0.1, text: String(format: "%.3f", model.recipe.preflash))
                        control("扫描锐化", symbol: "viewfinder", value: $model.recipe.scannerSharpness, range: 0...2, text: String(format: "%.2f", model.recipe.scannerSharpness))
                    }.padding(.top, 18)
                }.font(.subheadline)
            }.disabled(model.cube != nil).opacity(model.cube == nil ? 1 : 0.45)
            control("混合强度", symbol: "drop.halffull", value: $model.recipe.intensity, range: 0...1, text: "\(Int(model.recipe.intensity * 100))%")
        }.padding(18).background(panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func control(_ name: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Label(name, systemImage: symbol).font(.subheadline)
                Spacer()
                Text(text).font(.caption.monospacedDigit()).foregroundStyle(accent)
            }
            Slider(value: value, in: range).accessibilityLabel(name).accessibilityValue(text)
        }
    }

    private var printOptions:some View {
        VStack(alignment:.leading,spacing:15){
            HStack{Text("片边与日期背").font(.headline);Spacer();Image(systemName:"film.stack").foregroundStyle(accent)}
            Picker("画幅",selection:$model.recipe.printStyle.aspect){ForEach(FilmAspect.allCases){Text($0.rawValue).tag($0)}}
            Picker("片边",selection:$model.recipe.printStyle.border){ForEach(FilmBorder.allCases){Text($0.rawValue).tag($0)}}
            Picker("日期曝光",selection:$model.recipe.printStyle.dateStyle){ForEach(DateImprint.allCases){Text($0.rawValue).tag($0)}}
            if model.recipe.printStyle.dateStyle != .none{
                DatePicker("日期",selection:$model.recipe.printStyle.capturedAt,displayedComponents:.date).font(.subheadline)
            }
            if model.recipe.printStyle.dateStyle == .custom || model.recipe.printStyle.border == .instant{
                TextField("底片上的一句话",text:$model.recipe.printStyle.caption).textFieldStyle(.roundedBorder)
            }
            Stepper("第 \(model.recipe.printStyle.frameNumber) 格",value:$model.recipe.printStyle.frameNumber,in:1...999).font(.subheadline)
            Text("原画幅保留全部像素；选择其他画幅会居中裁切。片边在画面外添加，日期印在成片内。").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(panel,in:RoundedRectangle(cornerRadius:14))
    }
    private var bracketSheet:some View {
        NavigationStack{
            ScrollView{
                VStack(spacing:18){
                    StudioHeading(number:"±",title:"找到你的那一档。",subtitle:"EXPOSURE / TEST STRIP")
                    if model.preparingBracket{ProgressView("正在显影曝光试条…")}
                    ForEach(Array(model.bracketImages.enumerated()),id:\.offset){i,image in
                        VStack(alignment:.leading){Text(["−1 EV","0 EV","+1 EV"][i]).font(.caption.monospaced()).foregroundStyle(accent);Image(uiImage:image).resizable().scaledToFit()}
                    }
                    Button("分享接触印样"){
                        if let url=ContactSheet.render(images:model.bracketImages,labels:["−1 EV","0 EV","+1 EV"]){model.shareURL=url;showBracket=false}
                    }.disabled(model.bracketImages.count != 3)
                }.padding(20)
            }.background(StudioTheme.background).toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){showBracket=false}}}
        }
    }
    private var about:some View {
        NavigationStack{
            List{
                Section("GRAINROOM / 0.3"){
                    Text("免费开源的胶片相机、光谱暗房、观片台与黑白制片室。照片和配方保存在本机，无账号、无广告。")
                }
                Section("隐私"){NavigationLink("隐私政策"){LicenseText(name:"PRIVACY")}}
                Section("原片与成片"){
                    Text("相机按镜头能力请求最高分辨率 HEIF、JPEG、Apple ProRAW 或 Bayer RAW，并核验实际尺寸。原始 DNG 可原样导出；胶片效果输出为 HEIF、JPEG、16 位 PNG 或 TIFF，不能把调色后的像素重新变成传感器 RAW。")
                    Text("全尺寸光谱导出采用带重叠的分块计算，保持原始像素与物理画幅。无限空间滤波的边界使用有限重叠近似，随机颗粒不保证与整图计算逐像素一致。预览最长边 768px。")
                }
                Section("模型与许可"){
                    Text("使用 spektrafilm-rs CPU f64 光谱模型，包含光谱重建、密度曲线、DIR、乳剂颗粒、光晕、印相和扫描。自制黑白配方在 Double-X 测量数据上改变波段感光响应，不代表实际生产或校准过的新胶片。")
                    Link("spektrafilm · Andrea Volpato",destination:URL(string:"https://github.com/andreavolpato/spektrafilm")!)
                    Link("spektrafilm-rs · Rust 移植",destination:URL(string:"https://github.com/turbasvin/spektrafilm-rs")!)
                    Text("源码 GPL-3.0-only；实测 profiles 与其派生数据 CC BY-SA 4.0。本软件不提供担保，允许依许可复制、修改和再分发。")
                    NavigationLink("GPLv3 全文"){LicenseText(name:"LICENSE")}
                    NavigationLink("模型数据许可"){LicenseText(name:"SPEKTRAFILM_LICENSE")}
                    NavigationLink("第三方组件许可"){LicenseText(name:"DEPENDENCIES")}
                }
                Section("观片台"){
                    Text("负片视图是由照片生成的数字反相预览，用于排片与比较。接触印样为分享用缩略图，不代替全尺寸导出。原始文件保持元数据；成片不复制定位信息。")
                }
            }.navigationTitle("关于暗房").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){showAbout=false}}}
        }.tint(accent)
    }

}

private struct LicenseText: View {
    let name: String
    var body: some View {
        ScrollView {
            Text(contents).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding()
        }.navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    }
    private var contents: String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Legal"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可文件未找到，请查阅源码包中的许可。" }
        return text
    }
}
