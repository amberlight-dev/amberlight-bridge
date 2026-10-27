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

    static func pairingLink(baseURL: String, token: String) -> String {
        var components = URLComponents(string: "duostand://pair")!
        components.queryItems = [URLQueryItem(name: "url", value: baseURL), URLQueryItem(name: "token", value: token)]
        return components.string!
    }
}
