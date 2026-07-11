import Foundation
import Testing
import PlusPlusKit

@Suite("GitHubDeviceFlow")
struct GitHubDeviceFlowTests {
    private let config = GitHubAppConfiguration(clientID: "Iv1.testclientid")

    private func flow(_ client: ScriptedHTTPClient) -> GitHubDeviceFlow {
        // No-op sleep: the poll loop must not touch a real clock in tests.
        GitHubDeviceFlow(config: config, client: client, sleep: { _ in })
    }

    @Test("requestVerification returns the codes to show the user")
    func requestVerification() async throws {
        let client = ScriptedHTTPClient { _, _ in
            GHResponse.json([
                "device_code": "dc-123",
                "user_code": "WDJB-MJHT",
                "verification_uri": "https://github.com/login/device",
                "verification_uri_complete": "https://github.com/login/device?user_code=WDJB-MJHT",
                "expires_in": 900,
                "interval": 5,
            ])
        }
        let verification = try await flow(client).requestVerification()

        #expect(verification.deviceCode == "dc-123")
        #expect(verification.userCode == "WDJB-MJHT")
        #expect(verification.verificationURI == "https://github.com/login/device")
        // The pre-filled URL is captured so the app can open it directly.
        #expect(verification.verificationURIComplete == "https://github.com/login/device?user_code=WDJB-MJHT")
        #expect(verification.interval == 5)
        // Posts to the device-code endpoint with the client id.
        #expect(client.requests.first?.path.hasSuffix("login/device/code") == true)
        #expect(client.requests.first?.formBody?.contains("client_id=Iv1.testclientid") == true)
    }

    @Test("An unconfigured client ID fails before any network call")
    func unconfigured() async throws {
        let client = ScriptedHTTPClient { _, _ in GHResponse.status(500) }
        let unconfigured = GitHubDeviceFlow(config: GitHubAppConfiguration(clientID: ""), client: client, sleep: { _ in })

        await #expect(throws: GitHubDeviceFlow.FlowError.notConfigured) {
            try await unconfigured.requestVerification()
        }
        #expect(client.requests.isEmpty)
    }

    @Test("A single poll maps GitHub's states")
    func pollStates() async throws {
        func result(forError error: String) async throws -> GitHubDeviceFlow.PollResult {
            let client = ScriptedHTTPClient { _, _ in GHResponse.json(["error": error]) }
            return try await flow(client).poll(deviceCode: "dc")
        }
        #expect(try await result(forError: "authorization_pending") == .pending)
        #expect(try await result(forError: "slow_down") == .slowDown)
    }

    @Test("An approved poll returns the token")
    func pollAuthorized() async throws {
        let client = ScriptedHTTPClient { _, _ in
            GHResponse.json(["access_token": "gho_secret", "token_type": "bearer"])
        }
        let result = try await flow(client).poll(deviceCode: "dc")
        #expect(result == .authorized(token: "gho_secret"))
        // The poll body carries the device-flow grant type, form-encoded.
        // Colons are query-safe (RFC 3986) and GitHub accepts them literally.
        let body = client.requests.first?.formBody ?? ""
        #expect(body.contains("device_code=dc"))
        #expect(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
    }

    @Test("Denied and expired polls throw")
    func pollTerminalErrors() async throws {
        let denied = ScriptedHTTPClient { _, _ in GHResponse.json(["error": "access_denied"]) }
        await #expect(throws: GitHubDeviceFlow.FlowError.accessDenied) {
            try await flow(denied).poll(deviceCode: "dc")
        }
        let expired = ScriptedHTTPClient { _, _ in GHResponse.json(["error": "expired_token"]) }
        await #expect(throws: GitHubDeviceFlow.FlowError.expired) {
            try await flow(expired).poll(deviceCode: "dc")
        }
    }

    @Test("pollForToken loops through pending until approval")
    func pollForTokenLoops() async throws {
        // First two polls pending, then slow_down, then approved.
        let client = ScriptedHTTPClient { _, index in
            switch index {
            case 0, 1: return GHResponse.json(["error": "authorization_pending"])
            case 2: return GHResponse.json(["error": "slow_down"])
            default: return GHResponse.json(["access_token": "gho_final"])
            }
        }
        let verification = GitHubDeviceFlow.Verification(
            deviceCode: "dc", userCode: "AAAA-BBBB",
            verificationURI: "https://github.com/login/device",
            expiresIn: 900, interval: 1
        )
        let token = try await flow(client).pollForToken(for: verification)
        #expect(token == "gho_final")
        #expect(client.requests.count == 4)
    }

    @Test("pollForToken gives up when the code lifetime elapses")
    func pollForTokenExpires() async throws {
        // Always pending; expiresIn == interval means one poll then expiry.
        let client = ScriptedHTTPClient { _, _ in GHResponse.json(["error": "authorization_pending"]) }
        let verification = GitHubDeviceFlow.Verification(
            deviceCode: "dc", userCode: "AAAA-BBBB",
            verificationURI: "https://github.com/login/device",
            expiresIn: 5, interval: 5
        )
        await #expect(throws: GitHubDeviceFlow.FlowError.expired) {
            try await flow(client).pollForToken(for: verification)
        }
    }
}
