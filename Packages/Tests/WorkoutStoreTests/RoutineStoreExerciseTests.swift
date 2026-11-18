import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Created exercises in the store. A relaunch is a second store over the same container.
@Suite("Routine store, created exercises")
struct RoutineStoreExerciseTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private static let ringRow = CreatedExercise(
        name: "Ring row with rotation",
        muscleGroups: [.back],
        equipment: [.rings],
        createdAt: Date(timeIntervalSinceReferenceDate: 1),
    )

    private static let rotation = CreatedExercise(
        name: "Prone external rotation",
        muscleGroups: [.shoulders, .back],
        equipment: [.dumbbells, .bench],
        measure: .time,
        isPerSide: true,
        createdAt: Date(timeIntervalSinceReferenceDate: 2),
    )

    @Test("A created exercise, saved, is in the list a relaunch reads, every setting kept")
    func roundTrip() async throws {
        try await relaunch().save(Self.ringRow)
        try await relaunch().save(Self.rotation)
        let list = try await relaunch().exercises()
        #expect(list == ExerciseList(created: [Self.ringRow, Self.rotation]))
        #expect(list.exercise(id: Self.rotation.id) == Exercise(created: Self.rotation))
    }

    @Test("Saving an exercise again updates it rather than adding a second")
    func saveAgain() async throws {
        try await relaunch().save(Self.ringRow)
        var renamed = Self.ringRow
        renamed.name = "Ring row"
        try await relaunch().save(renamed)
        let list = try await relaunch().exercises()
        #expect(list == ExerciseList(created: [renamed]))
    }

    @Test("A routine and a workout in progress reopen with a created exercise's row")
    func routineReopens() async throws {
        let store = relaunch()
        try await store.save(Self.ringRow)
        var row = RoutineExercise(exercise: Exercise(created: Self.ringRow), weightUnit: .pounds)
        row.plan.sets = 4
        let routine = try Routine(
            name: "Day A",
            exercises: [row, RoutineExercise.builtIn("Waiter carry")],
        )
        try await store.save(routine)
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
        try await relaunch()
            .save(Workout(routineID: routine.id, routineName: "Day A", startedAt: .now))
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.workout != nil)
        #expect(launch.routine == routine)
        #expect(try await relaunch().routinesByRecency(weightUnit: .pounds) == [routine])
    }

    @Test("A created exercise with no muscle group reopens, and so does its routine's row")
    func noMuscleGroupReopens() async throws {
        let store = relaunch()
        let none = CreatedExercise(name: "Zq", muscleGroups: [])
        try await store.save(none)
        let routine = try Routine(
            name: "Day A",
            exercises: [RoutineExercise(exercise: Exercise(created: none), weightUnit: .pounds)],
        )
        try await store.save(routine)
        #expect(try await relaunch().exercises() == ExerciseList(created: [none]))
        #expect(try await relaunch().launch(weightUnit: .pounds).routine == routine)
    }

    @Test("An exercise this build can't read is left out of the list and kept in the store")
    func unreadable() async throws {
        let context = ModelContext(container)
        for (group, measure) in [("neck", "reps"), ("back", "distance")] {
            let stored = StoredExercise(id: CreatedExercise.newID())
            stored.name = "From later"
            stored.muscleGroup = group
            stored.measure = measure
            context.insert(stored)
        }
        let odd = StoredExercise(id: "created:odd")
        odd.name = "Odd kit"
        odd.muscleGroup = "back,neck"
        odd.equipment = "rings,sled"
        context.insert(odd)
        try context.save()

        let list = try await relaunch().exercises()
        #expect(list.all.count == Exercise.builtIn.count + 1)
        #expect(list.exercise(id: "created:odd")?.equipment == [.rings])
        #expect(list.exercise(id: "created:odd")?.muscleGroups == [.back])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredExercise>()) == 3)
    }
}
