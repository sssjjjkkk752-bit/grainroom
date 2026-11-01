// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

struct BWEmulsion: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = "我的银盐 01"
    var red = 1.0
    var green = 1.0
    var blue = 1.0
    var contrast = 1.0
    var grain = 1.0
    var halation = 0.4
}

enum FilmBorder: String, CaseIterable, Codable, Identifiable {
    case none = "无片边", perforated = "135 齿孔", medium = "120 黑框", instant = "即影即有", cinema = "电影画格"
    var id: String { rawValue }
}

enum FilmAspect: String, CaseIterable, Codable, Identifiable {
    case original = "原画幅", full = "135 · 3:2", half = "半格 · 3:4", square = "6×6 · 1:1", sixSeven = "6×7", panoramic = "宽幅 · 65:24"
    var id: String { rawValue }
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .full: return 1.5
        case .half: return 0.75
        case .square: return 1
        case .sixSeven: return 6/7
        case .panoramic: return 65/24
        }
    }
}

enum DateImprint: String, CaseIterable, Codable, Identifiable {
    case none = "不印日期", classic = "年月日", cinema = "场记字样", custom = "自定义文字"
    var id: String { rawValue }
}

struct PrintStyle: Codable, Equatable, Sendable {
    var border: FilmBorder = .perforated
    var aspect: FilmAspect = .original
    var dateStyle: DateImprint = .none
    var caption = "GOOD LIGHT, SLOW DAYS"
    var frameNumber = 1
    var capturedAt = Date()
}

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case heif = "HEIF", jpeg = "JPEG", png = "PNG · 16 位", tiff = "TIFF · 16 位", original = "原始文件 / RAW"
    var id: String { rawValue }
    var fileExtension: String {
        switch self { case .heif: return "heic"; case .jpeg: return "jpg"; case .png: return "png"; case .tiff: return "tiff"; case .original: return "dng" }
    }
    var type: UTType {
        switch self { case .heif: return .heic; case .jpeg: return .jpeg; case .png: return .png; case .tiff: return .tiff; case .original: return .rawImage }
    }
    var sixteenBit: Bool { self == .png || self == .tiff }
}

struct PhotoAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var thumbnailName: String
    var negativeName: String
    var createdAt: Date
    var width: Int
    var height: Int
    var label: String
    var isRAW: Bool
    var rating = 0
    var sizeLabel: String { String(format: "%.1f MP", Double(width * height) / 1_000_000) }
}

enum StudioTheme {
    static let background = Color(red: 0.055, green: 0.064, blue: 0.061)
    static let surface = Color(red: 0.095, green: 0.108, blue: 0.101)
    static let amber = Color(red: 0.94, green: 0.71, blue: 0.40)
    static let mint = Color(red: 0.70, green: 0.80, blue: 0.68)
    static let cream = Color(red: 0.92, green: 0.90, blue: 0.84)
}
