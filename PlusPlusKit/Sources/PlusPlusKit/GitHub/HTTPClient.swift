import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one HTTP call the GitHub adapters make, behind a protocol — the same
/// move as `RepoStore`/`SyncBaseStore`. Production wraps `URLSession`; tests
/// inject a scripted fake. This is what keeps every byte of GitHub logic
/// (paths, headers, SHA concurrency, device-flow polling) testable on Linux,
/// where custom `URLProtocol` stubbing is unreliable in swift-corelibs-foundation.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// A method + URL + headers + optional body. Deliberately tiny: the adapters
/// build these, the client just performs them.
public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case put = "PUT"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// A status code + body. Header access is intentionally omitted — GitHub's
/// git-data flow carries everything the adapter needs in the JSON bodies.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    /// 2xx. Callers branch on specific non-2xx codes (404, 409, 422) before
    /// falling back to this.
    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// The production `HTTPClient`: a thin `URLSession` wrapper. Untested on Linux
/// by design (it's the seam we mock); the logic above it is fully covered.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.notHTTP
        }
        return HTTPResponse(status: http.statusCode, body: data)
    }
}

public enum HTTPClientError: Error, Equatable {
    case notHTTP
}
