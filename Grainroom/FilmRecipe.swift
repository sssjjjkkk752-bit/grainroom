// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct FilmRecipe: Codable, Equatable, Sendable {
    var stock: Stock = .daylight
    var paper: Paper = .soft
    var exposure: Double = 0
    var warmth: Double = 0
    var grain: Double = 1
    var halation: Double = 1
    var intensity: Double = 1
    var dirCouplers: Double = 1
    var printExposure: Double = 0
    var magenta: Double = 0
    var filmFormat: Double = 35
    var preflash: Double = 0
    var scannerSharpness: Double = 0.7
    var autoExposure = false
    var scanFilm = false
    var customBW: BWEmulsion?
    var printStyle = PrintStyle()

    // Core Image provides linear sRGB floats. Only the physical engine encodes output.
    func spectralJSON() throws -> String {
        var params: [String: Any] = [
            "io": ["input_color_space": "sRGB", "input_cctf_decoding": false,
                   "output_color_space": "sRGB", "output_cctf_encoding": true,
                   "scan_film": scanFilm || stock.positive],
            "camera": ["auto_exposure": autoExposure, "exposure_compensation_ev": exposure,
                       "film_format_mm": filmFormat],
            "enlarger": ["print_exposure": pow(2, printExposure), "y_filter_shift": warmth * 15,
                         "m_filter_shift": magenta, "preflash_exposure": preflash],
            "film_render": [
                "grain": ["active": grain > 0, "agx_particle_area_um2": 0.2 * max(0.01, grain)],
                "halation": ["active": halation > 0, "halation_amount": halation],
                "dir_couplers": ["active": dirCouplers > 0, "amount": dirCouplers]],
            "scanner": ["unsharp_mask": [0.7, scannerSharpness]],
            "settings": ["use_enlarger_lut": false, "use_scanner_lut": false,
                         "rgb_to_raw_method": "hanatos2025"]
        ]
        if let bw=customBW {
            params["grainroom_custom_bw"]=["red":bw.red,"green":bw.green,"blue":bw.blue,"contrast":bw.contrast]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys]), as: UTF8.self)
    }
}

struct Stock: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let note: String
    let positive: Bool
    let targetPrint: String
    static var daylight: Stock { allCases.first { $0.id == "kodak_portra_400" }! }
    static let allCases: [Stock] = [
        Stock(id: "kodak_portra_400", name: "Kodak Portra 400", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "fujifilm_c200", name: "Fujifilm C200", note: "彩色负片", positive: false, targetPrint: "fujifilm_crystal_archive_typeii"),
        Stock(id: "fujifilm_pro_400h", name: "Fujifilm Pro 400H", note: "彩色负片", positive: false, targetPrint: "fujifilm_crystal_archive_typeii"),
        Stock(id: "fujifilm_provia_100f", name: "Fujifilm Provia 100F", note: "彩色反转片", positive: true, targetPrint: "kodak_portra_endura"),
        Stock(id: "fujifilm_velvia_100", name: "Fujifilm Velvia 100", note: "彩色反转片", positive: true, targetPrint: "kodak_portra_endura"),
        Stock(id: "fujifilm_xtra_400", name: "Fujifilm X-Tra 400", note: "彩色负片", positive: false, targetPrint: "fujifilm_crystal_archive_typeii"),
        Stock(id: "kodak_doublex", name: "Kodak Double-X Negative Film 5222", note: "黑白负片", positive: false, targetPrint: "kodak_2302"),
        Stock(id: "kodak_ektachrome_100", name: "Kodak Ektachrome 100", note: "彩色反转片", positive: true, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_ektar_100", name: "Kodak Ektar 100", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_gold_200", name: "Kodak Gold 200", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_kodachrome_64", name: "Kodak Kodachrome 64", note: "彩色反转片", positive: true, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_portra_160", name: "Kodak Portra 160", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_portra_800", name: "Kodak Portra 800", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_portra_800_push1", name: "Kodak Portra 800 (Push 1)", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_portra_800_push2", name: "Kodak Portra 800 (Push 2)", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_trix", name: "Kodak Tri-X Reversal Film 7266", note: "黑白反转片", positive: true, targetPrint: "kodak_2302"),
        Stock(id: "kodak_ultramax_400", name: "Kodak Ultramax 400", note: "彩色负片", positive: false, targetPrint: "kodak_portra_endura"),
        Stock(id: "kodak_verita_200d", name: "Kodak Verita 200D", note: "彩色负片", positive: false, targetPrint: "kodak_2383"),
        Stock(id: "kodak_vision3_200t", name: "Kodak Vision3 200T", note: "彩色负片", positive: false, targetPrint: "kodak_2383"),
        Stock(id: "kodak_vision3_250d", name: "Kodak Vision3 250D", note: "彩色负片", positive: false, targetPrint: "kodak_2383"),
        Stock(id: "kodak_vision3_500t", name: "Kodak Vision3 500T", note: "彩色负片", positive: false, targetPrint: "kodak_2383"),
        Stock(id: "kodak_vision3_50d", name: "Kodak Vision3 50D", note: "彩色负片", positive: false, targetPrint: "kodak_2383"),
    ]
}

struct Paper: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let rawValue: String
    static var soft: Paper { allCases.first { $0.id == "kodak_portra_endura" }! }
    static let allCases: [Paper] = [
        Paper(id: "fujifilm_crystal_archive_typeii", rawValue: "Fujifilm Crystal Archive Type II"),
        Paper(id: "kodak_ektacolor_edge", rawValue: "Kodak Ektacolor Edge"),
        Paper(id: "kodak_2302", rawValue: "Kodak Print Film 2302"),
        Paper(id: "kodak_endura_premier", rawValue: "Kodak Professional Endura Premier"),
        Paper(id: "kodak_portra_endura", rawValue: "Kodak Professional Portra Endura"),
        Paper(id: "kodak_supra_endura", rawValue: "Kodak Professional Supra Endura"),
        Paper(id: "kodak_ultra_endura", rawValue: "Kodak Professional Ultra Endura"),
        Paper(id: "kodak_2383", rawValue: "Kodak Vision 2383"),
        Paper(id: "kodak_2393", rawValue: "Kodak Vision Premier 2393"),
    ]
}

struct CubeLUT: Sendable {
    let name: String
    let dimension: Int
    let data: Data

    // .cube uses red-fastest ordering, matching CIColorCube. Require an explicit
    // 0...1 domain; silently accepting log or extended domains would alter colour.
    init(text: String, name: String) throws {
        var size: Int?
        var rows = [[Float]]()
        for source in text.components(separatedBy: .newlines) {
            let line = source.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            switch parts[0] {
            case "TITLE": continue
            case "LUT_3D_SIZE":
                guard size == nil, parts.count == 2, let n = Int(parts[1]), (2...64).contains(n) else { throw AppError.invalidCube }
                size = n
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let expected: Float = parts[0] == "DOMAIN_MIN" ? 0 : 1
                guard parts.count == 4, parts.dropFirst().allSatisfy({ Float($0) == expected }) else { throw AppError.cubeDomain }
            default:
                guard parts.count == 3 else { throw AppError.invalidCube }
                let values = parts.compactMap(Float.init)
                guard values.count == 3, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw AppError.invalidCube }
                rows.append(values)
                guard rows.count <= 64 * 64 * 64 else { throw AppError.invalidCube }
            }
        }
        guard let n = size, rows.count == n * n * n else { throw AppError.invalidCube }
        var rgba = [Float]()
        rgba.reserveCapacity(rows.count * 4)
        for row in rows { rgba.append(contentsOf: row); rgba.append(1) }
        self.name = name
        dimension = n
        data = rgba.withUnsafeBytes { Data($0) }
    }
}

enum AppError: LocalizedError {
    case spectral(String)
    case unreadableImage, rawUnsupported, rendering, invalidCube, cubeDomain, photoPermission
    var errorDescription: String? {
        switch self {
        case .spectral(let message): return "光谱引擎：\(message)"
        case .unreadableImage: return "无法读取这张照片，请选择 JPEG、HEIC 或 PNG。"
        case .rawUnsupported: return "系统无法解码此 RAW。原始文件仍可保留与导出；可选择配对的 HEIF 或 JPEG 进入暗房。"
        case .rendering: return "照片处理失败，请重试或选择较小的照片。"
        case .invalidCube: return "LUT 格式不支持。请选择 2–64 阶、数值位于 0–1 的标准 3D .cube 文件。"
        case .cubeDomain: return "此 LUT 的输入范围不是 0–1，暂不支持。"
        case .photoPermission: return "尚未获得保存权限。请到系统设置中允许添加照片，或使用分享导出。"
        }
    }
}
