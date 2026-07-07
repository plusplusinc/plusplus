import Foundation
import Testing
@testable import PlusPlusKit

@Suite("WatchSync")
struct WatchSyncTests {
    private var plan: WatchSync.Plan {
        WatchSync.Plan(
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            routines: [
                WatchSync.PlanRoutine(name: "Push Day", restSeconds: 90, steps: [
                    WatchSync.Step(exerciseName: "Bench Press", groupIndex: 0, setNumber: 1, isDuration: false, targetWeight: 135, targetRepsLower: 8, targetRepsUpper: 12),
                    WatchSync.Step(exerciseName: "Plank", groupIndex: 1, setNumber: 1, isDuration: true, targetDuration: 60),
                ]),
            ]
        )
    }

    @Test func planRoundTrips() throws {
        let data = try WatchSync.encode(plan)
        let decoded = try WatchSync.decode(WatchSync.Plan.self, from: data)
        #expect(decoded == plan)
    }

    @Test func sessionResultRoundTrips() throws {
        let started = Date(timeIntervalSince1970: 1_780_000_100)
        let result = WatchSync.SessionResult(
            routineName: "Push Day",
            startedAt: started,
            endedAt: started.addingTimeInterval(1800),
            restSeconds: 90,
            steps: [
                WatchSync.StepResult(
                    step: plan.routines[0].steps[0],
                    actualWeight: 135,
                    actualReps: 10,
                    completedAt: started.addingTimeInterval(120)
                ),
            ]
        )
        let data = try WatchSync.encode(result)
        let decoded = try WatchSync.decode(WatchSync.SessionResult.self, from: data)
        #expect(decoded == result)
    }

    @Test func encodingIsDeterministic() throws {
        // sortedKeys → byte-stable payloads, diffable in transit logs.
        #expect(try WatchSync.encode(plan) == WatchSync.encode(plan))
    }
}
