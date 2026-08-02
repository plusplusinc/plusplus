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
