import Foundation

enum MicroSlot: String, Codable, CaseIterable, Identifiable {
    case perimeter, top, bottom, leading, trailing
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    case earBefore, earAfter

    var id: Self { self }

    var isCorner: Bool { [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing].contains(self) }

    var title: String {
        switch self {
        case .perimeter: String(localized: "Umlauf")
        case .top: String(localized: "Oberkante")
        case .bottom: String(localized: "Unterkante")
        case .leading: String(localized: "Linker Rand")
        case .trailing: String(localized: "Rechter Rand")
        case .topLeading: String(localized: "Ecke oben links")
        case .topTrailing: String(localized: "Ecke oben rechts")
        case .bottomLeading: String(localized: "Ecke unten links")
        case .bottomTrailing: String(localized: "Ecke unten rechts")
        case .earBefore, .earAfter: String(localized: "Kamera-Ohr")
        }
    }
}
