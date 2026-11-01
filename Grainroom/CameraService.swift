// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import SwiftUI

struct CameraLens: Identifiable, Sendable {let id:String;let name:String}
struct CameraCapabilities: Sendable {
    var lenses:[CameraLens]=[]
    var selectedID=""
    var maxWidth=0
    var maxHeight=0
    var heif=false
    var proRAW=false
    var bayerRAW=false
    var supports48MP:Bool {maxWidth*maxHeight>=47_000_000}
}
enum CaptureFormat:String,CaseIterable,Identifiable,Sendable {
    case heif="HEIF",jpeg="JPEG",proRAW="ProRAW + HEIF",bayerRAW="RAW + JPEG"
    var id:String{rawValue}
}
struct CapturedFile:Sendable {let data:Data;let ext:String;let label:String;let width:Int;let height:Int}

final class CameraService:NSObject,@unchecked Sendable {
    let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"Grainroom.camera",qos:.userInitiated)
    private let output=AVCapturePhotoOutput()
    private var input:AVCaptureDeviceInput?
    private var devices:[AVCaptureDevice]=[]
    private var processor:PhotoProcessor?
    var onCapabilities:(@Sendable(CameraCapabilities)->Void)?
    var onResult:(@Sendable(Result<[CapturedFile],Error>)->Void)?
    var onError:(@Sendable(String)->Void)?

    func start() {
        queue.async {
            do {
                if self.input == nil {try self.configure(id:nil)}
                if !self.session.isRunning {self.session.startRunning()}
            } catch {self.onError?(error.localizedDescription)}
        }
    }
    func stop(){queue.async{if self.session.isRunning{self.session.stopRunning()}}}
    func switchLens(_ id:String){queue.async{do{try self.configure(id:id)}catch{self.onError?(error.localizedDescription)}}}

    private func configure(id:String?) throws {
        devices=AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.builtInUltraWideCamera,.builtInTelephotoCamera],mediaType:.video,position:.unspecified).devices
        guard let device=devices.first(where:{$0.uniqueID==id}) ?? devices.first(where:{$0.position == .back && $0.deviceType == .builtInWideAngleCamera}) else {throw AppError.spectral("未找到可用相机；模拟器无法验证真实拍摄")}
        let next=try AVCaptureDeviceInput(device:device)
        session.beginConfiguration();defer{session.commitConfiguration()}
        if let input{session.removeInput(input)}
        guard session.canAddInput(next) else {if let input,session.canAddInput(input){session.addInput(input)};throw AppError.rendering}
        session.addInput(next);input=next
        session.sessionPreset = .photo
        if !session.outputs.contains(output){guard session.canAddOutput(output) else{throw AppError.rendering};session.addOutput(output)}
        try device.lockForConfiguration();defer{device.unlockForConfiguration()}
        // Never infer capabilities from marketing model names. Query this lens.
        if let best=device.formats.max(by:{Self.area($0)<Self.area($1)}) {
            device.activeFormat=best
        }
        if device.minAvailableVideoZoomFactor<=1 && device.maxAvailableVideoZoomFactor>=1 {device.videoZoomFactor=1}
        output.maxPhotoQualityPrioritization = .quality
        output.isAppleProRAWEnabled=output.isAppleProRAWSupported
        let dimensions=device.activeFormat.supportedMaxPhotoDimensions
        if let largest=dimensions.max(by:{Int64($0.width)*Int64($0.height)<Int64($1.width)*Int64($1.height)}) {output.maxPhotoDimensions=largest}
        if let c=output.connection(with:.video),c.isVideoRotationAngleSupported(90){c.videoRotationAngle=90}
        var caps=CameraCapabilities()
        caps.selectedID=device.uniqueID
        caps.lenses=devices.map{CameraLens(id:$0.uniqueID,name:Self.lensName($0))}
        caps.maxWidth=Int(output.maxPhotoDimensions.width);caps.maxHeight=Int(output.maxPhotoDimensions.height)
        caps.heif=output.availablePhotoCodecTypes.contains(.hevc) && output.availablePhotoFileTypes.contains(.heic)
        caps.proRAW=output.isAppleProRAWEnabled && output.availableRawPhotoPixelFormatTypes.contains(where:AVCapturePhotoOutput.isAppleProRAWPixelFormat)
        if #available(iOS 18.0,*),let type=output.availableRawPhotoPixelFormatTypes.first(where:AVCapturePhotoOutput.isAppleProRAWPixelFormat){
            caps.proRAW = caps.proRAW && output.supportedRawPhotoCodecTypes(forRawPhotoPixelFormatType:type,fileType:.heic).contains(.hevc)
        }
        caps.bayerRAW=output.availableRawPhotoPixelFormatTypes.contains(where:AVCapturePhotoOutput.isBayerRAWPixelFormat)
        onCapabilities?(caps)
    }
    private static func area(_ f:AVCaptureDevice.Format)->Int64{f.supportedMaxPhotoDimensions.map{Int64($0.width)*Int64($0.height)}.max() ?? 0}
    private static func lensName(_ d:AVCaptureDevice)->String {
        if d.position == .front{return "前置"}
        switch d.deviceType {case .builtInUltraWideCamera:return "超广角";case .builtInTelephotoCamera:return "长焦";default:return "主摄"}
    }

    func capture(format:CaptureFormat,maxResolution:Bool) {
        queue.async {
            do {
                guard self.processor == nil,let device=self.input?.device,self.session.isRunning else {throw AppError.spectral("相机尚未准备好")}
                let settings:AVCapturePhotoSettings
                switch format {
                case .heif:
                    guard self.output.availablePhotoCodecTypes.contains(.hevc) else {throw AppError.spectral("此镜头不支持 HEIF 拍摄")}
                    settings=AVCapturePhotoSettings(format:[AVVideoCodecKey:AVVideoCodecType.hevc])
                case .jpeg:settings=AVCapturePhotoSettings(format:[AVVideoCodecKey:AVVideoCodecType.jpeg])
                case .proRAW:
                    guard self.output.isAppleProRAWEnabled,let raw=self.output.availableRawPhotoPixelFormatTypes.first(where:AVCapturePhotoOutput.isAppleProRAWPixelFormat),self.output.availableRawPhotoFileTypes.contains(.dng) else{throw AppError.spectral("当前镜头不支持 Apple ProRAW")}
                    if #available(iOS 18.0,*) {
                        guard self.output.supportedRawPhotoCodecTypes(forRawPhotoPixelFormatType:raw,fileType:.heic).contains(.hevc) else{throw AppError.spectral("当前 ProRAW 模式不支持同时输出 HEIF")}
                    }
                    settings=AVCapturePhotoSettings(rawPixelFormatType:raw,rawFileType:.dng,processedFormat:[AVVideoCodecKey:AVVideoCodecType.hevc],processedFileType:.heic)
                case .bayerRAW:
                    guard let raw=self.output.availableRawPhotoPixelFormatTypes.first(where:AVCapturePhotoOutput.isBayerRAWPixelFormat),self.output.availableRawPhotoFileTypes.contains(.dng) else{throw AppError.spectral("当前镜头不支持 Bayer RAW")}
                    settings=AVCapturePhotoSettings(rawPixelFormatType:raw,rawFileType:.dng,processedFormat:[AVVideoCodecKey:AVVideoCodecType.jpeg],processedFileType:.jpg)
                }
                let valid=device.activeFormat.supportedMaxPhotoDimensions.filter{maxResolution || Int64($0.width)*Int64($0.height)<=13_500_000}
                guard let dimensions=(maxResolution ? valid.max(by:{Int64($0.width)*Int64($0.height)<Int64($1.width)*Int64($1.height)}):valid.max(by:{Int64($0.width)*Int64($0.height)<Int64($1.width)*Int64($1.height)})) ?? device.activeFormat.supportedMaxPhotoDimensions.first else{throw AppError.rendering}
                settings.maxPhotoDimensions=dimensions
                settings.photoQualityPrioritization = format == .bayerRAW ? .speed:.quality
                if self.output.supportedFlashModes.contains(AVCaptureDevice.FlashMode.off){settings.flashMode = .off}
                let processor=PhotoProcessor(format:format){[weak owner = self] result in
                    guard let owner else{return}
                    owner.queue.async{[weak owner] in owner?.processor=nil;owner?.onResult?(result)}
                }
                self.processor=processor
                self.output.capturePhoto(with:settings,delegate:processor)
            } catch {self.onResult?(.failure(error))}
        }
    }
}

private final class PhotoProcessor:NSObject,AVCapturePhotoCaptureDelegate,@unchecked Sendable {
    private let lock=NSLock()
    private var files:[CapturedFile]=[]
    private var error:Error?
    private let format:CaptureFormat
    private let done:@Sendable(Result<[CapturedFile],Error>)->Void
    init(format:CaptureFormat,done:@escaping @Sendable(Result<[CapturedFile],Error>)->Void){self.format=format;self.done=done}
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?){
        lock.lock();defer{lock.unlock()}
        if let error{self.error=error;return}
        guard let data=photo.fileDataRepresentation() else{self.error=AppError.unreadableImage;return}
        let dims=photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions:photo.resolvedSettings.photoDimensions
        let ext=photo.isRawPhoto ? "dng":((format == .heif || format == .proRAW) ? "heic":"jpg")
        let name=photo.isRawPhoto ? (format == .proRAW ? "Apple ProRAW":"Bayer RAW"):ext.uppercased()
        files.append(CapturedFile(data:data,ext:ext,label:name,width:Int(dims.width),height:Int(dims.height)))
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishCaptureFor resolvedSettings:AVCaptureResolvedPhotoSettings,error:Error?){
        lock.lock();let captured=files;let failure=error ?? self.error;lock.unlock()
        if let failure{done(.failure(failure))}else if captured.isEmpty{done(.failure(AppError.unreadableImage))}else{done(.success(captured))}
    }
}

@MainActor
final class CameraModel:ObservableObject {
    let service=CameraService()
    @Published var capabilities=CameraCapabilities()
    @Published var format:CaptureFormat = .heif
    @Published var maxResolution=true
    @Published var capturing=false
    @Published var authorized=false
    @Published var message=""
    var onFiles:(([CapturedFile])->Void)?
    init(){
        service.onCapabilities={[weak self] caps in Task{@MainActor in
            self?.capabilities=caps
            if self?.format == .heif && !caps.heif {self?.format = .jpeg}
            if self?.format == .proRAW && !caps.proRAW {self?.format = caps.heif ? .heif:.jpeg}
            if self?.format == .bayerRAW && !caps.bayerRAW {self?.format = caps.heif ? .heif:.jpeg}
        }}
        service.onResult={[weak self] result in Task{@MainActor in
            guard let self else{return};self.capturing=false
            switch result {case .failure(let e):self.message=e.localizedDescription
            case .success(let files):
                self.message=files.map{String(format:"%@ %.1fMP",$0.label,Double($0.width*$0.height)/1e6)}.joined(separator:" + ")+" · 原片已保留"
                if self.maxResolution && self.capabilities.supports48MP && files.contains(where:{$0.width*$0.height<47_000_000}){self.message += "。系统此次未交付 48MP"}
                self.onFiles?(files)
            }
        }}
        service.onError={[weak self] error in Task{@MainActor in self?.message=error}}
    }
    func start() async{
        let status=AVCaptureDevice.authorizationStatus(for:.video)
        if status == .authorized {authorized=true}
        else if status == .notDetermined {authorized=await AVCaptureDevice.requestAccess(for:.video)}
        else {authorized=false}
        if authorized{service.start()}else{message="请到系统设置允许相机访问。观片台和照片暗房仍可使用。"}
    }
    func shoot(){guard !capturing else{return};capturing=true;service.capture(format:format,maxResolution:maxResolution)}
}

struct CameraPreview:UIViewRepresentable {
    let session:AVCaptureSession
    final class Preview:UIView {override class var layerClass:AnyClass{AVCaptureVideoPreviewLayer.self};var preview:AVCaptureVideoPreviewLayer{layer as! AVCaptureVideoPreviewLayer}}
    func makeUIView(context:Context)->Preview{let v=Preview();v.preview.session=session;v.preview.videoGravity = .resizeAspectFill;return v}
    func updateUIView(_ view:Preview,context:Context){if let c=view.preview.connection,c.isVideoRotationAngleSupported(90){c.videoRotationAngle=90}}
}
