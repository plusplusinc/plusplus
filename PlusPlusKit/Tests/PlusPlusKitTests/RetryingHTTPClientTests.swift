import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PlusPlusKit

@Suite("RetryingHTTPClient")
struct RetryingHTTPClientTests {
    private func retrying(_ client: ScriptedHTTPClient, maxAttempts: Int = 3) -> RetryingHTTPClient {
        RetryingHTTPClient(wrapping: client, maxAttempts: maxAttempts, sleep: { _ in })
    }

    @Test("A transient -1005 is retried and then succeeds")
    func retriesNetworkConnectionLost() async throws {
        let client = ScriptedHTTPClient { _, index in
            if index == 0 { throw URLError(.networkConnectionLost) }
            return GHResponse.status(200, body: "ok")
        }
        let response = try await retrying(client).send(HTTPRequest(method: .get, url: URL(string: "https://api.github.com/x")!))
        #expect(response.status == 200)
        #expect(client.requests.count == 2, "Should have retried once")
    }

    @Test("A persistent transient error gives up after maxAttempts")
    func givesUpAfterMaxAttempts() async throws {
        let client = ScriptedHTTPClient { _, _ in throw URLError(.timedOut) }
        await #expect(throws: URLError.self) {
            try await retrying(client, maxAttempts: 3).send(HTTPRequest(method: .get, url: URL(string: "https://x")!))
        }
        #expect(client.requests.count == 3)
    }

    @Test("A non-transient error is not retried")
    func doesNotRetryNonTransient() async throws {
        // badServerResponse isn't in the transient set → surfaces immediately.
        let client = ScriptedHTTPClient { _, _ in throw URLError(.badServerResponse) }
        await #expect(throws: URLError.self) {
            try await retrying(client).send(HTTPRequest(method: .get, url: URL(string: "https://x")!))
        }
        #expect(client.requests.count == 1)
    }

    @Test("A 503 is retried; a 404 is returned as-is")
    func retriesTransientStatusOnly() async throws {
        let flaky = ScriptedHTTPClient { _, index in
            GHResponse.status(index == 0 ? 503 : 200)
        }
        #expect(try await retrying(flaky).send(HTTPRequest(method: .get, url: URL(string: "https://x")!)).status == 200)
        #expect(flaky.requests.count == 2)

        let notFound = ScriptedHTTPClient { _, _ in GHResponse.status(404) }
        #expect(try await retrying(notFound).send(HTTPRequest(method: .get, url: URL(string: "https://x")!)).status == 404)
        #expect(notFound.requests.count == 1, "4xx is not retried")
    }
}
