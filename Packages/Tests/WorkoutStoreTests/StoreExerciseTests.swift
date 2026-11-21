import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Created exercises in the store. A relaunch is a second store over the same container.
@Suite("Workout store, created exercises")
struct StoreExerciseTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
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

    @Test("A workout and a logged workout in progress reopen with a created exercise's row")
    func workoutReopens() async throws {
        let store = relaunch()
        try await store.save(Self.ringRow)
        var row = WorkoutExercise(exercise: Exercise(created: Self.ringRow), weightUnit: .pounds)
        row.plan.sets = 4
        let workout = try Workout(
            name: "Day A",
            exercises: [row, WorkoutExercise.builtIn("Waiter carry")],
        )
        try await store.save(workout)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
        try await relaunch()
            .save(LoggedWorkout(workoutID: workout.id, workoutName: "Day A", startedAt: .now))
        let launch = try await relaunch().launch(weightUnit: .pounds)
        #expect(launch.loggedWorkout != nil)
        #expect(launch.workout == workout)
        #expect(try await relaunch().workoutsByRecency(weightUnit: .pounds) == [workout])
    }

    @Test("A created exercise with no muscle group reopens, and so does its workout's row")
    func noMuscleGroupReopens() async throws {
        let store = relaunch()
        let none = CreatedExercise(name: "Zq", muscleGroups: [])
        try await store.save(none)
        let workout = Workout(
            name: "Day A",
            exercises: [WorkoutExercise(exercise: Exercise(created: none), weightUnit: .pounds)],
        )
        try await store.save(workout)
        #expect(try await relaunch().exercises() == ExerciseList(created: [none]))
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
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
