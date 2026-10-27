import Foundation

enum GitLabClient {
    struct User: Decodable {
        let id: Int
    }

    struct Project: Decodable {
        let id: Int
        let name: String
    }

    struct Pipeline: Decodable {
        let id: Int
        let status: String
        let ref: String
        let webUrl: String
        let updatedAt: String?
    }

    struct MergeRequest: Decodable {
        let id: Int
        let iid: Int
        let projectId: Int
        let title: String
        let webUrl: String
        let draft: Bool?
    }

    private static let projectCount = 8
    private static let cacheLifetime: TimeInterval = 60
    private static var cache: (at: Date, account: GitLabAccount, payload: JSON)?
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func cachedReport(account: GitLabAccount? = Accounts.gitlab, now: Date = .now) async -> JSON {
        guard let account else { return empty(configured: false) }
        if let cache, cache.account == account, now.timeIntervalSince(cache.at) < cacheLifetime { return cache.payload }
        let payload = await report(account)
        cache = (now, account, payload)
        return payload
    }

    static func forgetCache() {
        cache = nil
    }

    static func report(_ account: GitLabAccount) async -> JSON {
        let headers = ["PRIVATE-TOKEN": account.token, "Accept": "application/json"]
        func get<Value: Decodable>(_ path: String) async throws -> Value {
            try await RemoteJSON.get(account.api + path, headers: headers, decoder: decoder)
        }
        do {
            let me: User = try await get("/user")
            let projects: [Project] = try await get("/projects?membership=true&archived=false&simple=true&order_by=last_activity_at&per_page=\(projectCount)")
            var pipelines: [Int: Pipeline] = [:]
            for project in projects {
                let latest: [Pipeline] = try await get("/projects/\(project.id)/pipelines?per_page=1")
                pipelines[project.id] = latest.first
            }
            let authored: [MergeRequest] = try await get("/merge_requests?state=opened&scope=created_by_me&per_page=20")
            let reviewing: [MergeRequest] = try await get("/merge_requests?state=opened&scope=all&reviewer_id=\(me.id)&per_page=20")
            return payload(projects: projects, pipelines: pipelines, requests: authored + reviewing)
        } catch {
            return RemoteJSON.failure(error, service: "GitLab", empty: empty(configured: true))
        }
    }

    static func payload(projects: [Project], pipelines: [Int: Pipeline], requests: [MergeRequest]) -> JSON {
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let latest = projects
            .compactMap { project in pipelines[project.id].map { (project, $0) } }
            .sorted { ($0.1.updatedAt ?? "") > ($1.1.updatedAt ?? "") }
            .map { project, pipeline -> JSON in
                ["id": pipeline.id, "project": project.name, "ref": pipeline.ref, "status": pipeline.status, "url": pipeline.webUrl]
            }
        var seen = Set<Int>()
        let open = requests
            .filter { seen.insert($0.id).inserted }
            .map { request -> JSON in
                [
                    "id": request.id,
                    "project": names[request.projectId] ?? "",
                    "reference": "!\(request.iid)",
                    "title": request.title,
                    "url": request.webUrl,
                    "draft": request.draft ?? false,
                ]
            }
        var payload = empty(configured: true)
        payload["pipelines"] = latest
        payload["mergeRequests"] = open
        return payload
    }

    private static func empty(configured: Bool) -> JSON {
        ["configured": configured, "pipelines": [JSON](), "mergeRequests": [JSON]()]
    }
}
