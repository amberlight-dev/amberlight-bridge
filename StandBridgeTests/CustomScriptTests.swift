import XCTest
@testable import StandBridge

@MainActor
final class CustomScriptTests: XCTestCase {
    private let api = CustomWidgetDefinition.ScriptHost(url: "https://api.example.com/v1", auth: .init(kind: .bearer))

    private func scripted(_ script: String, hosts: [CustomWidgetDefinition.ScriptHost]? = nil, confirmed: Bool = true) -> CustomWidgetDefinition {
        var definition = CustomWidgetDefinition()
        definition.name = "Skript"
        definition.script = script
        definition.hosts = hosts ?? [api]
        if confirmed { definition.confirmAll() }
        return definition
    }

    private func call(_ url: String, method: String = "GET", headers: [String: String]? = nil) -> CustomScriptCall {
        CustomScriptCall(method: method, url: url, headers: headers, body: nil)
    }

    private func studio(_ method: String, _ path: String, _ body: JSON, store: CustomWidgetStore) async -> (Int, JSON) {
        let request = HTTPRequest(method: method, path: path, query: [:], headers: [:], body: try! JSONSerialization.data(withJSONObject: body))
        return await CustomStudioAPI.handle(request, store: store)
    }

    func testStudioSaveCannotApproveHostsOrStoreSecrets() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        let (status, json) = await studio("POST", "/studio/widgets", [
            "definition": ["baseURL": "https://evil.example.com", "confirmedOrigin": "https://evil.example.com", "auth": ["kind": "bearer"],
                           "confirmedHosts": [["url": "https://evil.example.com", "writes": true]]],
            "secret": ["value": "smuggled-key"],
        ], store: store)
        XCTAssertEqual(status, 200)
        let saved = try XCTUnwrap(store.definitions.first)
        XCTAssertNil(saved.confirmedOrigin)
        XCTAssertNil(saved.confirmedHosts)
        XCTAssertFalse(saved.isConfirmed)
        XCTAssertNil(store.secret(for: saved))
        XCTAssertEqual((json["pending"] as? [String])?.count, 2, "Freigabe und Zugangsdaten bleiben offen")

        var approved = saved
        approved.confirmAll()
        store.save(approved)
        _ = await studio("POST", "/studio/widgets", ["definition": ["id": saved.id.uuidString, "name": "Neu", "confirmedOrigin": NSNull()]], store: store)
        XCTAssertTrue(try XCTUnwrap(store.definition(saved.id)).isConfirmed, "Patch kann Freigaben weder setzen noch löschen")
    }

    func testScriptHostsNeedHumanApprovalAndWriteRights() {
        var definition = scripted("return 1", confirmed: false)
        XCTAssertFalse(definition.isConfirmed)
        definition.confirmAll()
        XCTAssertTrue(definition.isConfirmed)

        definition.hosts = [CustomWidgetDefinition.ScriptHost(url: api.url, auth: api.auth, writes: true)]
        XCTAssertFalse(definition.isConfirmed, "Schreibrecht braucht eine eigene Freigabe")
        definition.hosts = [CustomWidgetDefinition.ScriptHost(url: api.url, auth: .init(kind: .queryKey, name: "leak"))]
        XCTAssertFalse(definition.isConfirmed, "geänderte Art der Zugangsdaten braucht eine neue Freigabe")
        definition.hosts = [api, .init(url: "https://other.example.com")]
        XCTAssertEqual(definition.unconfirmedHosts.map(\.origin), ["https://other.example.com"])

        XCTAssertTrue(scripted("return 1", hosts: []).isConfirmed, "ohne Host kein Netz, nichts freizugeben")
    }

    func testScriptRequestPolicy() throws {
        let definition = scripted("return 1")
        let secret: (String) -> CustomSecret? = { $0 == "https://api.example.com" ? CustomSecret(value: "s3cret-token") : nil }

        let request = try CustomScriptRunner.request(for: call("https://API.example.com/v1/items?from=2026-11-01", headers: ["X-Trace": "1"]), in: definition, secret: secret)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace"), "1")

        func rejects(_ call: CustomScriptCall, in definition: CustomWidgetDefinition = definition, _ expected: CustomRequestError, line: UInt = #line) {
            XCTAssertThrowsError(try CustomScriptRunner.request(for: call, in: definition, secret: secret), line: line) {
                XCTAssertEqual($0 as? CustomRequestError, expected, line: line)
            }
        }
        rejects(call("https://evil.example.com/steal"), .hostNotAllowed("https://evil.example.com"))
        rejects(call("https://api.example.com:8443/x"), .hostNotAllowed("https://api.example.com:8443"))
        rejects(call("http://api.example.com/x"), .hostNotAllowed("http://api.example.com"))
        rejects(call("https://user:pw@api.example.com/x"), .invalidURL)
        rejects(call("https://api.example.com/x", method: "DELETE"), .writeNotAllowed("https://api.example.com"))
        rejects(call("https://api.example.com/x", method: "TRACE"), .invalidURL)
        rejects(call("https://api.example.com/x", headers: ["Authorization": "Bearer mine"]), .sensitiveName("Authorization"))
        rejects(call("https://api.example.com/x?api_key=1"), .sensitiveName("api_key"))
        rejects(call("https://api.example.com/x"), in: scripted("return 1", confirmed: false), .hostNotAllowed("https://api.example.com"))

        var writer = scripted("return 1", hosts: [.init(url: api.url, auth: api.auth, writes: true)])
        XCTAssertNoThrow(try CustomScriptRunner.request(for: call("https://api.example.com/x", method: "POST"), in: writer, secret: secret))
        writer.confirmedHosts = [api]
        rejects(call("https://api.example.com/x", method: "POST"), in: writer, .hostNotAllowed("https://api.example.com"))

        XCTAssertThrowsError(try CustomScriptRunner.request(for: call("https://api.example.com/x"), in: definition, secret: { _ in nil })) {
            XCTAssertEqual($0 as? CustomRequestError, .missingSecret)
        }
    }

    func testScrubberMasksSecretsInAllForms() {
        let scrub = CustomScriptRunner.scrubber(for: [CustomSecret(value: "pa\"ss-word", username: "julian"), CustomSecret(value: "abc")])
        let basic = Data("julian:pa\"ss-word".utf8).base64EncodedString()
        XCTAssertEqual(scrub("raw pa\"ss-word json pa\\\"ss-word basic \(basic)"), "raw ••• json ••• basic •••")
        XCTAssertEqual(scrub("abc"), "abc", "zu kurze Werte würden echte Daten zerstören")
    }

    func testRunnerExecutesScriptInSandbox() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        let definition = scripted("""
        const items = http.get("https://api.example.com/v1/items", {query: {from: vars.today}}).json.items;
        console.log("echo", http.get("https://api.example.com/v1/echo").text);
        return {total: items.reduce((sum, item) => sum + item.hours, 0), day: vars.today};
        """)
        store.save(definition)
        store.setSecret(CustomSecret(value: "s3cret-token"), for: definition, origin: "https://api.example.com")
        var seen: [URLRequest] = []
        store.fetch = { request throws(CustomRequestError) in
            seen.append(request)
            let body = request.url?.path == "/v1/echo" ? #"{"you":"s3cret-token"}"# : #"{"items":[{"hours":2},{"hours":1.5}]}"#
            return CustomFetcher.Response(json: [:], data: Data(body.utf8))
        }

        let run = await store.runScript(definition, now: Date(timeIntervalSince1970: 1_793_000_000))
        let output = try XCTUnwrap(try run.result.get() as? [String: Any])
        XCTAssertEqual(output["total"] as? Double, 3.5)
        XCTAssertNotNil(output["day"] as? String)
        XCTAssertEqual(seen.first?.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret-token")
        XCTAssertTrue(seen.first?.url?.query?.hasPrefix("from=") == true)
        XCTAssertEqual(run.logs, [#"echo {"you":"•••"}"#], "Secret aus der Antwort ist geschwärzt")
    }

    func testRunnerReportsScriptErrorsAndBlockedHosts() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        store.fetch = { _ throws(CustomRequestError) in XCTFail("darf nie fetchen"); throw .unreachable }

        let blocked = scripted(#"return http.get("https://evil.example.com/x").json"#, hosts: [])
        guard case .failure(.scriptFailed(let message)) = await store.runScript(blocked).result else { return XCTFail() }
        XCTAssertTrue(message.contains("evil.example.com"), message)

        let syntax = scripted("return 1 +", hosts: [])
        guard case .failure(.scriptFailed(let reason)) = await store.runScript(syntax).result else { return XCTFail() }
        XCTAssertTrue(reason.hasPrefix("Syntax"), reason)

        let sandbox = scripted(#"return typeof fetch + typeof require + typeof XMLHttpRequest"#, hosts: [])
        let isolated = await store.runScript(sandbox)
        XCTAssertEqual(try isolated.result.get() as? String, "undefinedundefinedundefined")

        let unapproved = scripted("return 1", confirmed: false)
        guard case .failure(.unconfirmed) = await store.runScript(unapproved).result else { return XCTFail() }
    }

    func testRunnerKillsEndlessScripts() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        let started = Date.now
        let run = await store.runScript(scripted("while (true) {}", hosts: []))
        guard case .failure(.scriptTimeout) = run.result else { return XCTFail("\(run.result)") }
        XCTAssertLessThan(Date.now.timeIntervalSince(started), CustomScriptRunner.timeout + 5)

        let flood = await store.runScript(scripted(#"while (true) console.log("x".repeat(100000))"#, hosts: []))
        guard case .failure(.scriptTimeout) = flood.result else { return XCTFail("\(flood.result)") }
        XCTAssertEqual(flood.logs.count, CustomScriptRunner.maxLogLines)
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 2 * CustomScriptRunner.timeout + 10)
    }

    func testRefreshFeedsScriptOutputIntoSelection() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        var definition = scripted("return {booked: 6 * 7}", hosts: [])
        definition.selection.valuePath = "booked"
        store.save(definition)
        let refreshed = await store.refresh(definition.id)
        let display = try XCTUnwrap(refreshed)
        XCTAssertEqual(display.text, "42")
        XCTAssertNil(display.error)
    }

    func testExportAndImportDropApprovals() throws {
        let definition = scripted("return 1")
        let imported = try CustomWidgetShare.decode(CustomWidgetShare.export(definition))
        XCTAssertNil(imported.confirmedHosts)
        XCTAssertFalse(imported.isConfirmed)
        XCTAssertEqual(imported.script, "return 1")
    }

    func testValidationLimitsScripts() {
        var definition = scripted(String(repeating: "x", count: CustomWidgetDefinition.maxScriptBytes + 1))
        XCTAssertThrowsError(try CustomRequest.validate(definition)) { XCTAssertEqual($0 as? CustomRequestError, .scriptTooLarge) }
        definition.script = "return 1"
        definition.hosts = [.init(url: "ftp://api.example.com")]
        XCTAssertThrowsError(try CustomRequest.validate(definition)) { XCTAssertEqual($0 as? CustomRequestError, .insecureScheme) }
        definition.hosts = (0...CustomWidgetDefinition.maxHosts).map { .init(url: "https://h\($0).example.com") }
        XCTAssertThrowsError(try CustomRequest.validate(definition)) { XCTAssertEqual($0 as? CustomRequestError, .tooManyHosts) }
    }
}
