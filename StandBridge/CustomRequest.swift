import Foundation

nonisolated struct CustomSecret: Codable, Equatable {
    var value = ""
    var username = ""
}

nonisolated enum CustomRequestError: Error, Equatable {
    case invalidURL, insecureScheme, userInfo, sensitiveName(String), missingSecret, unconfirmed
    case layoutTooComplex, tooLarge, timeout, unreachable, unauthorized, status(Int), notJSON, redirected

    var message: String {
        switch self {
        case .invalidURL: String(localized: "Basis-URL ist ungültig")
        case .insecureScheme: String(localized: "Nur https – http nur für localhost bzw. private Adressen")
        case .userInfo: String(localized: "Zugangsdaten gehören nicht in die URL, nutze die Authentifizierung")
        case .sensitiveName(let name): String(localized: "„\(name)“ sieht nach Zugangsdaten aus – trag sie unter Authentifizierung ein")
        case .missingSecret: "Zugangsdaten fehlen"
        case .unconfirmed: String(localized: "Freigabe fehlt – Host am Mac bestätigen")
        case .layoutTooComplex: String(localized: "Layout zu verschachtelt – höchstens \(CustomNode.maxNodes) Bausteine in \(CustomNode.maxDepth) Ebenen")
        case .tooLarge: String(localized: "Antwort größer als \(CustomRequest.maxResponseBytes >> 10) KB")
        case .timeout: String(localized: "Keine Antwort nach \(Int(CustomRequest.timeout)) s")
        case .unreachable: String(localized: "API nicht erreichbar")
        case .unauthorized: String(localized: "API lehnt die Zugangsdaten ab")
        case .status(let code): String(localized: "API antwortet mit \(code)")
        case .notJSON: String(localized: "Antwort ist kein JSON")
        case .redirected: String(localized: "Weiterleitung auf einen anderen Host blockiert")
        }
    }
}

nonisolated enum CustomRequest {
    static let maxResponseBytes = 1 << 20
    static let timeout: TimeInterval = 10
    static let maxBodyBytes = 16 << 10

    private static let sensitiveExact: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "key", "sig", "signature", "auth",
    ]
    private static let sensitiveParts = ["token", "secret", "password", "passwd", "apikey", "api-key", "api_key", "session", "credential"]
    private static let reservedHeaders: Set<String> = ["host", "content-length", "connection", "transfer-encoding"]

    static func origin(of base: String) -> String? {
        guard let components = URLComponents(string: base.trimmingCharacters(in: .whitespaces)) else { return nil }
        return origin(of: components)
    }

    static func origin(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false).flatMap(origin(of:))
    }

    static func isSensitive(_ name: String) -> Bool {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespaces)
        return sensitiveExact.contains(lowered) || sensitiveParts.contains { lowered.contains($0) }
    }

    static func isPrivate(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.contains(":") { return host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, host.split(separator: ".").count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    static func usesPlainHTTP(_ base: String) -> Bool {
        URLComponents(string: base.trimmingCharacters(in: .whitespaces))?.scheme?.lowercased() == "http"
    }

    static func validate(_ definition: CustomWidgetDefinition) throws(CustomRequestError) {
        guard let components = URLComponents(string: definition.baseURL.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(), let host = components.host, !host.isEmpty else { throw .invalidURL }
        guard components.user == nil, components.password == nil else { throw .userInfo }
        switch scheme {
        case "https": break
        case "http" where isPrivate(host: host): break
        default: throw .insecureScheme
        }
        if [definition.display.layout, definition.display.compact, definition.display.wide].contains(where: { $0?.isTooComplex == true }) { throw .layoutTooComplex }
        for pair in definition.endpoint.headers where !pair.name.isEmpty {
            if isSensitive(pair.name) || reservedHeaders.contains(pair.name.lowercased()) { throw .sensitiveName(pair.name) }
        }
        for pair in definition.endpoint.query + queryItems(of: components).map({ .init(name: $0.name, value: $0.value ?? "") }) where isSensitive(pair.name) {
            throw .sensitiveName(pair.name)
        }
    }

    static func build(_ definition: CustomWidgetDefinition, now: Date = .now, secret: (String) -> CustomSecret?) throws(CustomRequestError) -> URLRequest {
        try validate(definition)
        guard var components = URLComponents(string: definition.baseURL.trimmingCharacters(in: .whitespaces)),
              let pinned = origin(of: components) else { throw .invalidURL }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let endpointPath = substitute(definition.endpoint.path.trimmingCharacters(in: .whitespaces), now: now)
        components.path = basePath + (endpointPath.isEmpty || endpointPath.hasPrefix("/") ? "" : "/") + endpointPath
        components.fragment = nil
        var items = queryItems(of: components)
        for pair in definition.endpoint.query where !pair.name.isEmpty {
            let value = substitute(pair.value, now: now)
            if !value.isEmpty { items.append(URLQueryItem(name: pair.name, value: value)) }
        }
        let credentials = definition.needsSecret ? secret(pinned) : nil
        if definition.needsSecret, credentials?.value.isEmpty ?? true { throw .missingSecret }
        if definition.auth.kind == .queryKey, let credentials {
            items.append(URLQueryItem(name: definition.auth.name.isEmpty ? "api_key" : definition.auth.name, value: credentials.value))
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url, origin(of: url) == pinned else { throw .invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = definition.endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for pair in definition.endpoint.headers where !pair.name.isEmpty {
            request.setValue(substitute(pair.value, now: now), forHTTPHeaderField: pair.name)
        }
        if definition.endpoint.method == .post, !definition.endpoint.body.isEmpty {
            let body = Data(substitute(definition.endpoint.body, now: now).utf8)
            guard body.count <= maxBodyBytes else { throw .tooLarge }
            request.httpBody = body
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        if let credentials { authorize(&request, auth: definition.auth, secret: credentials) }
        return request
    }

    static func substitute(_ text: String, now: Date) -> String {
        guard text.contains("{") else { return text }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        let values: [String: Date?] = [
            "{today}": day,
            "{yesterday}": calendar.date(byAdding: .day, value: -1, to: day),
            "{weekStart}": week?.start,
            "{weekEnd}": week.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) },
            "{monthStart}": month?.start,
            "{monthEnd}": month.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) },
        ]
        let format = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        return values.reduce(text) { text, entry in
            guard let date = entry.value else { return text }
            return text.replacingOccurrences(of: entry.key, with: date.formatted(format))
        }
    }

    private static func authorize(_ request: inout URLRequest, auth: CustomWidgetDefinition.Auth, secret: CustomSecret) {
        switch auth.kind {
        case .none, .queryKey: break
        case .bearer: request.setValue("Bearer " + secret.value, forHTTPHeaderField: "Authorization")
        case .headerKey: request.setValue(secret.value, forHTTPHeaderField: auth.name.isEmpty ? "X-API-Key" : auth.name)
        case .basic:
            let pair = Data((secret.username + ":" + secret.value).utf8).base64EncodedString()
            request.setValue("Basic " + pair, forHTTPHeaderField: "Authorization")
        case .customHeader: request.setValue(auth.prefix + secret.value, forHTTPHeaderField: auth.name.isEmpty ? "Authorization" : auth.name)
        }
    }

    private static func origin(of components: URLComponents) -> String? {
        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    private static func queryItems(of components: URLComponents) -> [URLQueryItem] {
        components.queryItems ?? []
    }
}
