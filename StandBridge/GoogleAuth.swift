import AppKit
import CryptoKit
import Foundation
import Network

struct GoogleChatAccount: Codable, Equatable {
    var clientID: String
    var clientSecret: String
    var refreshToken: String?
    var email: String?
    var userID: String?

    var isConnected: Bool { !(refreshToken ?? "").isEmpty }
}

enum GoogleChatError: Error, Equatable {
    case cancelled, denied, stateMismatch, timeout, missingScopes, invalidClient, reconnect
    case apiDisabled, appMissing, rateLimited, unreachable, malformed, status(Int)

    var message: String {
        switch self {
        case .cancelled: String(localized: "Anmeldung abgebrochen")
        case .denied: String(localized: "Zugriff in Google abgelehnt")
        case .stateMismatch: String(localized: "Antwort von Google passt nicht zur Anfrage")
        case .timeout: String(localized: "Keine Antwort aus dem Browser – bitte erneut verbinden")
        case .missingScopes: String(localized: "Bitte alle angefragten Google-Berechtigungen erlauben und neu verbinden")
        case .invalidClient: String(localized: "Client-ID oder Client-Secret stimmt nicht")
        case .reconnect: String(localized: "Google-Zugang abgelaufen – in Stand Bridge unter Konten neu verbinden")
        case .apiDisabled: String(localized: "Google Chat API im Cloud-Projekt aktivieren")
        case .appMissing: String(localized: "Chat-App im Cloud-Projekt konfigurieren (Chat API → Konfiguration)")
        case .rateLimited: String(localized: "Google-Kontingent erreicht – gleich wieder")
        case .unreachable: String(localized: "Google nicht erreichbar")
        case .malformed: String(localized: "Antwort von Google nicht lesbar")
        case .status(let code): String(localized: "Google antwortet mit \(code)")
        }
    }

    var isTransient: Bool {
        switch self {
        case .rateLimited, .unreachable: true
        case .status(let code): code >= 500
        default: false
        }
    }

    var isFatal: Bool {
        [.reconnect, .invalidClient, .apiDisabled, .appMissing, .missingScopes].contains(self)
    }
}

enum GoogleAuth {
    static let chatScopes = [
        "https://www.googleapis.com/auth/chat.spaces.readonly",
        "https://www.googleapis.com/auth/chat.users.readstate.readonly",
        "https://www.googleapis.com/auth/chat.messages.readonly",
    ]
    static let scopes = ["openid", "email"] + chatScopes
    static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let revokeEndpoint = "https://oauth2.googleapis.com/revoke"
    static let callbackTimeout: Duration = .seconds(300)

    struct PKCE: Equatable {
        let verifier: String
        let challenge: String

        init(verifier: String = GoogleAuth.randomToken(bytes: 48)) {
            self.verifier = verifier
            challenge = GoogleAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }
    }

    struct Tokens: Decodable {
        let accessToken: String
        let expiresIn: Double?
        let refreshToken: String?
        let scope: String?
        let idToken: String?
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func connect(clientID: String, clientSecret: String, hint: String? = nil) async throws -> GoogleChatAccount {
        let pkce = PKCE()
        let state = randomToken(bytes: 24)
        let loopback = try GoogleLoopback()
        defer { loopback.stop() }
        let port = try await loopback.start()
        let redirect = "http://127.0.0.1:\(port)"
        NSWorkspace.shared.open(authorizationURL(clientID: clientID, redirect: redirect, pkce: pkce, state: state, hint: hint))
        let reply = try await loopback.callback(timeout: callbackTimeout)
        NSApp.activate()
        guard reply["state"] == state else { throw GoogleChatError.stateMismatch }
        if let error = reply["error"] { throw error == "access_denied" ? GoogleChatError.denied : GoogleChatError.status(400) }
        guard let code = reply["code"], !code.isEmpty else { throw GoogleChatError.denied }
        let tokens = try await requestTokens([
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier,
        ])
        guard missingScopes(in: tokens.scope).isEmpty else { throw GoogleChatError.missingScopes }
        guard let refresh = tokens.refreshToken, !refresh.isEmpty else { throw GoogleChatError.reconnect }
        let identity = identity(fromIDToken: tokens.idToken)
        return GoogleChatAccount(clientID: clientID, clientSecret: clientSecret, refreshToken: refresh, email: identity.email, userID: identity.userID)
    }

    static func refresh(_ account: GoogleChatAccount, now: Date = .now) async throws -> (token: String, expires: Date) {
        guard let refresh = account.refreshToken, !refresh.isEmpty else { throw GoogleChatError.reconnect }
        let tokens = try await requestTokens([
            "client_id": account.clientID,
            "client_secret": account.clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        return (tokens.accessToken, now.addingTimeInterval(max((tokens.expiresIn ?? 3600) - 60, 30)))
    }

    static func revoke(_ token: String) async {
        guard let url = URL(string: revokeEndpoint) else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(["token": token]).utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func authorizationURL(clientID: String, redirect: String, pkce: PKCE, state: String, hint: String? = nil) -> URL {
        var components = URLComponents(string: authEndpoint)!
        components.percentEncodedQuery = formEncoded([
            "client_id": clientID,
            "redirect_uri": redirect,
            "response_type": "code",
            "scope": scopes.joined(separator: " "),
            "code_challenge": pkce.challenge,
            "code_challenge_method": "S256",
            "state": state,
            "access_type": "offline",
            "prompt": "consent",
            "login_hint": hint ?? "",
        ].filter { !$0.value.isEmpty })
        return components.url!
    }

    static func tokenFailure(status: Int, body: Data) -> GoogleChatError {
        switch ((try? JSONSerialization.jsonObject(with: body)) as? JSON)?["error"] as? String {
        case "invalid_grant": .reconnect
        case "invalid_client", "unauthorized_client": .invalidClient
        case "invalid_scope": .missingScopes
        default: .status(status)
        }
    }

    static func missingScopes(in granted: String?) -> [String] {
        let given = Set((granted ?? "").split(separator: " ").map(String.init))
        return chatScopes.filter { !given.contains($0) }
    }

    static func identity(fromIDToken token: String?) -> (email: String?, userID: String?) {
        let parts = (token ?? "").split(separator: ".")
        guard parts.count >= 2 else { return (nil, nil) }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return (nil, nil) }
        return (claims["email"] as? String, claims["sub"] as? String)
    }

    static func randomToken(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formEncoded(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }.map { "\(percentEncoded($0.key))=\(percentEncoded($0.value))" }.joined(separator: "&")
    }

    static func percentEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func requestTokens(_ fields: [String: String]) async throws -> Tokens {
        guard let url = URL(string: tokenEndpoint) else { throw GoogleChatError.unreachable }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(fields).utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw GoogleChatError.unreachable }
        guard status == 200 else { throw tokenFailure(status: status, body: data) }
        guard let tokens = try? decoder.decode(Tokens.self, from: data) else { throw GoogleChatError.malformed }
        return tokens
    }
}

final class GoogleLoopback {
    private let listener: NWListener
    private var ready: CheckedContinuation<UInt16, Error>?
    private var waiting: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.update(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func callback(timeout: Duration) async throws -> [String: String] {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { self?.finish(.failure(GoogleChatError.timeout)) }
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let result {
                    continuation.resume(with: result)
                } else {
                    waiting = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(GoogleChatError.cancelled)) }
        }
    }

    func stop() {
        listener.cancel()
    }

    private func update(_ state: NWListener.State) {
        switch state {
        case .ready:
            ready?.resume(returning: listener.port?.rawValue ?? 0)
            ready = nil
        case .failed(let error):
            ready?.resume(throwing: error)
            ready = nil
            finish(.failure(GoogleChatError.unreachable))
        default:
            break
        }
    }

    private func finish(_ outcome: Result<[String: String], Error>) {
        guard result == nil else { return }
        result = outcome
        waiting?.resume(with: outcome)
        waiting = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                let buffer = buffer + (data ?? Data())
                if let request = HTTPRequest.parse(buffer) {
                    self?.handle(request, on: connection)
                } else if error != nil || isComplete || buffer.count > 65536 {
                    connection.cancel()
                } else {
                    self?.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let isCallback = request.method == "GET" && request.path == "/" && (request.query["code"] != nil || request.query["error"] != nil)
        let body = isCallback ? Self.page(denied: request.query["error"] != nil) : ""
        let head = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(Data(body.utf8).count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
        if isCallback { finish(.success(request.query)) }
    }

    private static func page(denied: Bool) -> String {
        let title = denied ? String(localized: "Anmeldung abgebrochen") : String(localized: "Stand Bridge ist mit Google Chat verbunden")
        let hint = String(localized: "Du kannst dieses Fenster schließen.")
        return """
        <!doctype html><html lang="de"><meta charset="utf-8"><title>Stand Bridge</title>
        <body style="font:16px -apple-system,sans-serif;background:#111;color:#eee;display:grid;place-items:center;height:90vh">
        <div><h2>\(title)</h2><p>\(hint)</p></div></body></html>
        """
    }
}
