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

    // MARK: - Sets

    @Test("An added round is an improvement, not silence")
    func addedSetIsADelta() {
        // The regression this closes: RoutineDiff.Target carried no sets
        // field at all, so 3×8 becoming 4×8 evaluated as .unchanged and
        // Today said nothing about it.
        let delta = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", sets: 4, weight: 135, reps: 8),
            prior: RoutineDiff.Prior(sets: 3, weight: 135, reps: 8)
        )
        #expect(delta == .sets(1))
        #expect(RoutineDiff.summary(deltas: [delta]) == [RoutineDiff.Segment(kind: .up, text: "+1 set")])
    }

    @Test("Two added rounds pluralize")
    func addedSetsPluralize() {
        #expect(RoutineDiff.summary(deltas: [.sets(2)]) == [RoutineDiff.Segment(kind: .up, text: "+2 sets")])
        #expect(RoutineDiff.summary(deltas: [.sets(-1)]) == [RoutineDiff.Segment(kind: .down, text: "−1 set")])
    }

    @Test("An added round never silences something that genuinely moved")
    func setsComeLastSoTheyCannotSuppress() {
        // The target's set count is PLANNED and the prior's is
        // COMPLETED, so a shortfall last time manufactures a "+1 set"
        // out of nothing. Seated anywhere but last in a
        // first-match-wins list, that artifact hides the real edit:
        // this routine went 3×8 to 3×10 and must say so.
        let editedReps = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", sets: 3, weight: 135, reps: 10),
            prior: RoutineDiff.Prior(sets: 2, weight: 135, reps: 8)
        )
        #expect(editedReps == .reps(2))

        // Same shape for every other real metric below reps.
        let editedPace = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Run", sets: 3, extras: [.pace: 600], distanceUnit: .miles),
            prior: RoutineDiff.Prior(sets: 2, extras: [.pace: 660])
        )
        #expect(editedPace == .pace(-60, .miles))

        // Load is still the headline when it moves.
        let loaded = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", sets: 4, weight: 140, reps: 12),
            prior: RoutineDiff.Prior(sets: 3, weight: 135, reps: 10)
        )
        #expect(loaded == .weight(5))

        // With nothing else moving, the added round is the only thing
        // left to say.
        let onlySets = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", sets: 4, weight: 135, reps: 8),
            prior: RoutineDiff.Prior(sets: 3, weight: 135, reps: 8)
        )
        #expect(onlySets == .sets(1))
    }

    @Test("A lighter assistance stack outranks reps, as the load rule says")
    func assistanceOutranksReps() {
        // Pins the position the v3 rule depends on: less assistance IS
        // the load moving, so it speaks before an added rep.
        let delta = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Assisted Pull-Up", reps: 8, extras: [.assistance: 25]),
            prior: RoutineDiff.Prior(reps: 6, extras: [.assistance: 35])
        )
        #expect(delta == .assistance(-10))
    }

    @Test("Dropping a round stays quiet, like every other regression")
    func fewerSetsIsSilent() {
        // Anti-shame (#246): finishing three of four planned sets last
        // time must not render today's plan as a gain, and a genuine
        // deload must not render as a loss.
        let delta = RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", sets: 3, weight: 135, reps: 8),
            prior: RoutineDiff.Prior(sets: 4, weight: 135, reps: 8)
        )
        #expect(delta == .unchanged)
    }

    @Test("A missing set count on either side never invents a delta")
    func absentSetsAreNotAChange() {
        #expect(RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", sets: 4, weight: 135),
            prior: RoutineDiff.Prior(weight: 135)
        ) == .unchanged)
        #expect(RoutineDiff.delta(
            target: RoutineDiff.Target(name: "Bench Press", weight: 135),
            prior: RoutineDiff.Prior(sets: 3, weight: 135)
        ) == .unchanged)
    }

    // MARK: - changedFields

    @Test("Every moved field is reported, not just the headline one")
    func changedFieldsReportsAllOfThem() {
        let changed = RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Bench Press", sets: 4, weight: 140, reps: 12),
            prior: RoutineDiff.Prior(sets: 3, weight: 135, reps: 10)
        )
        #expect(changed == [.sets, .metric(.weight), .metric(.reps)])
    }

    @Test("Regressions and neutral settings count as changes here")
    func changedFieldsIsDirectionless() {
        // delta() stays silent on both of these by design; a ledger
        // showing target beside actual still has to mark them.
        let deload = RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Bench Press", weight: 125),
            prior: RoutineDiff.Prior(weight: 135)
        )
        #expect(deload == [.metric(.weight)])

        let setting = RoutineDiff.Target(name: "Bike", extras: [.resistance: 9])
        let settingPrior = RoutineDiff.Prior(extras: [.resistance: 3])
        #expect(RoutineDiff.delta(target: setting, prior: settingPrior) == .unchanged)
        #expect(RoutineDiff.changedFields(target: setting, prior: settingPrior) == [.metric(.resistance)])
    }

    @Test("A prior actual inside the target rep range is not a change")
    func repRangeBandIsHonored() {
        // 8–10 asked for, 9 done: nothing moved.
        let inside = RoutineDiff.Target(name: "Row", reps: 8, repsUpper: 10)
        #expect(RoutineDiff.changedFields(target: inside, prior: RoutineDiff.Prior(reps: 9)).isEmpty)
        // The same 9 against 10–12 is a change.
        let above = RoutineDiff.Target(name: "Row", reps: 10, repsUpper: 12)
        #expect(RoutineDiff.changedFields(target: above, prior: RoutineDiff.Prior(reps: 9)) == [.metric(.reps)])
        // And a 9 above the whole band is a change too.
        let below = RoutineDiff.Target(name: "Row", reps: 5, repsUpper: 7)
        #expect(RoutineDiff.changedFields(target: below, prior: RoutineDiff.Prior(reps: 9)) == [.metric(.reps)])
    }

    @Test("One side carrying a value is a change; neither side is not")
    func changedFieldsHandlesAbsence() {
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Run", extras: [.distance: 3]),
            prior: RoutineDiff.Prior()
        ) == [.metric(.distance)])
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Bench Press", weight: 135),
            prior: RoutineDiff.Prior(weight: 135)
        ).isEmpty)
    }

    @Test("Never performed has nothing to compare against")
    func changedFieldsOnANewExerciseIsEmpty() {
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "New", sets: 3, weight: 95),
            prior: nil
        ).isEmpty)
    }

    @Test("Rest and transition are block configuration, never diffed")
    func blockConfigurationIsExcluded() {
        // They reach a SetLog only as snapshotted TARGETS, so there is no
        // actual to compare them against — see RoutineDiff.Field's note.
        // A diffable extra rides along so this cannot pass against an
        // implementation that simply never looked at extras.
        let changed = RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Row", extras: [.rest: 60, .transition: 5, .distance: 500]),
            prior: RoutineDiff.Prior(extras: [.rest: 90, .transition: 15, .distance: 400])
        )
        #expect(changed == [.metric(.distance)])
    }

    @Test("A set count on one side only still reads as a change")
    func oneSidedSetsIsAChange() {
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Bench Press", sets: 3),
            prior: RoutineDiff.Prior()
        ) == [.sets])
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Bench Press"),
            prior: RoutineDiff.Prior(sets: 3)
        ) == [.sets])
    }

    @Test("Equal reps with no range set are not a change")
    func equalRepsWithoutARangeHold() {
        // Exercises the `?? staged` fallback: no upper means the band is
        // the single number.
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Row", reps: 10),
            prior: RoutineDiff.Prior(reps: 10)
        ).isEmpty)
    }

    @Test("An inverted rep range cannot invent a change")
    func invertedRepRangeIsClamped() {
        // `repsUpper` is a raw stored column and interchange import
        // assigns it straight from a hand-edited file, so "10–8" is
        // reachable. Unclamped it reported an identical rep count as
        // moved, because 10 sits above the bogus upper of 8.
        #expect(RoutineDiff.changedFields(
            target: RoutineDiff.Target(name: "Row", reps: 10, repsUpper: 8),
            prior: RoutineDiff.Prior(reps: 10)
        ).isEmpty)
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
