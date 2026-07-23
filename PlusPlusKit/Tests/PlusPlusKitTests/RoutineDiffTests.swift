import Foundation
import Testing
@testable import PlusPlusKit

@Suite("RoutineDiff")
struct RoutineDiffTests {
    private func target(_ name: String = "Bench Press", weight: Double? = nil, reps: Int? = nil) -> RoutineDiff.Target {
        RoutineDiff.Target(name: name, weight: weight, reps: reps)
    }

    // MARK: - Per-exercise delta

    @Test func neverPerformedIsNew() {
        #expect(RoutineDiff.delta(target: target(weight: 135, reps: 10), prior: nil) == .new)
    }

    @Test func weightChangeWinsOverRepsChange() {
        let delta = RoutineDiff.delta(
            target: target(weight: 140, reps: 12),
            prior: RoutineDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .weight(5))
    }

    @Test func repsChangeSurfacesWhenWeightIsSteady() {
        let delta = RoutineDiff.delta(
            target: target(weight: 135, reps: 12),
            prior: RoutineDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .reps(2))
    }

    /// #246: the prior is the last ACTUAL — a plan below it is the
    /// normal state after out-lifting the plan, not a regression.
    @Test func planBelowPriorIsNotAChange() {
        let delta = RoutineDiff.delta(
            target: target(weight: 130),
            prior: RoutineDiff.Prior(weight: 135)
        )
        #expect(delta == .unchanged)
    }

    @Test func silencedWeightDecreaseFallsThroughToRepsIncrease() {
        let delta = RoutineDiff.delta(
            target: target(weight: 130, reps: 12),
            prior: RoutineDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .reps(2))
    }

    @Test func decreasesAreSilencedForRepsAndDuration() {
        #expect(RoutineDiff.delta(
            target: target(reps: 8),
            prior: RoutineDiff.Prior(reps: 10)
        ) == .unchanged)
        let staged = RoutineDiff.Target(name: "Plank", isDuration: true, durationSeconds: 45)
        #expect(RoutineDiff.delta(target: staged, prior: RoutineDiff.Prior(durationSeconds: 60)) == .unchanged)
    }

    @Test func identicalTargetsAreUnchanged() {
        let delta = RoutineDiff.delta(
            target: target(weight: 135, reps: 10),
            prior: RoutineDiff.Prior(weight: 135, reps: 10)
        )
        #expect(delta == .unchanged)
    }

    @Test func durationExerciseComparesSeconds() {
        let staged = RoutineDiff.Target(name: "Plank", isDuration: true, durationSeconds: 75)
        #expect(RoutineDiff.delta(target: staged, prior: RoutineDiff.Prior(durationSeconds: 60)) == .duration(15))
        #expect(RoutineDiff.delta(target: staged, prior: RoutineDiff.Prior(durationSeconds: 75)) == .unchanged)
    }

    @Test func bodyweightExerciseWithNoPriorWeightFallsToReps() {
        let delta = RoutineDiff.delta(
            target: target(reps: 12),
            prior: RoutineDiff.Prior(reps: 10)
        )
        #expect(delta == .reps(2))
    }

    // MARK: - Summary line

    @Test func summaryOrdersChangesThenNewAndDropsUnchanged() {
        // Unchanged deltas emit no segment — no "=", no "n =" tail
        // (Dave, 2026-07-23: they read as noise, nowhere renders them).
        let segments = RoutineDiff.summary(deltas: [
            .weight(5), .unchanged, .reps(2), .weight(-5), .new, .unchanged,
        ])
        #expect(segments == [
            RoutineDiff.Segment(kind: .up, text: "+5 lb"),
            RoutineDiff.Segment(kind: .up, text: "+2 reps"),
            RoutineDiff.Segment(kind: .down, text: "−5 lb"),
            RoutineDiff.Segment(kind: .new, text: "1 new"),
        ])
    }

    @Test func summaryWithNoChangesIsEmpty() {
        // All-unchanged summarizes as NOTHING — callers omit the line
        // entirely rather than render a floating "=".
        let segments = RoutineDiff.summary(deltas: [.unchanged, .unchanged])
        #expect(segments.isEmpty)
    }

    @Test func summaryHonorsWeightUnit() {
        let segments = RoutineDiff.summary(deltas: [.weight(2.5)], weightUnit: .kg)
        #expect(segments == [RoutineDiff.Segment(kind: .up, text: "+2.5 kg")])
    }

    @Test func singleRepUsesSingularUnit() {
        let segments = RoutineDiff.summary(deltas: [.reps(1)])
        #expect(segments == [RoutineDiff.Segment(kind: .up, text: "+1 rep")])
    }

    @Test func emptyRoutineSummarizesAsNothing() {
        #expect(RoutineDiff.summary(deltas: []).isEmpty)
    }

    // MARK: - Net chip

    @Test func netGainSumsOnlyPositiveMovement() {
        let gain = RoutineDiff.netWeightGain(
            current: ["Bench Press": 140, "Squat": 180, "Row": 95],
            previous: ["Bench Press": 135, "Squat": 185, "Row": 95]
        )
        #expect(gain == 5)
    }

    @Test func newExercisesDoNotCountTowardNetGain() {
        let gain = RoutineDiff.netWeightGain(
            current: ["Bench Press": 135, "Curl": 30],
            previous: ["Bench Press": 135]
        )
        #expect(gain == 0)
    }
}
