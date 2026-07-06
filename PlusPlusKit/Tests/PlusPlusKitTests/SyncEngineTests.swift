import Foundation
import Testing
import PlusPlusKit

/// In-memory transport standing in for the app's GitHub adapter.
private final class FakeRepoStore: RepoStore {
    var files: [String: Data]
    private(set) var commits: [(message: String, paths: [String])] = []

    init(files: [String: Data] = [:]) {
        self.files = files
    }

    func fetchAll() async throws -> [String: Data] { files }

    func write(_ writes: [FileWrite], message: String) async throws {
        for write in writes { files[write.path] = write.data }
        commits.append((message, writes.map(\.path)))
    }
}

private final class FakeBaseStore: SyncBaseStore {
    var base: [String: Data] = [:]
    func loadBase() throws -> [String: Data] { base }
    func saveBase(_ files: [String: Data]) throws { base = files }
}

@Suite("SyncEngine")
struct SyncEngineTests {
    private let workoutPath = "program/workouts/push-day.json"
    private let exercisePath = "program/exercises/band-pulses.json"
    private let a = Data("a".utf8)
    private let b = Data("b".utf8)
    private let c = Data("c".utf8)

    @Test("First sync pushes everything and saves the base")
    func firstSync() async throws {
        let repo = FakeRepoStore()
        let baseStore = FakeBaseStore()
        let engine = SyncEngine(store: repo, baseStore: baseStore)

        let outcome = try await engine.sync(local: [workoutPath: a, exercisePath: b])

        #expect(outcome.pushed == [exercisePath, workoutPath])
        #expect(outcome.pulls.isEmpty && outcome.postponed.isEmpty)
        #expect(repo.files == [workoutPath: a, exercisePath: b])
        #expect(baseStore.base == [workoutPath: a, exercisePath: b])
        #expect(repo.commits.count == 1)
        #expect(repo.commits[0].message == "Sync: band-pulses, push-day")
    }

    @Test("A no-op sync makes no commit")
    func noOpMakesNoCommit() async throws {
        let repo = FakeRepoStore(files: [workoutPath: a])
        let baseStore = FakeBaseStore()
        baseStore.base = [workoutPath: a]
        let engine = SyncEngine(store: repo, baseStore: baseStore)

        let outcome = try await engine.sync(local: [workoutPath: a])

        #expect(outcome.pushed.isEmpty && outcome.pulls.isEmpty)
        #expect(outcome.commitMessage == nil)
        #expect(repo.commits.isEmpty)
        #expect(baseStore.base == [workoutPath: a])
    }

    @Test("Remote edits come back as pulls and advance the base")
    func remoteEditPulled() async throws {
        let repo = FakeRepoStore(files: [workoutPath: b])
        let baseStore = FakeBaseStore()
        baseStore.base = [workoutPath: a]
        let engine = SyncEngine(store: repo, baseStore: baseStore)

        let outcome = try await engine.sync(local: [workoutPath: a])

        #expect(outcome.pulls == [FileWrite(path: workoutPath, data: b)])
        #expect(repo.commits.isEmpty, "Pulling must not commit")
        #expect(baseStore.base == [workoutPath: b])
    }

    @Test("Conflict resolved keep-mine pushes local; take-theirs pulls")
    func conflictResolution() async throws {
        let repo = FakeRepoStore(files: [workoutPath: b, exercisePath: b])
        let baseStore = FakeBaseStore()
        baseStore.base = [workoutPath: a, exercisePath: a]
        let engine = SyncEngine(store: repo, baseStore: baseStore)

        let outcome = try await engine.sync(local: [workoutPath: c, exercisePath: c]) { path in
            path == self.workoutPath ? .keepMine : .takeTheirs
        }

        #expect(outcome.pushed == [workoutPath])
        #expect(outcome.pulls == [FileWrite(path: exercisePath, data: b)])
        #expect(repo.files[workoutPath] == c)
        #expect(baseStore.base == [workoutPath: c, exercisePath: b])
    }

    @Test("Postponed conflicts stay out of the base and re-conflict")
    func postponedConflictRecurs() async throws {
        let repo = FakeRepoStore(files: [workoutPath: b])
        let baseStore = FakeBaseStore()
        baseStore.base = [workoutPath: a]
        let engine = SyncEngine(store: repo, baseStore: baseStore)

        let first = try await engine.sync(local: [workoutPath: c])
        #expect(first.postponed == [workoutPath])
        #expect(repo.commits.isEmpty)
        #expect(baseStore.base == [workoutPath: a], "Postponing must not advance the base")

        let second = try await engine.sync(local: [workoutPath: c])
        #expect(second.postponed == [workoutPath], "Unresolved conflict must surface again")
    }

    // MARK: - Session pushes

    private func makeSession(startedAt: Date = Date(timeIntervalSince1970: 1_751_500_000)) -> SessionDTO {
        var set = SessionDTO.SetDTO(
            order: 0, groupIndex: 0, setNumber: 1,
            exerciseName: "Push-Up", exerciseType: .weightReps
        )
        set.actualReps = 10
        set.completedAt = startedAt.addingTimeInterval(60)
        return SessionDTO(
            workoutName: "Push Day",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1800),
            restSeconds: 90,
            sets: [set]
        )
    }

    @Test("Sessions push append-only with a log commit message")
    func sessionPush() async throws {
        let repo = FakeRepoStore()
        let engine = SyncEngine(store: repo, baseStore: FakeBaseStore())
        let session = makeSession()

        let path = try await engine.pushSession(session)

        let expected = try #require(path)
        #expect(expected.hasPrefix("history/2025/") || expected.hasPrefix("history/2026/"))
        #expect(expected.hasSuffix("-push-day.json"))
        #expect(repo.commits.count == 1)
        #expect(repo.commits[0].message.hasPrefix("Log: Push Day — 1 set ("))
    }

    @Test("Re-pushing the same session is a no-op, not a duplicate")
    func sessionPushIsIdempotent() async throws {
        let repo = FakeRepoStore()
        let engine = SyncEngine(store: repo, baseStore: FakeBaseStore())
        let session = makeSession()

        let first = try await engine.pushSession(session)
        let second = try await engine.pushSession(session)

        #expect(first != nil)
        #expect(second == nil)
        #expect(repo.commits.count == 1)
        #expect(repo.files.count == 1)
    }

    @Test("A different same-day session gets a numbered path, not a clobber")
    func sameDaySessionsBothSurvive() async throws {
        let repo = FakeRepoStore()
        let engine = SyncEngine(store: repo, baseStore: FakeBaseStore())
        let morning = makeSession()
        var evening = makeSession()
        evening.endedAt = morning.startedAt.addingTimeInterval(3600)

        let firstPath = try await engine.pushSession(morning)
        let secondPath = try await engine.pushSession(evening)

        #expect(firstPath != nil && secondPath != nil)
        #expect(firstPath != secondPath)
        #expect(repo.files.count == 2)
    }

    @Test("Commit messages summarize beyond two paths")
    func commitMessageSummarizes() {
        let message = SyncEngine.commitMessage(pushing: [
            "program/workouts/a.json", "program/workouts/b.json",
            "program/exercises/c.json", "program/exercises/d.json",
        ])
        #expect(message == "Sync: a, b (+2 more)")
    }
}
