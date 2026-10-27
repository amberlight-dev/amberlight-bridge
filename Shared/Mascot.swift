import Foundation

enum Mascot: String, Codable, CaseIterable, Identifiable {
    case sapling, cactus, cloud, robot, mushroom

    static let standard = Mascot.sapling

    var id: Self { self }

    var title: String {
        switch self {
        case .sapling: String(localized: "Bäumchen")
        case .cactus: String(localized: "Kaktus")
        case .cloud: String(localized: "Wölkchen")
        case .robot: String(localized: "Roboter")
        case .mushroom: String(localized: "Pilz")
        }
    }

    init(stored: String?) {
        self = stored.flatMap(Mascot.init(rawValue:)) ?? .standard
    }
}

enum MascotMood: CaseIterable {
    case working, sleeping, asking
}
