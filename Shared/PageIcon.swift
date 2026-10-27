import Foundation

extension StandPage {
    static let newPageIcon = "square.grid.2x2"

    static let iconChoices = [
        "desktopcomputer", "laptopcomputer", "display", "keyboard", "terminal", "chevron.left.forwardslash.chevron.right",
        "moon", "moon.stars", "bed.double", "sun.max", "sunrise", "cloud",
        "opticaldisc", "music.note", "headphones", "hifispeaker", "radio", "guitars",
        "square.grid.2x2", "rectangle.3.group", "square.split.2x2", "sparkle", "star", "heart",
        "house", "sofa", "cup.and.saucer", "fork.knife", "leaf", "flame",
        "briefcase", "calendar", "clock", "chart.bar", "book", "pencil",
        "gamecontroller", "figure.walk", "dumbbell", "paintpalette", "camera", "airplane",
    ]

    var symbol: String {
        if let icon, !icon.isEmpty { return icon }
        switch name {
        case "Schreibtisch": return "desktopcomputer"
        case "Nachttisch": return "moon"
        case "Plattenspieler": return "opticaldisc"
        default: return style.dimmed ? "moon" : Self.newPageIcon
        }
    }
}
