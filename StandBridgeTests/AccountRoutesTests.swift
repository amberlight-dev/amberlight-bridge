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
        server.gitlab = {
            calls += 1
            return ["configured": false, "pipelines": [JSON](), "mergeRequests": [JSON]()]
        }
        let denied = await [
            server.route(try request("/gitlab", token: "nope"), fromLoopback: true).0,
        ]
        XCTAssertEqual(denied, [401])
        XCTAssertEqual(calls, 0)

        let (gitlabStatus, gitlab) = await server.route(try request("/gitlab", token: "abcd1234"), fromLoopback: false)
        XCTAssertEqual(gitlabStatus, 200)
        XCTAssertEqual(gitlab["configured"] as? Bool, false)
    }

    func testGitLabSortsNewestPipelineFirstAndDeduplicatesRequests() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let projects = try decoder.decode([GitLabClient.Project].self, from: Data(#"[{"id":1,"name":"api"},{"id":2,"name":"stand"},{"id":3,"name":"leer"}]"#.utf8))
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
        XCTAssertEqual(rows.compactMap { $0["project"] as? String }, ["stand", "api"])
        XCTAssertEqual(rows.first?["status"] as? String, "failed")
        let open = try XCTUnwrap(payload["mergeRequests"] as? [JSON])
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?["reference"] as? String, "!42")
        XCTAssertEqual(open.first?["project"] as? String, "api")
        XCTAssertEqual(open.first?["draft"] as? Bool, true)
    }

    func testRemoteErrorsBecomeReadableMessages() {
        let payload = RemoteJSON.failure(RemoteError.unauthorized, service: "GitLab", empty: ["pipelines": [JSON]()])
        XCTAssertEqual(payload["configured"] as? Bool, true)
        XCTAssertEqual(payload["error"] as? String, "GitLab lehnt den Token ab")
    }
}
