import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Each row's plan saved with the workout, and read back field by field, with the exercise's
/// default for anything never stored or not understood.
@Suite("Workout store plans")
struct StorePlanTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: Store.schema)
    }

    private func relaunch() -> Store {
        Store(modelContainer: container)
    }

    /// Saves a workout of one `name` row, then sets its stored fields with `edit`.
    private func storedRow(_ name: String, edit: (StoredWorkoutExercise) -> Void) async throws {
        try await relaunch().save(Workout(exercises: [WorkoutExercise.builtIn(name)]))
        let context = ModelContext(container)
        let row = try #require(try context.fetch(FetchDescriptor<StoredWorkoutExercise>()).first)
        edit(row)
        try context.save()
    }

    @Test("Plans round-trip: reps, time, each load, both units")
    func roundTrip() async throws {
        let workout = try Workout(exercises: [
            WorkoutExercise.builtIn("Barbell bench press") {
                $0.sets = 5
                $0.weight = Weight(135, .pounds)
            },
            WorkoutExercise.builtIn("Biceps curl") { $0.weight = Weight(12.5, .kilograms) },
            WorkoutExercise.builtIn("Goblet squat") { $0.target = .reps(12) },
            WorkoutExercise.builtIn("Pigeon stretch") { $0.target = .time(seconds: 90) },
            WorkoutExercise.builtIn("Farmer\u{2019}s carry") { $0.weight = Weight(50, .pounds) },
        ])
        try await relaunch().save(workout)
        #expect(try await relaunch().launch(weightUnit: .pounds).workout == workout)
    }

    /// A weight off its load's 5 lb steps, as the ruler sets one, through every place a weight
    /// is kept: the plan, the stored workout, and a set logged at it.
    @Test("A 27.5 lb weight round-trips through the plan, the stored workout, and a logged set")
    func offStepWeightRoundTrip() async throws {
        var curl = try WorkoutExercise.builtIn("Biceps curl")
        curl.setWeight(27.5)
        let workout = Workout(name: "Arms", exercises: [curl])
        try await relaunch().save(workout, at: Date(timeIntervalSinceReferenceDate: 1))
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened.exercises.first?.plan.weight == Weight(27.5, .pounds))

        let next = try #require(reopened.nextSet(after: []))
        let row = try #require(reopened.exercises.first)
        let loggedWorkout = WorkoutSession(
            workoutID: reopened.id,
            workoutName: reopened.name,
            startedAt: Date(timeIntervalSinceReferenceDate: 10),
        ).logging(next, of: row, at: Date(timeIntervalSinceReferenceDate: 20))
        try await relaunch().save(loggedWorkout)
        let launched = try #require(try await relaunch().launch(weightUnit: .pounds).loggedWorkout)
        #expect(launched.sets.first?.weight == Weight(27.5, .pounds))
    }

    @Test("Rest round-trips: automatic, set by hand, and a hand rest kept while automatic")
    func restRoundTrip() async throws {
        var remembered = try WorkoutExercise.builtIn("Barbell bench press")
        remembered.step(.rest, by: 1)
        remembered.isRestAuto = true
        let workout = try Workout(exercises: [
            WorkoutExercise.builtIn("Push-up"),
            WorkoutExercise.builtIn("Biceps curl") {
                $0.rest = .byHand(0)
            },
            remembered,
        ])
        try await relaunch().save(workout)
        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened == workout)
        #expect(reopened.exercises.map(\.rest) == [60, 0, 150])
        var back = reopened.exercises[2]
        back.isRestAuto = false
        #expect(back.rest == 165)
    }

    @Test("A rest never set is stored as nil, to follow the reps; one out of range reads as unset")
    func restStoredUnset() async throws {
        try await storedRow("Push-up") { row in
            #expect(row.rest == nil)
            #expect(row.isRestAuto)
            row.rest = 900
            row.isRestAuto = false
        }
        let row = try #require(try await relaunch().launch(weightUnit: .pounds).workout?
            .exercises.first)
        #expect(row.plan.rest == .neverSet)
        #expect(row.rest == 60)
    }

    @Test("Two rows of one exercise keep their own values, and a kept row's change is saved")
    func rowsApart() async throws {
        let store = relaunch()
        var workout = try Workout(exercises: [
            WorkoutExercise.builtIn("Pull-up"),
            WorkoutExercise.builtIn("Pull-up"),
        ])
        try await store.save(workout)
        workout.exercises[1].plan.target = .reps(8)
        try await store.save(workout)

        let reopened = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(reopened.exercises.map(\.plan.target) == [.reps(6), .reps(8)])
    }

    @Test("A row's plan is stored even when it is the default")
    func defaultStored() async throws {
        try await relaunch().save(Workout(exercises: [WorkoutExercise.builtIn("Push-up")]))
        let row = try #require(
            try ModelContext(container).fetch(FetchDescriptor<StoredWorkoutExercise>()).first,
        )
        #expect(row.sets == 3)
        #expect(row.reps == 10)
        #expect(row.seconds == nil)
    }

    @Test("A row stored before plans reads as its defaults, its weight in the region's unit")
    func neverStored() async throws {
        try await storedRow("Dumbbell row") { row in
            row.sets = nil
            row.reps = nil
            row.weight = nil
            row.weightUnit = nil
        }
        let row = try Exercise.builtIn(named: "Dumbbell row")
        let inPounds = try #require(try await relaunch().launch(weightUnit: .pounds).workout)
        #expect(inPounds.exercises.map(\.plan) == [row.defaultPlan(in: .pounds)])
        let inKilograms = try #require(try await relaunch().launch(weightUnit: .kilograms).workout)
        #expect(inKilograms.exercises.map(\.plan) == [row.defaultPlan(in: .kilograms)])
        #expect(inKilograms.exercises.first?.plan.weight == Weight(12, .kilograms))
    }

    @Test("An unknown unit reads as the default weight, and the rest of the row loads")
    func unknownUnit() async throws {
        try await storedRow("Biceps curl") { row in
            row.reps = 8
            row.weight = 20
            row.weightUnit = "stone"
        }
        let plan = try #require(try await relaunch().launch(weightUnit: .pounds).workout?.exercises
            .first?.plan)
        #expect(plan == ExercisePlan(sets: 3, target: .reps(8), weight: Weight(15, .pounds)))
    }

    @Test("Stored seconds on a reps exercise, and zero or negative values, read as defaults")
    func outOfPlace() async throws {
        try await storedRow("Goblet squat") { row in
            row.sets = 0
            row.reps = nil
            row.seconds = 45
            row.weight = -5
            row.weightUnit = "lb"
        }
        let plan = try #require(try await relaunch().launch(weightUnit: .pounds).workout?.exercises
            .first?.plan)
        #expect(try plan == Exercise.builtIn(named: "Goblet squat").defaultPlan(in: .pounds))
    }

    @Test("A weight heavier than a stepper reaches reads as the default")
    func tooHeavy() async throws {
        try await storedRow("Goblet squat") { row in
            row.weight = 1005
            row.weightUnit = "lb"
        }
        let plan = try #require(try await relaunch().launch(weightUnit: .pounds).workout?.exercises
            .first?.plan)
        #expect(try plan.weight == Exercise.builtIn(named: "Goblet squat").defaultPlan(in: .pounds)
            .weight)
    }

    @Test("A weight stored on an exercise with no load is not shown")
    func noLoadNoWeight() async throws {
        try await storedRow("Push-up") { row in
            row.weight = 10
            row.weightUnit = "lb"
        }
        let plan = try #require(try await relaunch().launch(weightUnit: .pounds).workout?.exercises
            .first?.plan)
        #expect(plan.weight == nil)
    }
}
