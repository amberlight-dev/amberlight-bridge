import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    var json: JSON {
        (try? JSONSerialization.jsonObject(with: body)) as? JSON ?? [:]
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = max(0, Int(headers["content-length"] ?? "") ?? 0)
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        let components = URLComponents(string: String(requestLine[1]))
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        return HTTPRequest(
            method: String(requestLine[0]),
            path: components?.path ?? "",
            query: query,
            headers: headers,
            body: Data(body.prefix(length))
        )
    }
}
