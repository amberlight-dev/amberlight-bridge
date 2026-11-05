import SwiftUI

struct WidgetSettingsForm: View {
    let widget: StandWidget
    @Binding var settings: WidgetSettings

    var body: some View {
        switch widget {
        case .clock:
            Section("Uhr") {
                Toggle("Sekunden", isOn: binding(\.showsSeconds, default: false))
                Toggle("Datum", isOn: binding(\.showsDate, default: true))
                    .disabled(settings.weatherBelow)
                Toggle("Wetter darunter", isOn: binding(\.showsWeatherBelow, default: false))
                if settings.weatherBelow {
                    TextField("Stadt", text: Binding(
                        get: { settings.weatherCity ?? "" },
                        set: { settings.weatherCity = $0.isEmpty ? nil : $0 }
                    ), prompt: Text("aktueller Standort"))
                }
            }
        case .usage:
            Section("Usage") {
                Picker("Zeigt", selection: binding(\.usageWindow, default: .fiveHours)) {
                    ForEach(WidgetSettings.UsageWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
            }
        case .agents:
            Section {
                Picker("Darstellung", selection: binding(\.agentsDisplay, default: .list)) {
                    ForEach(WidgetSettings.AgentsDisplay.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Subagents", isOn: binding(\.showsSubagents, default: true))
                Toggle("Aufgabenfortschritt", isOn: binding(\.showsTodos, default: true))
                Toggle("Nur aktive", isOn: binding(\.showsOnlyActive, default: false))
                if !settings.onlyActive {
                    Picker("Abgeschlossene", selection: binding(\.idleWindow, default: .thirtyMinutes)) {
                        ForEach(IdleSessionWindow.allCases) { Text($0.title).tag($0) }
                    }
                }
                if settings.display == .list {
                    Toggle("Überschrift", isOn: binding(\.showsSessionHeader, default: true))
                        .disabled(settings.onlyActive)
                    Toggle("„+ N ältere“", isOn: binding(\.showsOlderCount, default: true))
                        .disabled(settings.onlyActive)
                    Picker("Gruppieren nach", selection: binding(\.agentsGrouping, default: .none)) {
                        ForEach(WidgetSettings.AgentsGrouping.allCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Quelle", selection: binding(\.agentsSource, default: .all)) {
                    ForEach(WidgetSettings.AgentsSource.allCases) { Text($0.title).tag($0) }
                }
                TextField("Nur Projekt", text: Binding(
                    get: { settings.repoFilter ?? "" },
                    set: { settings.repoFilter = $0.isEmpty ? nil : $0 }
                ), prompt: Text("alle Projekte"))
                Toggle("Fertig und Wartet im Vollbild", isOn: binding(\.fullscreenAlerts, default: false))
            } header: {
                Text(widget.title)
            } footer: {
                Text("Arbeitende und wartende Sessions stehen immer da. „Nur aktive“ zeigt nur sie. Der Projektfilter vergleicht mit dem Ordnernamen. Der Aufgabenfortschritt kommt aus der Aufgabenliste der Session. Im Vollbild legen sich „Fertig“ und „Wartet auf dich“ wie eine Freigabe über den ganzen Stand.")
            }
        case .nowPlaying:
            Section("Läuft gerade") {
                Toggle("Steuerknöpfe", isOn: binding(\.showsControls, default: true))
            }
        case .calendar:
            CalendarSettingsSection(names: $settings.calendarNames)
        case .weather:
            Section {
                TextField("Stadt", text: Binding(
                    get: { settings.weatherCity ?? "" },
                    set: { settings.weatherCity = $0.isEmpty ? nil : $0 }
                ), prompt: Text("aktueller Standort"))
                Toggle("Nur Symbol und Temperatur", isOn: binding(\.prefersCompact, default: false))
            } header: {
                Text("Wetter")
            } footer: {
                Text("Leer lassen, um den Standort des iPhones zu nutzen.")
            }
        case .focus:
            FocusSettingsSection(focus: binding(\.focusMinutes, default: 25), rest: binding(\.breakMinutes, default: 5))
        case .mascot:
            Section {
                MascotPicker(selection: $settings.mascot, offersStandard: true)
            } header: {
                Text("Maskottchen")
            } footer: {
                Text("„Standard“ folgt der Figur aus den Darstellungs-Einstellungen.")
            }
        case .radio:
            Section {
                TextField("Eigener Stream", text: Binding(
                    get: { settings.radioStream ?? "" },
                    set: { settings.radioStream = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
                ), prompt: Text(verbatim: "https://…"))
                .autocorrectionDisabled()
                TextField("Name", text: Binding(
                    get: { settings.radioName ?? "" },
                    set: { settings.radioName = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Mein Sender"))
            } header: {
                Text("Internetradio")
            } footer: {
                Text("Ein MP3- oder AAC-Stream über https, etwa von Icecast oder Shoutcast. Er steht vor den NTS-Sendern.")
            }
        case .googleChat:
            Section {
                Toggle("Vorschau ausblenden", isOn: binding(\.chatHidesPreview, default: false))
            } header: {
                Text("Google Chat")
            } footer: {
                Text("Zeigt nur Absender, Bereich und Anzahl. Der Nachrichtentext verlässt den Mac dann nicht.")
            }
        case .shortcuts, .mac, .gitlab, .custom:
            EmptyView()
        }
    }

    private func binding<Value: Equatable>(_ key: WritableKeyPath<WidgetSettings, Value?>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: key] ?? fallback },
            set: { settings[keyPath: key] = $0 }
        )
    }
}
