import Foundation

nonisolated enum BackgroundStyle: String, CaseIterable, Sendable {
    case aurora
    case starfield
    case ember
    case contours
    case caustics
    case fireflies
    case rainWindow
    case pixelDither
    case retroHorizon
    case ascii
    case black
    case solid
    case pulse

    var title: String {
        switch self {
        case .aurora: String(localized: "Aurora")
        case .starfield: String(localized: "Sternenhimmel")
        case .ember: String(localized: "Glut")
        case .contours: String(localized: "Höhenlinien")
        case .caustics: String(localized: "Tiefsee")
        case .fireflies: String(localized: "Glühwürmchen")
        case .rainWindow: String(localized: "Regen am Fenster")
        case .pixelDither: String(localized: "Pixel")
        case .retroHorizon: String(localized: "Retro-Horizont")
        case .ascii: String(localized: "ASCII")
        case .black: String(localized: "Schwarz")
        case .solid: String(localized: "Farbe")
        case .pulse: String(localized: "Puls")
        }
    }

    var symbol: String {
        switch self {
        case .aurora: "lightspectrum.horizontal"
        case .starfield: "moon.stars"
        case .ember: "flame"
        case .contours: "mountain.2"
        case .caustics: "water.waves"
        case .fireflies: "sparkle"
        case .rainWindow: "cloud.rain"
        case .pixelDither: "square.grid.3x3"
        case .retroHorizon: "sun.horizon"
        case .ascii: "apple.terminal"
        case .black: "circle.fill"
        case .solid: "paintpalette"
        case .pulse: "waveform.path"
        }
    }
}

nonisolated extension BackgroundStyle {
    var usesTint: Bool { self == .solid || self == .pulse }
}

nonisolated enum PulseTempo: String, CaseIterable, Sendable {
    case calm
    case medium
    case lively

    var title: String {
        switch self {
        case .calm: String(localized: "Ruhig")
        case .medium: String(localized: "Mittel")
        case .lively: String(localized: "Lebhaft")
        }
    }

    var breathsPerSecond: Double {
        switch self {
        case .calm: 0.08
        case .medium: 0.16
        case .lively: 0.32
        }
    }
}

nonisolated struct BackgroundTint: Codable, Hashable, Sendable {
    static let palette = ["#1E3A5F", "#16424A", "#1F4D3A", "#4A3B1C", "#5A2A1E", "#4B1F3F", "#33265C", "#2B2F36"]
    static let brightnessRange: ClosedRange<Double> = 0.15...1

    var hex: String?
    var brightness: Double?
    var gradient: Bool?
    var tempo: String?
    var reactive: Bool?

    init(hex: String? = nil, brightness: Double? = nil, gradient: Bool? = nil, tempo: String? = nil, reactive: Bool? = nil) {
        self.hex = hex
        self.brightness = brightness
        self.gradient = gradient
        self.tempo = tempo
        self.reactive = reactive
    }

    init(json: String?) {
        self = json.flatMap { try? JSONDecoder().decode(Self.self, from: Data($0.utf8)) } ?? Self()
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    var resolvedHex: String {
        guard let hex, Self.rgb(hex) != nil else { return Self.palette[0] }
        return hex
    }
    var resolvedBrightness: Double { min(max(brightness ?? 0.7, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound) }
    var resolvedGradient: Bool { gradient ?? false }
    var resolvedTempo: PulseTempo { tempo.flatMap(PulseTempo.init(rawValue:)) ?? .calm }
    var resolvedReactive: Bool { reactive ?? true }
    var rgb: (red: Double, green: Double, blue: Double) { Self.rgb(resolvedHex)! }

    static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ channel: Double) -> Int { Int((min(max(channel, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
