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

    @Test("repository adopts the repo at its real default branch, nil on 404")
    func repositoryCarriesDefaultBranch() async throws {
        let present = ScriptedHTTPClient { _, _ in
            GHResponse.json([
                "name": "workouts",
                "owner": ["login": "octocat"],
                "default_branch": "master",
            ])
        }
        let coordinate = try await account(present).repository(owner: "octocat", name: "workouts")
        #expect(coordinate == GitHubRepoCoordinate(owner: "octocat", repo: "workouts", branch: "master"))

        let absent = ScriptedHTTPClient { _, _ in GHResponse.status(404, body: "Not Found") }
        #expect(try await account(absent).repository(owner: "octocat", name: "workouts") == nil)
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

    @Test("installedRepositories discovers repos from the App's installation")
    func installedRepositories() async throws {
        let client = ScriptedHTTPClient { request, _ in
            if request.path.hasSuffix("/user/installations") {
                return GHResponse.json(["installations": [["id": 42], ["id": 43]]])
            }
            if request.path.contains("installations/42/repositories") {
                return GHResponse.json(["repositories": [
                    ["name": "plusplus-data", "owner": ["login": "octocat"], "default_branch": "trunk"],
                ]])
            }
            if request.path.contains("installations/43/repositories") {
                return GHResponse.json(["repositories": [
                    ["name": "extra", "owner": ["login": "octocat"], "default_branch": "main"],
                ]])
            }
            return GHResponse.status(500, body: "unexpected \(request.path)")
        }
        let repos = try await account(client).installedRepositories()
        // Both installations' repos, sorted deterministically, at real branches.
        #expect(repos == [
            GitHubRepoCoordinate(owner: "octocat", repo: "extra", branch: "main"),
            GitHubRepoCoordinate(owner: "octocat", repo: "plusplus-data", branch: "trunk"),
        ])
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
