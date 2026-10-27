import XCTest
@testable import StandBridge

@MainActor
final class AccountRoutesTests: XCTestCase {
    private func request(_ path: String, token: String) throws -> HTTPRequest {
        let raw = "GET \(path) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: 0\r\n\r\n"
        return try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8)))
    }

    private func makeServer() -> BridgeServer {
        BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
    }

    func testAccountRoutesRequireTokenAndPassPayload() async throws {
        let server = makeServer()
        var calls = 0
        server.orbit = {
            calls += 1
            return ["configured": true, "issues": [["key": "ORB-1"]]]
        }
        server.gitlab = {
            calls += 1
            return ["configured": false, "pipelines": [JSON](), "mergeRequests": [JSON]()]
        }
        let denied = await [
            server.route(try request("/orbit", token: "nope"), fromLoopback: true).0,
            server.route(try request("/gitlab", token: "nope"), fromLoopback: true).0,
        ]
        XCTAssertEqual(denied, [401, 401])
        XCTAssertEqual(calls, 0)

        let (orbitStatus, orbit) = await server.route(try request("/orbit", token: "abcd1234"), fromLoopback: false)
        let (gitlabStatus, gitlab) = await server.route(try request("/gitlab", token: "abcd1234"), fromLoopback: false)
        XCTAssertEqual([orbitStatus, gitlabStatus], [200, 200])
        XCTAssertEqual((orbit["issues"] as? [JSON])?.first?["key"] as? String, "ORB-1")
        XCTAssertEqual(gitlab["configured"] as? Bool, false)
    }

    func testOrbitKeepsOnlyIssuesBeforeTheLastStatus() {
        let statuses = [
            "p1": [
                OrbitClient.Status(key: "DONE", label: "Erledigt", sortOrder: 3),
                OrbitClient.Status(key: "TODO", label: "Offen", sortOrder: 1),
                OrbitClient.Status(key: "DOING", label: "In Arbeit", sortOrder: 2),
            ],
        ]
        let issues = [
            OrbitClient.Issue(issueKey: "ORB-1", title: "Läuft", projectId: "p1", status: "DOING"),
            OrbitClient.Issue(issueKey: "ORB-2", title: "Fertig", projectId: "p1", status: "DONE"),
            OrbitClient.Issue(issueKey: "ORB-3", title: "Neu", projectId: "p1", status: "TODO"),
        ]
        let open = OrbitClient.openIssues(issues, statuses: statuses, web: "https://orbit.test")
        XCTAssertEqual(open.compactMap { $0["key"] as? String }, ["ORB-1", "ORB-3"])
        XCTAssertEqual(open.first?["status"] as? String, "In Arbeit")
        XCTAssertEqual(open.first?["url"] as? String, "https://orbit.test/issues/ORB-1")
    }

    func testOrbitWithoutAccountIsUnconfigured() async {
        let payload = await OrbitClient.cachedReport(account: nil)
        XCTAssertEqual(payload["configured"] as? Bool, false)
    }

    func testGitLabSortsNewestPipelineFirstAndDeduplicatesRequests() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let projects = try decoder.decode([GitLabClient.Project].self, from: Data(#"[{"id":1,"name":"orbit"},{"id":2,"name":"stand"},{"id":3,"name":"leer"}]"#.utf8))
        let pipelines = try decoder.decode([GitLabClient.Pipeline].self, from: Data(#"""
        [{"id":10,"status":"success","ref":"main","web_url":"https://git.test/p/10","updated_at":"2026-10-20T10:00:00.000Z"},
         {"id":20,"status":"failed","ref":"feat","web_url":"https://git.test/p/20","updated_at":"2026-10-20T12:00:00.000Z"}]
        """#.utf8))
        let requests = try decoder.decode([GitLabClient.MergeRequest].self, from: Data(#"""
        [{"id":5,"iid":42,"project_id":1,"title":"Neue Suche","web_url":"https://git.test/mr/42","draft":true},
         {"id":5,"iid":42,"project_id":1,"title":"Neue Suche","web_url":"https://git.test/mr/42","draft":true}]
        """#.utf8))
        let payload = GitLabClient.payload(projects: projects, pipelines: [1: pipelines[0], 2: pipelines[1]], requests: requests)
        let rows = try XCTUnwrap(payload["pipelines"] as? [JSON])
        XCTAssertEqual(rows.compactMap { $0["project"] as? String }, ["stand", "orbit"])
        XCTAssertEqual(rows.first?["status"] as? String, "failed")
        let open = try XCTUnwrap(payload["mergeRequests"] as? [JSON])
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?["reference"] as? String, "!42")
        XCTAssertEqual(open.first?["project"] as? String, "orbit")
        XCTAssertEqual(open.first?["draft"] as? Bool, true)
    }

    func testRemoteErrorsBecomeReadableMessages() {
        let payload = RemoteJSON.failure(RemoteError.unauthorized, service: "GitLab", empty: ["pipelines": [JSON]()])
        XCTAssertEqual(payload["configured"] as? Bool, true)
        XCTAssertEqual(payload["error"] as? String, "GitLab lehnt den Token ab")
    }
}
