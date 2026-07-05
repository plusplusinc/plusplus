import Foundation
import Testing
import SwiftData
@testable import PlusPlus

@Suite("Last performance lookup")
struct LastPerformanceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Workout.self, ExerciseGroup.self,
            WorkoutExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A finished session with `sets` completed logs of one exercise.
    @discardableResult
    private func makeFinishedSession(
        exercise: Exercise?,
        exerciseName: String,
        sets: Int,
        reps: Int,
        endedAt: Date,
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(workoutName: "W", startedAt: endedAt.addingTimeInterval(-1800))
        context.insert(session)
        for setNumber in 1...sets {
            let log = SetLog(order: setNumber - 1, groupIndex: 0, setNumber: setNumber,
                             exercise: exercise, exerciseName: exerciseName)
            log.actualReps = reps
            log.actualWeight = 100
            log.completedAt = endedAt.addingTimeInterval(TimeInterval(-60 * (sets - setNumber)))
            log.session = session
            context.insert(log)
        }
        session.endedAt = endedAt
        return session
    }

    private func pendingLog(for exercise: Exercise?, named name: String, setNumber: Int, context: ModelContext) -> SetLog {
        let current = WorkoutSession(workoutName: "W", startedAt: Date())
        context.insert(current)
        let log = SetLog(order: 0, groupIndex: 0, setNumber: setNumber, exercise: exercise, exerciseName: name)
        log.session = current
        context.insert(log)
        return log
    }

    @Test("Finds the same set number in the newest prior session")
    func newestSessionSameSet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(bench)

        let old = makeFinishedSession(exercise: bench, exerciseName: "Bench Press", sets: 3, reps: 8,
                                      endedAt: Date(timeIntervalSince1970: 1_000), context: context)
        let recent = makeFinishedSession(exercise: bench, exerciseName: "Bench Press", sets: 3, reps: 10,
                                         endedAt: Date(timeIntervalSince1970: 2_000), context: context)

        let current = pendingLog(for: bench, named: "Bench Press", setNumber: 2, context: context)
        let match = WorkoutSession.lastPerformance(matching: current, in: [old, recent])

        #expect(match?.session === recent)
        #expect(match?.setNumber == 2)
        #expect(match?.actualReps == 10)
    }

    @Test("Falls back to the exercise's last set when set numbers don't align")
    func setNumberFallback() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(bench)

        let prior = makeFinishedSession(exercise: bench, exerciseName: "Bench Press", sets: 2, reps: 8,
                                        endedAt: Date(timeIntervalSince1970: 1_000), context: context)

        let current = pendingLog(for: bench, named: "Bench Press", setNumber: 5, context: context)
        let match = WorkoutSession.lastPerformance(matching: current, in: [prior])

        #expect(match?.setNumber == 2)
    }

    @Test("Matches by name snapshot when the exercise reference is gone")
    func nameFallback() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let prior = makeFinishedSession(exercise: nil, exerciseName: "Band Pulses", sets: 1, reps: 15,
                                        endedAt: Date(timeIntervalSince1970: 1_000), context: context)

        let current = pendingLog(for: nil, named: "Band Pulses", setNumber: 1, context: context)
        let match = WorkoutSession.lastPerformance(matching: current, in: [prior])

        #expect(match?.session === prior)
        #expect(match?.actualReps == 15)
    }

    @Test("The current session's own logs never match")
    func ignoresCurrentSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(bench)

        // A finished-looking session that IS the current one: its earlier
        // sets must not surface as "last time".
        let current = makeFinishedSession(exercise: bench, exerciseName: "Bench Press", sets: 2, reps: 8,
                                          endedAt: Date(timeIntervalSince1970: 1_000), context: context)
        let log = SetLog(order: 2, groupIndex: 0, setNumber: 3, exercise: bench, exerciseName: "Bench Press")
        log.session = current
        context.insert(log)

        #expect(WorkoutSession.lastPerformance(matching: log, in: [current]) == nil)
    }

    @Test("Returns nil with no prior history")
    func noHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let squat = Exercise(name: "Squat", muscleGroup: .quads)
        context.insert(squat)

        let other = makeFinishedSession(exercise: nil, exerciseName: "Bench Press", sets: 2, reps: 8,
                                        endedAt: Date(timeIntervalSince1970: 1_000), context: context)

        let current = pendingLog(for: squat, named: "Squat", setNumber: 1, context: context)
        #expect(WorkoutSession.lastPerformance(matching: current, in: [other]) == nil)
        #expect(WorkoutSession.lastPerformance(matching: current, in: []) == nil)
    }

    @Test("Unfinished sessions are excluded")
    func excludesUnfinished() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(bench)

        let unfinished = makeFinishedSession(exercise: bench, exerciseName: "Bench Press", sets: 1, reps: 12,
                                             endedAt: Date(timeIntervalSince1970: 1_000), context: context)
        unfinished.endedAt = nil

        let current = pendingLog(for: bench, named: "Bench Press", setNumber: 1, context: context)
        #expect(WorkoutSession.lastPerformance(matching: current, in: [unfinished]) == nil)
    }
}
