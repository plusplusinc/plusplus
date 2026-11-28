import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// The order the session sends its writes in. A relaunch is a second store over the same
/// container: it sees only what landed.
@Suite("Workout session")
struct AppSessionTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    private func session(_ workout: Workout = Workout()) -> AppSession {
        AppSession(workout: workout, store: relaunch(), namer: .muscleGroupsOnly)
    }

    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func upper() throws -> Workout {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let bench = WorkoutExercise(exercise: exercise, weightUnit: .pounds)
        return Workout(name: "Upper", exercises: [bench])
    }

    @Test("An edit just before a switch is saved before the next workout opens")
    func editBeforeSwitch() async throws {
        let session = session()
        let workout = try Self.upper()
        session.save(workout)
        await session.startNew()
        #expect(session.current.isEmpty)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
    }

    @Test("An edit just before opening another workout is saved")
    func editBeforeOpen() async throws {
        let other = Workout(name: "Lower")
        try await relaunch().save(other, at: Self.at(1))
        let session = session()
        let workout = try Self.upper()
        session.save(workout)
        await session.open(other.id, weightUnit: .pounds)
        #expect(session.current == other)
        #expect(try await relaunch().openWorkout(workout.id, weightUnit: .pounds) == workout)
    }

    @Test("Of edits not yet saved, the newest is the one that lands")
    func newestLands() async throws {
        let session = session()
        var workout = try Self.upper()
        for name in ["One", "Two", "Three"] {
            workout.name = name
            session.save(workout)
        }
        await session.startNew()
        #expect(try await relaunch().openWorkout(workout.id, weightUnit: .pounds)?.name == "Three")
    }

    /// The store deletes a cleared workout it is handed (`StoreTests`); this holds that the
    /// session hands it one, with no workout running and no switch, as the screen's last edit
    /// before a quit.
    @Test("A saved workout cleared to nothing, rows then name, is gone at a relaunch")
    func clearedIsGone() async throws {
        let session = session()
        var workout = try Self.upper()
        session.save(workout)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
        workout.exercises = []
        session.save(workout)
        workout.name = ""
        session.save(workout)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == nil)
    }

    @Test("An edit made while the next workout is being read is saved")
    func editDuringRead() async throws {
        let workout = try Self.upper()
        let session = session(workout)
        let other = Workout(name: "Lower")
        let (reading, readStarted) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseRead) = AsyncStream.makeStream(of: Void.self)
        let switching = Task {
            await session.switchTo {
                readStarted.yield()
                for await _ in release {
                    break
                }
                return other
            }
        }
        for await _ in reading {
            break
        }
        var edited = workout
        edited.name = "Push day"
        session.save(edited)
        releaseRead.yield()
        await switching.value
        #expect(session.current == other)
        #expect(try await relaunch().openWorkout(workout.id, weightUnit: .pounds) == edited)
    }

    @Test("An edit made as the read ends is saved before the next workout shows")
    func editAsReadEnds() async throws {
        let workout = try Self.upper()
        let session = session(workout)
        let other = Workout(name: "Lower")
        var edited = workout
        edited.name = "Push day"
        // The edit is still on its way to the store when the read returns.
        await session.switchTo { @MainActor [edited] in
            session.save(edited)
            return other
        }
        #expect(session.current == other)
        #expect(try await relaunch().openWorkout(workout.id, weightUnit: .pounds) == edited)
    }

    @Test("A workout's end is saved even with the next start queued behind it")
    func endBeforeNextStart() async throws {
        let workout = try Self.upper()
        let session = session(workout)
        session.start(on: workout.id, at: Self.at(10))
        let first = try #require(session.workoutSession)
        await session.writesLanded()
        session.finish(at: Self.at(20))
        session.start(on: workout.id, at: Self.at(30))
        let second = try #require(session.workoutSession)
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
            .map(\.workoutSession)
        #expect(stored.first { $0.id == first.id }?.endedAt == Self.at(20))
        #expect(stored.first { $0.id == second.id }?.isInProgress == true)
    }

    @Test("Finish writes the name the workout shows then, not the one at Start")
    func finishName() async throws {
        var workout = try Self.upper()
        workout.name = ""
        let session = session(workout)
        session.start(on: workout.id)
        let generated = try #require(WorkoutNamer.muscleGroupsOnly.shownName(of: workout))
        #expect(session.workoutSession?.workoutName == generated)
        workout.name = "Push day"
        session.save(workout)
        session.finish()
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
        #expect(stored.map(\.workoutSession.workoutName) == ["Push day"])
    }

    @Test("A workout emptied while in progress is kept until it ends, then deleted")
    func emptiedDuringLiveWorkout() async throws {
        let workout = try Self.upper()
        let session = session(workout)
        session.save(workout)
        session.start(on: workout.id)
        session.save(Workout(id: workout.id))
        await session.writesLanded()
        let kept = try await relaunch().openWorkout(workout.id, weightUnit: .pounds)
        #expect(kept?.isEmpty == true)
        session.finish()
        await session.writesLanded()
        #expect(try await relaunch().openWorkout(workout.id, weightUnit: .pounds) == nil)
    }

    @Test("After every change to a workout, a relaunch opens it as the session shows it")
    func relaunchAfterEachChange() async throws {
        let workout = try Self.upper()
        let row = workout.exercises[0]
        let session = session(workout)
        session.save(workout)
        let steps: [(name: String, change: () -> Void)] = [
            ("start", { session.start(on: workout.id, at: Self.at(10)) }),
            ("pause", { session.togglePause(at: Self.at(20)) }),
            ("resume", { session.togglePause(at: Self.at(30)) }),
            ("log", { session.log(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(40)) }),
            ("finish", { session.finish(at: Self.at(50)) }),
            ("start again", { session.start(on: workout.id, at: Self.at(60)) }),
            ("discard", { session.discard() }),
        ]
        for step in steps {
            step.change()
            await session.writesLanded()
            let relaunched = try await relaunch().launch(weightUnit: .pounds).workoutSession
            #expect(relaunched == session.workoutSession, "after \(step.name)")
        }
        #expect(session.workoutSession == nil)
        // Of the two workouts, only the finished one is kept.
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutSession>())
        #expect(stored.map(\.workoutSession.startedAt) == [Self.at(10)])
    }

    @Test("Start pressed on a workout with no exercises starts nothing")
    func startOnEmptyWorkout() async throws {
        let workout = Workout(name: "Empty")
        let session = session(workout)
        #expect(!session.canStart(on: workout.id))
        session.start(on: workout.id)
        #expect(session.workoutSession == nil)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).workoutSession == nil)
    }

    @Test("Start pressed on a workout since switched away from starts nothing")
    func startOnAnotherWorkout() async throws {
        let session = try session(Self.upper())
        session.start(on: Workout().id)
        #expect(session.workoutSession == nil)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).workoutSession == nil)
    }

    @Test("Start pressed on a workout while a switch away from it is under way starts nothing")
    func startDuringSwitch() async throws {
        let workout = try Self.upper()
        let session = session(workout)
        let other = Workout(name: "Lower")
        let (reading, readStarted) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseRead) = AsyncStream.makeStream(of: Void.self)
        let switching = Task {
            await session.switchTo {
                readStarted.yield()
                for await _ in release {
                    break
                }
                return other
            }
        }
        for await _ in reading {
            break
        }
        #expect(!session.canStart(on: workout.id))
        session.start(on: workout.id)
        #expect(session.workoutSession == nil)
        releaseRead.yield()
        await switching.value
        #expect(session.current == other)
        #expect(session.workoutSession == nil)
    }

    @Test("The drawer opens with no workout, and stays shut while one runs, whoever opens it")
    func drawerLockedInLiveWorkout() throws {
        let workout = try Self.upper()
        let session = session(workout)
        session.openDrawer()
        #expect(session.isDrawerOpen)
        session.start(on: workout.id)
        #expect(!session.isDrawerOpen)
        session.openDrawer()
        #expect(!session.isDrawerOpen)
    }

    @Test("Logging through the session stores the set at the row's numbers")
    func logStores() async throws {
        let workout = try Self.upper()
        let row = workout.exercises[0]
        let session = session(workout)
        session.save(workout)
        session.start(on: workout.id)
        let set = PlannedSet(row: row.id, round: 1)
        session.log(set, of: row)
        await session.writesLanded()
        let stored = try #require(try await relaunch().launch(weightUnit: .pounds).workoutSession)
        #expect(stored.sets.map(\.planned) == [set])
        #expect(stored.sets.first?.target == row.plan.target)
        #expect(stored.sets.first?.weight == row.shownWeight)
    }
}
