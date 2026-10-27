import Foundation

enum LegacyBridge {
    static let label = "local.duostand.bridge"
    static let agentPlist = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist")
    static let scriptFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/duo-stand")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: agentPlist.path)
    }

    static func remove() throws {
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try bootout.run()
        bootout.waitUntilExit()
        try FileManager.default.removeItem(at: agentPlist)
        try? FileManager.default.removeItem(at: scriptFolder)
    }
}
