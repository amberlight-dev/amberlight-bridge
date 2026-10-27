import AppKit

enum MacLauncher {
    private static let appFolders = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    static func apps() -> [JSON] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningIds = Set(running.compactMap(\.bundleIdentifier))
        let installed = appFolders.flatMap(bundles(in:))
        let launched = running.compactMap(\.bundleURL)
        var seen = Set<String>()
        return (installed + launched)
            .compactMap { url -> JSON? in
                guard let bundleId = Bundle(url: url)?.bundleIdentifier, seen.insert(bundleId).inserted else { return nil }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                return ["name": name, "bundleId": bundleId, "running": runningIds.contains(bundleId)]
            }
            .sorted { ($0["name"] as? String ?? "").localizedStandardCompare($1["name"] as? String ?? "") == .orderedAscending }
    }

    static func icon(bundleId: String, side: CGFloat = 64) -> Data? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func open(_ target: JSON) async -> Bool {
        if let bundleId = target["bundleId"] as? String {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return false }
            return (try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())) != nil
        }
        if let link = target["url"] as? String {
            guard let url = openableURL(link) else { return false }
            return NSWorkspace.shared.open(url)
        }
        if let shortcut = target["shortcut"] as? String, !shortcut.isEmpty {
            return runShortcut(shortcut)
        }
        return false
    }

    private static let blockedSchemes: Set<String> = ["file", "smb", "afp", "nfs", "ftp", "vnc", "ssh", "telnet", "x-man-page", "applescript"]

    static func openFolder(_ link: String) -> Bool {
        guard let url = URL(string: link), isPlainFolder(url) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func isPlainFolder(_ url: URL) -> Bool {
        guard url.isFileURL, let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        return values.isDirectory == true && values.isPackage != true
    }

    static func openableURL(_ link: String) -> URL? {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), !blockedSchemes.contains(scheme) else { return nil }
        return url
    }

    static func isWebURL(_ link: String) -> Bool {
        ["http", "https"].contains(URL(string: link)?.scheme?.lowercased() ?? "")
    }

    private static func runShortcut(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        return (try? process.run()) != nil
    }

    private static func bundles(in folder: String) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return contents.filter { $0.pathExtension == "app" }
    }
}
