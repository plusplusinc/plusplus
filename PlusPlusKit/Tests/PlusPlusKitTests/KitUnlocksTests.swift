import Foundation
import Testing
@testable import PlusPlusKit

@Suite("KitUnlocks")
struct KitUnlocksTests {
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

    /// What the app means by "the kit can do this move", written out here so
    /// the invariant test below is not expressed in terms of the thing it is
    /// checking.
    private func doable(_ catalog: [ExerciseSimilarityFeatures], kit: Set<String>) -> Int {
        catalog.count { $0.equipmentNames.isSubset(of: kit) }
    }

    @Test("A piece opens the moves it is the ONLY thing standing in front of")
    func countsTheLastMissingPiece() {
        let catalog = [
            move([.chest], gear: ["Barbell"]),               // barbell alone
            move([.back], gear: ["Barbell"]),                // barbell alone
            move([.quads], gear: ["Barbell", "Squat Rack"]), // needs both
            move([.core]),                                   // already doable
        ]
        let unlocks = KitUnlocks.byPiece(catalog, kit: [])
        #expect(unlocks["Barbell"] == 2)
        // The two-piece move counts for NEITHER: each is one of two.
        #expect(unlocks["Squat Rack"] == nil)
    }

    @Test("A piece that is one of two missing scores nothing until the other arrives")
    func unlocksAreMarginal() {
        let catalog = [move([.quads], gear: ["Barbell", "Squat Rack"])]
        #expect(KitUnlocks.byPiece(catalog, kit: [])["Squat Rack"] == nil)
        // Own the barbell, and the rack becomes the last thing in the way.
        #expect(KitUnlocks.byPiece(catalog, kit: ["Barbell"])["Squat Rack"] == 1)
    }

    @Test("Pieces already in the kit are absent, never zero")
    func ownedPiecesDropOut() {
        let catalog = [move([.chest], gear: ["Dumbbells"]), move([.back], gear: ["Barbell"])]
        let unlocks = KitUnlocks.byPiece(catalog, kit: ["Dumbbells"])
        #expect(unlocks["Dumbbells"] == nil)
        #expect(unlocks["Barbell"] == 1)
    }

    @Test("A piece nothing needs is absent from the map")
    func unusedPieceIsAbsent() {
        let catalog = [move([.chest], gear: ["Dumbbells"])]
        #expect(KitUnlocks.byPiece(catalog, kit: [])["Yoke"] == nil)
    }

    @Test("Bodyweight moves are doable with any kit and open nothing")
    func bodyweightIsNeverAnUnlock() {
        let catalog = [move([.core]), move([.chest])]
        #expect(doable(catalog, kit: []) == 2)
        #expect(KitUnlocks.byPiece(catalog, kit: []).isEmpty)
    }

    @Test("An unlock count is exactly what the doable count would gain")
    func unlocksAgreeWithDoability() {
        // The invariant that lets the equipment screen's "+N" add beat and
        // the Kit tier's "Opens N" tag read one function and never disagree.
        // ⚠️ `doable` is counted independently above rather than borrowed
        // from the thing under test, so this cannot be satisfied by both
        // sides sharing a bug.
        let catalog = [
            move([.chest], gear: ["Barbell"]),
            move([.back], gear: ["Barbell"]),
            move([.quads], gear: ["Barbell", "Squat Rack"]),
            move([.core]),
        ]
        let kit: Set<String> = ["Squat Rack"]
        let claimed = KitUnlocks.byPiece(catalog, kit: kit)["Barbell"] ?? 0
        let gained = doable(catalog, kit: kit.union(["Barbell"])) - doable(catalog, kit: kit)
        #expect(claimed == gained)
        #expect(claimed == 3)
    }

    @Test("An empty catalog opens nothing")
    func emptyCatalog() {
        #expect(KitUnlocks.byPiece([], kit: ["Barbell"]).isEmpty)
    }
}
