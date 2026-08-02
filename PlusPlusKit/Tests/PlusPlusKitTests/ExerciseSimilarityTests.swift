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

    // MARK: - Multiple muscle groups (2026-07-28)

    private func bag(_ groups: [MuscleGroup],
                     _ modality: ExerciseModality = .strength,
                     _ gear: Set<String> = []) -> ExerciseSimilarityFeatures {
        ExerciseSimilarityFeatures(muscleGroups: groups, modality: modality, equipmentNames: gear)
    }

    @Test("Sharing the primary beats sharing only a secondary")
    func primaryLeads() {
        let bench = bag([.chest, .triceps, .shoulders])
        let fly = bag([.chest])                       // shares the primary only
        let skullCrusher = bag([.triceps, .chest])    // shares two, primary differs
        #expect(ExerciseSimilarity.score(candidate: fly, origin: bench)
            > ExerciseSimilarity.score(candidate: skullCrusher, origin: bench))
    }

    @Test("Secondaries still separate a near-twin from a bare primary match")
    func secondariesBreakTies() {
        let bench = bag([.chest, .triceps, .shoulders])
        let dumbbellBench = bag([.chest, .triceps, .shoulders])
        let fly = bag([.chest])
        #expect(ExerciseSimilarity.score(candidate: dumbbellBench, origin: bench)
            > ExerciseSimilarity.score(candidate: fly, origin: bench))
    }

    @Test("Sharing nothing still scores zero on muscle")
    func noOverlap() {
        #expect(ExerciseSimilarity.muscleScore([.chest, .triceps], [.quads, .glutes]) == 0)
    }

    @Test("A single-group bag reads the same through either initializer")
    func initializerParity() {
        let viaSingle = features(.quads, .strength, ["Barbell"])
        let viaList = bag([.quads], .strength, ["Barbell"])
        #expect(viaSingle == viaList)
        #expect(viaList.muscleGroup == .quads)
    }

    // MARK: - Authored attributes (#495)

    private func attributed(_ groups: [MuscleGroup],
                            pattern: MovementPattern? = nil,
                            mechanic: ExerciseMechanic? = nil,
                            gear: Set<String> = []) -> ExerciseSimilarityFeatures {
        ExerciseSimilarityFeatures(muscleGroups: groups, modality: .strength,
                                   equipmentNames: gear, movementPattern: pattern, mechanic: mechanic)
    }

    @Test("Sharing the movement pattern beats a different one, same muscles")
    func patternSeparatesSameMuscle() {
        let squat = attributed([.quads, .glutes], pattern: .squat, mechanic: .compound, gear: ["Barbell"])
        let anotherSquat = attributed([.quads, .glutes], pattern: .squat, mechanic: .compound, gear: ["Barbell"])
        let lunge = attributed([.quads, .glutes], pattern: .lunge, mechanic: .compound, gear: ["Barbell"])
        #expect(ExerciseSimilarity.score(candidate: anotherSquat, origin: squat)
            > ExerciseSimilarity.score(candidate: lunge, origin: squat))
    }

    /// The case #495 was filed for. An RDL and a Leg Curl share hamstrings
    /// and need no shared gear to look alike; the curl carries NO pattern,
    /// so mechanic is the signal that has to do the work.
    @Test("Mechanic separates a hinge from an isolation on the same muscle")
    func mechanicSeparatesCompoundFromIsolation() {
        let rdl = attributed([.hamstrings, .glutes], pattern: .hinge, mechanic: .compound)
        let goodMorning = attributed([.hamstrings, .glutes], pattern: .hinge, mechanic: .compound)
        let legCurl = attributed([.hamstrings, .glutes], mechanic: .isolation)
        #expect(ExerciseSimilarity.score(candidate: goodMorning, origin: rdl)
            > ExerciseSimilarity.score(candidate: legCurl, origin: rdl))
    }

    @Test("An absent attribute is unavailable, never a mismatch")
    func absentAttributeRenormalizes() {
        // A pair carrying NO attributes scores exactly what it scored
        // before the attributes existed — that is what keeps every
        // pre-#495 ranking test honest.
        let plain = bag([.quads], .strength, ["Barbell"])
        #expect(ExerciseSimilarity.score(candidate: plain, origin: plain) == 1.0)

        // And a row that simply says nothing is not punished for it: an
        // attribute-less twin still outranks a genuine mismatch that DOES
        // carry attributes.
        let origin = attributed([.quads], pattern: .squat, mechanic: .compound, gear: ["Barbell"])
        let silentTwin = bag([.quads], .strength, ["Barbell"])
        let wrongPattern = attributed([.quads], pattern: .carry, mechanic: .isolation, gear: ["Barbell"])
        #expect(ExerciseSimilarity.score(candidate: silentTwin, origin: origin)
            > ExerciseSimilarity.score(candidate: wrongPattern, origin: origin))
    }

    @Test("Muscle still outranks the attributes combined")
    func muscleStillDominates() {
        let origin = attributed([.chest], pattern: .horizontalPush, mechanic: .compound)
        // Right muscle, both attributes wrong...
        let sameMuscle = attributed([.chest], pattern: .carry, mechanic: .isolation)
        // ...still beats wrong muscle with both attributes right.
        let otherMuscle = attributed([.quads], pattern: .horizontalPush, mechanic: .compound)
        #expect(ExerciseSimilarity.score(candidate: sameMuscle, origin: origin)
            > ExerciseSimilarity.score(candidate: otherMuscle, origin: origin))
    }

    @Test("Every score stays inside 0…1 whatever is present")
    func scoresStayNormalized() {
        let bags = [
            attributed([.chest], pattern: .horizontalPush, mechanic: .compound, gear: ["Barbell"]),
            attributed([.quads], mechanic: .isolation),
            bag([.core], .cardio, ["Treadmill"]),
            attributed([.back], pattern: .verticalPull),
        ]
        for candidate in bags {
            for origin in bags {
                let score = ExerciseSimilarity.score(candidate: candidate, origin: origin)
                #expect(score >= 0 && score <= 1, "score \(score) out of range")
            }
        }
    }
}
