import Foundation
import Testing
@testable import PlusPlusKit

@Suite("WorkoutDiff")
struct WorkoutDiffTests {
    private func target(_ name: String = "Bench Press", weight: Double? = nil, reps: Int? = nil) -> WorkoutDiff.Target {
        WorkoutDiff.Target(name: name, weight: weight, reps: reps)
    }

    // MARK: - Per-exercise delta

    @Test func neverPerformedIsNew() {
        #expect(WorkoutDiff.delta(target: target(weight: 135, reps: 10), prior: nil) == .new)
    }

    @Test func weightChangeWinsOverRepsChange() {
        let delta = WorkoutDiff.delta(
            target: target(weight: 140, reps: 12),
            prior: WorkoutDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .weight(5))
    }

    @Test func repsChangeSurfacesWhenWeightIsSteady() {
        let delta = WorkoutDiff.delta(
            target: target(weight: 135, reps: 12),
            prior: WorkoutDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .reps(2))
    }

    @Test func regressionIsAWeightDeltaDownNotSpecialCased() {
        let delta = WorkoutDiff.delta(
            target: target(weight: 130),
            prior: WorkoutDiff.Prior(weight: 135)
        )
        #expect(delta == .weight(-5))
    }

    @Test func identicalTargetsAreUnchanged() {
        let delta = WorkoutDiff.delta(
            target: target(weight: 135, reps: 10),
            prior: WorkoutDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .unchanged)
    }

    @Test func durationExerciseComparesSeconds() {
        let staged = WorkoutDiff.Target(name: "Plank", isDuration: true, durationSeconds: 75)
        #expect(WorkoutDiff.delta(target: staged, prior: WorkoutDiff.Prior(durationSeconds: 60)) == .duration(15))
        #expect(WorkoutDiff.delta(target: staged, prior: WorkoutDiff.Prior(durationSeconds: 75)) == .unchanged)
    }

    @Test func bodyweightExerciseWithNoPriorWeightFallsToReps() {
        let delta = WorkoutDiff.delta(
            target: target(reps: 12),
            prior: WorkoutDiff.Prior(reps: 10)
        )
        #expect(delta == .reps(2))
    }

    // MARK: - Summary line

    @Test func summaryOrdersChangesThenNewThenUnchangedCount() {
        let segments = WorkoutDiff.summary(deltas: [
            .weight(5), .unchanged, .reps(2), .weight(-5), .new, .unchanged,
        ])
        #expect(segments == [
            WorkoutDiff.Segment(kind: .up, text: "+5 lb"),
            WorkoutDiff.Segment(kind: .up, text: "+2 reps"),
            WorkoutDiff.Segment(kind: .down, text: "−5 lb"),
            WorkoutDiff.Segment(kind: .new, text: "1 new"),
            WorkoutDiff.Segment(kind: .unchanged, text: "2 ="),
        ])
    }

    @Test func summaryWithNoChangesCollapses() {
        let segments = WorkoutDiff.summary(deltas: [.unchanged, .unchanged])
        #expect(segments == [WorkoutDiff.Segment(kind: .unchanged, text: "no changes")])
    }

    @Test func summaryHonorsWeightUnit() {
        let segments = WorkoutDiff.summary(deltas: [.weight(2.5)], weightUnit: .kg)
        #expect(segments == [WorkoutDiff.Segment(kind: .up, text: "+2.5 kg")])
    }

    @Test func singleRepUsesSingularUnit() {
        let segments = WorkoutDiff.summary(deltas: [.reps(1)])
        #expect(segments == [WorkoutDiff.Segment(kind: .up, text: "+1 rep")])
    }

    @Test func emptyWorkoutSummarizesAsNoChanges() {
        #expect(WorkoutDiff.summary(deltas: []) == [WorkoutDiff.Segment(kind: .unchanged, text: "no changes")])
    }

    // MARK: - Net chip

    @Test func netGainSumsOnlyPositiveMovement() {
        let gain = WorkoutDiff.netWeightGain(
            current: ["Bench Press": 140, "Squat": 180, "Row": 95],
            previous: ["Bench Press": 135, "Squat": 185, "Row": 95]
        )
        #expect(gain == 5)
    }

    @Test func newExercisesDoNotCountTowardNetGain() {
        let gain = WorkoutDiff.netWeightGain(
            current: ["Bench Press": 135, "Curl": 30],
            previous: ["Bench Press": 135]
        )
        #expect(gain == 0)
    }
}
