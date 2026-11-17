import Foundation
import SwiftData
import Testing
@testable import Session
@testable import WorkoutStore

/// The order the session sends its writes in. A relaunch is a second store over the same
/// container: it sees only what landed.
@Suite("Routine session")
struct RoutineSessionTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private func session(_ routine: Routine = Routine()) -> RoutineSession {
        RoutineSession(routine: routine, store: relaunch(), namer: .muscleGroupsOnly)
    }

    private static func at(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func upper() throws -> Routine {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let bench = RoutineExercise(exercise: exercise, weightUnit: .pounds)
        return Routine(name: "Upper", exercises: [bench])
    }

    @Test("An edit just before a switch is saved before the next routine opens")
    func editBeforeSwitch() async throws {
        let session = session()
        let routine = try Self.upper()
        session.save(routine)
        await session.startNew()
        #expect(session.current.isEmpty)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }

    @Test("An edit just before opening another routine is saved")
    func editBeforeOpen() async throws {
        let other = Routine(name: "Lower")
        try await relaunch().save(other, at: Self.at(1))
        let session = session()
        let routine = try Self.upper()
        session.save(routine)
        await session.open(other.id, weightUnit: .pounds)
        #expect(session.current == other)
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds) == routine)
    }

    @Test("Of edits not yet saved, the newest is the one that lands")
    func newestLands() async throws {
        let session = session()
        var routine = try Self.upper()
        for name in ["One", "Two", "Three"] {
            routine.name = name
            session.save(routine)
        }
        await session.startNew()
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds)?.name == "Three")
    }

    @Test("An edit made while the next routine is being read is saved")
    func editDuringRead() async throws {
        let routine = try Self.upper()
        let session = session(routine)
        let other = Routine(name: "Lower")
        let (reading, readStarted) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseRead) = AsyncStream.makeStream(of: Void.self)
        let switching = Task {
            await session.switchTo(pushed: false) {
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
        var edited = routine
        edited.name = "Push day"
        session.save(edited)
        releaseRead.yield()
        await switching.value
        #expect(session.current == other)
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds) == edited)
    }

    @Test("An edit made as the read ends is saved before the next routine shows")
    func editAsReadEnds() async throws {
        let routine = try Self.upper()
        let session = session(routine)
        let other = Routine(name: "Lower")
        var edited = routine
        edited.name = "Push day"
        // The edit is still on its way to the store when the read returns.
        await session.switchTo(pushed: false) { @MainActor [edited] in
            session.save(edited)
            return other
        }
        #expect(session.current == other)
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds) == edited)
    }

    @Test("A workout's end is saved even with the next start queued behind it")
    func endBeforeNextStart() async throws {
        let routine = try Self.upper()
        let session = session(routine)
        session.start(on: routine.id, at: Self.at(10))
        let first = try #require(session.workout)
        await session.writesLanded()
        session.finish(at: Self.at(20))
        session.start(on: routine.id, at: Self.at(30))
        let second = try #require(session.workout)
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
            .map(\.workout)
        #expect(stored.first { $0.id == first.id }?.endedAt == Self.at(20))
        #expect(stored.first { $0.id == second.id }?.isInProgress == true)
    }

    @Test("Finish writes the name the routine shows then, not the one at Start")
    func finishName() async throws {
        var routine = try Self.upper()
        routine.name = ""
        let session = session(routine)
        session.start(on: routine.id)
        let generated = try #require(RoutineNamer.muscleGroupsOnly.shownName(of: routine))
        #expect(session.workout?.routineName == generated)
        routine.name = "Push day"
        session.save(routine)
        session.finish()
        await session.writesLanded()
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(stored.map(\.workout.routineName) == ["Push day"])
    }

    @Test("A routine emptied during a workout is kept until the workout ends, then deleted")
    func emptiedDuringWorkout() async throws {
        let routine = try Self.upper()
        let session = session(routine)
        session.save(routine)
        session.start(on: routine.id)
        session.save(Routine(id: routine.id))
        await session.writesLanded()
        let kept = try await relaunch().openRoutine(routine.id, weightUnit: .pounds)
        #expect(kept?.isEmpty == true)
        session.finish()
        await session.writesLanded()
        #expect(try await relaunch().openRoutine(routine.id, weightUnit: .pounds) == nil)
    }

    @Test("After every change to a workout, a relaunch opens it as the session shows it")
    func relaunchAfterEachChange() async throws {
        let routine = try Self.upper()
        let row = routine.exercises[0]
        let session = session(routine)
        session.save(routine)
        let steps: [(name: String, change: () -> Void)] = [
            ("start", { session.start(on: routine.id, at: Self.at(10)) }),
            ("pause", { session.togglePause(at: Self.at(20)) }),
            ("resume", { session.togglePause(at: Self.at(30)) }),
            ("log", { session.log(PlannedSet(row: row.id, round: 1), of: row, at: Self.at(40)) }),
            ("finish", { session.finish(at: Self.at(50)) }),
            ("start again", { session.start(on: routine.id, at: Self.at(60)) }),
            ("discard", { session.discard() }),
        ]
        for step in steps {
            step.change()
            await session.writesLanded()
            let relaunched = try await relaunch().launch(weightUnit: .pounds).workout
            #expect(relaunched == session.workout, "after \(step.name)")
        }
        #expect(session.workout == nil)
        // Of the two workouts, only the finished one is kept.
        let stored = try ModelContext(container).fetch(FetchDescriptor<StoredWorkout>())
        #expect(stored.map(\.workout.startedAt) == [Self.at(10)])
    }

    @Test("Start pressed on a routine with no exercises starts nothing")
    func startOnEmptyRoutine() async throws {
        let routine = Routine(name: "Empty")
        let session = session(routine)
        #expect(!session.canStart(on: routine.id))
        session.start(on: routine.id)
        #expect(session.workout == nil)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == nil)
    }

    @Test("Start pressed on a routine since switched away from starts nothing")
    func startOnAnotherRoutine() async throws {
        let session = try session(Self.upper())
        session.start(on: Routine().id)
        #expect(session.workout == nil)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == nil)
    }

    @Test("Start pressed on a routine while a switch away from it is under way starts nothing")
    func startDuringSwitch() async throws {
        let routine = try Self.upper()
        let session = session(routine)
        let other = Routine(name: "Lower")
        let (reading, readStarted) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseRead) = AsyncStream.makeStream(of: Void.self)
        let switching = Task {
            await session.switchTo(pushed: false) {
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
        #expect(!session.canStart(on: routine.id))
        session.start(on: routine.id)
        #expect(session.workout == nil)
        releaseRead.yield()
        await switching.value
        #expect(session.current == other)
        #expect(session.workout == nil)
    }

    @Test("The drawer opens with no workout, and stays shut while one runs, whoever opens it")
    func drawerLockedInWorkout() throws {
        let routine = try Self.upper()
        let session = session(routine)
        session.openDrawer()
        #expect(session.isDrawerOpen)
        session.start(on: routine.id)
        #expect(!session.isDrawerOpen)
        session.openDrawer()
        #expect(!session.isDrawerOpen)
    }

    @Test("Logging through the session stores the set at the row's numbers")
    func logStores() async throws {
        let routine = try Self.upper()
        let row = routine.exercises[0]
        let session = session(routine)
        session.save(routine)
        session.start(on: routine.id)
        let set = PlannedSet(row: row.id, round: 1)
        session.log(set, of: row)
        await session.writesLanded()
        let stored = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(stored.sets.map(\.planned) == [set])
        #expect(stored.sets.first?.target == row.plan.target)
        #expect(stored.sets.first?.weight == row.shownWeight)
    }

    @Test("A created exercise is stored before the routine save that names it, and listed at once")
    func createdBeforeRow() async throws {
        let session = session()
        let created = CreatedExercise(name: "Ring row with rotation", muscleGroups: [.back])
        let exercise = await session.create(created)
        #expect(session.exercises.exercise(id: created.id) == exercise)
        // Stored once `create` returns, before any routine save could name it.
        #expect(try await relaunch().exercises().exercise(id: created.id) == exercise)
        let routine = Routine(exercises: [RoutineExercise(exercise: exercise, weightUnit: .pounds)])
        session.save(routine)
        await session.writesLanded()
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }
}
