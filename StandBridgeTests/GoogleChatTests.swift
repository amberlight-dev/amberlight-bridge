import XCTest
@testable import StandBridge

@MainActor
final class GoogleChatTests: XCTestCase {
    private typealias Client = GoogleChatClient

    private let account = GoogleChatAccount(clientID: "id", clientSecret: "secret", refreshToken: "r", email: "Max.Muster@example.com", userID: "999")

    private final class FakeGoogle {
        var routes: [String: String] = [:]
        var failures: [String: GoogleChatError] = [:]
        var paths: [String] = []

        func get(_ path: String) throws -> Data {
            paths.append(path)
            let key = path.components(separatedBy: "?")[0]
            if let failure = failures[key] { throw failure }
            guard let body = routes[key] else { throw GoogleChatError.status(404) }
            return Data(body.utf8)
        }

        func reset() { paths = [] }
        func count(_ fragment: String) -> Int { paths.filter { $0.contains(fragment) }.count }
    }

    private static let spaces = #"""
    {"spaces":[
     {"name":"spaces/AAA","displayName":"Design-Team","spaceType":"SPACE","lastActiveTime":"2026-10-23T09:58:00.123456Z","spaceUri":"https://chat.google.com/room/AAA?cls=7"},
     {"name":"spaces/DM1","displayName":"","spaceType":"DIRECT_MESSAGE","lastActiveTime":"2026-10-23T09:59:30Z"},
     {"name":"spaces/OLD","displayName":"Archiv","spaceType":"SPACE","lastActiveTime":"2026-09-01T08:00:00Z"},
     {"name":"spaces/MINE","displayName":"Notizen","spaceType":"SPACE","lastActiveTime":"2026-10-23T08:00:00Z"}
    ],"nextPageToken":""}
    """#

    private static let designMessages = #"""
    {"messages":[
     {"name":"spaces/AAA/messages/m3","sender":{"name":"users/111","displayName":"Anna Huber","email":"anna@example.com","type":"HUMAN"},
      "createTime":"2026-10-23T09:58:00.123456Z","text":"Hallo <users/222> –\n\nkannst du dir   den Entwurf ansehen?","thread":{"name":"spaces/AAA/threads/t1"}},
     {"name":"spaces/AAA/messages/m2","sender":{"name":"users/999","displayName":"Max Muster","type":"HUMAN"},"createTime":"2026-10-23T09:30:00Z","text":"Mein Text"},
     {"name":"spaces/AAA/messages/m1","sender":{"name":"users/333","displayName":"Bernd","type":"HUMAN"},"createTime":"2026-10-23T09:10:00Z","text":"",
      "attachment":[{"contentName":"plan.pdf"}]}
    ]}
    """#

    private static let directMessages = #"""
    {"messages":[{"name":"spaces/DM1/messages/x","sender":{"name":"users/444","displayName":"Clara","email":"clara@example.com","type":"HUMAN"},
      "createTime":"2026-10-23T09:59:30Z","text":"Mittagessen?"}],"nextPageToken":"weiter"}
    """#

    private func fake() -> FakeGoogle {
        let google = FakeGoogle()
        google.routes = [
            "spaces": Self.spaces,
            "users/me/spaces/AAA/spaceReadState": #"{"lastReadTime":"2026-10-23T09:00:00Z"}"#,
            "users/me/spaces/DM1/spaceReadState": #"{"lastReadTime":"2026-10-22T18:00:00.5Z"}"#,
            "users/me/spaces/MINE/spaceReadState": #"{"lastReadTime":"2026-10-23T08:00:00Z"}"#,
            "spaces/AAA/messages": Self.designMessages,
            "spaces/DM1/messages": Self.directMessages,
        ]
        return google
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(Client.date(text))
    }

    private func poll(_ inbox: Client.Inbox, _ google: FakeGoogle, at now: Date) async throws -> Client.Inbox {
        try await Client.poll(inbox, account: account, now: now) { try google.get($0) }
    }

    // MARK: Parsing

    func testParsesSpacesReadStateAndMessages() throws {
        let page = try JSONDecoder().decode(Client.SpacePage.self, from: Data(Self.spaces.utf8))
        let spaces = try XCTUnwrap(page.spaces)
        XCTAssertEqual(spaces.map(\.name), ["spaces/AAA", "spaces/DM1", "spaces/OLD", "spaces/MINE"])
        XCTAssertEqual(spaces[1].spaceType, "DIRECT_MESSAGE")
        let active = try XCTUnwrap(spaces[0].lastActive)
        XCTAssertEqual(active.timeIntervalSince(try date("2026-10-23T09:58:00Z")), 0.123456, accuracy: 0.000_01)

        let state = try JSONDecoder().decode(Client.ReadState.self, from: Data(#"{"lastReadTime":"2026-10-23T11:00:00+02:00"}"#.utf8))
        XCTAssertEqual(Client.date(state.lastReadTime), try date("2026-10-23T09:00:00Z"))
        XCTAssertNil(try JSONDecoder().decode(Client.ReadState.self, from: Data("{}".utf8)).lastReadTime)

        let messages = try XCTUnwrap(try JSONDecoder().decode(Client.MessagePage.self, from: Data(Self.designMessages.utf8)).messages)
        XCTAssertEqual(messages.first?.sender?.displayName, "Anna Huber")
        XCTAssertEqual(messages.last?.attachment?.count, 1)
        XCTAssertNil(try JSONDecoder().decode(Client.MessagePage.self, from: Data("{}".utf8)).messages)
    }

    func testExcerptCleansMentionsWhitespaceAndLength() throws {
        let messages = try XCTUnwrap(try JSONDecoder().decode(Client.MessagePage.self, from: Data(Self.designMessages.utf8)).messages)
        XCTAssertEqual(Client.excerpt(messages[0]), "Hallo @… – kannst du dir den Entwurf ansehen?")
        XCTAssertEqual(Client.excerpt(messages[2]), "Anhang")
        let long = Client.Message(name: "m", sender: nil, createTime: "2026-10-23T09:00:00Z", text: String(repeating: "a", count: 400), argumentText: nil, fallbackText: nil, attachment: nil)
        XCTAssertEqual(Client.excerpt(long).count, Client.excerptLimit)
        XCTAssertTrue(Client.excerpt(long).hasSuffix("…"))
        XCTAssertEqual(Client.senderName(long), "Unbekannt")
    }

    // MARK: Ungelesen

    func testUnreadSkipsOwnAndAlreadyReadMessages() throws {
        let messages = try XCTUnwrap(try JSONDecoder().decode(Client.MessagePage.self, from: Data(Self.designMessages.utf8)).messages)
        let unread = Client.unread(messages, after: try date("2026-10-23T09:00:00Z"), account: account)
        XCTAssertEqual(unread.map(\.name), ["spaces/AAA/messages/m3", "spaces/AAA/messages/m1"])
        XCTAssertEqual(Client.unread(messages, after: try date("2026-10-23T09:58:00.123456Z"), account: account), [])

        var byMail = account
        byMail.userID = nil
        let anna = messages[0]
        XCTAssertFalse(Client.isOwn(anna, account: byMail))
        byMail.email = "ANNA@example.com"
        XCTAssertTrue(Client.isOwn(anna, account: byMail))
        XCTAssertTrue(Client.isOwn(messages[1], account: account))
    }

    func testSpacesToCheckPrefersChangedThenUnreadAndSkipsOldOnes() throws {
        let spaces = try XCTUnwrap(try JSONDecoder().decode(Client.SpacePage.self, from: Data(Self.spaces.utf8)).spaces)
        let now = try date("2026-10-23T10:00:00Z")
        XCTAssertEqual(Client.spacesToCheck(spaces, tracked: [:], now: now).map(\.name), ["spaces/DM1", "spaces/AAA", "spaces/MINE"])
        XCTAssertEqual(Client.spacesToCheck(spaces, tracked: [:], now: now, limit: 1).map(\.name), ["spaces/DM1"])

        let message = Client.Message(name: "m", sender: nil, createTime: "2026-10-23T09:58:00Z", text: "x", argumentText: nil, fallbackText: nil, attachment: nil)
        let tracked: [String: Client.Tracked] = [
            "spaces/AAA": Client.Tracked(lastActive: spaces[0].lastActive, unread: [message], checked: now),
            "spaces/DM1": Client.Tracked(lastActive: spaces[1].lastActive, checked: now),
            "spaces/MINE": Client.Tracked(lastActive: try date("2026-10-23T07:00:00Z"), checked: now),
            "spaces/OLD": Client.Tracked(lastActive: spaces[2].lastActive, unread: [message], checked: now.addingTimeInterval(-60)),
        ]
        XCTAssertEqual(Client.spacesToCheck(spaces, tracked: tracked, now: now).map(\.name), ["spaces/MINE", "spaces/OLD", "spaces/AAA"])
    }

    func testPollOnlyFetchesMessagesForChangedSpaces() async throws {
        let google = fake()
        let now = try date("2026-10-23T10:00:00Z")

        var inbox = try await poll(Client.Inbox(), google, at: now)
        XCTAssertEqual(google.paths.count, 6)
        XCTAssertEqual(google.count("/messages?"), 2)
        XCTAssertEqual(google.count("OLD"), 0)
        let request = try XCTUnwrap(google.paths.first { $0.hasPrefix("spaces/AAA/messages?") })
        XCTAssertTrue(request.contains("filter=createTime%20%3E%20%222026-10-23T09%3A00%3A00Z%22"), request)
        XCTAssertTrue(request.contains("orderBy=DESC"))
        XCTAssertTrue(request.contains("pageSize=20"))
        XCTAssertEqual(inbox.tracked["spaces/AAA"]?.unread.count, 2)
        XCTAssertEqual(inbox.tracked["spaces/DM1"]?.more, true)
        XCTAssertEqual(inbox.tracked["spaces/MINE"]?.unread, [])

        google.reset()
        inbox = try await poll(inbox, google, at: now.addingTimeInterval(30))
        XCTAssertEqual(google.paths, ["spaces?pageSize=1000", "users/me/spaces/DM1/spaceReadState", "users/me/spaces/AAA/spaceReadState"])
        XCTAssertEqual(inbox.tracked["spaces/AAA"]?.unread.count, 2)

        google.reset()
        google.routes["users/me/spaces/AAA/spaceReadState"] = #"{"lastReadTime":"2026-10-23T09:58:30Z"}"#
        inbox = try await poll(inbox, google, at: now.addingTimeInterval(60))
        XCTAssertEqual(google.count("/messages?"), 0)
        XCTAssertEqual(inbox.tracked["spaces/AAA"]?.unread, [])

        google.reset()
        google.routes["spaces"] = Self.spaces.replacingOccurrences(of: "2026-10-23T09:58:00.123456Z", with: "2026-10-23T10:01:00Z")
        inbox = try await poll(inbox, google, at: now.addingTimeInterval(90))
        XCTAssertEqual(google.count("spaces/AAA/messages?"), 1)
        XCTAssertEqual(google.count("spaces/DM1/messages?"), 0)
    }

    func testPollKeepsGoingPastBrokenSpacesAndStopsOnFatalErrors() async throws {
        let google = fake()
        let now = try date("2026-10-23T10:00:00Z")
        google.failures["users/me/spaces/DM1/spaceReadState"] = .status(403)
        let inbox = try await poll(Client.Inbox(), google, at: now)
        XCTAssertEqual(inbox.tracked["spaces/DM1"]?.unread, [])
        XCTAssertEqual(inbox.tracked["spaces/AAA"]?.unread.count, 2)

        google.failures["users/me/spaces/DM1/spaceReadState"] = .rateLimited
        let partial = try await poll(Client.Inbox(), google, at: now)
        XCTAssertNil(partial.tracked["spaces/DM1"])
        XCTAssertNil(partial.tracked["spaces/AAA"])

        google.failures["users/me/spaces/DM1/spaceReadState"] = .reconnect
        do {
            _ = try await poll(Client.Inbox(), google, at: now)
            XCTFail("Abgelaufener Zugang muss die Abfrage abbrechen")
        } catch {
            XCTAssertEqual(error as? GoogleChatError, .reconnect)
        }
    }

    func testPayloadSortsNewestFirstAndHidesTextWithoutPreview() async throws {
        let inbox = try await poll(Client.Inbox(), fake(), at: try date("2026-10-23T10:00:00Z"))
        let payload = Client.payload(inbox, preview: true)
        XCTAssertEqual(payload["unread"] as? Int, 3)
        XCTAssertEqual(payload["more"] as? Bool, true)
        let rows = try XCTUnwrap(payload["spaces"] as? [JSON])
        XCTAssertEqual(rows.compactMap { $0["id"] as? String }, ["spaces/DM1", "spaces/AAA"])
        XCTAssertEqual(rows[0]["title"] as? String, "Clara")
        XCTAssertEqual(rows[0]["kind"] as? String, "dm")
        XCTAssertEqual(rows[1]["url"] as? String, "https://chat.google.com/room/AAA?cls=7")
        let latest = try XCTUnwrap(rows[1]["latest"] as? JSON)
        XCTAssertEqual(latest["sender"] as? String, "Anna Huber")
        XCTAssertEqual(latest["text"] as? String, "Hallo @… – kannst du dir den Entwurf ansehen?")
        XCTAssertEqual(latest["at"] as? Double ?? 0, try date("2026-10-23T09:58:00.123456Z").timeIntervalSince1970, accuracy: 0.001)

        let quiet = Client.payload(inbox, preview: false)
        let quietRows = try XCTUnwrap(quiet["spaces"] as? [JSON])
        XCTAssertTrue(quietRows.allSatisfy { ($0["latest"] as? JSON)?["text"] == nil })
        XCTAssertNotNil(try JSONSerialization.data(withJSONObject: payload))

        var failing = inbox
        failing.error = .apiDisabled
        XCTAssertEqual(Client.payload(failing, preview: true)["error"] as? String, GoogleChatError.apiDisabled.message)
    }

    func testLinkPrefersSpaceUriAndFallsBackPerType() {
        func space(_ name: String, type: String, uri: String? = nil, title: String? = nil) -> Client.Space {
            Client.Space(name: name, displayName: title, spaceType: type, lastActiveTime: nil, spaceUri: uri)
        }
        XCTAssertEqual(Client.link(for: space("spaces/A", type: "SPACE", uri: "https://chat.google.com/room/A")), "https://chat.google.com/room/A")
        XCTAssertEqual(Client.link(for: space("spaces/A", type: "SPACE", uri: "javascript:alert(1)")), "https://mail.google.com/chat/u/0/#chat/space/A")
        XCTAssertEqual(Client.link(for: space("spaces/D", type: "DIRECT_MESSAGE")), "https://mail.google.com/chat/u/0/#chat/dm/D")
        XCTAssertEqual(Client.title(of: space("spaces/G", type: "GROUP_CHAT"), unread: []), "Gruppenchat")
        XCTAssertEqual(Client.title(of: space("spaces/A", type: "SPACE", title: " Team "), unread: []), "Team")
    }

    func testUnconnectedAccountIsUnconfigured() async {
        let none = await Client.cachedReport(account: nil)
        XCTAssertEqual(none["configured"] as? Bool, false)
        var signedOut = account
        signedOut.refreshToken = nil
        let disconnected = await Client.cachedReport(account: signedOut)
        XCTAssertEqual(disconnected["configured"] as? Bool, false)
    }

    // MARK: OAuth

    func testPKCEMatchesRFC7636AndUsesUnreservedCharacters() {
        let known = GoogleAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(known.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")

        let fresh = GoogleAuth.PKCE()
        XCTAssertTrue((43...128).contains(fresh.verifier.count))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        XCTAssertTrue(fresh.verifier.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertNotEqual(fresh.verifier, GoogleAuth.PKCE().verifier)
    }

    func testAuthorizationURLCarriesLoopbackPKCEAndOfflineAccess() throws {
        let pkce = GoogleAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = GoogleAuth.authorizationURL(clientID: "123.apps.googleusercontent.com", redirect: "http://127.0.0.1:5555", pkce: pkce, state: "s1")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host(), "accounts.google.com")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:5555")
        XCTAssertEqual(query["code_challenge"], pkce.challenge)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["access_type"], "offline")
        XCTAssertEqual(query["prompt"], "consent")
        XCTAssertEqual(query["state"], "s1")
        XCTAssertNil(query["login_hint"])
        XCTAssertEqual(query["scope"]?.split(separator: " ").map(String.init), GoogleAuth.scopes)
        XCTAssertFalse(url.absoluteString.contains("+"))
    }

    func testGrantedScopesAndIdentity() throws {
        let granted = "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/chat.spaces.readonly https://www.googleapis.com/auth/chat.messages.readonly"
        XCTAssertEqual(GoogleAuth.missingScopes(in: granted), ["https://www.googleapis.com/auth/chat.users.readstate.readonly"])
        XCTAssertEqual(GoogleAuth.missingScopes(in: granted + " https://www.googleapis.com/auth/chat.users.readstate.readonly"), [])

        let claims = GoogleAuth.base64URL(try JSONSerialization.data(withJSONObject: ["email": "max.muster@example.com", "sub": "1180", "hd": "example.com"]))
        let identity = GoogleAuth.identity(fromIDToken: "eyJhbGciOiJSUzI1NiJ9.\(claims).sig")
        XCTAssertEqual(identity.email, "max.muster@example.com")
        XCTAssertEqual(identity.userID, "1180")
        XCTAssertNil(GoogleAuth.identity(fromIDToken: "kaputt").email)
    }

    func testTokenAndAPIErrorsMapToActions() {
        func body(_ text: String) -> Data { Data(text.utf8) }
        XCTAssertEqual(GoogleAuth.tokenFailure(status: 400, body: body(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)), .reconnect)
        XCTAssertEqual(GoogleAuth.tokenFailure(status: 401, body: body(#"{"error":"invalid_client"}"#)), .invalidClient)
        XCTAssertEqual(GoogleAuth.tokenFailure(status: 503, body: body("")), .status(503))
        XCTAssertTrue(GoogleChatError.status(503).isTransient)
        XCTAssertTrue(GoogleChatError.reconnect.isFatal)
        XCTAssertTrue(GoogleChatError.reconnect.message.contains("neu verbinden"))

        let disabled = #"{"error":{"code":403,"message":"Google Chat API has not been used in project 1 before or it is disabled.","status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}"#
        XCTAssertEqual(Client.apiFailure(status: 403, body: body(disabled)), .apiDisabled)
        XCTAssertEqual(Client.apiFailure(status: 403, body: body(#"{"error":{"details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#)), .missingScopes)
        XCTAssertEqual(Client.apiFailure(status: 404, body: body(#"{"error":{"code":404,"message":"Google Chat app not found. To create a Chat app, you must turn on the Chat API and configure the app in the Google Cloud console."}}"#)), .appMissing)
        XCTAssertEqual(Client.apiFailure(status: 404, body: body("{}")), .status(404))
        XCTAssertEqual(Client.apiFailure(status: 429, body: body("{}")), .rateLimited)
        XCTAssertEqual(Client.apiFailure(status: 401, body: body("{}")), .reconnect)
    }

    func testLoopbackCapturesGoogleRedirect() async throws {
        let loopback = try GoogleLoopback()
        defer { loopback.stop() }
        let port = try await loopback.start()
        XCTAssertGreaterThan(port, 0)
        let base = "http://127.0.0.1:\(port)"
        let page = Task {
            _ = try? await URLSession.shared.data(from: URL(string: base + "/favicon.ico")!)
            return try await URLSession.shared.data(from: URL(string: base + "/?state=s1&code=4%2Fabc&scope=x")!).0
        }
        let query = try await loopback.callback(timeout: .seconds(10))
        XCTAssertEqual(query["code"], "4/abc")
        XCTAssertEqual(query["state"], "s1")
        let html = String(decoding: try await page.value, as: UTF8.self)
        XCTAssertTrue(html.contains("verbunden"))
    }

    func testLoopbackTimesOut() async throws {
        let loopback = try GoogleLoopback()
        defer { loopback.stop() }
        _ = try await loopback.start()
        do {
            _ = try await loopback.callback(timeout: .milliseconds(50))
            XCTFail("Ohne Antwort muss die Anmeldung ablaufen")
        } catch {
            XCTAssertEqual(error as? GoogleChatError, .timeout)
        }
    }

    // MARK: Route

    func testGoogleChatRouteRequiresTokenAndPassesPreviewFlag() async throws {
        func request(_ path: String, token: String) throws -> HTTPRequest {
            try XCTUnwrap(HTTPRequest.parse(Data("GET \(path) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: 0\r\n\r\n".utf8)))
        }
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), deviceToken: "abcd1234", localToken: "hook5678", port: 1, hostName: "mac.local")
        var previews: [Bool] = []
        server.googleChat = { preview in
            previews.append(preview)
            return ["configured": true, "unread": 2]
        }
        let (denied, _) = await server.route(try request("/gchat", token: "nope"), fromLoopback: true)
        XCTAssertEqual(denied, 401)
        XCTAssertEqual(previews, [])

        let (status, payload) = await server.route(try request("/gchat", token: "abcd1234"), fromLoopback: false)
        let (quiet, _) = await server.route(try request("/gchat?preview=0", token: "abcd1234"), fromLoopback: false)
        XCTAssertEqual([status, quiet], [200, 200])
        XCTAssertEqual(payload["unread"] as? Int, 2)
        XCTAssertEqual(previews, [true, false])
        XCTAssertTrue(RequestLogEntry.quietPaths.contains("/gchat"))
    }
}
