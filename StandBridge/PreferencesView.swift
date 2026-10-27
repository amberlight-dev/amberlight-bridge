import SwiftUI

struct PreferencesView: View {
    let store: LayoutStore
    let onShowDevices: () -> Void

    private var preferences: StandPreferences { store.preferences }

    var body: some View {
        Form {
            if store.revision == 0 {
                Section {
                    StatusLabel(text: "Noch kein iPhone verbunden – Änderungen gelten, sobald es sich meldet.", symbol: "hourglass", tint: .secondary)
                }
            }

            Section("Darstellung") {
                Picker("Schrift", selection: binding(\.typeface, default: StandTypeface.newYork.rawValue)) {
                    ForEach(StandTypeface.allCases) { face in
                        Text(face.name)
                            .font(face.font(size: 13, weight: .regular))
                            .tag(face.rawValue)
                    }
                }
                Picker("Hintergrund", selection: binding(\.background, default: BackgroundStyle.aurora.rawValue)) {
                    ForEach(BackgroundStyle.allCases, id: \.self) { style in
                        Label(style.title, systemImage: style.symbol).tag(style.rawValue)
                    }
                }
                Picker("Akzentfarbe", selection: binding(\.accentColor, default: "")) {
                    Text("Standard").tag("")
                    ForEach(StandAccent.palette, id: \.hex) { accent in
                        Label {
                            Text(accent.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(StandAccent.color(hex: accent.hex) ?? .clear)
                        }
                        .tag(accent.hex)
                    }
                    if let custom = preferences.accentColor, !custom.isEmpty, !StandAccent.palette.contains(where: { $0.hex == custom }) {
                        Text("Eigene").tag(custom)
                    }
                }
                ColorPicker("Eigene Akzentfarbe", selection: Binding(
                    get: { StandAccent.color(hex: preferences.accentColor ?? "") ?? .white },
                    set: { color in store.updatePreferences { $0.accentColor = StandAccent.hex(of: color) } }
                ), supportsOpacity: false)
                Toggle("Uhr in Akzentfarbe", isOn: binding(\.accentClock, default: false))
                    .disabled((preferences.accentColor ?? "").isEmpty)
                LabeledContent("Maskottchen") {
                    MascotPicker(selection: Binding(
                        get: { Mascot(stored: preferences.mascot) },
                        set: { mascot in store.updatePreferences { $0.mascot = mascot?.rawValue } }
                    ))
                }
            }

            if let style = BackgroundStyle(rawValue: preferences.background ?? BackgroundStyle.aurora.rawValue), style.usesTint {
                BackgroundTintSection(style: style, tint: Binding(
                    get: { BackgroundTint(json: preferences.backgroundTint) },
                    set: { tint in store.updatePreferences { $0.backgroundTint = tint.json } }
                ))
            }

            Section {
                Toggle("Kompakt", isOn: binding(\.compactLayout, default: false))
                LabeledContent("Außenabstand") {
                    HStack {
                        Slider(value: binding(\.edgePadding, default: StandPreferences.defaultPadding), in: StandPreferences.paddingRange, step: 4)
                            .frame(maxWidth: 240)
                        Text("\(Int(preferences.edgePadding ?? StandPreferences.defaultPadding)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(preferences.compactLayout ?? false)
            } header: {
                Text("Raster")
            } footer: {
                Text("Kompakt rückt alles an Rand und Nachbarn heran und blendet die Rand-Widgets aus. Standard-Abstand: 28 pt.")
            }

            Section {
                Toggle("Fragen in Amberlight beantworten", isOn: binding(\.answerHere, default: true))
            } header: {
                Text("Fragen und Antworten")
            } footer: {
                Text("Aus: Fragen erscheinen am iPhone nur zur Info und werden am Mac beantwortet. Wie Antworten am Mac ankommen, stellst du unter „Antworten“ ein.")
            }

            Section {
                Toggle("LED blinkt bei Ereignissen", isOn: binding(\.ledAlerts, default: false))
                if store.device?.ledAvailable == false {
                    StatusLabel(text: "Das zuletzt verbundene iPhone hat keine LED.", symbol: "info.circle", tint: .secondary)
                }
            } header: {
                Text("Benachrichtigungen")
            } footer: {
                Text("Fertig: zweimal kurz. Frage oder Freigabe: dreimal. Nicht im Nachttisch-Modus und nur, solange Amberlight offen ist.")
            }

            Section {
                Picker("Abgeschlossene zeigen", selection: binding(\.idleSessionWindow, default: IdleSessionWindow.thirtyMinutes.rawValue)) {
                    ForEach(IdleSessionWindow.allCases) { window in
                        Text(window.title).tag(window.rawValue)
                    }
                }
            } header: {
                Text("Sessions")
            } footer: {
                Text("Gilt für alle Session-Widgets ohne eigene Einstellung. Einzelne Widgets stellst du im Inspector ein.")
            }

            Section {
                LabeledContent("Kopplung") {
                    Button("Geräte öffnen", action: onShowDevices)
                }
                LabeledContent("Berechtigungen", value: "Kamera, Standort, Kalender")
            } header: {
                Text("Nur am iPhone")
            } footer: {
                Text("Bridge-Adresse, Code und Berechtigungen gehören zum Gerät und werden in der Amberlight-App eingestellt.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
    }

    private func binding<Value>(_ key: WritableKeyPath<StandPreferences, Value?>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: key] ?? fallback },
            set: { value in store.updatePreferences { $0[keyPath: key] = value } }
        )
    }
}
