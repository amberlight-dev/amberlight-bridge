import SwiftUI

enum WidgetInk {
    static let ember = Color(red: 0.85, green: 0.12, blue: 0.08).opacity(0.5)
    static let alarm = Color(red: 1, green: 0.42, blue: 0.38)
    static let calm = Color(red: 0.45, green: 0.86, blue: 0.62)
    static let busy = Color(red: 1, green: 0.78, blue: 0.36)

    static func text(_ opacity: Double, dimmed: Bool) -> Color {
        dimmed ? ember : .white.opacity(opacity)
    }

    static func accent(_ color: Color, dimmed: Bool) -> Color {
        dimmed ? ember : color
    }
}
