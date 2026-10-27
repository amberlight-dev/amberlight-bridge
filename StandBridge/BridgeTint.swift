import AppKit
import SwiftUI

extension StandAccent {
    static let bridgeTint = Color(nsColor: NSColor(name: "BridgeTint") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0xC7 / 255, green: 0x7A / 255, blue: 0x12 / 255, alpha: 1)
            : NSColor(srgbRed: 0x8F / 255, green: 0x54 / 255, blue: 0, alpha: 1)
    })
}
