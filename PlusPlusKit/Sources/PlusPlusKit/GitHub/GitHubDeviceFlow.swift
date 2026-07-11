import Foundation

/// GitHub App device flow (the "enter this code at github.com/login/device"
/// dance). No client secret, no redirect URL, no embedded web view — it's the
/// auth model docs/PLATFORM.md commits to for a serverless app. Two steps:
/// ask for a code, then poll until the user approves.
///
/// Pure over `HTTPClient` and an injected `sleep`, so the whole poll loop —
/// pending, slow-down back-off, approval, expiry — tests on Linux without a
/// network or a real clock.
public struct GitHubDeviceFlow: Sendable {
    /// The codes to show the user, plus how to poll. `verificationURI` is
    /// where they type `userCode` (usually https://github.com/login/device).
    public struct Verification: Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURI: String
        /// The verification URI with `userCode` already embedded
        /// (`…/login/device?user_code=XXXX`) — open THIS so the user just taps
        /// Authorize instead of typing the code. nil if GitHub omitted it;
        /// callers fall back to `verificationURI` + showing the code.
        public let verificationURIComplete: String?
        /// Seconds until `deviceCode` expires.
        public let expiresIn: Int
        /// Minimum seconds between token polls.
        public let interval: Int

        public init(
            deviceCode: String,
            userCode: String,
            verificationURI: String,
            verificationURIComplete: String? = nil,
            expiresIn: Int,
            interval: Int
        ) {
            self.deviceCode = deviceCode
            self.userCode = userCode
            self.verificationURI = verificationURI
            self.verificationURIComplete = verificationURIComplete
            self.expiresIn = expiresIn
            self.interval = interval
        }
    }

    /// One poll's outcome. `pending`/`slowDown` mean keep going; `slowDown`
    /// also bumps the interval. Everything else is terminal.
    public enum PollResult: Sendable, Equatable {
        case authorized(token: String)
        case pending
        case slowDown
    }

    public enum FlowError: Error, Equatable {
        /// The user clicked "Cancel" on the GitHub approval page.
        case accessDenied
        /// The device code expired before the user approved it.
        case expired
        /// GitHub returned an error code we don't special-case.
        case server(String)
        /// Non-2xx HTTP with no usable error body.
        case http(Int)
        /// The body didn't parse as the expected shape.
        case malformedResponse
        /// The client ID isn't configured yet (App not registered).
        case notConfigured
    }

    private let host: URL
    private let config: GitHubAppConfiguration
    private let client: any HTTPClient
    /// Injected so tests skip real waiting. Seconds.
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        config: GitHubAppConfiguration,
        client: any HTTPClient,
        host: URL = URL(string: "https://github.com")!,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.config = config
        self.client = client
        self.host = host
        self.sleep = sleep
    }

    // MARK: - Step 1: request the codes

    public func requestVerification(scope: String? = nil) async throws -> Verification {
        guard !config.clientID.isEmpty else { throw FlowError.notConfigured }
        var fields = ["client_id": config.clientID]
        if let scope { fields["scope"] = scope }
        let response = try await client.send(HTTPRequest(
            method: .post,
            url: host.appendingPathComponent("login/device/code"),
            headers: Self.jsonPostHeaders,
            body: Self.formEncode(fields)
        ))
        guard response.isSuccess else { throw FlowError.http(response.status) }
        guard let decoded = try? JSONDecoder().decode(VerificationBody.self, from: response.body) else {
            throw FlowError.malformedResponse
        }
        return Verification(
            deviceCode: decoded.device_code,
            userCode: decoded.user_code,
            verificationURI: decoded.verification_uri,
            verificationURIComplete: decoded.verification_uri_complete,
            expiresIn: decoded.expires_in,
            interval: decoded.interval
        )
    }

    // MARK: - Step 2: poll for the token

    /// One poll. The caller (or `pollForToken`) decides whether to wait and
    /// retry based on the result.
    public func poll(deviceCode: String) async throws -> PollResult {
        let response = try await client.send(HTTPRequest(
            method: .post,
            url: host.appendingPathComponent("login/oauth/access_token"),
            headers: Self.jsonPostHeaders,
            body: Self.formEncode([
                "client_id": config.clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
        ))
        // GitHub returns 200 for both the success and the pending/error cases;
        // the body's `access_token` or `error` field decides.
        guard let decoded = try? JSONDecoder().decode(TokenBody.self, from: response.body) else {
            guard response.isSuccess else { throw FlowError.http(response.status) }
            throw FlowError.malformedResponse
        }
        if let token = decoded.access_token, !token.isEmpty {
            return .authorized(token: token)
        }
        switch decoded.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied": throw FlowError.accessDenied
        case "expired_token": throw FlowError.expired
        case let other?: throw FlowError.server(other)
        case nil:
            guard response.isSuccess else { throw FlowError.http(response.status) }
            throw FlowError.malformedResponse
        }
    }

    /// Polls to completion: waits `interval` between attempts, backs off by 5s
    /// on `slow_down`, and gives up once the code's lifetime elapses. Returns
    /// the access token on approval; throws on denial/expiry.
    ///
    /// `elapsed` is injectable purely so the expiry ceiling is testable
    /// without a wall clock; it defaults to counting the intervals it slept.
    public func pollForToken(for verification: Verification) async throws -> String {
        var interval = TimeInterval(max(verification.interval, 1))
        var waited: TimeInterval = 0
        let ceiling = TimeInterval(verification.expiresIn)

        while true {
            try await sleep(interval)
            waited += interval
            switch try await poll(deviceCode: verification.deviceCode) {
            case .authorized(let token):
                return token
            case .pending:
                break
            case .slowDown:
                interval += 5
            }
            if waited >= ceiling { throw FlowError.expired }
        }
    }

    // MARK: - Wire formats

    private static let jsonPostHeaders = [
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    ]

    private static func formEncode(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        // `+` in a form body is a space; percent-encode it explicitly.
        let encoded = (components.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return Data(encoded.utf8)
    }

    private struct VerificationBody: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let verification_uri_complete: String?
        let expires_in: Int
        let interval: Int
    }

    private struct TokenBody: Decodable {
        let access_token: String?
        let error: String?
    }
}
