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

    @Test func heartRateFieldsRoundTrip() throws {
        let step = WatchSync.Step(
            exerciseName: "Spin Bike",
            groupIndex: 0,
            setNumber: 1,
            isDuration: true,
            targetDuration: 1200,
            targetHeartRateLowerBPM: 114,
            targetHeartRateUpperBPM: 132
        )
        let started = Date(timeIntervalSince1970: 1_780_000_100)
        let result = WatchSync.SessionResult(
            routineName: "Cardio",
            startedAt: started,
            endedAt: started.addingTimeInterval(1200),
            restSeconds: 60,
            steps: [WatchSync.StepResult(step: step, actualDuration: 1200, completedAt: started.addingTimeInterval(1200))],
            averageHeartRate: 128,
            maxHeartRate: 151
        )
        let decoded = try WatchSync.decode(WatchSync.SessionResult.self, from: WatchSync.encode(result))
        #expect(decoded == result)
        #expect(decoded.averageHeartRate == 128)
        #expect(decoded.steps[0].step.targetHeartRateLowerBPM == 114)
    }

    @Test func payloadsWithoutHeartRateStillDecode() throws {
        // Version skew both ways: an older watch's result (no HR keys)
        // and an older phone's plan must decode on new builds — the HR
        // fields are additive optionals, never requirements.
        let resultJSON = """
        {"endedAt":"2026-06-01T10:30:00Z","restSeconds":90,"routineName":"Push Day",\
        "startedAt":"2026-06-01T10:00:00Z","steps":[]}
        """
        let result = try WatchSync.decode(WatchSync.SessionResult.self, from: Data(resultJSON.utf8))
        #expect(result.averageHeartRate == nil)
        #expect(result.maxHeartRate == nil)

        let stepJSON = """
        {"exerciseName":"Plank","groupIndex":0,"isDuration":true,"setNumber":1,"targetDuration":60}
        """
        let step = try WatchSync.decode(WatchSync.Step.self, from: Data(stepJSON.utf8))
        #expect(step.targetHeartRateLowerBPM == nil)
        // A pre-outdoor step decodes with no outdoor flag.
        #expect(step.isOutdoor == nil)
    }

    @Test func isOutdoorRunNeedsEveryStepOutdoor() {
        func step(_ name: String, outdoor: Bool?) -> WatchSync.Step {
            WatchSync.Step(exerciseName: name, groupIndex: 0, setNumber: 1, isDuration: true, isOutdoor: outdoor)
        }
        let run = WatchSync.PlanRoutine(name: "5K", restSeconds: 0, steps: [
            step("Running", outdoor: true), step("Running", outdoor: true),
        ])
        #expect(run.isOutdoorRun)
        // One indoor (or unflagged) step keeps the whole session indoor —
        // an HKWorkoutSession is a single activity type.
        let mixed = WatchSync.PlanRoutine(name: "Brick", restSeconds: 0, steps: [
            step("Running", outdoor: true), step("Squat", outdoor: nil),
        ])
        #expect(mixed.isOutdoorRun == false)
        let empty = WatchSync.PlanRoutine(name: "Empty", restSeconds: 0, steps: [])
        #expect(empty.isOutdoorRun == false)
    }
}
