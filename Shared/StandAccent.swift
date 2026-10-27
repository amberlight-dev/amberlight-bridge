import SwiftUI

enum StandAccent {
    static let amberHex = "FFC566"
    static let amber = Color(.sRGB, red: 1, green: 0xC5 / 255, blue: 0x66 / 255)

    static let palette: [(name: String, hex: String)] = [
        (String(localized: "Amber"), amberHex),
        (String(localized: "Kobalt"), "6F9BFF"),
        (String(localized: "Lavendel"), "B39DFF"),
        (String(localized: "Magenta"), "F08CDB"),
        (String(localized: "Sand"), "E6D3B3"),
    ]

    static func color(hex: String) -> Color? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(.sRGB,
                     red: Double(value >> 16 & 0xFF) / 255,
                     green: Double(value >> 8 & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    static func hex(of color: Color) -> String {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let components = color.resolve(in: EnvironmentValues()).cgColor
            .converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1]
        return components.prefix(3)
            .map { String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded())) }
            .joined()
    }
}

extension EnvironmentValues {
    @Entry var standAccent: Color?
    @Entry var accentsClock = false
}
