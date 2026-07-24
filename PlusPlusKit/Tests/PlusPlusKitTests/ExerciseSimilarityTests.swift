import Foundation
import Testing
@testable import PlusPlusKit

@Suite("ExerciseSimilarity")
struct ExerciseSimilarityTests {
    private func features(_ muscle: MuscleGroup,
                         _ modality: ExerciseModality,
                         _ gear: Set<String>) -> ExerciseSimilarityFeatures {
        ExerciseSimilarityFeatures(muscleGroup: muscle, modality: modality, equipmentNames: gear)
    }

    @Test("An identical feature bag scores 1")
    func identical() {
        let bag = features(.quads, .strength, ["Barbell"])
        #expect(ExerciseSimilarity.score(candidate: bag, origin: bag) == 1.0)
    }

    @Test("Muscle group is the dominant signal")
    func muscleDominates() {
        let origin = features(.quads, .strength, ["Barbell"])
        // Same muscle, different family AND gear still beats a same-family,
        // same-gear move on a different muscle — quads is the spine.
        let sameMuscle = features(.quads, .cardio, ["Treadmill"])
        let otherMuscle = features(.chest, .strength, ["Barbell"])
        #expect(ExerciseSimilarity.score(candidate: sameMuscle, origin: origin)
            > ExerciseSimilarity.score(candidate: otherMuscle, origin: origin))
    }

    @Test("Within a muscle, gear overlap and family break the tie")
    func gearAndFamilyBreakTies() {
        let origin = features(.quads, .strength, ["Barbell"])
        let sameGear = features(.quads, .strength, ["Barbell"])       // 1.0
        let sharedGear = features(.quads, .strength, ["Barbell", "Rack"]) // partial gear
        let noGear = features(.quads, .strength, [])                  // bodyweight sub
        let sameScore = ExerciseSimilarity.score(candidate: sameGear, origin: origin)
        let sharedScore = ExerciseSimilarity.score(candidate: sharedGear, origin: origin)
        let noGearScore = ExerciseSimilarity.score(candidate: noGear, origin: origin)
        #expect(sameScore > sharedScore)
        #expect(sharedScore > noGearScore)
    }

    @Test("Two bodyweight moves count as a full gear match")
    func bodyweightMatch() {
        let origin = features(.core, .strength, [])
        let alsoBodyweight = features(.core, .strength, [])
        #expect(ExerciseSimilarity.score(candidate: alsoBodyweight, origin: origin) == 1.0)
    }

    @Test("ranked orders best-first and keeps ties in incoming order")
    func rankedOrdering() {
        let origin = features(.quads, .strength, ["Barbell"])
        struct Move { let name: String; let bag: ExerciseSimilarityFeatures }
        // Two identical quad/barbell moves (A, B) tie at the top and must
        // keep their A-before-B incoming order; a chest move sinks last.
        let moves = [
            Move(name: "A", bag: features(.quads, .strength, ["Barbell"])),
            Move(name: "B", bag: features(.quads, .strength, ["Barbell"])),
            Move(name: "Chest", bag: features(.chest, .strength, ["Barbell"])),
            Move(name: "QuadCardio", bag: features(.quads, .cardio, [])),
        ]
        let ranked = ExerciseSimilarity.ranked(moves, like: origin, features: \.bag)
        #expect(ranked.map(\.name) == ["A", "B", "QuadCardio", "Chest"])
    }
}
