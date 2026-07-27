import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// What's left of `ExerciseFilterState` after the catalog surfaces lost their
/// facet chips (2026-07-25): pure exercise-set arithmetic. The filtering tests
/// that used to live here — favorites, muscle-group union, equipment
/// intersection, search ranking, the create-from-here prefills — went with the
/// instance state they exercised. Search ranking is `FindOrCreateEngineTests`'
/// job now.
@Suite("ExerciseFilterState")
struct ExerciseFilterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exercisefilter-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeExercises(context: ModelContext) -> (barbell: Equipment, dumbbells: Equipment, cable: Equipment, exercises: [Exercise]) {
        let barbell = Equipment(name: "Barbell", isBuiltIn: true)
        let dumbbells = Equipment(name: "Dumbbells", isBuiltIn: true)
        let cable = Equipment(name: "Cable Machine", isBuiltIn: true)
        context.insert(barbell)
        context.insert(dumbbells)
        context.insert(cable)

        let benchPress = Exercise(name: "Probe Press", muscleGroup: .chest)
        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        let cableFly = Exercise(name: "Probe Fly", muscleGroup: .chest)
        let pushUp = Exercise(name: "Probe Push", muscleGroup: .chest)
        let squat = Exercise(name: "Probe Squat", muscleGroup: .quads)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)

        let exercises = [benchPress, curl, cableFly, pushUp, squat, plank]
        for e in exercises { context.insert(e) }
        // Post-insert relationship assignment — pre-insert loses
        // nondeterministically (the #186/CI seeder bug).
        benchPress.equipment = [barbell]
        curl.equipment = [dumbbells]
        cableFly.equipment = [cable]
        squat.equipment = [barbell]
        return (barbell, dumbbells, cable, exercises)
    }

    /// Kit availability never HIDES a row (#113 flag-don't-hide): the surface
    /// shows the whole catalog and partitions on `missingEquipment` (empty ==
    /// doable), so the gap has to be reported exactly.
    @Test func missingEquipmentReportsTheGap() throws {
        let context = ModelContext(try makeContainer())
        let (_, _, _, exercises) = makeExercises(context: context)

        // A kit with dumbbells but no barbell.
        let kit: Set<String> = ["Dumbbells"]
        let press = try #require(exercises.first { $0.name == "Probe Press" })
        let curl = try #require(exercises.first { $0.name == "Probe Curl" })
        let push = try #require(exercises.first { $0.name == "Probe Push" })

        #expect(ExerciseFilterState.missingEquipment(for: press, available: kit) == ["Barbell"])
        #expect(ExerciseFilterState.missingEquipment(for: curl, available: kit).isEmpty)
        // Bodyweight needs nothing, so it's doable with any kit at all.
        #expect(ExerciseFilterState.missingEquipment(for: push, available: kit).isEmpty)
    }

    /// The muscle group rides the search haystack — which is the whole reason
    /// the Muscle facet could be deleted rather than replaced. Typing a muscle
    /// name has to reach exercises that never say it in their own name.
    @Test func searchHaystackCarriesTheMuscleGroup() throws {
        let context = ModelContext(try makeContainer())
        let (_, _, _, exercises) = makeExercises(context: context)

        let press = try #require(exercises.first { $0.name == "Probe Press" })
        let haystack = ExerciseFilterState.searchHaystack(press)

        #expect(haystack.contains("Probe Press"))
        #expect(haystack.localizedCaseInsensitiveContains(MuscleGroup.chest.displayName))
        let reachedByMuscle = FuzzySearch.matches(query: MuscleGroup.chest.displayName, candidate: haystack)
        #expect(reachedByMuscle, "typing the muscle group must reach a move that doesn't name it")
    }
}
