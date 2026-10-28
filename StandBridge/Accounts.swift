import Foundation

struct OrbitAccount: Codable, Equatable {
    var apiURL: String
    var webURL: String
    var token: String

    var api: String { Accounts.trimmed(apiURL) }
    var web: String { Accounts.trimmed(webURL.isEmpty ? apiURL : webURL) }
}

struct GitLabAccount: Codable, Equatable {
    var url: String
    var token: String

    var api: String { Accounts.trimmed(url) + "/api/v4" }
}

enum Accounts {
    private static let orbitKey = "account.orbit"
    private static let gitlabKey = "account.gitlab"

    static var orbit: OrbitAccount? { load(orbitKey) }
    static var gitlab: GitLabAccount? { load(gitlabKey) }

    static func save(_ account: OrbitAccount?) {
        store(account, at: orbitKey)
        OrbitClient.forgetCache()
    }

    static func save(_ account: GitLabAccount?) {
        store(account, at: gitlabKey)
        GitLabClient.forgetCache()
    }

    static func trimmed(_ url: String) -> String {
        var url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    private static func load<Account: Decodable>(_ key: String) -> Account? {
        Keychain.read(key).flatMap { try? JSONDecoder().decode(Account.self, from: $0) }
    }

    private static func store<Account: Encodable>(_ account: Account?, at key: String) {
        guard let account, let data = try? JSONEncoder().encode(account) else {
            Keychain.delete(key)
            return
        }
        Keychain.write(data, for: key)
    }
}

enum RemoteError: Error {
    case unauthorized, unreachable, status(Int)

    func message(for service: String) -> String {
        switch self {
        case .unauthorized: String(localized: "\(service) lehnt den Token ab")
        case .unreachable: String(localized: "\(service) nicht erreichbar")
        case .status(let code): String(localized: "\(service) antwortet mit \(code)")
        }
    }
}

enum RemoteJSON {
    static func get<Value: Decodable>(_ url: String, headers: [String: String], decoder: JSONDecoder = JSONDecoder()) async throws -> Value {
        guard let url = URL(string: url) else { throw RemoteError.unreachable }
        var request = URLRequest(url: url, timeoutInterval: 15)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw RemoteError.unreachable }
        if status == 401 || status == 403 { throw RemoteError.unauthorized }
        guard status == 200 else { throw RemoteError.status(status) }
        return try decoder.decode(Value.self, from: data)
    }

    static func failure(_ error: Error, service: String, empty: JSON) -> JSON {
        var payload = empty
        payload["configured"] = true
        payload["error"] = (error as? RemoteError ?? .status(0)).message(for: service)
        return payload
    }
}
