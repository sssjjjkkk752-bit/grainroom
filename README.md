# Grainroom · 掌上暗房 0.3

免费开源的 iPhone 胶片相机、光谱暗房、观片台和黑白制片室。SwiftUI + AVFoundation + Core Image + 原生 Rust 光谱引擎，最低 iOS 17。原片、成片和配方在本机保存，无账号、无广告。

## 这一版可以做什么

| 空间 | 功能 |
|---|---|
| 相机 | 查询当前镜头实际能力；请求最高像素 HEIF / JPEG、支持设备上的 Apple ProRAW + HEIF 或 Bayer RAW + JPEG；记录并显示每个文件实际交付尺寸；保留原始文件；36 格计数与随机配方“盲盒胶卷” |
| 暗房 | 真实光谱重建、底片、DIR、三乳剂层颗粒、光晕、印相和扫描；22 种胶片 / 9 种印相材料；全尺寸分块显影、进度和取消；原图对比；−1 / 0 / +1 EV 曝光试条 |
| 片边与日期背 | 135 齿孔、120 黑框、即影即有、电影画格、无边框；原画幅、3:2、半格 3:4、6×6、6×7、65:24；日期、场记、自定义文字和格号 |
| 观片台 | 持久化本机图库；相册 / 文件导入；正片与数字负片预览；0–3 星评级；多选并排比较；分享接触印样或原始文件；可将暗房成片再次放上观片台 |
| 黑白制片室 | 在 Double-X 测量数据上修改红 / 绿 / 蓝波段的光谱感度、显影反差、颗粒和光晕；全色 / 正色 / 红敏实验起点；保存、导入和分享 JSON 乳剂配方 |

取景画面目前是系统原图。拍摄后在暗房执行光谱显影，**没有实现实时光谱取景**。

## 4800 万像素与拍摄格式

相机不按 iPhone 型号硬编码能力，而是查询：

- 当前镜头 activeFormat 的 `supportedMaxPhotoDimensions`。
- `AVCapturePhotoOutput.maxPhotoDimensions`、可用 photo codecs / file types。
- Apple ProRAW 与 Bayer RAW 像素格式及配对处理格式的支持。

“48MP MAX”只在当前镜头声明了至少 4700 万像素的尺寸时显示。拍照设置请求该尺寸，回调后分别检查 DNG / HEIF / JPEG 的真实尺寸。如果系统没有交付请求的 48MP，会明确提示；不把小图放大成 48MP。

不同镜头、RAW 类型和拍摄条件的实际输出可能不同。**本次未连接真实 iPhone，48MP / ProRAW 拍摄代码已编译，但还没有真机拍摄验证。** 模拟器无法替代这项测试。

技术依据：[Apple maxPhotoDimensions](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)、[AVCapturePhotoSettings](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings)。

## 全尺寸导出与 RAW 的含义

| 导出项 | 内容 |
|---|---|
| HEIF / HEIC | 全尺寸、sRGB、8 位成片 |
| JPEG | 全尺寸、sRGB、8 位、97% 品质成片 |
| PNG | 全尺寸、sRGB、16 位成片 |
| TIFF | 全尺寸、sRGB、16 位成片 |
| 原始文件 / RAW | 原始 DNG、HEIF、JPEG 或导入文件的逐字节副本，另附当前暗房配方 JSON |

RAW 导出保留真实的原始文件，**不会把调色后的 RGB 成片伪装成传感器 RAW**。片边、日期和胶片效果写入成片，不改写原始 DNG。导出原始文件时，原有元数据也保留；成片不复制原图 GPS。

保留原画幅时，不缩小原始图像。切换其他画幅会居中裁切；片边在画面之外增加画布像素。当前单张源图上限为 1.1 亿像素，覆盖 48MP iPhone 照片。

HEIF / JPEG / PNG / TIFF 属于此版支持的常用成片格式，不代表支持任意存在的图像容器。RAW 解码由系统 CIRAWFilter 提供；对系统不能解码的 RAW，仍可在观片台分享原始文件。

## 全尺寸显影如何控制内存

- 预览最长边 768px；最终导出从原始文件重新读取，不从预览放大。
- CPU f64 光谱模型逐块处理，输入输出 float32；磁盘映射保存全尺寸输出栅格。
- 每块依据完整画幅设置物理像素尺寸，并带重叠区处理 DIR、光晕和锐化。相同图像只做一次全局测光。
- 不同块采用不同、可复现的颗粒种子；有限重叠近似无限空间滤波尾部。**带空间效果的分块结果不承诺与整图计算逐像素相同。**
- 输出编码和增加片边仍可能占用较多系统内存；48MP 全光谱处理也可能耗时较长。请勿将模拟器速度视为手机性能保证。
- 支持前台进度和取消；单次正在执行的原生计算先完成再响应取消。尚无后台显影任务恢复。

## 运行工程

1. 用 Xcode 打开 `Grainroom.xcodeproj`，选择 `Grainroom` Scheme。
2. 模拟器：安装 iOS runtime，选择一个 iPhone Simulator 并 Run。
3. 真机：在 Signing & Capabilities 选择自己的 Team，修改 Bundle Identifier 为自己的唯一标识，连接已开启开发者模式的 iPhone 后运行。
4. 真机相机权限在进入相机页时请求；保存系统照片图库时才请求添加照片权限。

本地完整交付 ZIP 包含 iPhone arm64 和模拟器 arm64 / x86_64 静态 XCFramework，首次运行无需安装 Rust 或 Python。GitHub 源码仓库不提交大型二进制；克隆仓库后先安装 Rust 并运行 `bash Scripts/build-engine.sh`。尚未配置 App Store、TestFlight、发布证书或签名 IPA。

原始文件、缩略图和图库清单位于 App Documents/GrainroomLibrary；通过系统“文件”可见。当前编辑会话尚未自动恢复，原片、已保存成片和乳剂配方会保留。

## 界面预览

`Preview/` 中为运行中的 iPhone Simulator 截图。预览里的山景是仅用于布局测试的代码生成插画，不是真机拍摄样片。默认运行不会插入这些测试图。

Debug 构建可通过启动参数 `--studio-fixture` 创建布局测试图库，配合 `--light-table` 或 `--emulsion-studio` 预览对应页面。这些辅助逻辑不进入 Release 构建。

## 实际验证与限制

- Xcode 27.2 / iOS 27.2 SDK 下，模拟器和 iPhone 未签名 Release 编译通过。
- iOS 集成测试包含：8064×6048 HEIF 原尺寸导出；HEIF/JPEG/16 位 PNG/TIFF 及片边日期；分块方向、偏移与无空间效果时的整图对照；持久化图库；原始文件逐字节保真；黑白光谱响应；取消导出。
- 41 项 Rust 桥接、数学和模型单元测试通过。
- 31 个胶片 / 印相材料及跨语言边界检查通过。
- 25 组 Python 参考对照通过，固定输入上的最大绝对 RGB 误差约 1.51e-6。
- 报告和本版验证说明在 `Tests/Reports/`。

已验证的是模拟器的导出与软件逻辑。未验证真实 iPhone 的 48MP ProRAW/HEIF 拍摄、低内存设备的 48MP 全特效导出峰值、系统照片权限与分享的完整交互流程，亦未测试所有 iOS 17+ 机型。此版是可编译、经过上述检查的开发版本，不是已完成真机验收的发布版。

## 光谱引擎与开源许可

源码采用 **GPL-3.0-only**。实测 profiles 与其派生数据按 **CC BY-SA 4.0** 提供，原始署名、元数据和许可随源码与 App 保留。

- **spektrafilm by Andrea Volpato**：[原项目](https://github.com/andreavolpato/spektrafilm)
- **turbasvin/spektrafilm-rs**：[原生 Rust 移植](https://github.com/turbasvin/spektrafilm-rs)
- Rust 基础 commit：`9dd59b0380194b93686aaa230a8bb9680aa270a4`
- Python 对照 commit：`3bb2c2d2801ff68b92019cf1dbcbb133d60832bc`

本工程保留完整的照片光谱成像阶段，使用 Hanatos2025、xy 输入色域压缩与 CAM16-UCS 输出压缩，不以预烘焙 RGB LUT 替代光谱管线。不是对 Python GUI、所有实验算法、RAW 桌面工具和 LUT 烘焙器的逐项移植。

本次新增的黑白乳剂通过修改模型感光谱生成实验效果，不声称是校准过、制造出来的实体胶片。自定义 `.cube` 仍为独立模式；原片导出 JSON 不嵌入外部 LUT。

`NativeEngine/vendor/CHANGES.md` 记录光源修正、胶片专属参数、三乳剂层颗粒、分块物理画幅和自制黑白响应的改动。所有原始 JSON profiles、光谱重建数据和中性滤镜数据未修改。

## 从源码构建与测试

重建原生库需要 Rust / rustup 和完整 Xcode：

```sh
bash Scripts/build-engine.sh
```

该脚本使用 `Cargo.lock`，生成三个 Apple 目标的库，并更新 `Frameworks/GrainroomSpectral.xcframework`。旧库保留到 Cargo target staging 目录。

运行 iOS 集成测试（替换为本机模拟器名称或 ID）：

```sh
xcodebuild -project Grainroom.xcodeproj -scheme Grainroom \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

运行 Rust 测试：

```sh
cargo test --locked --release --manifest-path NativeEngine/Cargo.toml \
  -p grainroom-spectral -p spektrafilm-math -p spektrafilm-model
```

Python 对照工具为 `Tests/parity.py`、`Tests/smoke.py`、`Tests/grain_statistics.py`，需要其脚本说明中的 Python 3.13 / numpy / spektrafilm 参考环境，以及本机编译的 macOS 动态库。参考环境不随 App 打包。

图标由 Core Graphics 生成，源文件是 `Scripts/generate-icon.swift`；光源导出源文件为 `Scripts/export-reference-illuminants.py`。完整 GPL 文本在 `LICENSE`，第三方许可在 `Grainroom/Legal/`，应用“关于暗房”中也可阅读。

## 发布状态

公开源码仓库：https://github.com/sssjjjkkk752-bit/grainroom

尚未提交 App Store。当前没有已配置的 Apple Developer Program Team、分发签名或 App Store Connect 应用记录。上架资料草案在 `Release/APP_STORE_METADATA.md`；GPLv3 经 App Store 分发的许可核对记录在 `Release/LICENSING_CLEARANCE.md`。

隐私政策：[docs/privacy.md](docs/privacy.md)。支持：[docs/support.md](docs/support.md)，功能问题可使用仓库 Issues。
