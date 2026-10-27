import SwiftUI

enum StandTypeface: String, CaseIterable, Identifiable {
    case newYork, sfThin, sfCompressed, sfExpanded, sfRounded, sfMono, didot, optima, avenirCondensed, typewriter,
         futuraCondensed

    var id: Self { self }

    var name: String {
        switch self {
        case .newYork: "New York"
        case .sfThin: "SF Pro Thin"
        case .sfCompressed: "SF Compressed"
        case .sfExpanded: "SF Expanded"
        case .sfRounded: "SF Rounded"
        case .sfMono: "SF Mono"
        case .didot: "Didot"
        case .optima: "Optima"
        case .futuraCondensed: "Futura Condensed"
        case .avenirCondensed: "Avenir Next Condensed"
        case .typewriter: "American Typewriter"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .light) -> Font {
        base(size: size, light: weight == .light, weight: weight).monospacedDigit()
    }

    private func base(size: CGFloat, light: Bool, weight: Font.Weight) -> Font {
        switch self {
        case .newYork: .system(size: size, weight: weight, design: .serif)
        case .sfThin: .system(size: size, weight: light ? .thin : .light)
        case .sfCompressed: .system(size: size, weight: weight).width(.compressed)
        case .sfExpanded: .system(size: size, weight: light ? .ultraLight : .light).width(.expanded)
        case .sfRounded: .system(size: size, weight: weight, design: .rounded)
        case .sfMono: .system(size: size, weight: weight, design: .monospaced)
        case .didot: .custom("Didot", fixedSize: size)
        case .optima: .custom("Optima-Regular", fixedSize: size)
        case .futuraCondensed: .custom("Futura-CondensedMedium", fixedSize: size)
        case .avenirCondensed: .custom(light ? "AvenirNextCondensed-UltraLight" : "AvenirNextCondensed-Regular", fixedSize: size)
        case .typewriter: .custom(light ? "AmericanTypewriter-Light" : "AmericanTypewriter", fixedSize: size)
        }
    }
}

extension EnvironmentValues {
    @Entry var standTypeface = StandTypeface.newYork
}
