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
            }
        case .usage:
            Section("Usage") {
                Picker("Zeigt", selection: binding(\.usageWindow, default: .fiveHours)) {
                    ForEach(WidgetSettings.UsageWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
            }
        case .claude:
            Section {
                Picker("Abgeschlossene", selection: binding(\.idleWindow, default: .thirtyMinutes)) {
                    ForEach(IdleSessionWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                TextField("Nur Projekt", text: Binding(
                    get: { settings.repoFilter ?? "" },
                    set: { settings.repoFilter = $0.isEmpty ? nil : $0 }
                ), prompt: Text("alle Projekte"))
            } header: {
                Text("Claude-Sessions")
            } footer: {
                Text("Arbeitende und wartende Sessions stehen immer da. Der Projektfilter vergleicht mit dem Ordnernamen.")
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
        case .shortcuts, .mac, .orbit, .gitlab, .custom:
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
