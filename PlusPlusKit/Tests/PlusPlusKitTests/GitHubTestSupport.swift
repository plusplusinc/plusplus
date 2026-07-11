import Foundation
import PlusPlusKit

/// A scripted `HTTPClient` for the GitHub adapter tests. The handler sees each
/// request and its 0-based call index, so a test can route by URL/method and
/// sequence by count (e.g. poll returns pending, then authorized). Every
/// request is recorded for assertions.
final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    private let handler: @Sendable (HTTPRequest, Int) throws -> HTTPResponse
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []

    init(_ handler: @escaping @Sendable (HTTPRequest, Int) throws -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [HTTPRequest] {
        lock.withLock { _requests }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        // Record synchronously (no lock held across the await/handler call).
        let index = lock.withLock { () -> Int in
            let index = _requests.count
            _requests.append(request)
            return index
        }
        return try handler(request, index)
    }
}

/// Convenience builders for test responses.
enum GHResponse {
    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return HTTPResponse(status: status, body: data)
    }

    static func status(_ status: Int, body: String = "") -> HTTPResponse {
        HTTPResponse(status: status, body: Data(body.utf8))
    }
}

extension HTTPRequest {
    /// The URL path without host — what the adapters key their routing on.
    var path: String { url.path }

    /// Decodes the JSON body into a dictionary for assertions.
    var jsonBody: [String: Any]? {
        guard let body else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// The form-encoded body as a string (device flow uses form encoding).
    var formBody: String? {
        body.map { String(decoding: $0, as: UTF8.self) }
    }
}
