import Foundation
import Testing
@testable import WorkoutStore

@Suite("Routine namer")
struct RoutineNamerTests {
    private static func exercises(_ names: String...) throws -> [Exercise] {
        try names.map { name in
            try #require(Exercise.builtIn.first { $0.name == name }, "No built-in \(name)")
        }
    }

    /// A routine whose seed is 1: plain, its first variant.
    private static let routine = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0))
    /// A routine whose seed is 0: character, its first variant.
    private static let characterRoutine =
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    /// A routine whose seed is 4: plain, its second variant.
    private static let otherRoutine = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0))

    @Test("No exercises get no name")
    func noExercises() {
        #expect(RoutineNamer.standard.name(for: [], of: Self.routine) == nil)
        #expect(RoutineNamer.muscleGroupsOnly.name(for: [], of: Self.routine) == nil)
    }

    @Test("Muscle-group names only: one group, two, or full body")
    func muscleGroupsOnly() throws {
        let namer = RoutineNamer.muscleGroupsOnly
        #expect(try namer.name(for: Self.exercises("Goblet squat"), of: Self.routine) == "Legs")
        #expect(try namer.name(
            for: Self.exercises("Pull-up", "Barbell bench press"),
            of: Self.routine,
        )
            == "Chest and back")
        #expect(try namer.name(
            for: Self.exercises("Pull-up", "Goblet squat", "Plank"),
            of: Self.routine,
        ) == "Full body")
    }

    @Test("A routine is named for what it works, plain or with character by its id")
    func namedForFocus() throws {
        let legs = try Self.exercises("Goblet squat", "Reverse lunge", "Romanian deadlift")
        #expect(RoutineNamer.standard.name(for: legs, of: Self.routine) == "Leg day")
        #expect(RoutineNamer.standard.name(for: legs, of: Self.otherRoutine) == "Lower body")
        #expect(RoutineNamer.standard.name(for: legs, of: Self.characterRoutine) == "Heavy legs")
    }

    @Test("Tags sharpen a name: biceps, grip, balance, a shared kettlebell")
    func sharpenedByTags() throws {
        let name = { (names: [String]) in
            try RoutineNamer.standard.name(
                for: names.map { name in try #require(Exercise.builtIn.first { $0.name == name }) },
                of: Self.otherRoutine,
            )
        }
        #expect(try name(["Biceps curl", "Hammer curl", "Triceps extension"]) ==
            "Biceps and triceps")
        #expect(try name(["Pull-up", "Dead hang"]) == "Back and grip")
        #expect(try name(["Balance board hold", "Step-up", "Side plank"]) == "Balance and legs")
        #expect(try name(["Kettlebell swing", "Turkish get-up", "Goblet squat"]) ==
            "Kettlebell legs")
    }

    @Test("Stretches with scattered strength work read as both, not as the strength alone")
    func stretchHeavyMix() throws {
        let mix = try Self.exercises(
            "Cat-cow",
            "Child\u{2019}s pose",
            "Pigeon stretch",
            "Goblet squat",
            "Barbell bench press",
        )
        #expect(RoutineNamer.standard.name(for: mix, of: Self.routine) == "Stretch and strength")
        #expect(RoutineNamer.standard.name(for: mix, of: Self.characterRoutine)
            == "Lift and stretch")
    }

    @Test("Character says only what the work bears out: heavy under a weight, steady for balance")
    func honestCharacter() throws {
        let light = try Self.exercises(
            "Hammer curl",
            "Pigeon stretch",
            "Push-up",
            "Kettlebell swing",
        )
        let balance = try Self.exercises("Balance board hold", "Step-up", "Side plank")
        let barbells = try Self.exercises("Barbell back squat", "Barbell deadlift")
        let loadedPair = try Self.exercises("Dumbbell bench press", "Goblet squat")
        let five = try Self.exercises(
            "Barbell back squat",
            "Barbell bench press",
            "Barbell row",
            "Barbell overhead press",
            "Barbell deadlift",
        )
        let name = { (exercises: [Exercise]) in
            RoutineNamer.standard.name(for: exercises, of: Self.characterRoutine)
        }
        #expect(name(light) == "Head to toe")
        #expect(name(balance) == "Steady legs")
        #expect(name(barbells) == "Barbell day")
        #expect(name(five) == "The big five")
        #expect(name(loadedPair) == "Heavy day")
    }

    @Test("Every routine of up to two built-ins, in any style, gets a short name as written")
    func everyPair() {
        // Seeds 0 to 17 cover both styles at every variant of a list up to six long.
        let styles = (0 ..< 18).map { seed in
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, UInt8(seed), 0, 0, 0, 0, 0, 0, 0, 0))
        }
        for first in Exercise.builtIn {
            for second in Exercise.builtIn {
                let exercises = first == second ? [first] : [first, second]
                let focus = RoutineFocus(of: exercises)
                let written = focus.names(for: exercises)
                for style in styles {
                    let name = RoutineNamer.standard.name(for: exercises, of: style) ?? ""
                    #expect((1 ... RoutineNamer.longestName).contains(name.count), "\(name)")
                    // The name was honest as written, so the check left it alone.
                    #expect(
                        (written.plain + written.character).contains(name),
                        "\(name) for \(first.name), \(second.name)",
                    )
                }
            }
        }
    }

    @Test("Duplicates count once")
    func duplicates() throws {
        let once = try Self.exercises("Pull-up", "Dead hang")
        let thrice = try Self.exercises("Pull-up", "Pull-up", "Pull-up", "Dead hang")
        #expect(RoutineNamer.standard.name(for: thrice, of: Self.routine)
            == RoutineNamer.standard.name(for: once, of: Self.routine))
    }

    @Test("A routine keeps its style, and about a third of routines have character")
    func styleBySeed() {
        let routine = UUID()
        let first = NameStyle(of: routine)
        let again = NameStyle(of: routine)
        #expect(first == again)
        let character = (0 ..< 300).count { _ in NameStyle(of: UUID()).hasCharacter }
        #expect((60 ... 140).contains(character))
        #expect(!NameStyle(of: Self.routine).hasCharacter)
        #expect(NameStyle(of: Self.characterRoutine).hasCharacter)
    }
}
