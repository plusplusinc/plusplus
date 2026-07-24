import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// The "Swap for…" suggestions ranker (2026-07-24): same-muscle catalog
/// moves, kit-doable first, then ranked by similarity. Distinct from
/// `kitDoableAlternatives`, which HIDES not-in-kit moves; this keeps them,
/// flagged, below the doable ones.
@Suite("Swap suggestions")
struct SwapSuggestionsTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swap-suggest-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Same muscle only, kit-doable first, self and other muscles excluded")
    func ranksSameMuscleKitDoableFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let barbell = Equipment(name: "Probe Barbell")
        let dumbbells = Equipment(name: "Probe Dumbbells")
        let machine = Equipment(name: "Probe Leg Machine")
        for piece in [barbell, dumbbells, machine] { context.insert(piece) }

        let squat = Exercise(name: "Probe Squat", muscleGroup: .quads)          // origin
        let goblet = Exercise(name: "Probe Goblet", muscleGroup: .quads)        // dumbbells → doable
        let bodyweightSquat = Exercise(name: "Probe Air Squat", muscleGroup: .quads) // bodyweight → doable
        let legPress = Exercise(name: "Probe Leg Press", muscleGroup: .quads)   // machine → NOT in kit
        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)           // other muscle
        for exercise in [squat, goblet, bodyweightSquat, legPress, curl] { context.insert(exercise) }
        squat.equipment = [barbell]
        goblet.equipment = [dumbbells]
        legPress.equipment = [machine]
        curl.equipment = [dumbbells]

        let catalog = [squat, goblet, bodyweightSquat, legPress, curl]
        let suggestions = ExerciseFilterState.swapSuggestions(
            for: squat, in: catalog, kit: ["Probe Dumbbells"]
        )
        let names = suggestions.map(\.name)

        // Only quad moves, self and biceps excluded.
        #expect(!names.contains("Probe Squat"))
        #expect(!names.contains("Probe Curl"))
        // The two kit-doable quad moves come before the machine one the kit
        // can't do (flag-don't-hide: it stays, just ranked last).
        #expect(names.last == "Probe Leg Press")
        #expect(Set(names.prefix(2)) == ["Probe Goblet", "Probe Air Squat"])
    }

    @Test("An exercise with no same-muscle peers yields an empty tray")
    func emptyWhenNoPeers() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let lonely = Exercise(name: "Probe Lonely Core", muscleGroup: .core)
        let chest = Exercise(name: "Probe Press", muscleGroup: .chest)
        for exercise in [lonely, chest] { context.insert(exercise) }

        let suggestions = ExerciseFilterState.swapSuggestions(
            for: lonely, in: [lonely, chest], kit: []
        )
        #expect(suggestions.isEmpty)
    }
}
