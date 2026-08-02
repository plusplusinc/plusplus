import Foundation
import Testing
@testable import PlusPlusKit

@Suite("CatalogReach")
struct CatalogReachTests {
    private func move(
        _ muscles: [MuscleGroup],
        gear: Set<String> = [],
        pattern: MovementPattern? = nil
    ) -> ExerciseSimilarityFeatures {
        ExerciseSimilarityFeatures(
            muscleGroups: muscles,
            modality: .strength,
            equipmentNames: gear,
            movementPattern: pattern
        )
    }

    @Test("A kit does a move only when it has everything the move names")
    func doabilityIsASubsetTest() {
        let kit: Set<String> = ["Dumbbells", "Bench"]
        #expect(CatalogReachCalculator.canDo(move([.chest], gear: ["Dumbbells"]), kit: kit))
        #expect(CatalogReachCalculator.canDo(move([.chest], gear: ["Dumbbells", "Bench"]), kit: kit))
        #expect(!CatalogReachCalculator.canDo(move([.chest], gear: ["Dumbbells", "Barbell"]), kit: kit))
    }

    @Test("Bodyweight is doable with any kit, the empty one included")
    func bodyweightIsAlwaysDoable() {
        let bodyweight = move([.core])
        #expect(CatalogReachCalculator.canDo(bodyweight, kit: []))
        let reach = CatalogReachCalculator.reach([bodyweight], kit: [])
        #expect(reach.doable == 1)
        #expect(reach.noEquipment == 1)
    }

    @Test("The headline counts are the whole catalog and the doable subset")
    func headlineCounts() {
        let catalog = [
            move([.chest]),                              // bodyweight
            move([.chest], gear: ["Dumbbells"]),         // doable
            move([.back], gear: ["Barbell"]),            // not doable
            move([.back], gear: ["Barbell", "Rack"]),    // not doable
        ]
        let reach = CatalogReachCalculator.reach(catalog, kit: ["Dumbbells"])
        #expect(reach.total == 4)
        #expect(reach.doable == 2)
        #expect(reach.noEquipment == 1)
    }

    @Test("Muscle buckets file under the PRIMARY group, so they sum to the catalog")
    func muscleBucketsUsePrimaryOnly() {
        // A move working chest AND triceps files under chest alone. Bucketing
        // every group would make the columns sum past the catalog size.
        let catalog = [
            move([.chest, .triceps], gear: ["Dumbbells"]),
            move([.chest]),
            move([.back], gear: ["Barbell"]),
        ]
        let reach = CatalogReachCalculator.reach(catalog, kit: ["Dumbbells"])
        #expect(reach.byMuscle.map(\.value) == [.chest, .back])
        #expect(reach.byMuscle.reduce(0) { $0 + $1.total } == reach.total)
        let chest = reach.byMuscle.first { $0.value == .chest }
        #expect(chest?.total == 2)
        #expect(chest?.doable == 2)
        let back = reach.byMuscle.first { $0.value == .back }
        #expect(back?.total == 1)
        #expect(back?.doable == 0)
    }

    @Test("A move with no movement pattern is absent from byPattern, not bucketed as a null")
    func patternlessMovesDropOut() {
        let catalog = [
            move([.hamstrings], gear: ["Barbell"], pattern: .hinge),
            move([.hamstrings], gear: ["Dumbbells"], pattern: .hinge),
            move([.fullBody]),   // cardio-shaped: carries no pattern
            move([.biceps], gear: ["Dumbbells"]),
        ]
        let reach = CatalogReachCalculator.reach(catalog, kit: ["Dumbbells"])
        #expect(reach.byPattern.map(\.value) == [.hinge])
        let hinge = reach.byPattern[0]
        #expect(hinge.total == 2)
        #expect(hinge.doable == 1)
        // The two pattern-less moves are still in the headline totals.
        #expect(reach.total == 4)
    }

    @Test("Buckets keep the enum's authored order, never a count order")
    func bucketsKeepDeclarationOrder() {
        // Back has more moves than chest; chest still leads, because
        // MuscleGroup declares it first. A count order would reshuffle the
        // row every time the kit changed.
        let catalog = [
            move([.back]), move([.back]), move([.back]),
            move([.chest]),
        ]
        let reach = CatalogReachCalculator.reach(catalog, kit: [])
        #expect(reach.byMuscle.map(\.value) == [.chest, .back])
    }

    // MARK: - unlocks

    @Test("A piece opens the moves it is the ONLY thing standing in front of")
    func unlocksCountsTheLastMissingPiece() {
        let catalog = [
            move([.chest], gear: ["Barbell"]),              // barbell alone
            move([.back], gear: ["Barbell"]),               // barbell alone
            move([.quads], gear: ["Barbell", "Squat Rack"]), // needs both
            move([.core]),                                  // already doable
        ]
        let unlocks = CatalogReachCalculator.unlocks(catalog, kit: [])
        #expect(unlocks["Barbell"] == 2)
        // The two-piece move counts for NEITHER: each is one of two.
        #expect(unlocks["Squat Rack"] == nil)
    }

    @Test("A piece that is one of two missing scores nothing until the other arrives")
    func unlocksAreMarginal() {
        let catalog = [move([.quads], gear: ["Barbell", "Squat Rack"])]
        #expect(CatalogReachCalculator.unlocks(catalog, kit: [])["Squat Rack"] == nil)
        // Own the barbell, and the rack becomes the last thing in the way.
        #expect(CatalogReachCalculator.unlocks(catalog, kit: ["Barbell"])["Squat Rack"] == 1)
    }

    @Test("Pieces already in the kit are absent, never zero")
    func ownedPiecesDropOut() {
        let catalog = [move([.chest], gear: ["Dumbbells"]), move([.back], gear: ["Barbell"])]
        let unlocks = CatalogReachCalculator.unlocks(catalog, kit: ["Dumbbells"])
        #expect(unlocks["Dumbbells"] == nil)
        #expect(unlocks["Barbell"] == 1)
    }

    @Test("A piece nothing needs is absent from the map")
    func unusedPieceIsAbsent() {
        let catalog = [move([.chest], gear: ["Dumbbells"])]
        #expect(CatalogReachCalculator.unlocks(catalog, kit: [])["Yoke"] == nil)
    }

    @Test("An unlock count is exactly what the doable count would gain")
    func unlocksAgreeWithReach() {
        // The invariant that lets the equipment screen's "+N" beat and the
        // catalog's ordering read from one function without disagreeing.
        let catalog = [
            move([.chest], gear: ["Barbell"]),
            move([.back], gear: ["Barbell"]),
            move([.quads], gear: ["Barbell", "Squat Rack"]),
            move([.core]),
        ]
        let kit: Set<String> = ["Squat Rack"]
        let before = CatalogReachCalculator.reach(catalog, kit: kit).doable
        let claimed = CatalogReachCalculator.unlocks(catalog, kit: kit)["Barbell"] ?? 0
        let after = CatalogReachCalculator.reach(catalog, kit: kit.union(["Barbell"])).doable
        #expect(after - before == claimed)
    }

    @Test("An empty catalog reports zeros and no buckets")
    func emptyCatalog() {
        let reach = CatalogReachCalculator.reach([], kit: ["Barbell"])
        #expect(reach.total == 0)
        #expect(reach.doable == 0)
        #expect(reach.noEquipment == 0)
        #expect(reach.byMuscle.isEmpty)
        #expect(reach.byPattern.isEmpty)
    }

    @Test("A bigger kit never lowers the doable count")
    func growingTheKitOnlyOpens() {
        let catalog = [
            move([.chest], gear: ["Dumbbells"]),
            move([.back], gear: ["Barbell"]),
            move([.quads], gear: ["Barbell", "Squat Rack"]),
        ]
        let small = CatalogReachCalculator.reach(catalog, kit: ["Dumbbells"]).doable
        let bigger = CatalogReachCalculator.reach(catalog, kit: ["Dumbbells", "Barbell"]).doable
        let biggest = CatalogReachCalculator.reach(catalog, kit: ["Dumbbells", "Barbell", "Squat Rack"]).doable
        #expect(small == 1)
        #expect(bigger == 2)
        #expect(biggest == 3)
    }
}
