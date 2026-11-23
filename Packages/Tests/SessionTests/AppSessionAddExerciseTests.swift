import Foundation
import Testing
@testable import Session
@testable import WorkoutStore

/// Add exercise's openings, and its filter, which is the open workout's: kept from one opening
/// to the next until cleared, and none in a different workout.
@Suite("Add exercise's openings and kept filter")
struct AppSessionAddExerciseTests {
    private let store: Store
    private let saved = Workout(name: "Lower")
    private let legs = ExerciseFilter(muscleGroups: [.legs])

    init() async throws {
        let container = try WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: Store.schema,
        )
        store = Store(modelContainer: container)
        try await store.save(saved, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    /// A session on a workout of one bench press row, with Legs chosen in Add exercise and the
    /// sheet closed by a pick.
    private func sessionKeepingLegs() throws -> AppSession {
        let exercise = try #require(Exercise.builtIn(id: "barbell-bench-press"))
        let row = WorkoutExercise(exercise: exercise, weightUnit: .pounds)
        let session = AppSession(
            workout: Workout(name: "Upper", exercises: [row]),
            store: store,
            namer: .muscleGroupsOnly,
        )
        session.openAddExercise()
        session.addExerciseFilter = legs
        session.closeAddExercise()
        return session
    }

    @Test("Add exercise opened again in the same workout is a new opening on the last filter")
    func addExerciseReopensWithItsFilter() throws {
        let session = try sessionKeepingLegs()
        session.openAddExercise()
        let first = try #require(session.addExercise).id
        // A double tap, the sheet still rising.
        session.openAddExercise()
        #expect(session.addExercise?.id == first)
        session.closeAddExercise()
        session.openAddExercise()
        let second = try #require(session.addExercise)
        #expect(second.id != first, "The picker opened again would keep the last one's search")
        #expect(session.addExerciseFilter.muscleGroups == [.legs])
    }

    @Test("Clearing Add exercise's filter leaves none on at the next opening")
    func clearedFilterStaysCleared() throws {
        let session = try sessionKeepingLegs()
        session.openAddExercise()
        // What Clear writes (`FilterBar`).
        session.addExerciseFilter = ExerciseFilter()
        session.closeAddExercise()
        session.openAddExercise()
        #expect(!session.addExerciseFilter.isOn)
    }

    @Test("Another workout opened from the list starts Add exercise with no filter")
    func anotherWorkoutStartsClear() async throws {
        let session = try sessionKeepingLegs()
        session.showWorkouts()
        await session.open(saved.id, weightUnit: .pounds)
        #expect(session.current.id == saved.id)
        #expect(!session.addExerciseFilter.isOn)
    }

    @Test("A new workout starts Add exercise with no filter")
    func newWorkoutStartsClear() async throws {
        let session = try sessionKeepingLegs()
        session.showWorkouts()
        await session.startNew()
        #expect(session.current.isEmpty)
        #expect(!session.addExerciseFilter.isOn)
    }

    @Test("Deleting the open workout drops its Add exercise filter")
    func deletingOpenDropsFilter() async throws {
        let session = try sessionKeepingLegs()
        await session.delete(session.current.id)
        #expect(!session.addExerciseFilter.isOn)
    }

    @Test("The same workout, popped to the list and opened again, keeps its Add exercise filter")
    func sameWorkoutKeepsFilter() async throws {
        let session = try sessionKeepingLegs()
        session.showWorkouts()
        await session.open(session.current.id, weightUnit: .pounds)
        session.popWorkout()
        await session.open(session.current.id, weightUnit: .pounds)
        #expect(session.addExerciseFilter.muscleGroups == [.legs])
    }

    @Test("A filter handed to Add exercise replaces the kept one, and is kept in turn")
    func handedInFilterReplacesKept() throws {
        let session = try sessionKeepingLegs()
        session.openAddExercise(filter: ExerciseFilter(muscleGroups: [.back]))
        #expect(session.addExerciseFilter.muscleGroups == [.back])
        #expect(session.addExerciseFilter.muscleLabel == "Back")
        session.closeAddExercise()
        session.openAddExercise()
        #expect(session.addExerciseFilter.muscleGroups == [.back])
    }
}
