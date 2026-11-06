import Foundation

nonisolated struct CustomScriptCall: Decodable, Equatable {
    var method: String?
    var url: String
    var headers: [String: String]?
    var body: String?
}

nonisolated enum CustomScriptRunner {
    struct Run {
        var result: Result<Any, CustomRequestError>
        var logs: [String]
    }

    static let executableName = "amberlight-script"
    static let timeout: TimeInterval = 20
    static let maxRequests = 20
    static let maxLogLines = 200
    static let maxLineBytes = 2 * CustomRequest.maxResponseBytes
    static let minScrubLength = 4
    static let mask = "•••"

    private static let readMethods: Set<String> = ["GET", "HEAD"]
    private static let writeMethods: Set<String> = ["POST", "PUT", "PATCH", "DELETE"]
    private static let dateKeys = ["today", "yesterday", "weekStart", "weekEnd", "monthStart", "monthEnd"]

    static func request(for call: CustomScriptCall, in definition: CustomWidgetDefinition, secret: (String) -> CustomSecret?) throws(CustomRequestError) -> URLRequest {
        guard let url = URL(string: call.url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              let origin = CustomRequest.origin(of: url) else { throw .invalidURL }
        let method = (call.method ?? "GET").uppercased()
        guard readMethods.contains(method) || writeMethods.contains(method) else { throw .invalidURL }
        guard let declared = definition.scriptHost(for: origin),
              (definition.confirmedHosts ?? []).contains(where: { $0.covers(declared) }) else { throw .hostNotAllowed(origin) }
        guard readMethods.contains(method) || declared.writes else { throw .writeNotAllowed(origin) }
        for item in components.queryItems ?? [] where CustomRequest.isSensitive(item.name) { throw .sensitiveName(item.name) }

        let credentials = declared.needsSecret ? secret(origin) : nil
        if declared.needsSecret, credentials?.value.isEmpty ?? true { throw .missingSecret }
        if declared.auth.kind == .queryKey, let credentials {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: declared.auth.name.isEmpty ? "api_key" : declared.auth.name, value: credentials.value)]
        }
        guard let pinned = components.url, CustomRequest.origin(of: pinned) == origin else { throw .invalidURL }

        var request = URLRequest(url: pinned, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: CustomRequest.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in call.headers ?? [:] {
            try CustomRequest.checkScriptHeader(name)
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = call.body, !body.isEmpty {
            guard body.utf8.count <= CustomRequest.maxBodyBytes else { throw .tooLarge }
            request.httpBody = Data(body.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        if let credentials { CustomRequest.authorize(&request, auth: declared.auth, secret: credentials) }
        return request
    }

    static func scrubber(for secrets: [CustomSecret]) -> (String) -> String {
        let needles = secrets.filter { $0.value.count >= minScrubLength }.flatMap { secret in
            [secret.value, CustomRequest.jsonEscaped(secret.value), Data((secret.username + ":" + secret.value).utf8).base64EncodedString()]
        }
        return { text in needles.reduce(text) { $0.replacingOccurrences(of: $1, with: mask) } }
    }

    static func variables(of definition: CustomWidgetDefinition, now: Date) -> [String: String] {
        var variables = Dictionary((definition.variables ?? []).map { ($0.name, $0.value) }, uniquingKeysWith: { $1 })
        for key in dateKeys { variables[key] = CustomRequest.substitute("{\(key)}", now: now) }
        variables["now"] = now.ISO8601Format()
        return variables
    }

    @MainActor
    static func run(_ definition: CustomWidgetDefinition, now: Date = .now, secret: @escaping (String) -> CustomSecret?,
                    fetch: CustomWidgetStore.Fetch) async -> Run {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: executableName) else { return Run(result: .failure(.runnerMissing), logs: []) }
        let scrub = scrubber(for: definition.scriptHosts.compactMap { $0.origin.flatMap(secret) })
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.environment = [:]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch { return Run(result: .failure(.runnerMissing), logs: []) }

        func stop() {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let deadline = Date.now.addingTimeInterval(timeout)
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            stop()
        }
        defer {
            watchdog.cancel()
            stop()
        }

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            try? input.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))
        }

        var logs: [String] = []
        var requests = 0
        func finish(_ result: Result<Any, CustomRequestError>) -> Run { Run(result: result, logs: logs) }

        func handle(_ line: Data) async -> Run? {
            let text = scrub(String(decoding: line, as: UTF8.self))
            guard let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
                return finish(.failure(.scriptFailed(String(localized: "Ungültige Ausgabe"))))
            }
            if let log = message["log"] as? String {
                if logs.count < maxLogLines { logs.append(log) }
            } else if let error = message["error"] as? String {
                return finish(.failure(.scriptFailed(error)))
            } else if let result = message["result"] {
                return finish(.success(result))
            } else if let call = message["http"] {
                requests += 1
                guard requests <= maxRequests else { return finish(.failure(.tooManyRequests)) }
                send(await answer(call, definition: definition, secret: secret, fetch: fetch, scrub: scrub))
            }
            return nil
        }

        let reader = output.fileHandleForReading
        defer { reader.readabilityHandler = nil }
        send(["script": definition.script ?? "", "vars": variables(of: definition, now: now)])
        var buffer = Data()
        for await chunk in chunks(of: reader) {
            guard Date.now < deadline else { return finish(.failure(.scriptTimeout)) }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let run = await handle(line) { return run }
            }
            guard buffer.count <= maxLineBytes else { return finish(.failure(.scriptFailed(String(localized: "Ausgabe zu groß")))) }
        }
        return finish(.failure(Date.now >= deadline ? .scriptTimeout : .scriptFailed(String(localized: "Skript ohne Ergebnis beendet"))))
    }

    private static func chunks(of handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }

    @MainActor
    private static func answer(_ call: Any, definition: CustomWidgetDefinition, secret: (String) -> CustomSecret?,
                               fetch: CustomWidgetStore.Fetch, scrub: (String) -> String) async -> [String: Any] {
        do throws(CustomRequestError) {
            guard let data = try? JSONSerialization.data(withJSONObject: call),
                  let decoded = try? JSONDecoder().decode(CustomScriptCall.self, from: data) else { throw .invalidURL }
            let response = try await fetch(try request(for: decoded, in: definition, secret: secret))
            return ["status": 200, "body": scrub(String(decoding: response.data, as: UTF8.self))]
        } catch {
            return ["error": scrub(error.message)]
        }
    }
}
