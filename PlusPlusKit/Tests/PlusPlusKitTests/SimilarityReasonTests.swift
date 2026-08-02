import Foundation
import Testing
@testable import PlusPlusKit

@Suite("SimilarityReason")
struct SimilarityReasonTests {
    private func bag(
        _ muscles: [MuscleGroup],
        gear: Set<String> = [],
        pattern: MovementPattern? = nil,
        mechanic: ExerciseMechanic? = nil
    ) -> ExerciseSimilarityFeatures {
        ExerciseSimilarityFeatures(
            muscleGroups: muscles,
            modality: .strength,
            equipmentNames: gear,
            movementPattern: pattern,
            mechanic: mechanic
        )
    }

    @Test("A shared pattern outranks everything else that is true")
    func patternLeads() {
        let origin = bag([.hamstrings], gear: ["Barbell"], pattern: .hinge)
        let candidate = bag([.hamstrings], gear: ["Barbell"], pattern: .hinge)
        let reasons = ExerciseSimilarity.reasons(candidate: candidate, origin: origin)
        #expect(reasons.first == .samePattern)
        // Everything else true is still reported, in display order.
        #expect(reasons == [.samePattern, .samePrimaryMuscle, .sameEquipment])
    }

    @Test("An absent pattern yields no reason rather than a false one")
    func absentAttributeIsNotAMatch() {
        // Two moves that carry no pattern must NOT read as sharing one.
        let origin = bag([.biceps], gear: ["Dumbbells"])
        let candidate = bag([.biceps], gear: ["Dumbbells"])
        #expect(!ExerciseSimilarity.reasons(candidate: candidate, origin: origin).contains(.samePattern))
        // Nor when only one side carries it.
        let patterned = bag([.biceps], gear: ["Dumbbells"], pattern: .horizontalPull)
        #expect(!ExerciseSimilarity.reasons(candidate: patterned, origin: origin).contains(.samePattern))
    }

    @Test("Two bodyweight moves report no equipment, never same equipment")
    func bodyweightPairs() {
        let origin = bag([.chest], pattern: .horizontalPush)
        let candidate = bag([.chest], pattern: .horizontalPush)
        let reasons = ExerciseSimilarity.reasons(candidate: candidate, origin: origin)
        #expect(reasons.contains(.noEquipment))
        #expect(!reasons.contains(.sameEquipment))
    }

    @Test("Same equipment needs the requirement lists to actually match")
    func sameEquipmentIsExact() {
        let origin = bag([.back], gear: ["Barbell"])
        #expect(ExerciseSimilarity.reasons(candidate: bag([.back], gear: ["Barbell"]), origin: origin)
            .contains(.sameEquipment))
        // A superset is not the same requirement.
        #expect(!ExerciseSimilarity.reasons(candidate: bag([.back], gear: ["Barbell", "Bench"]), origin: origin)
            .contains(.sameEquipment))
        // Nor is bodyweight against a loaded move.
        #expect(!ExerciseSimilarity.reasons(candidate: bag([.back]), origin: origin)
            .contains(.sameEquipment))
    }

    @Test("A shared secondary reports sharedMuscle, and only when the primary differs")
    func sharedMuscleIsTheFallback() {
        // Bench Press (chest · triceps) against a Skull Crusher (triceps · chest):
        // different primaries, overlapping lists.
        let origin = bag([.chest, .triceps], gear: ["Barbell", "Bench"])
        let secondaryOnly = bag([.triceps, .chest], gear: ["EZ Bar", "Bench"])
        let reasons = ExerciseSimilarity.reasons(candidate: secondaryOnly, origin: origin)
        #expect(reasons.contains(.sharedMuscle))
        #expect(!reasons.contains(.samePrimaryMuscle))

        // When the primary DOES match, sharedMuscle is a weaker restatement
        // and must not be reported beside it.
        let samePrimary = bag([.chest, .shoulders], gear: ["Dumbbells"])
        let both = ExerciseSimilarity.reasons(candidate: samePrimary, origin: origin)
        #expect(both.contains(.samePrimaryMuscle))
        #expect(!both.contains(.sharedMuscle))
    }

    @Test("Nothing in common reports nothing")
    func noOverlapIsEmpty() {
        let origin = bag([.chest], gear: ["Barbell"], pattern: .horizontalPush)
        let candidate = bag([.calves], gear: ["Calf Raise Machine"], pattern: .jump)
        #expect(ExerciseSimilarity.reasons(candidate: candidate, origin: origin).isEmpty)
    }

    @Test("Findings come back in allCases order, whatever order they were found in")
    func displayOrderIsStable() {
        let origin = bag([.quads, .glutes], gear: [], pattern: .squat)
        let candidate = bag([.quads, .core], gear: [], pattern: .squat)
        let reasons = ExerciseSimilarity.reasons(candidate: candidate, origin: origin)
        let ranks = reasons.compactMap { SimilarityReason.allCases.firstIndex(of: $0) }
        #expect(ranks == ranks.sorted())
    }
}
