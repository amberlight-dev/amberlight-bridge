import Foundation

enum GoogleChatClient {
    struct Space: Decodable, Equatable {
        let name: String
        let displayName: String?
        let spaceType: String?
        let lastActiveTime: String?
        let spaceUri: String?

        var lastActive: Date? { GoogleChatClient.date(lastActiveTime) }
    }

    struct SpacePage: Decodable {
        let spaces: [Space]?
        let nextPageToken: String?
    }

    struct ReadState: Decodable {
        let lastReadTime: String?
    }

    struct User: Decodable, Equatable {
        let name: String?
        let displayName: String?
        let email: String?
        let type: String?
    }

    struct Attachment: Decodable, Equatable {
        let contentName: String?
    }

    struct Message: Decodable, Equatable {
        let name: String
        let sender: User?
        let createTime: String
        let text: String?
        let argumentText: String?
        let fallbackText: String?
        let attachment: [Attachment]?

        var created: Date { GoogleChatClient.date(createTime) ?? .distantPast }
    }

    struct MessagePage: Decodable {
        let messages: [Message]?
        let nextPageToken: String?
    }

    struct Tracked: Equatable {
        var lastActive: Date?
        var lastRead: Date?
        var unread: [Message] = []
        var more = false
        var checked: Date
    }

    struct Inbox {
        var spaces: [Space] = []
        var tracked: [String: Tracked] = [:]
        var polledAt: Date?
        var error: GoogleChatError?
    }

    typealias Get = (String) async throws -> Data

    static let api = "https://chat.googleapis.com/v1/"
    static let home = "https://chat.google.com/"
    static let pollInterval: TimeInterval = 30
    static let lookback: TimeInterval = 7 * 86_400
    static let checkLimit = 25
    static let messageLimit = 20
    static let rowLimit = 12
    static let excerptLimit = 240
    private static let readTolerance: TimeInterval = 0.001

    private static var inbox = Inbox()
    private static var inboxAccount: GoogleChatAccount?
    private static var polling: Task<Void, Never>?
    private static var access: (token: String, expires: Date, account: GoogleChatAccount)?

    static func cachedReport(account: GoogleChatAccount? = Accounts.googleChat, preview: Bool = true, now: Date = .now) async -> JSON {
        guard let account, account.isConnected else { return ["configured": false] }
        if inboxAccount != account {
            inbox = Inbox()
            inboxAccount = account
        }
        if now.timeIntervalSince(inbox.polledAt ?? .distantPast) >= pollInterval {
            let task = polling ?? Task { await refreshInbox(account, now: now) }
            polling = task
            await task.value
            polling = nil
        }
        return payload(inbox, preview: preview)
    }

    static func forgetCache() {
        inbox = Inbox()
        inboxAccount = nil
        access = nil
    }

    private static func refreshInbox(_ account: GoogleChatAccount, now: Date) async {
        do {
            let fresh = try await poll(inbox, account: account, now: now) { try await fetch($0, account: account) }
            if inboxAccount == account { inbox = fresh }
        } catch {
            guard inboxAccount == account else { return }
            let failure = error as? GoogleChatError ?? .unreachable
            inbox.polledAt = now
            if !(failure.isTransient && !inbox.spaces.isEmpty) { inbox.error = failure }
        }
    }


    static func poll(_ previous: Inbox, account: GoogleChatAccount, now: Date, get: Get) async throws -> Inbox {
        var spaces: [Space] = []
        var token = ""
        for _ in 0..<3 {
            let page: SpacePage = try decode(try await get("spaces?" + query(["pageSize": "1000", "pageToken": token])))
            spaces += page.spaces ?? []
            token = page.nextPageToken ?? ""
            if token.isEmpty { break }
        }
        let names = Set(spaces.map(\.name))
        var tracked = previous.tracked.filter { names.contains($0.key) }
        for space in spacesToCheck(spaces, tracked: tracked, now: now) {
            do {
                tracked[space.name] = try await check(space, previous: tracked[space.name], account: account, now: now, get: get)
            } catch let error as GoogleChatError where error.isFatal {
                throw error
            } catch let error as GoogleChatError where error.isTransient {
                break
            } catch {
                tracked[space.name] = Tracked(lastActive: space.lastActive, checked: now)
            }
        }
        return Inbox(spaces: spaces, tracked: tracked, polledAt: now)
    }

    static func spacesToCheck(_ spaces: [Space], tracked: [String: Tracked], now: Date, limit: Int = checkLimit) -> [Space] {
        let newestFirst = spaces.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
        let changed = newestFirst
            .filter { ($0.lastActive ?? .distantPast) > now.addingTimeInterval(-lookback) }
            .filter { space in tracked[space.name].map { $0.lastActive != space.lastActive } ?? true }
        let pending = newestFirst
            .filter { space in tracked[space.name].map { $0.lastActive == space.lastActive && !$0.unread.isEmpty } ?? false }
            .enumerated()
            .sorted { (tracked[$0.element.name]?.checked ?? .distantPast, $0.offset) < (tracked[$1.element.name]?.checked ?? .distantPast, $1.offset) }
            .map(\.element)
        return Array((changed + pending).prefix(limit))
    }

    static func check(_ space: Space, previous: Tracked?, account: GoogleChatAccount, now: Date, get: Get) async throws -> Tracked {
        let state: ReadState = try decode(try await get("users/me/\(space.name)/spaceReadState"))
        let lastRead = date(state.lastReadTime)
        var tracked = Tracked(lastActive: space.lastActive, lastRead: lastRead, unread: previous?.unread ?? [], more: previous?.more ?? false, checked: now)
        if let active = space.lastActive, let lastRead, active <= lastRead.addingTimeInterval(readTolerance) {
            tracked.unread = []
            tracked.more = false
            return tracked
        }
        let stale = previous == nil || previous?.lastActive != space.lastActive || (previous?.more == true && previous?.lastRead != lastRead)
        guard stale else {
            tracked.unread = tracked.unread.filter { isAfter($0.created, lastRead) }
            return tracked
        }
        let since = state.lastReadTime ?? timestamp(now.addingTimeInterval(-lookback))
        var parameters = ["filter": "createTime > \"\(since)\"", "pageSize": "\(messageLimit)", "orderBy": "DESC"]
        let page: MessagePage
        do {
            page = try decode(try await get("\(space.name)/messages?" + query(parameters)))
        } catch GoogleChatError.status(400) {
            parameters["orderBy"] = nil
            page = try decode(try await get("\(space.name)/messages?" + query(parameters)))
        }
        tracked.unread = unread(page.messages ?? [], after: lastRead, account: account)
        tracked.more = !(page.nextPageToken ?? "").isEmpty
        return tracked
    }

    static func unread(_ messages: [Message], after lastRead: Date?, account: GoogleChatAccount) -> [Message] {
        messages
            .filter { !isOwn($0, account: account) && isAfter($0.created, lastRead) }
            .sorted { $0.created > $1.created }
    }

    static func isOwn(_ message: Message, account: GoogleChatAccount) -> Bool {
        if let id = account.userID, message.sender?.name == "users/" + id { return true }
        guard let mine = account.email?.lowercased(), let email = message.sender?.email?.lowercased() else { return false }
        return mine == email
    }

    private static func isAfter(_ created: Date, _ lastRead: Date?) -> Bool {
        lastRead.map { created > $0.addingTimeInterval(readTolerance) } ?? true
    }


    static func payload(_ inbox: Inbox, preview: Bool) -> JSON {
        if let error = inbox.error { return ["configured": true, "error": error.message] }
        let rows = inbox.spaces
            .compactMap { space -> (space: Space, tracked: Tracked)? in
                guard let tracked = inbox.tracked[space.name], !tracked.unread.isEmpty else { return nil }
                return (space, tracked)
            }
            .sorted { $0.tracked.unread[0].created > $1.tracked.unread[0].created }
        return [
            "configured": true,
            "unread": rows.reduce(0) { $0 + $1.tracked.unread.count },
            "more": rows.contains { $0.tracked.more },
            "home": home,
            "spaces": rows.prefix(rowLimit).map { row($0.space, tracked: $0.tracked, preview: preview) },
        ]
    }

    static func row(_ space: Space, tracked: Tracked, preview: Bool) -> JSON {
        let newest = tracked.unread[0]
        var latest: JSON = ["id": newest.name, "sender": senderName(newest), "at": newest.created.timeIntervalSince1970]
        if preview { latest["text"] = excerpt(newest) }
        return [
            "id": space.name,
            "title": title(of: space, unread: tracked.unread),
            "kind": kind(of: space),
            "unread": tracked.unread.count,
            "more": tracked.more,
            "url": link(for: space),
            "latest": latest,
        ]
    }

    static func link(for space: Space) -> String {
        if let uri = space.spaceUri, MacLauncher.isWebURL(uri) { return uri }
        let id = space.name.replacingOccurrences(of: "spaces/", with: "")
        return "https://mail.google.com/chat/u/0/#chat/\(space.spaceType == "DIRECT_MESSAGE" ? "dm" : "space")/\(id)"
    }

    static func kind(of space: Space) -> String {
        switch space.spaceType {
        case "DIRECT_MESSAGE": "dm"
        case "GROUP_CHAT": "group"
        default: "space"
        }
    }

    static func title(of space: Space, unread: [Message]) -> String {
        if let name = space.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        var senders: [String] = []
        for name in unread.map(senderName) where !senders.contains(name) { senders.append(name) }
        switch space.spaceType {
        case "DIRECT_MESSAGE": return senders.first ?? String(localized: "Direktnachricht")
        case "GROUP_CHAT": return senders.isEmpty ? String(localized: "Gruppenchat") : senders.prefix(3).joined(separator: ", ")
        default: return String(localized: "Bereich")
        }
    }

    static func senderName(_ message: Message) -> String {
        if let name = message.sender?.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let local = message.sender?.email?.split(separator: "@").first { return String(local) }
        return message.sender?.type == "BOT" ? String(localized: "Chat-App") : String(localized: "Unbekannt")
    }

    static func excerpt(_ message: Message, limit: Int = excerptLimit) -> String {
        let raw = message.text ?? message.argumentText ?? ""
        var text = raw.replacing(/<users\/[^>]+>/, with: "@…").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.isEmpty {
            let fallback = (message.fallbackText ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text = !fallback.isEmpty ? fallback : (message.attachment ?? []).isEmpty ? String(localized: "Nachricht ohne Text") : String(localized: "Anhang")
        }
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }


    static func date(_ text: String?) -> Date? {
        guard var text, !text.isEmpty else { return nil }
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let end = text[dot...].dropFirst().firstIndex { !$0.isNumber } ?? text.endIndex
            fraction = Double("0" + text[dot..<end]) ?? 0
            text.removeSubrange(dot..<end)
        }
        return (try? Date(text, strategy: .iso8601)).map { $0.addingTimeInterval(fraction) }
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func query(_ parameters: [String: String]) -> String {
        GoogleAuth.formEncoded(parameters.filter { !$0.value.isEmpty })
    }

    static func apiFailure(status: Int, body: Data) -> GoogleChatError {
        let text = String(decoding: body, as: UTF8.self)
        switch status {
        case 401: return .reconnect
        case 403 where ["SERVICE_DISABLED", "accessNotConfigured", "has not been used"].contains { text.contains($0) }: return .apiDisabled
        case 403 where text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") || text.contains("insufficient authentication scopes"): return .missingScopes
        case 404 where text.contains("Chat app not found"): return .appMissing
        case 429: return .rateLimited
        default: return .status(status)
        }
    }

    private static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else { throw GoogleChatError.malformed }
        return value
    }

    private static func fetch(_ path: String, account: GoogleChatAccount) async throws -> Data {
        let (status, data) = try await send(path, token: try await accessToken(for: account))
        guard status == 401 else { return try accepted(status, data) }
        access = nil
        let (retried, body) = try await send(path, token: try await accessToken(for: account))
        return try accepted(retried, body)
    }

    private static func accepted(_ status: Int, _ data: Data) throws -> Data {
        guard status == 200 else { throw apiFailure(status: status, body: data) }
        return data
    }

    private static func send(_ path: String, token: String) async throws -> (Int, Data) {
        guard let url = URL(string: api + path) else { throw GoogleChatError.malformed }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw GoogleChatError.unreachable }
        return (status, data)
    }

    private static func accessToken(for account: GoogleChatAccount, now: Date = .now) async throws -> String {
        if let access, access.account == account, access.expires > now { return access.token }
        let fresh = try await GoogleAuth.refresh(account, now: now)
        access = (fresh.token, fresh.expires, account)
        return fresh.token
    }
}
