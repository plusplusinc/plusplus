import Foundation
import Testing
import PlusPlusKit

@Suite("GitHubAccount")
struct GitHubAccountTests {
    private func account(_ client: ScriptedHTTPClient, token: String? = "gho_token") -> GitHubAccount {
        GitHubAccount(tokens: InMemoryTokenStore(token: token), client: client)
    }

    @Test("currentLogin returns the authenticated user")
    func currentLogin() async throws {
        let client = ScriptedHTTPClient { _, _ in GHResponse.json(["login": "octocat", "id": 1]) }
        let login = try await account(client).currentLogin()
        #expect(login == "octocat")
        #expect(client.requests.first?.path.hasSuffix("/user") == true)
    }

    @Test("repositoryExists distinguishes 200 from 404")
    func repositoryExists() async throws {
        let present = ScriptedHTTPClient { _, _ in GHResponse.json(["name": "workouts"]) }
        #expect(try await account(present).repositoryExists(owner: "octocat", name: "workouts"))

        let absent = ScriptedHTTPClient { _, _ in GHResponse.status(404, body: "Not Found") }
        #expect(try await account(absent).repositoryExists(owner: "octocat", name: "workouts") == false)
    }

    @Test("createRoutineRepository asks for a private, auto-init'd repo")
    func createRepository() async throws {
        let client = ScriptedHTTPClient { _, _ in
            GHResponse.json([
                "name": "workouts",
                "owner": ["login": "octocat"],
                "default_branch": "main",
            ], status: 201)
        }
        let coordinate = try await account(client).createRoutineRepository(name: "workouts")

        #expect(coordinate == GitHubRepoCoordinate(owner: "octocat", repo: "workouts", branch: "main"))
        let body = client.requests.first?.jsonBody
        #expect(body?["name"] as? String == "workouts")
        #expect(body?["private"] as? Bool == true)
        #expect(body?["auto_init"] as? Bool == true)
    }

    @Test("An unauthenticated call throws before hitting the network")
    func unauthenticated() async throws {
        let client = ScriptedHTTPClient { _, _ in GHResponse.status(200) }
        await #expect(throws: GitHubAccount.AccountError.notAuthenticated) {
            try await account(client, token: nil).currentLogin()
        }
        #expect(client.requests.isEmpty)
    }
}
