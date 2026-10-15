import Foundation
import SwiftData
import Testing
@testable import WorkoutStore

/// Each row's plan saved with the routine, and read back field by field, with the exercise's
/// default for anything never stored or not understood.
@Suite("Routine store plans")
struct RoutineStorePlanTests {
    private let container: ModelContainer

    init() throws {
        container = try WorkoutStoreContainer.make(mode: .inMemory, schema: RoutineStore.schema)
    }

    private func relaunch() -> RoutineStore {
        RoutineStore(modelContainer: container)
    }

    private static func row(_ name: String, _ edit: (inout ExercisePlan) -> Void = { _ in })
        throws -> RoutineExercise
    {
        let exercise = try Exercise.builtIn(named: name)
        var plan = exercise.defaultPlan
        edit(&plan)
        return RoutineExercise(exercise: exercise, plan: plan)
    }

    /// Saves a routine of one `name` row, then sets its stored fields with `edit`.
    private func storedRow(_ name: String, edit: (StoredRoutineExercise) -> Void) async throws {
        try await relaunch().save(Routine(exercises: [Self.row(name)]))
        let context = ModelContext(container)
        let row = try #require(try context.fetch(FetchDescriptor<StoredRoutineExercise>()).first)
        edit(row)
        try context.save()
    }

    @Test("Plans round-trip: reps, time, each load, both units")
    func roundTrip() async throws {
        let routine = try Routine(exercises: [
            Self.row("Barbell bench press") {
                $0.sets = 5
                $0.weight = Weight(135, .pounds)
            },
            Self.row("Biceps curl") { $0.weight = Weight(12.5, .kilograms) },
            Self.row("Goblet squat") { $0.target = .reps(12) },
            Self.row("Pigeon stretch") { $0.target = .time(seconds: 90) },
            Self.row("Farmer\u{2019}s carry") { $0.weight = Weight(50, .pounds) },
        ])
        try await relaunch().save(routine)
        #expect(try await relaunch().launchRoutine() == routine)
    }

    @Test("Two rows of one exercise keep their own values, and a kept row's change is saved")
    func rowsApart() async throws {
        let store = relaunch()
        var routine = try Routine(exercises: [Self.row("Pull-up"), Self.row("Pull-up")])
        try await store.save(routine)
        routine.exercises[1].plan.target = .reps(8)
        try await store.save(routine)

        let reopened = try #require(try await relaunch().launchRoutine())
        #expect(reopened.exercises.map(\.plan.target) == [.reps(6), .reps(8)])
    }

    @Test("A row stored before plans existed reads as its exercise's defaults")
    func neverStored() async throws {
        try await storedRow("Dumbbell row") { row in
            row.sets = nil
            row.reps = nil
            row.weight = nil
            row.weightUnit = nil
        }
        let reopened = try #require(try await relaunch().launchRoutine())
        #expect(try reopened.exercises.map(\.plan) == [Exercise.builtIn(named: "Dumbbell row")
                .defaultPlan])
    }

    @Test("An unknown unit reads as not set, and the rest of the row loads")
    func unknownUnit() async throws {
        try await storedRow("Biceps curl") { row in
            row.reps = 8
            row.weight = 20
            row.weightUnit = "stone"
        }
        let plan = try #require(try await relaunch().launchRoutine()?.exercises.first?.plan)
        #expect(plan == ExercisePlan(sets: 3, target: .reps(8)))
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
        let plan = try #require(try await relaunch().launchRoutine()?.exercises.first?.plan)
        #expect(try plan == Exercise.builtIn(named: "Goblet squat").defaultPlan)
    }

    @Test("A weight stored on an exercise with no load is not shown")
    func noLoadNoWeight() async throws {
        try await storedRow("Push-up") { row in
            row.weight = 10
            row.weightUnit = "lb"
        }
        let plan = try #require(try await relaunch().launchRoutine()?.exercises.first?.plan)
        #expect(plan.weight == nil)
    }
}
