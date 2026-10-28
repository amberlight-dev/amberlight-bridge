import Foundation

struct CustomTemplate: Identifiable {
    enum Input {
        case subdomain(label: String, pattern: String, prompt: String)
        case secret(label: String, prompt: String)
        case query(name: String, label: String, prompt: String)
    }

    let id: String
    let group: String
    let title: String
    let blurb: String
    let needsAccount: Bool
    let definition: CustomWidgetDefinition
    var inputs: [Input] = []
    var sample = ""

    func sampleJSON(now: Date = .now) -> Any? {
        var text = sample
        let day = Date.ISO8601FormatStyle().year().month().day()
        for offset in 0..<7 {
            text = text.replacingOccurrences(of: "{day-\(offset)}", with: now.addingTimeInterval(-Double(offset) * 86_400).formatted(day))
        }
        text = text.replacingOccurrences(of: "{timer}", with: now.addingTimeInterval(-25 * 60).formatted(.iso8601))
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    func instantiate() -> CustomWidgetDefinition {
        var definition = definition
        definition.id = UUID()
        definition.template = id
        definition.confirmedOrigin = needsAccount ? nil : definition.origin
        return definition
    }

    static func named(_ id: String) -> CustomTemplate? {
        all.first { $0.id == id }
    }

    static let all: [CustomTemplate] = [mocoToday, mocoWeek, mocoTimer, openMeteo, githubStatus]

    static let mocoPlaceholder = "FIRMA"
    private static let mocoBase = "https://\(mocoPlaceholder).mocoapp.com/api/v1"
    private static let mocoInputs: [Input] = [
        .subdomain(label: "MOCO-Subdomain", pattern: "https://{}.mocoapp.com/api/v1", prompt: String(localized: "deine-firma")),
        .secret(label: "API-Key", prompt: String(localized: "MOCO → Profil → Integrationen")),
        .query(name: "user_id", label: "Benutzer-ID", prompt: String(localized: "leer = alle Mitarbeitenden")),
    ]
    private static let mocoDaySample = """
    [{"id":1,"date":"{day-0}","hours":2.5,"timer_started_at":null,"project":{"name":"Relaunch"}},
     {"id":2,"date":"{day-0}","hours":1.25,"timer_started_at":null,"project":{"name":"Wartung"}},
     {"id":3,"date":"{day-0}","hours":0.17,"seconds":600,"description":"Widget-Editor","timer_started_at":"{timer}","project":{"name":"Stand-Widgets"},"task":{"name":"Entwicklung"}}]
    """
    private static let mocoWeekSample = """
    [{"id":6,"date":"{day-3}","hours":8,"timer_started_at":null,"project":{"name":"Wartung"}},
     {"id":5,"date":"{day-2}","hours":6.25,"timer_started_at":null,"project":{"name":"Relaunch"}},
     {"id":4,"date":"{day-1}","hours":7.5,"timer_started_at":null,"project":{"name":"Relaunch"}},
     {"id":1,"date":"{day-0}","hours":2.5,"timer_started_at":null,"project":{"name":"Relaunch"}},
     {"id":3,"date":"{day-0}","hours":1.67,"seconds":6000,"description":"Widget-Editor","timer_started_at":"{timer}","project":{"name":"Stand-Widgets"},"task":{"name":"Entwicklung"}}]
    """


    private static let mocoAuth = CustomWidgetDefinition.Auth(kind: .customHeader, name: "Authorization", prefix: "Token token=")

    private static func mocoActivities(from: String, to: String) -> CustomWidgetDefinition.Endpoint {
        CustomWidgetDefinition.Endpoint(path: "activities", query: [
            .init(name: "from", value: from),
            .init(name: "to", value: to),
            .init(name: "user_id", value: ""),
        ])
    }

    static let mocoToday = CustomTemplate(
        id: "moco-today", group: String(localized: "MOCO Zeiterfassung"), title: String(localized: "Heute erfasst"),
        blurb: String(localized: "Summe der heute erfassten Stunden als Zahl."), needsAccount: true,
        definition: CustomWidgetDefinition(
            name: "MOCO heute", symbol: "clock.badge.checkmark", baseURL: mocoBase, auth: mocoAuth,
            endpoint: mocoActivities(from: "{today}", to: "{today}"), interval: 300,
            selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum),
            values: [.init(name: "booked", selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum))],
            display: .init(style: .text, caption: "Heute", format: .hoursMinutes, unit: "h", layout: CustomLayoutPresets.mocoToday.layout)
        ),
        inputs: mocoInputs, sample: mocoDaySample
    )

    static let mocoWeek = CustomTemplate(
        id: "moco-week", group: String(localized: "MOCO Zeiterfassung"), title: String(localized: "Diese Woche"),
        blurb: String(localized: "Stunden der laufenden Woche, ab 2×2 als Balken pro Tag."), needsAccount: true,
        definition: CustomWidgetDefinition(
            name: "MOCO Woche", symbol: "chart.bar.xaxis", baseURL: mocoBase, auth: mocoAuth,
            endpoint: mocoActivities(from: "{weekStart}", to: "{weekEnd}"), interval: 600,
            selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum, seriesPath: "", labelField: "date",
                             seriesField: "hours", groupsLabels: true, labelsAreDates: true),
            display: .init(style: .bar, caption: "Woche", format: .hoursMinutes, unit: "h")
        ),
        inputs: mocoInputs, sample: mocoWeekSample
    )

    static let mocoTimer = CustomTemplate(
        id: "moco-timer", group: String(localized: "MOCO Zeiterfassung"), title: String(localized: "Laufender Timer"),
        blurb: String(localized: "Was gerade läuft: Projekt, Aufgabe, Beschreibung und wie lange schon – live mitgezählt."), needsAccount: true,
        definition: CustomWidgetDefinition(
            name: "MOCO Timer", symbol: "stopwatch", baseURL: mocoBase, auth: mocoAuth,
            endpoint: mocoActivities(from: "{today}", to: "{today}"), interval: 60,
            selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .countPresent),
            values: [
                .init(name: "project", selection: .init(arrayPath: "", valueField: "project.name", aggregation: .first, filter: "timer_started_at")),
                .init(name: "task", selection: .init(arrayPath: "", valueField: "task.name", aggregation: .first, filter: "timer_started_at")),
                .init(name: "description", selection: .init(arrayPath: "", valueField: "description", aggregation: .first, filter: "timer_started_at")),
                .init(name: "booked", selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum)),
                .init(name: "running", selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .countPresent), format: .number),
                .init(name: "runningStart", selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .first, filter: "timer_started_at")),
                .init(name: "runningSeconds", selection: .init(arrayPath: "", valueField: "seconds", aggregation: .sum, filter: "timer_started_at"), format: .number),
            ],
            display: .init(style: .status, caption: String(localized: "Timer"), format: .hoursMinutes, rules: [
                .init(comparison: .atLeast, operand: "1", tone: .green, label: String(localized: "Timer läuft")),
                .init(comparison: .below, operand: "1", tone: .gray, label: String(localized: "Kein Timer")),
            ], lines: ["{project}", String(localized: "{booked} h heute")], layout: CustomLayoutPresets.mocoTimer.layout,
                compact: CustomLayoutPresets.mocoTimer.compact, wide: CustomLayoutPresets.mocoTimer.wide)
        ),
        inputs: mocoInputs, sample: mocoDaySample
    )

    static let openMeteo = CustomTemplate(
        id: "open-meteo", group: String(localized: "Ohne Konto"), title: String(localized: "Open-Meteo Temperatur"),
        blurb: String(localized: "Aktuelle Temperatur in Wien, ab 2×2 mit Verlauf."), needsAccount: false,
        definition: CustomWidgetDefinition(
            name: "Wien", symbol: "thermometer.medium", baseURL: "https://api.open-meteo.com/v1",
            endpoint: .init(path: "forecast", query: [
                .init(name: "latitude", value: "48.21"),
                .init(name: "longitude", value: "16.37"),
                .init(name: "current", value: "temperature_2m"),
            ]),
            interval: 900,
            selection: .init(valuePath: "current.temperature_2m"),
            display: .init(style: .line, caption: String(localized: "Temperatur"), decimals: 1, unit: "°C", layout: CustomLayoutPresets.bigNumber.layout)
        ),
        sample: #"{"current":{"temperature_2m":17.4}}"#
    )

    static let githubStatus = CustomTemplate(
        id: "github-status", group: String(localized: "Ohne Konto"), title: "GitHub-Status",
        blurb: String(localized: "Gesamtstatus von GitHub, ab 2×2 mit den einzelnen Diensten."), needsAccount: false,
        definition: CustomWidgetDefinition(
            name: "GitHub", symbol: "server.rack", baseURL: "https://www.githubstatus.com/api/v2",
            endpoint: .init(path: "summary.json"), interval: 300,
            selection: .init(valuePath: "status.indicator", seriesPath: "components", labelField: "name", seriesField: "status"),
            display: .init(style: .status, caption: "GitHub", rules: [
                .init(comparison: .equals, operand: "none", tone: .green, label: String(localized: "Alles in Ordnung")),
                .init(comparison: .equals, operand: "minor", tone: .yellow, label: String(localized: "Störung")),
                .init(comparison: .equals, operand: "major", tone: .red, label: String(localized: "Größere Störung")),
                .init(comparison: .equals, operand: "critical", tone: .red, label: String(localized: "Ausfall")),
            ])
        ),
        sample: #"{"status":{"indicator":"none"},"components":[{"name":"Git","status":"operational"},{"name":"Actions","status":"operational"},{"name":"Pages","status":"operational"}]}"#
    )
}
