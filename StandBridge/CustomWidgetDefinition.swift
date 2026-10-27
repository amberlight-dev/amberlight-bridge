import Foundation

nonisolated struct CustomWidgetDefinition: Codable, Hashable, Identifiable {
    enum AuthKind: String, Codable, CaseIterable, Identifiable {
        case none, bearer, headerKey, queryKey, basic, customHeader

        var id: Self { self }

        var title: String {
            switch self {
            case .none: "Keine"
            case .bearer: "Bearer-Token"
            case .headerKey: "API-Key als Header"
            case .queryKey: "API-Key als Query"
            case .basic: "Basic (Benutzer + Passwort)"
            case .customHeader: "Eigener Header"
            }
        }
    }

    struct Auth: Codable, Hashable {
        var kind = AuthKind.none
        var name = ""
        var prefix = ""
    }

    enum Method: String, Codable, CaseIterable, Identifiable {
        case get = "GET", post = "POST"

        var id: Self { self }
    }

    struct Pair: Codable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var value: String

        private enum CodingKeys: String, CodingKey { case name, value }

        init(name: String, value: String) {
            self.name = name
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decode(String.self, forKey: .value)
        }
    }

    struct Endpoint: Codable, Hashable {
        var method = Method.get
        var path = ""
        var query: [Pair] = []
        var headers: [Pair] = []
        var body = ""
    }

    enum Aggregation: String, Codable, CaseIterable, Identifiable {
        case sum, count, countPresent, average, minimum, maximum, first, last

        var id: Self { self }

        var title: String {
            switch self {
            case .sum: "Summe"
            case .count: "Anzahl"
            case .countPresent: "Anzahl mit Wert"
            case .average: "Mittelwert"
            case .minimum: "Minimum"
            case .maximum: "Maximum"
            case .first: "Erstes Element"
            case .last: "Letztes Element"
            }
        }
    }

    struct Selection: Codable, Hashable {
        var valuePath = ""
        var arrayPath: String?
        var valueField = ""
        var aggregation = Aggregation.sum
        var seriesPath: String?
        var filter: String?
        var labelField = ""
        var seriesField = ""
        var groupsLabels = false
        var labelsAreDates = false
    }

    enum NumberFormat: String, Codable, CaseIterable, Identifiable {
        case number, percent, hoursMinutes

        var id: Self { self }

        var title: String {
            switch self {
            case .number: "Zahl"
            case .percent: "Prozent"
            case .hoursMinutes: "Stunden:Minuten"
            }
        }
    }

    enum Comparison: String, Codable, CaseIterable, Identifiable {
        case equals, atLeast, below

        var id: Self { self }

        var title: String {
            switch self {
            case .equals: "ist gleich"
            case .atLeast: "mindestens"
            case .below: "kleiner als"
            }
        }
    }

    struct StatusRule: Codable, Hashable, Identifiable {
        var id = UUID()
        var comparison = Comparison.equals
        var operand = ""
        var tone = CustomWidgetDisplay.Tone.green
        var label = ""

        private enum CodingKeys: String, CodingKey { case comparison, operand, tone, label }

        init(comparison: Comparison = .equals, operand: String = "", tone: CustomWidgetDisplay.Tone = .green, label: String = "") {
            self.comparison = comparison
            self.operand = operand
            self.tone = tone
            self.label = label
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            comparison = try container.decode(Comparison.self, forKey: .comparison)
            operand = try container.decode(String.self, forKey: .operand)
            tone = try container.decode(CustomWidgetDisplay.Tone.self, forKey: .tone)
            label = try container.decode(String.self, forKey: .label)
        }
    }

    struct NamedValue: Codable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var selection: Selection
        var format: NumberFormat?

        private enum CodingKeys: String, CodingKey { case name, selection, format }

        init(name: String, selection: Selection, format: NumberFormat? = nil) {
            self.name = name
            self.selection = selection
            self.format = format
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            selection = try container.decode(Selection.self, forKey: .selection)
            format = try container.decodeIfPresent(NumberFormat.self, forKey: .format)
        }
    }

    struct Display: Codable, Hashable {
        var style = CustomWidgetDisplay.Style.text
        var caption = ""
        var format = NumberFormat.number
        var decimals = 0
        var prefix = ""
        var suffix = ""
        var unit = ""
        var rules: [StatusRule] = []
        var gaugeMin = 0.0
        var gaugeMax = 100.0
        var lines: [String]?
        var layout: CustomNode?
        var compact: CustomNode?
        var wide: CustomNode?
    }

    var id = UUID()
    var name = "Neues Widget"
    var symbol = "square.stack.3d.up"
    var baseURL = "https://"
    var auth = Auth()
    var endpoint = Endpoint()
    var interval = 300
    var selection = Selection()
    var values: [NamedValue]?
    var display = Display()
    var confirmedOrigin: String?
    var template: String?
    var repairVersion: Int?

    static let minimumInterval = 30
    static let maximumInterval = 86_400
}

nonisolated extension CustomWidgetDefinition {
    var origin: String? { CustomRequest.origin(of: baseURL) }
    var needsSecret: Bool { auth.kind != .none }
    var isConfirmed: Bool { origin != nil && confirmedOrigin == origin }
    var clampedInterval: Int { min(max(interval, Self.minimumInterval), Self.maximumInterval) }
}
