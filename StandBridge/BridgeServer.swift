import Foundation
import Network
import Observation

@Observable
final class BridgeServer {
    enum Status: Equatable {
        case starting
        case running
        case failed(String)
    }

    static let serviceType = "_duostand._tcp"
    static let maxRequestBytes = 4 << 20
    static let maxConnections = 64

    let board: Board
    let layout: LayoutStore
    let token: String
    let port: UInt16
    let hostName: String
    private(set) var status = Status.starting
    private(set) var lastFocus: WindowFocus.Outcome?
    private(set) var replyLog: [String] = []
    private(set) var lastClient: ClientContact?
    private(set) var requestLog: [RequestLogEntry] = []
    @ObservationIgnored var focus: @MainActor (JSON) async -> WindowFocus.Outcome = WindowFocus.bringToFront
    @ObservationIgnored var reply: @MainActor (String, JSON) async -> JSON = { text, entry in
        await MacReply.send(text, to: entry, via: SystemReplyDesk(), direct: MacReply.isDirectReplyEnabled)
    }
    @ObservationIgnored var apps: @MainActor () -> [JSON] = MacLauncher.apps
    @ObservationIgnored var icon: @MainActor (String) -> Data? = { MacLauncher.icon(bundleId: $0) }
    @ObservationIgnored var open: @MainActor (JSON) async -> Bool = MacLauncher.open
    @ObservationIgnored var openFolder: @MainActor (String) -> Bool = MacLauncher.openFolder
    @ObservationIgnored var system: @MainActor () -> JSON = SystemStats.current
    @ObservationIgnored var orbit: @MainActor () async -> JSON = { await OrbitClient.cachedReport() }
    @ObservationIgnored var gitlab: @MainActor () async -> JSON = { await GitLabClient.cachedReport() }
    @ObservationIgnored var custom: @MainActor (UUID?) -> JSON = { _ in ["widgets": [JSON]()] }
    @ObservationIgnored var codexUsage: @MainActor () -> JSON? = { BridgeModel.isTestHost ? nil : CodexUsage.cachedProvider(in: CodexSettings.sessionsDir) }
    @ObservationIgnored var nowPlaying: @MainActor () async -> JSON = { BridgeModel.isTestHost ? [:] : await MacNowPlaying.info() }
    @ObservationIgnored var nowPlayingArtwork: @MainActor (String?) -> JSON? = MacNowPlaying.artworkPayload
    @ObservationIgnored var nowPlayingControl: @MainActor (JSON) async -> Bool = { BridgeModel.isTestHost ? false : await MacNowPlaying.perform($0) }
    @ObservationIgnored var readTimeout: Duration = .seconds(10)
    @ObservationIgnored private var openConnections: Set<ObjectIdentifier> = []
    @ObservationIgnored private var readingConnections: Set<ObjectIdentifier> = []
    private var listener: NWListener?

    init(board: Board, layout: LayoutStore = LayoutStore(file: nil), token: String, port: UInt16, hostName: String) {
        self.board = board
        self.layout = layout
        self.token = token
        self.port = port
        self.hostName = hostName
    }

    var baseURL: String { "http://\(hostName):\(port)" }

    func start() {
        listener?.cancel()
        status = .starting
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener.service = NWListener.Service(
                type: Self.serviceType,
                txtRecord: NWTXTRecord(["host": hostName, "port": String(port)])
            )
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated { self?.update(state, of: listener) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func update(_ state: NWListener.State, of source: NWListener?) {
        guard source === listener else { return }
        switch state {
        case .ready: status = .running
        case .failed(let error), .waiting(let error):
            listener?.cancel()
            guard error == .posix(.EADDRINUSE) else {
                status = .failed(error.localizedDescription)
                return
            }
            status = .failed("Port \(port) ist belegt – neuer Versuch läuft")
            Task {
                try? await Task.sleep(for: .seconds(3))
                if case .failed = status { start() }
            }
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard openConnections.count < Self.maxConnections else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        openConnections.insert(id)
        readingConnections.insert(id)
        connection.stateUpdateHandler = { [weak self] state in
            guard case .cancelled = state else { return }
            MainActor.assumeIsolated {
                self?.openConnections.remove(id)
                self?.readingConnections.remove(id)
            }
        }
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
        Task { [weak self, readTimeout] in
            try? await Task.sleep(for: readTimeout)
            if self?.readingConnections.contains(id) == true { connection.cancel() }
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                let buffer = buffer + (data ?? Data())
                if let request = HTTPRequest.parse(buffer) {
                    self?.readingConnections.remove(ObjectIdentifier(connection))
                    Task { await self?.respond(to: request, on: connection) }
                } else if error != nil || isComplete || buffer.count > Self.maxRequestBytes {
                    connection.cancel()
                } else {
                    self?.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) async {
        let fromLoopback = Self.isLoopback(connection.endpoint)
        let (status, payload) = await route(request, fromLoopback: fromLoopback)
        record(request, status: status, from: connection.endpoint, loopback: fromLoopback)
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    func route(_ request: HTTPRequest, fromLoopback: Bool) async -> (Int, JSON) {
        switch (request.method, request.path) {
        case ("GET", "/snapshot"):
            guard isAuthorized(request) else { return (401, [:]) }
            var snapshot = board.snapshot(standAnswers: request.query["answer"] == "1")
            snapshot["layoutRevision"] = layout.revision
            snapshot["providers"] = Usage.providers([board.statuslineUsage(), codexUsage()])
            return (200, snapshot)
        case ("GET", "/layout"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (200, layout.json)
        case ("PUT", "/layout"):
            guard isAuthorized(request) else { return (401, [:]) }
            let body = request.json
            if let base = body["baseRevision"] as? Int, base != layout.revision { return (409, layout.json) }
            guard let revision = layout.replace(json: body) else { return (400, [:]) }
            return (200, ["revision": revision])
        case ("POST", "/layout/backup"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (layout.storeDeviceBackup(json: request.json) ? 200 : 400, [:])
        case ("POST", "/hook"):
            guard fromLoopback, isLoopbackRequest(request) else { return (403, [:]) }
            guard Self.constantTimeEquals(request.headers[ClaudeSettings.hookHeaderName] ?? "", token) else { return (401, [:]) }
            return (200, await board.handleHook(Self.hookPayload(request)))
        case ("POST", "/answer"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (board.answer(request.json) ? 200 : 409, [:])
        case ("POST", "/reply"):
            guard isAuthorized(request) else { return (401, [:]) }
            guard let sessionId = request.json["sessionId"] as? String, let entry = board.session(sessionId),
                  let noteId = request.json["noteId"] as? String, let option = request.json["option"] as? Int,
                  let text = board.redeemReply(of: sessionId, noteId: noteId, option: option) else { return (404, [:]) }
            let result = await reply(text, entry)
            if result["sent"] as? Bool == true {
                replyLog = (replyLog + [MacReply.record(sessionId: sessionId, option: option)]).suffix(20)
            }
            return (200, result)
        case ("POST", "/focus"):
            guard isAuthorized(request) else { return (401, [:]) }
            guard let entry = (request.json["sessionId"] as? String).flatMap(board.session) else { return (404, [:]) }
            let outcome = await focus(entry)
            lastFocus = outcome
            return (outcome == .missing ? 404 : 200, ["focused": outcome.rawValue])
        case ("GET", "/apps"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (200, ["apps": apps()])
        case ("GET", "/icon"):
            guard isAuthorized(request) else { return (401, [:]) }
            guard let png = request.query["bundleId"].flatMap(icon) else { return (404, [:]) }
            return (200, ["png": png.base64EncodedString()])
        case ("GET", "/system"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (200, system())
        case ("GET", "/orbit"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (200, await orbit())
        case ("GET", "/gitlab"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (200, await gitlab())
        case ("GET", "/nowplaying"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (200, await nowPlaying())
        case ("GET", "/nowplaying/artwork"):
            guard isAuthorized(request) else { return (401, [:]) }
            guard let artwork = nowPlayingArtwork(request.query["id"]) else { return (404, [:]) }
            return (200, artwork)
        case ("POST", "/nowplaying"):
            guard isAuthorized(request) else { return (401, [:]) }
            return (await nowPlayingControl(request.json) ? 200 : 400, [:])
        case ("GET", "/custom"):
            guard isAuthorized(request) else { return (401, [:]) }
            guard let raw = request.query["id"] else { return (200, custom(nil)) }
            guard let id = UUID(uuidString: raw) else { return (200, ["widgets": [JSON]()]) }
            return (200, custom(id))
        case ("POST", "/open"):
            guard isAuthorized(request) else { return (401, [:]) }
            if let link = request.json["url"] as? String, layout.folderLinks.contains(link) {
                return (openFolder(link) ? 200 : 404, [:])
            }
            guard isAllowedOpenTarget(request.json) else { return (403, [:]) }
            return (await open(request.json) ? 200 : 404, [:])
        default:
            return (404, [:])
        }
    }

    static func hookPayload(_ request: HTTPRequest) -> JSON {
        var payload = request.json
        payload["agent"] = request.query["agent"] == "codex" ? "codex" : "claude"
        payload["pid"] = nil
        if let pid = Int32(request.query["pid"] ?? ""), pid > 1 { payload["pid"] = pid }
        return payload
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        Self.constantTimeEquals(request.headers["authorization"] ?? "", "Bearer \(token)")
    }

    private func isAllowedOpenTarget(_ target: JSON) -> Bool {
        if let bundleId = target["bundleId"] as? String {
            return apps().contains { $0["bundleId"] as? String == bundleId }
        }
        if let link = target["url"] as? String {
            return MacLauncher.isWebURL(link) || layout.shortcuts.contains { $0.kind == .url && $0.value == link }
        }
        if let name = target["shortcut"] as? String {
            return layout.shortcuts.contains { $0.kind == .shortcut && $0.value == name }
        }
        return false
    }

    private func isLoopbackRequest(_ request: HTTPRequest) -> Bool {
        let loopbackHosts: Set<String> = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"]
        return request.headers["origin"] == nil && loopbackHosts.contains(request.headers["host"]?.lowercased() ?? "")
    }

    static func constantTimeEquals(_ given: String, _ expected: String) -> Bool {
        let given = Array(given.utf8)
        let expected = Array(expected.utf8)
        return given.count == expected.count && zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func record(_ request: HTTPRequest, status: Int, from endpoint: NWEndpoint, loopback: Bool) {
        record(request, status: status, host: Self.hostDescription(endpoint), loopback: loopback)
    }

    func record(_ request: HTTPRequest, status: Int, host: String, loopback: Bool, at date: Date = .now) {
        if request.path == "/snapshot" {
            if status == 200 && !loopback { lastClient = ClientContact(at: date, host: host) }
            return
        }
        guard !RequestLogEntry.quietPaths.contains(request.path) else { return }
        let entry = RequestLogEntry(at: date, method: request.method, path: request.path, status: status, host: loopback ? "Mac" : host)
        requestLog = Array((requestLog + [entry]).suffix(RequestLogEntry.limit))
    }

    private static func hostDescription(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "\(endpoint)" }
        switch host {
        case .ipv6(let address): return address.asIPv4.map { "\($0)" } ?? "\(address)"
        default: return "\(host)"
        }
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback || address.asIPv4?.isLoopback == true
        default: return false
        }
    }
}
