import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Session cursor, jump/redo, carry-forward")
struct SessionNavigationTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Bench 3 sets @ 100 lb target, then Plank 1×45s.
    private func makeSession(context: ModelContext) -> WorkoutSession {
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        let plank = Exercise(name: "Plank", muscleGroup: .core, exerciseType: .duration)
        context.insert(bench)
        context.insert(plank)

        let routine = Routine(name: "W", restSeconds: 60)
        context.insert(routine)
        let benchGroup = routine.addExerciseInNewGroup(bench, context: context)
        benchGroup.sortedExercises[0].weight = 100
        let plankGroup = routine.addExerciseInNewGroup(plank, context: context)
        plankGroup.sets = 1
        plankGroup.sortedExercises[0].durationSeconds = 45

        return WorkoutSession.start(from: routine, context: context)
    }

    @Test("Completing advances the cursor; a changed weight carries to remaining sets")
    func carryForward() throws {
        let context = ModelContext(try makeContainer())
        let session = makeSession(context: context)

        let first = try #require(session.currentLog)
        #expect(first.setNumber == 1)
        first.actualWeight = 105
        #expect(session.weightCarriesForward(from: first))
        session.complete(first)

        let second = try #require(session.currentLog)
        #expect(second.setNumber == 2)
        #expect(second.targetWeight == 105, "New weight becomes the remaining sets' target")
        #expect(session.sortedSetLogs[2].targetWeight == 105)
        // The plank is a different exercise — untouched.
        #expect(session.sortedSetLogs[3].targetDuration == 45)
    }

    @Test("Matching or nil weight does not rewrite targets")
    func noCarryWhenUnchanged() throws {
        let context = ModelContext(try makeContainer())
        let session = makeSession(context: context)

        let first = try #require(session.currentLog)
        #expect(!session.weightCarriesForward(from: first), "No edit yet — no hint")
        session.complete(first)
        #expect(session.sortedSetLogs[1].targetWeight == 100)
    }

    @Test("Jump moves the cursor; completing there returns to the earliest pending")
    func jumpAndReturn() throws {
        let context = ModelContext(try makeContainer())
        let session = makeSession(context: context)

        let plankLog = try #require(session.sortedSetLogs.last)
        session.jump(to: plankLog)
        #expect(session.currentLog === plankLog)

        session.complete(plankLog)
        let back = try #require(session.currentLog)
        #expect(back.exerciseName == "Bench Press", "Wraps to the first pending log")
        #expect(back.setNumber == 1)
    }

    @Test("Redo reopens a completed set keeping its actuals as prefill")
    func redo() throws {
        let context = ModelContext(try makeContainer())
        let session = makeSession(context: context)

        let first = try #require(session.currentLog)
        first.actualReps = 8
        session.complete(first)
        #expect(first.isCompleted)

        session.jump(to: first, redo: true)
        #expect(!first.isCompleted)
        #expect(session.currentLog === first)
        #expect(first.actualReps == 8, "Previous actuals stay as the prefill")
    }

    @Test("Jump without redo refuses completed logs")
    func jumpRefusesCompleted() throws {
        let context = ModelContext(try makeContainer())
        let session = makeSession(context: context)

        let first = try #require(session.currentLog)
        session.complete(first)
        session.jump(to: first)
        let current = try #require(session.currentLog)
        #expect(current !== first)
    }
}
