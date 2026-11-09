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

    private func actions(in node: CustomNode?) -> Set<String> {
        guard let node else { return [] }
        return (node.children ?? []).reduce(Set([node.action].compactMap(\.self))) { $0.union(actions(in: $1)) }
    }

    func testStudioCannotApproveActionsAndScriptEditsDropApproval() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        let stop = ["name": "stop", "script": "return 1"]
        let (status, json) = await studio("POST", "/studio/widgets", [
            "definition": ["script": "return 1", "hosts": [], "actions": [stop], "confirmedActions": [stop]],
        ], store: store)
        XCTAssertEqual(status, 200)
        let saved = try XCTUnwrap(store.definitions.first)
        XCTAssertNil(saved.confirmedActions)
        XCTAssertEqual(saved.unconfirmedActions.map(\.name), ["stop"])
        XCTAssertTrue((json["pending"] as? [String])?.contains { $0.contains("Aktion „stop“") } == true, "\(json)")
        let (blocked, _) = await studio("POST", "/studio/run", ["id": saved.id.uuidString, "action": "stop"], store: store)
        XCTAssertEqual(blocked, 403)

        var approved = saved
        approved.confirmAll()
        let before = store.revision
        store.save(approved)
        XCTAssertGreaterThan(store.revision, before, "Freigabe meldet sich beim Stand über den Snapshot")
        let afterSave = store.revision
        await store.refresh(saved.id)
        XCTAssertGreaterThan(store.revision, afterSave, "neue Daten ebenso")
        XCTAssertEqual(store.definition(saved.id)?.runnableActionNames, ["stop"])
        _ = await studio("POST", "/studio/widgets", ["definition": ["id": saved.id.uuidString, "actions": [["name": "stop", "script": "return 2"]]]], store: store)
        XCTAssertEqual(store.definition(saved.id)?.runnableActionNames, [], "geändertes Aktions-Skript braucht eine neue Freigabe")

        let (unknown, _) = await studio("POST", "/studio/run", ["id": saved.id.uuidString, "action": "nope"], store: store)
        XCTAssertEqual(unknown, 404)
        let (duplicate, _) = await studio("POST", "/studio/widgets", ["definition": ["id": saved.id.uuidString, "actions": [stop, stop]]], store: store)
        XCTAssertEqual(duplicate, 400)
    }

    func testActionsRunOnlyOnTapWithLastValuesThenRefetch() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        let moco = CustomWidgetDefinition.ScriptHost(url: "https://x.mocoapp.com", writes: true)
        var definition = scripted(#"const a = http.get("https://x.mocoapp.com/api/v1/activities").json; return {running: a.running, runningId: a.id}"#, hosts: [moco], confirmed: false)
        definition.actions = [.init(name: "stop", script: #"http.patch("https://x.mocoapp.com/api/v1/activities/" + vars.last.runningId + "/stop_timer"); return true"#)]
        definition.values = [.init(name: "running", selection: .init(valuePath: "running"))]
        definition.selection.valuePath = "running"
        definition.display.layout = CustomNode(type: .pill, text: "Stop", when: "running >= 1", action: "stop")
        store.save(definition)

        var running = 1
        var writes: [String] = []
        store.fetch = { request throws(CustomRequestError) in
            if request.httpMethod == "PATCH" {
                writes.append(request.url?.path ?? "")
                running = 0
                return CustomFetcher.Response(json: [:], data: Data("{}".utf8))
            }
            return CustomFetcher.Response(json: [:], data: Data(#"{"running": \#(running), "id": 7}"#.utf8))
        }

        var approvedHostsOnly = definition
        approvedHostsOnly.confirmedHosts = approvedHostsOnly.scriptHosts
        store.save(approvedHostsOnly)
        let unapproved = await store.refresh(definition.id)
        XCTAssertEqual(actions(in: unapproved?.root), [], "nicht freigegebene Aktion ist nicht tippbar")

        store.confirm(definition.id)
        let before = await store.refresh(definition.id)
        await store.refreshDue(now: .now.addingTimeInterval(86_400))
        XCTAssertEqual(actions(in: before?.root), ["stop"])
        XCTAssertEqual(writes, [], "Abruf im Intervall schreibt nie")

        let id = definition.id
        let taps = (0..<2).map { _ in
            Task {
                let tap = await store.runAction(id, named: "stop")
                return (error: tap.run.result.failureValue, text: tap.display?.text, showsStop: tap.display?.root != nil)
            }
        }
        var results: [(error: CustomRequestError?, text: String?, showsStop: Bool)] = []
        for tap in taps { results.append(await tap.value) }
        XCTAssertEqual(writes, ["/api/v1/activities/7/stop_timer"], "IDs kommen aus vars.last, Doppel-Tap schreibt nur einmal")
        XCTAssertEqual(results.map(\.error), [nil, .actionBusy])
        XCTAssertEqual(results.first?.text, "0", "nach der Aktion wird sofort neu abgerufen")
        XCTAssertEqual(results.first?.showsStop, false, "when blendet Stop aus")
    }

    func testStudioAcceptsPartialValueSelectionsAndNamesSchemaErrors() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        let (status, _) = await studio("POST", "/studio/widgets", ["definition": ["script": "return {a: {b: 1}}", "hosts": [], "values": [["name": "b", "selection": ["valuePath": "a.b"]]]]], store: store)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(store.definitions.first?.values?.first?.selection.valuePath, "a.b")

        var templated = CustomLayout.Scope()
        templated.text["icon"] = "checkmark"
        XCTAssertEqual(CustomLayout.resolve(CustomNode(type: .symbol, text: "{icon}"), scope: templated)?.text, "checkmark")

        let (bad, json) = await studio("POST", "/studio/widgets", ["definition": ["display": ["style": "nope"]]], store: store)
        XCTAssertEqual(bad, 400)
        XCTAssertTrue((json["error"] as? String)?.contains("display.style") == true, "\(json)")
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
        XCTAssertNil(imported.confirmedActions)
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

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
