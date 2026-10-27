import Foundation

nonisolated struct CustomWidgetDisplay: Codable, Equatable, Identifiable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case text, status, gauge, line, bar, list

        var id: Self { self }

        var title: String {
            switch self {
            case .text: String(localized: "Text bzw. Zahl")
            case .status: String(localized: "Status")
            case .gauge: String(localized: "Fortschritt")
            case .line: String(localized: "Liniendiagramm")
            case .bar: String(localized: "Balkendiagramm")
            case .list: String(localized: "Liste")
            }
        }

        var symbol: String {
            switch self {
            case .text: "textformat.123"
            case .status: "circle.fill"
            case .gauge: "gauge.with.dots.needle.50percent"
            case .line: "chart.xyaxis.line"
            case .bar: "chart.bar"
            case .list: "list.bullet"
            }
        }
    }

    enum Tone: String, Codable, CaseIterable, Identifiable {
        case green, yellow, red, blue, gray

        var id: Self { self }

        var title: String {
            switch self {
            case .green: String(localized: "Grün")
            case .yellow: String(localized: "Gelb")
            case .red: String(localized: "Rot")
            case .blue: String(localized: "Blau")
            case .gray: String(localized: "Grau")
            }
        }
    }

    struct Point: Codable, Equatable {
        var label: String
        var value: Double?
        var text: String?
    }

    struct Sample: Codable, Equatable {
        var at: Date
        var value: Double
    }

    var id: UUID
    var name: String
    var symbol: String
    var style: Style
    var caption: String
    var text: String?
    var tone: Tone?
    var progress: Double?
    var points: [Point] = []
    var history: [Sample] = []
    var lines: [String]?
    var root: CustomNode?
    var error: String?
    var updatedAt: Date?
}

nonisolated struct CustomWidgetFeed: Codable, Equatable {
    var widgets: [CustomWidgetDisplay]
}

extension CustomWidgetDisplay.Style {
    var preferredSpan: GridSpan {
        switch self {
        case .text, .status, .gauge: GridSpan(w: 2, h: 1)
        case .line, .bar, .list: GridSpan(w: 3, h: 2)
        }
    }
}

extension WidgetSettings {
    init(custom display: CustomWidgetDisplay) {
        self.init()
        customID = display.id
        customName = display.name
    }
}
