import Foundation

enum CustomFetcher {
    struct Response {
        let json: Any
        let data: Data
    }

    nonisolated static func session(protocols: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = CustomRequest.timeout
        configuration.timeoutIntervalForResource = CustomRequest.timeout
        if let protocols { configuration.protocolClasses = protocols }
        return URLSession(configuration: configuration)
    }

    static let shared = session()

    static func fetch(_ request: URLRequest, session: URLSession = shared, limit: Int = CustomRequest.maxResponseBytes) async throws(CustomRequestError) -> Response {
        guard let url = request.url, let origin = CustomRequest.origin(of: url) else { throw .invalidURL }
        let redirects = RedirectGuard(origin: origin)
        let data: Data
        let status: Int
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            guard let http = response as? HTTPURLResponse else { throw CustomRequestError.unreachable }
            if http.expectedContentLength > Int64(limit) { throw CustomRequestError.tooLarge }
            status = http.statusCode
            data = try await collect(bytes, limit: limit)
        } catch let error as CustomRequestError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw .timeout
        } catch {
            throw redirects.blocked ? .redirected : .unreachable
        }
        if status == 401 || status == 403 { throw .unauthorized }
        guard (200..<300).contains(status) else { throw .status(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { throw .notJSON }
        return Response(json: json, data: data)
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw CustomRequestError.tooLarge }
        }
        return data
    }
}

nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: String
    private let lock = NSLock()
    private var wasBlocked = false

    init(origin: String) {
        self.origin = origin
    }

    var blocked: Bool { lock.withLock { wasBlocked } }

    func allows(_ request: URLRequest) -> Bool {
        guard let url = request.url, CustomRequest.origin(of: url) == origin else {
            lock.withLock { wasBlocked = true }
            return false
        }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard allows(request) else {
            task.cancel()
            return completionHandler(nil)
        }
        completionHandler(request)
    }
}
