import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The equipment-resolution logic behind the missing-gear sheet (2026-07-22):
/// the pure `EquipmentResolution` (which route wins, which kit trades the gap)
/// and the muscle-matched, kit-doable substitution finder.
@Suite("Equipment resolution")
struct EquipmentResolveTests {

    // MARK: - Pure resolution

    /// Squat/Deadlift/Bench Press need a barbell that main lacks; Garage has
    /// everything, Studio has the barbell but no dumbbells for the curl.
    private func sampleResolution() -> EquipmentResolution {
        EquipmentResolution(
            item: "Barbell",
            required: ["Barbell", "Squat Rack", "Bench", "Dumbbells"],
            activeKit: "main",
            exercises: [
                .init(name: "Squat", needs: ["Barbell", "Squat Rack"]),
                .init(name: "Deadlift", needs: ["Barbell"]),
                .init(name: "Bench Press", needs: ["Barbell", "Bench"]),
                .init(name: "Dumbbell Curl", needs: ["Dumbbells"]),
            ],
            otherKits: [
                .init(name: "Garage", members: ["Barbell", "Squat Rack", "Bench", "Dumbbells"]),
                .init(name: "Studio", members: ["Barbell", "Squat Rack", "Bench"]),
            ]
        )
    }

    @Test("Affected lists every exercise using the piece, once, in order")
    func affected() {
        #expect(sampleResolution().affected == ["Squat", "Deadlift", "Bench Press"])
    }

    @Test("Best kit is the one that has the piece and covers everything else")
    func bestKit() {
        #expect(sampleResolution().bestKit == "Garage")
    }

    @Test("A kit that has the piece but lacks another required one is a trade, named")
    func trades() {
        let trades = sampleResolution().trades
        #expect(trades.count == 1)
        #expect(trades.first?.kit == "Studio")
        #expect(trades.first?.lack == "Dumbbells")
        #expect(trades.first?.exercise == "Dumbbell Curl")
    }

    @Test("No fully-covering kit means no best fix (add or swap is the route)")
    func noBestKit() {
        let res = EquipmentResolution(
            item: "Barbell",
            required: ["Barbell", "Dumbbells"],
            activeKit: "main",
            exercises: [.init(name: "Squat", needs: ["Barbell"])],
            otherKits: [.init(name: "Hotel", members: ["Barbell"])] // lacks Dumbbells
        )
        #expect(res.bestKit == nil)
        #expect(res.trades.first?.kit == "Hotel")
    }

    // MARK: - Kit-doable alternatives

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("equip-resolve-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Alternatives share the muscle group, are kit-doable, and exclude self")
    @MainActor
    func kitDoableAlternatives() throws {
        let context = try makeContainer().mainContext
        let barbell = Equipment(name: "Barbell", isBuiltIn: true)
        let dumbbells = Equipment(name: "Dumbbells", isBuiltIn: true)
        let legMachine = Equipment(name: "Leg Press Machine", isBuiltIn: true)
        for piece in [barbell, dumbbells, legMachine] { context.insert(piece) }

        let squat = Exercise(name: "Squat", muscleGroup: .quads, exerciseType: .weightReps, isBuiltIn: true)
        let goblet = Exercise(name: "Goblet Squat", muscleGroup: .quads, exerciseType: .weightReps, isBuiltIn: true)
        let legPress = Exercise(name: "Machine Leg Press", muscleGroup: .quads, exerciseType: .weightReps, isBuiltIn: true)
        let curl = Exercise(name: "Dumbbell Curl", muscleGroup: .biceps, exerciseType: .weightReps, isBuiltIn: true)
        for exercise in [squat, goblet, legPress, curl] { context.insert(exercise) }
        // Relationships assigned AFTER insert (the pre-insert-loss rule).
        squat.equipment = [barbell]
        goblet.equipment = [dumbbells]
        legPress.equipment = [legMachine]
        curl.equipment = [dumbbells]

        let catalog = [squat, goblet, legPress, curl]
        let alts = ExerciseFilterState.kitDoableAlternatives(for: squat, in: catalog, kit: ["Dumbbells"])

        // Goblet Squat only: same muscle (quads), doable with dumbbells; the
        // machine press needs gear the kit lacks, the curl is a different
        // muscle, and Squat itself is excluded.
        #expect(alts.map(\.name) == ["Goblet Squat"])
    }
}
