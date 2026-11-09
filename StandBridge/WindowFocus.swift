import AppKit

enum WindowFocus {
    enum Outcome: String {
        case window, app, denied, missing
    }

    static let claudeBundleId = "com.anthropic.claudefordesktop"
    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    static func bringToFront(_ entry: JSON) async -> Outcome {
        if entry["entrypoint"] as? String == "claude-desktop" {
            return openDesktopSession(entry["hostSessionId"] as? String)
        }
        guard let pid = entry["pid"] as? Int32, let app = hostApp(of: pid) else { return .missing }
        if let bundleId = app.bundleIdentifier, let tty = tty(of: pid),
           let source = selectTabScript(bundleId: bundleId, tty: tty) {
            guard await isAutomationAllowed(bundleId) else {
                activate(app)
                return .denied
            }
            var error: NSDictionary?
            if NSAppleScript(source: source)?.executeAndReturnError(&error).booleanValue == true { return .window }
        }
        let raised = raiseWindow(of: app, matching: windowHints(for: entry))
        activate(app)
        return raised ? .window : .app
    }

    static func frontmostBundleId(for entry: JSON) -> String? {
        if entry["entrypoint"] as? String == "claude-desktop" { return claudeBundleId }
        return (entry["pid"] as? Int32).flatMap(hostApp)?.bundleIdentifier
    }

    static func windowHints(for entry: JSON) -> [String] {
        let cwd = entry["cwd"] as? String ?? ""
        let home = NSHomeDirectory()
        let tildeCwd = cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : ""
        let hints = [entry["name"] as? String ?? "", cwd, tildeCwd, (cwd as NSString).lastPathComponent]
        return hints.filter { $0.count > 1 }
    }

    static func bestWindowIndex(titles: [String], hints: [String]) -> Int? {
        hints.lazy.compactMap { hint in titles.firstIndex { $0.localizedCaseInsensitiveContains(hint) } }.first
    }

    static func inheritedValue(_ key: String, inProcessArguments raw: [UInt8]) -> String? {
        guard raw.count > 4 else { return nil }
        let argc = raw.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        let prefix = key + "="
        return raw.dropFirst(4).split(separator: 0).dropFirst(1 + argc)
            .lazy.map { String(decoding: $0, as: UTF8.self) }
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        owningApp(of: pid) ?? inheritedApp(of: pid)
    }

    private static func inheritedApp(of pid: pid_t) -> NSRunningApplication? {
        guard let raw = processArguments(of: pid),
              let bundleId = inheritedValue("__CFBundleIdentifier", inProcessArguments: raw) else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first { $0.activationPolicy == .regular }
    }

    private static func processArguments(of pid: pid_t) -> [UInt8]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return Array(buffer.prefix(size))
    }

    private static func raiseWindow(of app: NSRunningApplication, matching hints: [String]) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let index = bestWindowIndex(titles: windows.map(title), hints: hints) else { return false }
        let window = windows[index]
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    private static func title(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    static func isForegroundOnTerminal(_ pid: pid_t) -> Bool {
        guard let info = processInfo(of: pid), info.kp_eproc.e_tdev != -1 else { return false }
        return info.kp_eproc.e_tpgid > 0 && info.kp_eproc.e_tpgid == info.kp_eproc.e_pgid
    }

    private static func openDesktopSession(_ hostSessionId: String?) -> Outcome {
        var link = URLComponents(string: "claude://code/continue")!
        link.queryItems = [URLQueryItem(name: "session", value: hostSessionId)]
        if hostSessionId != nil, let url = link.url, NSWorkspace.shared.open(url) { return .window }
        guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleId).first else { return .missing }
        activate(claude)
        return .app
    }

    private static func activate(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        while current > 1, let info = processInfo(of: current) {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            current = info.kp_eproc.e_ppid
        }
        return nil
    }

    private static func tty(of pid: pid_t) -> String? {
        guard let device = processInfo(of: pid)?.kp_eproc.e_tdev, device != -1,
              let name = devname(device, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty.hasPrefix("tty") ? "/dev/" + tty : nil
    }

    private static func processInfo(of pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        return sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 && size > 0 ? info : nil
    }

    private static func isAutomationAllowed(_ bundleId: String) async -> Bool {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true) == noErr
        }.value
    }

    private static func selectTabScript(bundleId: String, tty: String) -> String? {
        switch bundleId {
        case "com.apple.Terminal":
            """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set miniaturized of w to false
                            set selected of t to true
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            nil
        }
    }
}
