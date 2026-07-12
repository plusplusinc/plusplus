import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wraps an `HTTPClient` and retries transient failures with a short backoff.
/// The motivating case: device flow sends the user to Safari to authorize, and
/// the FIRST request after the app returns from background frequently fails
/// with `URLError.networkConnectionLost` (-1005) — iOS reused a keep-alive
/// connection the system had already torn down. A single retry gets a fresh
/// connection and succeeds, so the user never sees a spurious "network error."
///
/// Retries thrown transient `URLError`s and 502/503/504 responses; leaves
/// everything else (4xx, real 500s, auth errors) untouched. Pure over an
/// injected `sleep`, so the backoff tests on Linux without a clock.
public struct RetryingHTTPClient: HTTPClient {
    private let wrapped: any HTTPClient
    private let maxAttempts: Int
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        wrapping wrapped: any HTTPClient,
        maxAttempts: Int = 3,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.wrapped = wrapped
        self.maxAttempts = max(1, maxAttempts)
        self.sleep = sleep
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var attempt = 1
        while true {
            do {
                let response = try await wrapped.send(request)
                if attempt < maxAttempts, Self.isTransientStatus(response.status) {
                    try await sleep(Self.backoff(attempt))
                    attempt += 1
                    continue
                }
                return response
            } catch {
                if attempt >= maxAttempts || !Self.isTransient(error) { throw error }
                try await sleep(Self.backoff(attempt))
                attempt += 1
            }
        }
    }

    /// Linear-ish backoff: 0.4 s, 0.8 s. Short — this is masking a stale
    /// connection, not rate-limiting.
    static func backoff(_ attempt: Int) -> TimeInterval { Double(attempt) * 0.4 }

    static func isTransientStatus(_ status: Int) -> Bool {
        // Gateway/unavailable/timeout — GitHub hasn't processed the request.
        // Deliberately NOT 500 (often a real, non-retryable error).
        status == 502 || status == 503 || status == 504
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,   // -1005, the post-foreground case
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}
