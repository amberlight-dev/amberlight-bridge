import Foundation

enum OrbitClient {
    struct User: Decodable {
        let id: String
    }

    struct Page<Item: Decodable>: Decodable {
        let data: [Item]
    }

    struct Issue: Decodable {
        let issueKey: String
        let title: String
        let projectId: String
        let status: String
    }

    struct Status: Decodable {
        let key: String
        let label: String
        let sortOrder: Int
    }

    private static let limit = 50
    private static let cacheLifetime: TimeInterval = 60
    private static var cache: (at: Date, account: OrbitAccount, payload: JSON)?

    static func cachedReport(account: OrbitAccount? = Accounts.orbit, now: Date = .now) async -> JSON {
        guard let account else { return empty(configured: false) }
        if let cache, cache.account == account, now.timeIntervalSince(cache.at) < cacheLifetime { return cache.payload }
        let payload = await report(account)
        cache = (now, account, payload)
        return payload
    }

    static func forgetCache() {
        cache = nil
    }

    static func report(_ account: OrbitAccount) async -> JSON {
        let headers = ["Authorization": "Bearer " + account.token, "Accept": "application/json"]
        do {
            let me: User = try await RemoteJSON.get(account.api + "/api/v1/users/me", headers: headers)
            let page: Page<Issue> = try await RemoteJSON.get(
                account.api + "/api/v1/issues?assigneeId=\(me.id)&archived=false&size=200", headers: headers
            )
            var statuses: [String: [Status]] = [:]
            for projectId in Set(page.data.map(\.projectId)) {
                statuses[projectId] = try await RemoteJSON.get(account.api + "/api/v1/issue-statuses?projectId=\(projectId)", headers: headers)
            }
            var payload = empty(configured: true)
            payload["home"] = account.web
            payload["issues"] = openIssues(page.data, statuses: statuses, web: account.web)
            return payload
        } catch {
            return RemoteJSON.failure(error, service: "Orbit", empty: empty(configured: true))
        }
    }

    static func openIssues(_ issues: [Issue], statuses: [String: [Status]], web: String) -> [JSON] {
        issues
            .compactMap { issue -> JSON? in
                let sorted = (statuses[issue.projectId] ?? []).sorted { $0.sortOrder < $1.sortOrder }
                guard issue.status != sorted.last?.key else { return nil }
                return [
                    "key": issue.issueKey,
                    "title": issue.title,
                    "status": sorted.first { $0.key == issue.status }?.label ?? issue.status,
                    "url": web + "/issues/" + issue.issueKey,
                ]
            }
            .prefix(limit)
            .map(\.self)
    }

    private static func empty(configured: Bool) -> JSON {
        ["configured": configured, "issues": [JSON]()]
    }
}
