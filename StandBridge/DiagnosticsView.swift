import AppKit
import Sparkle
import SwiftUI

struct DiagnosticsView: View {
    let model: BridgeModel
    let updater: SPUUpdater

    @AppStorage(WindowPrimer.enabledKey) private var primeWindow = false
    @AppStorage(WindowPrimer.minuteKey) private var primeMinute = WindowPrimer.defaultMinute
    @AppStorage(WindowPrimer.lastRunKey) private var primeLastRun: Double?
    @AppStorage(WindowPrimer.lastResultKey) private var primeLastResult = ""
    @AppStorage("SUEnableAutomaticChecks") private var checksForUpdates = true
    @AppStorage(BridgeStatusItem.visibleKey) private var showsMenuBarIcon = true

    private var primeTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(primeMinute * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                primeMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Hooks") {
                    HStack(spacing: 12) {
                        StateLabel(isOK: model.hookState == .installed, ok: String(localized: "Installiert"), missing: hookProblem)
                        switch model.hookState {
                        case .installed: Button("Entfernen …") { model.removeHooks() }
                        case .legacy: Button("Umstellen …") { model.installHooks() }
                        case .outdated: Button("Aktualisieren …") { model.installHooks() }
                        case .missing: Button("Installieren …") { model.installHooks() }
                        }
                    }
                }
                LabeledContent("Usage aus der Statusline") {
                    switch model.statuslineState {
                    case .installed:
                        StateLabel(isOK: true, ok: String(localized: "Aktiv"), missing: "")
                    case .manual:
                        HStack(spacing: 12) {
                            StateLabel(isOK: false, ok: "", missing: String(localized: "Eigene Statusline"))
                            Button("Zeile kopieren") { model.installStatusline() }
                        }
                    case .missing, .insertable:
                        HStack(spacing: 12) {
                            StateLabel(isOK: false, ok: "", missing: String(localized: "Fehlt"))
                            Button("Einrichten …") { model.installStatusline() }
                        }
                    }
                }
                Toggle("5h-Fenster vorab starten (experimentell)", isOn: $primeWindow)
                if primeWindow {
                    DatePicker("Startzeit", selection: primeTime, displayedComponents: .hourAndMinute)
                    if let lastRun = primeLastRun {
                        LabeledContent("Zuletzt") {
                            Text("\(primeLastResult) · \(Date(timeIntervalSince1970: lastRun).formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Vorab starten: Läuft zur Startzeit kein 5h-Fenster, schickt die Bridge einen Mini-Prompt mit Haiku. Das Fenster beginnt so früher und setzt im Arbeitstag einmal öfter zurück. Der Mac muss dafür wach sein; bis drei Stunden danach wird nachgeholt.")
            }

            Section {
                LabeledContent("Hooks") {
                    HStack(spacing: 12) {
                        StateLabel(isOK: model.codexHookState == .installed, ok: String(localized: "Installiert"),
                                   missing: model.codexHookState == .outdated ? String(localized: "Veraltet") : String(localized: "Fehlen"))
                        switch model.codexHookState {
                        case .installed: Button("Entfernen …") { model.removeCodexHooks() }
                        case .outdated: Button("Aktualisieren …") { model.installCodexHooks() }
                        case .missing: Button("Installieren …") { model.installCodexHooks() }
                        }
                    }
                }
                LabeledContent("Usage aus den Codex-Sitzungen") {
                    StateLabel(isOK: model.codexUsageFound, ok: String(localized: "Aktiv"), missing: String(localized: "Noch keine Daten"))
                }
            } header: {
                Text("Codex")
            } footer: {
                Text("Nach dem Installieren oder Aktualisieren einmal in Codex /hooks aufrufen und die Amberlight-Hooks als vertrauenswürdig bestätigen – vorher führt Codex sie nicht aus. Die Usage liest Amberlight Bridge aus den neuesten Dateien in ~/.codex/sessions; sie erscheint, sobald Codex dort ein Limit gemeldet hat.")
            }

            Section {
                LabeledContent("Version") {
                    HStack(spacing: 12) {
                        Text(Bundle.main.versionLabel)
                            .monospacedDigit()
                            .textSelection(.enabled)
                        Button("Über …") {
                            NSApp.orderFrontStandardAboutPanel(nil)
                        }
                    }
                }
                Toggle("Beim Login starten", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) }))
                Toggle("Symbol in der Menüleiste", isOn: $showsMenuBarIcon)
                    .onChange(of: showsMenuBarIcon) { BridgeAppDelegate.applyStatusItemVisibility() }
                LabeledContent("Amberlight Bridge") {
                    Button("Beenden") {
                        BridgeAppDelegate.quitRequested = true
                        NSApp.terminate(nil)
                    }
                }
                Toggle("Automatisch nach Updates suchen", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { updater.automaticallyChecksForUpdates = checksForUpdates }
                if model.legacyInstalled {
                    LabeledContent("Alte Python-Bridge") {
                        Button("Entfernen …") { model.removeLegacyBridge() }
                    }
                }
                if let server = model.server {
                    LabeledContent("Server") { ServerStatusLabel(status: server.status) }
                    LabeledContent("Port", value: "\(server.port)")
                    LabeledContent("Kopplungscode", value: String(localized: "\(server.token.count) Zeichen"))
                }
                LabeledContent("Anordnung") {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([LayoutStore.file(forPort: model.server?.port ?? LayoutStore.defaultPort)])
                    }
                }
                if let message = model.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Mac")
            } footer: {
                Text("Ohne Symbol läuft die Bridge unsichtbar weiter. Öffnest du sie erneut, etwa über Spotlight, kommt dieses Fenster nach vorn. Updates meldet sie dann gleich mit einem eigenen Fenster.")
            }

            Section("Aktivität") {
                ActivityList(entries: model.server?.requestLog ?? [], limit: RequestLogEntry.limit)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnose")
        .onAppear { model.refresh() }
    }

    private var hookProblem: String {
        switch model.hookState {
        case .legacy: String(localized: "Alte Python-Hooks")
        case .outdated: String(localized: "Veraltet")
        case .missing, .installed: String(localized: "Fehlen")
        }
    }
}

struct StateLabel: View {
    let isOK: Bool
    let ok: String
    let missing: String

    var body: some View {
        if isOK {
            StatusLabel(text: ok, symbol: "checkmark.circle.fill", tint: .green)
        } else {
            StatusLabel(text: missing, symbol: "exclamationmark.triangle.fill", tint: .yellow)
        }
    }
}

struct ActivityList: View {
    let entries: [RequestLogEntry]
    let limit: Int

    var body: some View {
        if entries.isEmpty {
            Text("Noch keine Aktivität seit dem Start.")
                .foregroundStyle(.secondary)
        }
        ForEach(entries.suffix(limit).reversed()) { entry in
            HStack(spacing: 8) {
                Image(systemName: entry.succeeded ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(entry.succeeded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                Text(entry.title)
                Spacer()
                Text(entry.host)
                    .foregroundStyle(.secondary)
                Text(entry.at, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
    }
}
