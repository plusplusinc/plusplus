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

    @Test("A wrist result carries what was MEASURED, and it round-trips")
    func measuredActualsRoundTrip() throws {
        let step = WatchSync.Step(
            exerciseName: "Rowing",
            groupIndex: 0,
            setNumber: 1,
            isDuration: true,
            extraTargets: ["distance": 500, "resistance": 5],
            distanceUnit: .meters,
            modality: .rowing
        )
        // Rowed 412 of a planned 500. The result must say 412.
        let actuals = LoggedActuals.extras(
            planned: MetricValues.fromRaw(step.extraTargets),
            measured: [.distance: 412, .pace: 128]
        )
        let started = Date(timeIntervalSince1970: 1_780_000_100)
        let result = WatchSync.SessionResult(
            routineName: "Erg",
            startedAt: started,
            endedAt: started.addingTimeInterval(600),
            restSeconds: 120,
            steps: [WatchSync.StepResult(
                step: step,
                actualDuration: 128,
                extraActuals: MetricValues.toRaw(actuals),
                completedAt: started.addingTimeInterval(128)
            )]
        )
        let decoded = try WatchSync.decode(WatchSync.SessionResult.self, from: WatchSync.encode(result))
        #expect(decoded == result)
        let landed = MetricValues.fromRaw(decoded.steps[0].extraActuals)
        #expect(landed[.distance] == 412)
        #expect(landed[.pace] == 128)
        // The damper is what the user set, so it carries; the target
        // distance does not masquerade as a result.
        #expect(landed[.resistance] == 5)
        #expect(decoded.steps[0].step.extraTargets?["distance"] == 500)
        #expect(decoded.steps[0].step.modality == .rowing)
    }

    @Test("A step carries the heart rate it was performed at, per step")
    func stepCarriesHeartRate() throws {
        let step = WatchSync.Step(exerciseName: "Rowing", groupIndex: 0, setNumber: 1, isDuration: true)
        let started = Date(timeIntervalSince1970: 1_780_000_100)
        let result = WatchSync.SessionResult(
            routineName: "Erg",
            startedAt: started,
            endedAt: started.addingTimeInterval(600),
            restSeconds: 120,
            steps: [WatchSync.StepResult(
                step: step,
                actualDuration: 128,
                averageHeartRate: 162,
                maxHeartRate: 178,
                completedAt: started.addingTimeInterval(128)
            )]
        )
        let decoded = try WatchSync.decode(WatchSync.SessionResult.self, from: WatchSync.encode(result))
        #expect(decoded == result)
        // Per STEP: the wrist wears the sensor, and a 4 × 500 m piece
        // wants four numbers rather than one session average.
        #expect(decoded.steps[0].averageHeartRate == 162)
        #expect(decoded.steps[0].maxHeartRate == 178)
    }

    @Test("A result from a watch that predates measured actuals decodes clean")
    func resultWithoutExtraActualsDecodes() throws {
        let step = WatchSync.Step(exerciseName: "Rowing", groupIndex: 0, setNumber: 1, isDuration: true)
        let started = Date(timeIntervalSince1970: 1_780_000_100)
        let result = WatchSync.SessionResult(
            routineName: "Erg",
            startedAt: started,
            endedAt: started.addingTimeInterval(600),
            restSeconds: 120,
            steps: [WatchSync.StepResult(step: step, actualDuration: 600, completedAt: started)]
        )
        let decoded = try WatchSync.decode(WatchSync.SessionResult.self, from: WatchSync.encode(result))
        #expect(decoded.steps[0].extraActuals == nil)
        #expect(decoded.steps[0].step.modality == nil)
        // Same additive tolerance for the heart-rate pair: absent stays
        // absent rather than becoming a zero.
        #expect(decoded.steps[0].averageHeartRate == nil)
        #expect(decoded.steps[0].maxHeartRate == nil)
    }

    @Test("A plan's modality resolves the session, and falls back when absent")
    func planModality() {
        let outdoor = WatchSync.Step(
            exerciseName: "Running", groupIndex: 0, setNumber: 1, isDuration: true,
            isOutdoor: true, modality: .running
        )
        let plan = WatchSync.PlanRoutine(name: "R", restSeconds: 60, steps: [outdoor])
        #expect(plan.sessionModality.primary == .running)
        #expect(plan.sessionModality.isOutdoor)

        // A plan pushed before modalities existed has nothing to go on
        // but the outdoor flag, and guessing strength for a run would be
        // worse than the old answer.
        let legacy = WatchSync.Step(
            exerciseName: "Running", groupIndex: 0, setNumber: 1, isDuration: true, isOutdoor: true
        )
        let legacyPlan = WatchSync.PlanRoutine(name: "R", restSeconds: 60, steps: [legacy])
        #expect(legacyPlan.sessionModality.primary == .running)
        #expect(legacyPlan.sessionModality.isOutdoor)

        let legacyIndoor = WatchSync.Step(exerciseName: "Bench", groupIndex: 0, setNumber: 1, isDuration: false)
        let indoorPlan = WatchSync.PlanRoutine(name: "B", restSeconds: 60, steps: [legacyIndoor])
        #expect(indoorPlan.sessionModality.primary == .strength)
        #expect(!indoorPlan.sessionModality.isOutdoor)
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

    @Test func transitionSecondsIsAdditive() throws {
        // New plans carry it; a pre-transition phone's plan decodes nil
        // (#369) so the wrist falls back to resting everywhere.
        let routine = WatchSync.PlanRoutine(name: "Pairs", restSeconds: 45, transitionSeconds: 15, steps: [])
        let decoded = try WatchSync.decode(WatchSync.PlanRoutine.self, from: WatchSync.encode(routine))
        #expect(decoded.transitionSeconds == 15)

        let legacyJSON = """
        {"name":"Push Day","restSeconds":90,"steps":[]}
        """
        let legacy = try WatchSync.decode(WatchSync.PlanRoutine.self, from: Data(legacyJSON.utf8))
        #expect(legacy.transitionSeconds == nil)
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
