import AppKit
import ApplicationServices
import OSLog

typealias ClipboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

protocol ReplyDesk {
    var canPaste: Bool { get }
    func snapshotClipboard() -> ClipboardSnapshot
    func restoreClipboard(_ snapshot: ClipboardSnapshot)
    func copy(_ text: String)
    func focus(_ entry: JSON) async -> WindowFocus.Outcome
    func isFrontmost(_ entry: JSON) async -> Bool
    func isReadyForInput(_ entry: JSON) async -> Bool
    func pasteAndSubmit() async
}

enum MacReply {
    static let directReplyKey = "directReply"
    static let accessibilitySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    fileprivate static let log = Logger(subsystem: "at.lab73.amberlight.bridge", category: "reply")

    static var isTrusted: Bool { AXIsProcessTrusted() }
    static var isDirectReplyEnabled: Bool { UserDefaults.standard.bool(forKey: directReplyKey) }

    static func send(_ text: String, to entry: JSON, via desk: ReplyDesk, direct: Bool) async -> JSON {
        let previous = desk.snapshotClipboard()
        desk.copy(text)
        let focused = await desk.focus(entry)
        guard direct else { return ["sent": false, "copied": true] }
        if let blocker = await pasteBlocker(entry, focused: focused, desk: desk) {
            log.notice("Nicht direkt gesendet: \(blocker, privacy: .public)")
            return ["sent": false, "copied": true]
        }
        await desk.pasteAndSubmit()
        try? await Task.sleep(for: .milliseconds(500))
        desk.restoreClipboard(previous)
        return ["sent": true, "copied": false]
    }

    private static func pasteBlocker(_ entry: JSON, focused: WindowFocus.Outcome, desk: ReplyDesk) async -> String? {
        if !desk.canPaste { return "Bedienungshilfen fehlen" }
        if focused != .window { return "Session-Fenster nicht gefunden (\(focused.rawValue))" }
        if !(await desk.isFrontmost(entry)) { return "Session-App nicht vorne" }
        if !(await desk.isReadyForInput(entry)) { return "Kein Eingabefeld im Fokus" }
        return nil
    }

    static func record(sessionId: String, option: Int) -> String {
        let line = "\(Date.now.formatted(date: .omitted, time: .standard)) · \(sessionId) · Option \(option + 1)"
        log.notice("Direkt gesendet: \(line, privacy: .public)")
        return line
    }
}

struct SystemReplyDesk: ReplyDesk {
    private static let vKey: CGKeyCode = 9
    private static let returnKey: CGKeyCode = 36
    private static let textRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole]

    var canPaste: Bool { MacReply.isTrusted }

    func snapshotClipboard() -> ClipboardSnapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(snapshot.map { contents in
            let item = NSPasteboardItem()
            contents.forEach { item.setData($1, forType: $0) }
            return item
        })
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func focus(_ entry: JSON) async -> WindowFocus.Outcome {
        await WindowFocus.bringToFront(entry)
    }

    func isFrontmost(_ entry: JSON) async -> Bool {
        guard let expected = WindowFocus.frontmostBundleId(for: entry) else { return false }
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expected {
                try? await Task.sleep(for: .milliseconds(600))
                return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expected
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func isReadyForInput(_ entry: JSON) async -> Bool {
        if entry["entrypoint"] as? String != "claude-desktop" {
            guard let pid = entry["pid"] as? Int32, WindowFocus.isForegroundOnTerminal(pid) else { return false }
        }
        var role: String?
        for _ in 0..<5 {
            role = Self.focusedRole()
            if Self.textRoles.contains(role ?? "") { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        MacReply.log.notice("Fokus-Rolle: \(role ?? "keine", privacy: .public)")
        return false
    }

    func pasteAndSubmit() async {
        press(Self.vKey, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(300))
        press(Self.returnKey, flags: [])
    }

    private static func focusedRole() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
        return role as? String
    }

    private func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
