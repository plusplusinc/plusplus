import Foundation
import Testing
import PlusPlusKit
@testable import PlusPlus

/// Authored attribute accounting (catalog expansion, 2026-07-31): the
/// movement-pattern/mechanic/laterality columns stay complete as the
/// catalog grows. The load-bearing invariant is the tripwire: a
/// strength COMPOUND that names no pattern is invisible to the
/// Movement facet, so every such row either carries one or sits in
/// `deliberatelyPatternless` below — exactly one of the two, the
/// FormCues partition shape.
@Suite("Exercise attributes")
struct ExerciseAttributeTests {
    /// Strength compounds with no honest program bucket — conditioning
    /// drills, complexes, get-ups, rollouts, slams, and the console
    /// cardio whose profile carries no distance/pace/calories (its
    /// derived modality reads .strength). Adding a row here is a
    /// DECISION: the Movement facet will never reach it.
    private static let deliberatelyPatternless: Set<String> = [
        "Ab Wheel Rollout", "Agility Ladder Drills", "Battle Rope Slams",
        "Battle Rope Waves", "Bear Crawl", "Burpee", "Butt Kicks",
        "Devil Press", "Elliptical", "Heavy Bag Rounds", "High Knees",
        "Jumping Jacks", "Man Maker", "Medicine Ball Slam",
        "Mountain Climber", "Slam Ball Slam", "Squat Thrust",
        "Stability Ball Rollout", "Stair Climber", "Turkish Get-Up",
        "Upper Body Ergometer", "Vertical Climber",
    ]

    /// A definition's modality as the app resolves it: authored
    /// override, else derived from gear + tracked metrics.
    private func resolvedModality(_ def: SeedData.BuiltInExerciseDefinition) -> ExerciseModality {
        if let authored = def.modality { return authored }
        let profile = SeedData.builtInProfile(named: def.name)
        return ExerciseModality.derive(
            equipmentNames: Set(def.equipmentNames),
            metrics: profile?.metrics ?? []
        )
    }

    private func allDefinitions() -> [SeedData.BuiltInExerciseDefinition] {
        SeedData.makeBuiltInExercisesForTesting(equipment: []).compactMap {
            SeedData.builtInDefinition(named: $0.name)
        }
    }

    @Test("Every strength compound names a pattern or an exemption, never both")
    func compoundImpliesPattern() {
        let names = Set(allDefinitions().map(\.name))
        for stale in Self.deliberatelyPatternless.subtracting(names) {
            Issue.record("deliberatelyPatternless names an unknown exercise: \(stale)")
        }
        for def in allDefinitions() {
            let exempt = Self.deliberatelyPatternless.contains(def.name)
            guard resolvedModality(def) == .strength, def.mechanic == .compound else {
                if exempt { Issue.record("\(def.name) is exempted but isn't a strength compound") }
                continue
            }
            if def.movementPattern == nil {
                #expect(exempt, "\(def.name) is a strength compound with no movement pattern and no exemption")
            } else {
                #expect(!exempt, "\(def.name) has a pattern — drop it from deliberatelyPatternless")
            }
        }
    }

    @Test("Mechanic is nil exactly on the flexibility rows")
    func mechanicPartition() {
        for def in allDefinitions() {
            if def.modality == .flexibility {
                #expect(def.mechanic == nil, "\(def.name) is mobility work but carries a mechanic")
            } else {
                #expect(def.mechanic != nil, "\(def.name) dodges the Mechanic facet with a nil mechanic")
            }
        }
    }

    @Test("No facet option is empty: every pattern, isolation, and unilateral reach the catalog")
    func facetOptionsReachTheCatalog() {
        let defs = allDefinitions()
        for pattern in MovementPattern.allCases {
            let reached = defs.contains { $0.movementPattern == pattern }
            #expect(reached, "no built-in files under \(pattern.rawValue)")
        }
        let hasIsolation = defs.contains { $0.mechanic == .isolation }
        #expect(hasIsolation)
        let hasUnilateral = defs.contains { $0.laterality == .unilateral }
        #expect(hasUnilateral)
    }

    @Test("Key rows file where a lifter would look for them")
    func spotChecks() throws {
        func def(_ name: String) throws -> SeedData.BuiltInExerciseDefinition {
            try #require(SeedData.builtInDefinition(named: name), "\(name) not in the catalog")
        }
        #expect(try def("Bench Press").movementPattern == .horizontalPush)
        #expect(try def("Bench Press").mechanic == .compound)
        #expect(try def("Bench Press").laterality == .bilateral)
        #expect(try def("Squat").movementPattern == .squat)
        #expect(try def("Romanian Deadlift").movementPattern == .hinge)
        #expect(try def("Kettlebell Swing").movementPattern == .hinge)
        #expect(try def("Pull-Up").movementPattern == .verticalPull)
        #expect(try def("Lateral Raise").movementPattern == nil)
        #expect(try def("Lateral Raise").mechanic == .isolation)
        #expect(try def("Bulgarian Split Squat").laterality == .unilateral)
        #expect(try def("Suitcase Carry").movementPattern == .carry)
        #expect(try def("Suitcase Carry").laterality == .unilateral)
        #expect(try def("Pallof Press").movementPattern == .rotation)
        #expect(try def("Plank").movementPattern == .hold)
        #expect(try def("Pigeon Pose").mechanic == nil)
        #expect(try def("Pigeon Pose").laterality == .unilateral)
    }

    @Test("A built-in resolves its attributes through the catalog; a custom resolves nil")
    func modelResolution() throws {
        let def = try #require(SeedData.builtInDefinition(named: "Deadlift"))
        let builtIn = Exercise(name: def.name, muscleGroup: def.muscleGroup, exerciseType: def.exerciseType, isBuiltIn: true)
        #expect(builtIn.movementPattern == .hinge)
        #expect(builtIn.mechanic == .compound)
        #expect(builtIn.laterality == .bilateral)

        let custom = Exercise(name: "Probe Custom Move", muscleGroup: .chest)
        #expect(custom.movementPattern == nil)
        #expect(custom.mechanic == nil)
        #expect(custom.laterality == nil)
    }
}
