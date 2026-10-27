import Foundation

struct StandPreferences: Codable, Equatable {
    static let defaultPadding: Double = 28
    static let paddingRange: ClosedRange<Double> = 8...40

    enum Key {
        static let answerHere = "answerHere"
        static let ledAlerts = "ledAlerts"
        static let typeface = "standTypeface"
        static let background = "backgroundStyle"
        static let backgroundTint = "backgroundTint"
        static let edgePadding = "edgePadding"
        static let compactLayout = "compactLayout"
        static let idleSessionWindow = "idleSessionWindow"
        static let accentColor = "accentColor"
        static let accentClock = "accentClock"
        static let mascot = "mascot"
    }

    var answerHere: Bool?
    var ledAlerts: Bool?
    var typeface: String?
    var background: String?
    var backgroundTint: String?
    var edgePadding: Double?
    var compactLayout: Bool?
    var idleSessionWindow: String?
    var accentColor: String?
    var accentClock: Bool?
    var mascot: String?

    init(answerHere: Bool? = nil, ledAlerts: Bool? = nil, typeface: String? = nil, background: String? = nil, backgroundTint: String? = nil,
         edgePadding: Double? = nil, compactLayout: Bool? = nil, idleSessionWindow: String? = nil,
         accentColor: String? = nil, accentClock: Bool? = nil, mascot: String? = nil) {
        self.answerHere = answerHere
        self.ledAlerts = ledAlerts
        self.typeface = typeface
        self.background = background
        self.backgroundTint = backgroundTint
        self.edgePadding = edgePadding
        self.compactLayout = compactLayout
        self.idleSessionWindow = idleSessionWindow
        self.accentColor = accentColor
        self.accentClock = accentClock
        self.mascot = mascot
    }

    init(defaults: UserDefaults) {
        func value<Value>(_ key: String, _ read: (String) -> Value) -> Value? {
            defaults.object(forKey: key) == nil ? nil : read(key)
        }
        self.init(
            answerHere: value(Key.answerHere, defaults.bool),
            ledAlerts: value(Key.ledAlerts, defaults.bool),
            typeface: defaults.string(forKey: Key.typeface),
            background: defaults.string(forKey: Key.background),
            backgroundTint: defaults.string(forKey: Key.backgroundTint),
            edgePadding: value(Key.edgePadding, defaults.double),
            compactLayout: value(Key.compactLayout, defaults.bool),
            idleSessionWindow: defaults.string(forKey: Key.idleSessionWindow),
            accentColor: defaults.string(forKey: Key.accentColor),
            accentClock: value(Key.accentClock, defaults.bool),
            mascot: defaults.string(forKey: Key.mascot)
        )
    }

    func apply(to defaults: UserDefaults) {
        let current = StandPreferences(defaults: defaults)
        func write<Value: Equatable>(_ new: Value?, _ old: Value?, _ key: String) {
            if let new, new != old { defaults.set(new, forKey: key) }
        }
        write(answerHere, current.answerHere, Key.answerHere)
        write(ledAlerts, current.ledAlerts, Key.ledAlerts)
        write(typeface, current.typeface, Key.typeface)
        write(background, current.background, Key.background)
        write(backgroundTint, current.backgroundTint, Key.backgroundTint)
        write(edgePadding.map(Self.clampedPadding), current.edgePadding, Key.edgePadding)
        write(compactLayout, current.compactLayout, Key.compactLayout)
        write(idleSessionWindow, current.idleSessionWindow, Key.idleSessionWindow)
        write(accentColor, current.accentColor, Key.accentColor)
        write(accentClock, current.accentClock, Key.accentClock)
        write(mascot, current.mascot, Key.mascot)
    }

    func merged(over base: StandPreferences) -> StandPreferences {
        StandPreferences(
            answerHere: answerHere ?? base.answerHere,
            ledAlerts: ledAlerts ?? base.ledAlerts,
            typeface: typeface ?? base.typeface,
            background: background ?? base.background,
            backgroundTint: backgroundTint ?? base.backgroundTint,
            edgePadding: edgePadding ?? base.edgePadding,
            compactLayout: compactLayout ?? base.compactLayout,
            idleSessionWindow: idleSessionWindow ?? base.idleSessionWindow,
            accentColor: accentColor ?? base.accentColor,
            accentClock: accentClock ?? base.accentClock,
            mascot: mascot ?? base.mascot
        )
    }

    static func clampedPadding(_ value: Double) -> Double {
        min(max(value, paddingRange.lowerBound), paddingRange.upperBound)
    }
}

struct StandDeviceStatus: Codable, Equatable {
    var ledAvailable: Bool?
}
