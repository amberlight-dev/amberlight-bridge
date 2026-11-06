import Foundation
import Security
import SystemConfiguration

enum BridgeIdentity {
    static let tokenFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/duo-stand/token")
    static let tokenBytes = 32

    static func loadToken(at file: URL = tokenFile) throws -> String {
        if let existing = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= tokenBytes * 2 {
            return existing
        }
        let token = try randomToken()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try token.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return token
    }

    static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: tokenBytes)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CocoaError(.featureUnsupported) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func isLegacyToken(at file: URL = tokenFile) -> Bool {
        guard let existing = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !existing.isEmpty && existing.count < tokenBytes * 2
    }

    static var localHostName: String {
        (SCDynamicStoreCopyLocalHostName(nil) as String? ?? "localhost") + ".local"
    }

    static func pairingLink(baseURL: String, fallbackURL: String?, token: String) -> String {
        var components = URLComponents(string: "duostand://pair")!
        components.queryItems = [URLQueryItem(name: "url", value: baseURL), URLQueryItem(name: "token", value: token)]
            + (fallbackURL.map { [URLQueryItem(name: "fallback", value: $0)] } ?? [])
        return components.string!
    }

    static var lanIPv4: String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }).map(\.pointee) {
            let flags = Int32(entry.ifa_flags)
            guard String(cString: entry.ifa_name).hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254.") { return ip }
        }
        return nil
    }
}
