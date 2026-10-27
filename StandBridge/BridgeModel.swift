import AppKit
import Observation
import ServiceManagement

@Observable
final class BridgeModel {
    static let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    static let settingsFile = claudeDir.appending(path: "settings.json")

    let server: BridgeServer?
    static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let layout: LayoutStore
    let customWidgets: CustomWidgetStore
    var sidebar: BridgeSidebarItem? = BridgeModel.launchSection
    var librarySelection: UUID?
    private(set) var loginItemEnabled = false
    private(set) var legacyInstalled = false
    private(set) var hookState = ClaudeSettings.HookState.missing
    private(set) var statuslineState = ClaudeSettings.StatuslineState.missing
    private(set) var codexHookState = CodexSettings.HookState.missing
    private(set) var codexUsageFound = false
    private(set) var message: String?
    var availableUpdate: String?
    let tokenRenewed = BridgeIdentity.isLegacyToken()

    private static func adoptDefaults(from formerBundleID: String) {
        let defaults = UserDefaults.standard
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID != formerBundleID,
              defaults.persistentDomain(forName: bundleID) == nil,
              let former = defaults.persistentDomain(forName: formerBundleID) else { return }
        defaults.setPersistentDomain(former, forName: bundleID)
    }

    init() {
        Self.adoptDefaults(from: "at.lab73.stand.bridge")
        Self.adoptDefaults(from: LegacyBridge.label)
        let port = UInt16(exactly: UserDefaults.standard.integer(forKey: "port")).flatMap { $0 == 0 ? nil : $0 } ?? 7420
        layout = LayoutStore(file: Self.isTestHost ? nil : LayoutStore.file(forPort: port))
        customWidgets = CustomWidgetStore(file: Self.isTestHost ? nil : CustomWidgetStore.file(forPort: port))
        do {
            let token = try BridgeIdentity.loadToken()
            server = BridgeServer(board: Board(claudeDir: Self.claudeDir), layout: layout, token: token, port: port, hostName: BridgeIdentity.localHostName)
            server?.custom = { [customWidgets] in customWidgets.feedJSON(only: $0) }
            if !Self.isTestHost {
                server?.start()
                Task { [customWidgets] in await customWidgets.run() }
                if let board = server?.board {
                    Task { await WindowPrimer.run { WindowPrimer.sessionWindow(of: board) } }
                }
            }
        } catch {
            server = nil
            message = "Token konnte nicht angelegt werden: \(error.localizedDescription)"
        }
        refresh()
    }

    private static var launchSection: BridgeSidebarItem? {
        switch UserDefaults.standard.string(forKey: "section") {
        case "devices": .devices
        case "replies": .replies
        case "diagnostics": .diagnostics
        case "accounts": .accounts
        case "library": .library
        case "preferences": .preferences
        default: nil
        }
    }

    var pairingLink: String? {
        server.map { BridgeIdentity.pairingLink(baseURL: $0.baseURL, token: $0.token) }
    }

    func refresh() {
        loginItemEnabled = SMAppService.mainApp.status == .enabled
        legacyInstalled = LegacyBridge.isInstalled
        let settings = (try? ClaudeSettings.read(Self.settingsFile)) ?? [:]
        hookState = ClaudeSettings.hookState(settings)
        statuslineState = ClaudeSettings.statuslineState(settings)
        codexHookState = CodexSettings.hookState((try? ClaudeSettings.read(CodexSettings.hooksFile)) ?? [:])
        codexUsageFound = CodexUsage.provider(in: CodexSettings.sessionsDir) != nil
    }

    func setLoginItem(_ enabled: Bool) {
        perform {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }
    }

    func removeLegacyBridge() {
        guard confirm("Alte Python-Bridge entfernen?",
                      "Stoppt den launchd-Agent \(LegacyBridge.label) und löscht \(LegacyBridge.agentPlist.path) sowie \(LegacyBridge.scriptFolder.path).") else { return }
        perform {
            try LegacyBridge.remove()
            Task {
                try? await Task.sleep(for: .seconds(1))
                server?.start()
            }
        }
    }

    func installHooks() {
        guard confirm("Claude-Code-Hooks installieren?",
                      "Schreibt sechs Hooks in \(Self.settingsFile.path), die Fragen und Freigaben per curl an Amberlight Bridge melden. Alte stand_hook.py-Einträge werden ersetzt, alles andere bleibt. Vorher wird eine Sicherungskopie angelegt.") else { return }
        updateSettings(Self.settingsFile, ClaudeSettings.installingHooks)
    }

    func removeHooks() {
        guard confirm("Claude-Code-Hooks entfernen?",
                      "Entfernt alle Amberlight-Bridge-Hooks aus \(Self.settingsFile.path). Vorher wird eine Sicherungskopie angelegt.") else { return }
        updateSettings(Self.settingsFile, ClaudeSettings.removingHooks)
    }

    func installCodexHooks() {
        guard confirm("Codex-Hooks installieren?",
                      "Schreibt sieben Hooks in \(CodexSettings.hooksFile.path), die Status und Freigaben per curl an Amberlight Bridge melden. Deine anderen Hooks bleiben erhalten. Vorher wird eine Sicherungskopie angelegt.\n\nDanach in Codex einmal /hooks aufrufen und die Amberlight-Hooks als vertrauenswürdig bestätigen – vorher führt Codex sie nicht aus.") else { return }
        updateSettings(CodexSettings.hooksFile, CodexSettings.installingHooks)
    }

    func removeCodexHooks() {
        guard confirm("Codex-Hooks entfernen?",
                      "Entfernt alle Amberlight-Bridge-Hooks aus \(CodexSettings.hooksFile.path). Vorher wird eine Sicherungskopie angelegt.") else { return }
        updateSettings(CodexSettings.hooksFile, ClaudeSettings.removingHooks)
    }

    func installStatusline() {
        switch statuslineState {
        case .missing:
            guard confirm("Statusline für Usage einrichten?",
                          "Setzt in \(Self.settingsFile.path) eine Statusline, die nur die Usage-Werte für Amberlight mitschreibt. Vorher wird eine Sicherungskopie angelegt.") else { return }
            updateSettings(Self.settingsFile, ClaudeSettings.installingStatusline)
        case .insertable(let script):
            guard confirm("Usage-Zeile in deine Statusline einfügen?",
                          "Fügt in \(script.path) nach input=$(cat) eine Zeile ein, die die Usage-Werte nach ~/.claude/stand-usage.json schreibt. Vorher wird eine Sicherungskopie angelegt.") else { return }
            perform { try ClaudeSettings.insertUsageLine(into: script) }
        case .manual:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ClaudeSettings.usageLine, forType: .string)
            message = "Deine Statusline ist kein bekanntes Skript. Die Zeile liegt in der Zwischenablage – füge sie dort ein, wo $input das Statusline-JSON enthält."
        case .installed:
            break
        }
    }

    private func updateSettings(_ file: URL, _ transform: (JSON) -> JSON) {
        perform {
            let backup = try ClaudeSettings.update(file, transform)
            message = backup.map { "Gesichert: \($0.lastPathComponent)" }
        }
    }

    private func perform(_ action: () throws -> Void) {
        message = nil
        do { try action() } catch { message = error.localizedDescription }
        refresh()
    }

    private func confirm(_ title: String, _ text: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "Fortfahren")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
