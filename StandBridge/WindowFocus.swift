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
        guard let pid = entry["pid"] as? Int32, let app = owningApp(of: pid) else { return .missing }
        guard let bundleId = app.bundleIdentifier, let tty = tty(of: pid),
              let source = selectTabScript(bundleId: bundleId, tty: tty) else {
            activate(app)
            return .app
        }
        guard await isAutomationAllowed(bundleId) else {
            activate(app)
            return .denied
        }
        var error: NSDictionary?
        if NSAppleScript(source: source)?.executeAndReturnError(&error).booleanValue == true { return .window }
        activate(app)
        return .app
    }

    static func frontmostBundleId(for entry: JSON) -> String? {
        if entry["entrypoint"] as? String == "claude-desktop" { return claudeBundleId }
        return (entry["pid"] as? Int32).flatMap(owningApp)?.bundleIdentifier
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
