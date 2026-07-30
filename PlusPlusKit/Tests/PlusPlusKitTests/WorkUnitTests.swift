import Foundation
import Testing
@testable import PlusPlusKit

@Suite("WorkUnit — what one unit of work is called")
struct WorkUnitTests {
    @Test("Each sport counts in its own noun")
    func perModalityNouns() {
        #expect(ExerciseModality.rowing.workUnit == .piece)
        #expect(ExerciseModality.running.workUnit == .rep)
        #expect(ExerciseModality.swimming.workUnit == .rep)
        #expect(ExerciseModality.cycling.workUnit == .effort)
        #expect(ExerciseModality.strength.workUnit == .set)
        #expect(ExerciseModality.flexibility.workUnit == .set)
    }

    @Test("A walk is a walk — no countable unit at all")
    func locomotionHasNoUnit() {
        #expect(ExerciseModality.walking.workUnit == nil)
        #expect(ExerciseModality.hiking.workUnit == nil)
    }

    @Test("Every modality answers the question one way or the other")
    func exhaustive() {
        // No crash, no default — a new family has to decide.
        for modality in ExerciseModality.allCases {
            _ = modality.workUnit
        }
        let countable = ExerciseModality.allCases.filter { $0.workUnit != nil }
        #expect(countable.count == ExerciseModality.allCases.count - 2)
    }

    @Test("The kicker disappears at a count of one")
    func kickerHiddenAtOne() {
        // A steady forty-minute ride must not read "EFFORT 1 OF 1" — it
        // implies a second one is coming.
        #expect(WorkUnit.kicker(.effort, index: 1, total: 1) == nil)
        #expect(WorkUnit.kicker(.set, index: 1, total: 1) == nil)
        #expect(WorkUnit.inline(.piece, index: 1, total: 1) == nil)
        // And a sport with no unit never renders one, however many.
        #expect(WorkUnit.kicker(nil, index: 2, total: 5) == nil)
    }

    @Test("The kicker reads in the sport's own words above one")
    func kickerRendering() {
        #expect(WorkUnit.kicker(.piece, index: 3, total: 8) == "PIECE 3 OF 8")
        #expect(WorkUnit.kicker(.rep, index: 1, total: 6) == "REP 1 OF 6")
        #expect(WorkUnit.kicker(.set, index: 2, total: 3) == "SET 2 OF 3")
        #expect(WorkUnit.inline(.effort, index: 4, total: 5) == "effort 4")
    }

    @Test("Counting pluralizes")
    func counting() {
        #expect(WorkUnit.set.counted(1) == "1 set")
        #expect(WorkUnit.set.counted(3) == "3 sets")
        #expect(WorkUnit.piece.counted(1) == "1 piece")
        #expect(WorkUnit.piece.counted(4) == "4 pieces")
        #expect(WorkUnit.effort.counted(2) == "2 efforts")
    }
}

@Suite("SessionModality — what kind of workout this was")
struct SessionModalityTests {
    private func leg(_ modality: ExerciseModality, outdoor: Bool = false) -> SessionModality.Leg {
        SessionModality.Leg(modality: modality, isOutdoor: outdoor)
    }

    @Test("An empty session files exactly as it always did")
    func empty() {
        let resolved = SessionModality.resolve([])
        #expect(resolved == .empty)
        #expect(resolved.primary == .strength)
        #expect(!resolved.isOutdoor)
    }

    @Test("One family names the session")
    func single() {
        let ride = SessionModality.resolve([leg(.cycling), leg(.cycling)])
        #expect(ride.primary == .cycling)
        #expect(!ride.isMixed)

        let lift = SessionModality.resolve([leg(.strength), leg(.strength)])
        #expect(lift.primary == .strength)
        #expect(!lift.isMixed)
    }

    @Test("Mobility work never renames a session")
    func flexibilityDoesNotVote() {
        // A hamstring stretch at the end of a lifting day does not make
        // it a mobility workout, and does not make it mixed.
        let lift = SessionModality.resolve([leg(.strength), leg(.flexibility)])
        #expect(lift.primary == .strength)
        #expect(!lift.isMixed)

        // Nor does it turn a run into cross-training.
        let run = SessionModality.resolve([leg(.running, outdoor: true), leg(.flexibility)])
        #expect(run.primary == .running)
        #expect(!run.isMixed)
        #expect(run.isOutdoor)

        // A stretching-only session is still filed as strength, which is
        // what it was before any of this existed.
        let stretch = SessionModality.resolve([leg(.flexibility)])
        #expect(stretch.primary == .strength)
    }

    @Test("Strength plus cardio is cross-training, not a lie about either")
    func mixedWithStrength() {
        let brick = SessionModality.resolve([leg(.running, outdoor: true), leg(.strength)])
        #expect(brick.primary == .strength)
        #expect(brick.isMixed)
    }

    @Test("Several cardio families with no lifting is mixed cardio")
    func mixedCardio() {
        let brick = SessionModality.resolve([leg(.cycling, outdoor: true), leg(.running, outdoor: true)])
        #expect(brick.primary == .cardio)
        #expect(brick.isMixed)
        #expect(brick.isOutdoor)
    }

    @Test("Outdoor is a property of the cardio, and strength does not vote")
    func outdoorRules() {
        // The divergence this closes: the phone used to call anything with
        // one GPS segment an outdoor run, while the watch demanded every
        // step be outdoor — so a run-plus-core session filed two different
        // ways depending on which device logged it.
        let runPlusCore = SessionModality.resolve([leg(.running, outdoor: true), leg(.strength)])
        #expect(runPlusCore.isOutdoor)

        // An indoor cardio leg does vote, and vetoes.
        let mixedPlace = SessionModality.resolve([leg(.running, outdoor: true), leg(.cycling, outdoor: false)])
        #expect(!mixedPlace.isOutdoor)

        // Pure lifting is never outdoors.
        #expect(!SessionModality.resolve([leg(.strength)]).isOutdoor)

        // An erg is cardio, and indoors.
        let erg = SessionModality.resolve([leg(.rowing)])
        #expect(erg.primary == .rowing)
        #expect(!erg.isOutdoor)
    }
}
