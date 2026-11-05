import Foundation

enum McpSettings {
    enum State: Equatable { case missing, outdated, installed }

    static let serverName = "amberlight-widgets"
    static let scriptName = "widgets-mcp"
    static let scriptExtension = "mjs"
    static let configFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")

    static var bundledScript: URL? {
        Bundle.main.url(forResource: scriptName, withExtension: scriptExtension)
    }

    static func entry(script: String) -> JSON {
        ["type": "stdio", "command": "node", "args": [script]]
    }

    static func state(_ config: JSON, script: String) -> State {
        guard let existing = (config["mcpServers"] as? JSON)?[serverName] as? JSON else { return .missing }
        return (existing as NSDictionary).isEqual(to: entry(script: script)) ? .installed : .outdated
    }

    static func installing(_ config: JSON, script: String) -> JSON {
        var servers = config["mcpServers"] as? JSON ?? [:]
        servers[serverName] = entry(script: script)
        return config.merging(["mcpServers": servers]) { $1 }
    }

    static func removing(_ config: JSON) -> JSON {
        guard var servers = config["mcpServers"] as? JSON, servers[serverName] != nil else { return config }
        servers[serverName] = nil
        var result = config
        result["mcpServers"] = servers.isEmpty ? nil : servers
        return result
    }

    static func nodeURL(searching directories: [String] = defaultNodeDirectories) -> URL? {
        directories
            .map { URL(fileURLWithPath: $0).appending(path: "node") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var defaultNodeDirectories: [String] {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let nvm = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".nvm/versions/node")
        let nvmBins = ((try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? []).sorted().reversed()
            .map { nvm.appending(path: "\($0)/bin").path }
        return path + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + nvmBins
    }
}
