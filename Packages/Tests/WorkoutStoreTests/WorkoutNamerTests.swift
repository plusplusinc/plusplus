import Foundation
import Testing
@testable import WorkoutStore

@Suite("Routine namer")
struct WorkoutNamerTests {
    private static func exercises(_ names: String...) throws -> [Exercise] {
        try Exercise.builtIn(named: names)
    }

    /// A routine whose style seed is `seed`: a multiple of three has character, and the seed
    /// over three picks the variant.
    private static func workout(seed: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, seed, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    /// Plain, its first variant.
    private static let workout = workout(seed: 1)
    /// Character, its first variant.
    private static let characterWorkout = workout(seed: 0)
    /// Plain, its second variant.
    private static let otherWorkout = workout(seed: 4)

    @Test("No exercises get no name")
    func noExercises() {
        #expect(WorkoutNamer.standard.name(for: [], of: Self.workout) == nil)
        #expect(WorkoutNamer.muscleGroupsOnly.name(for: [], of: Self.workout) == nil)
    }

    @Test("Muscle-group names only: one group, two, or full body")
    func muscleGroupsOnly() throws {
        let namer = WorkoutNamer.muscleGroupsOnly
        #expect(try namer.name(for: Self.exercises("Goblet squat"), of: Self.workout) == "Legs")
        #expect(try namer.name(
            for: Self.exercises("Pull-up", "Barbell bench press"),
            of: Self.workout,
        )
            == "Chest and back")
        #expect(try namer.name(
            for: Self.exercises("Pull-up", "Goblet squat", "Plank"),
            of: Self.workout,
        ) == "Full body")
    }

    @Test("A routine is named for what it works, plain or with character by its id")
    func namedForFocus() throws {
        let legs = try Self.exercises("Goblet squat", "Reverse lunge", "Romanian deadlift")
        #expect(WorkoutNamer.standard.name(for: legs, of: Self.workout) == "Leg day")
        #expect(WorkoutNamer.standard.name(for: legs, of: Self.otherWorkout) == "Lower body")
        #expect(WorkoutNamer.standard.name(for: legs, of: Self.characterWorkout) == "Heavy legs")
    }

    @Test("Tags sharpen a name: biceps, grip, balance, a shared kettlebell")
    func sharpenedByTags() throws {
        let name = { (names: [String]) in
            try WorkoutNamer.standard.name(
                for: Exercise.builtIn(named: names),
                of: Self.otherWorkout,
            )
        }
        #expect(try name(["Biceps curl", "Hammer curl", "Triceps extension"]) ==
            "Biceps and triceps")
        #expect(try name(["Pull-up", "Dead hang"]) == "Back and grip")
        #expect(try name(["Balance board hold", "Step-up", "Side plank"]) == "Balance and legs")
        #expect(try name(["Kettlebell swing", "Turkish get-up", "Goblet squat"]) ==
            "Kettlebell legs")
        // Half core work is not kettlebell legs.
        #expect(try name(["Turkish get-up", "Goblet squat"]) == "Core and legs")
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
        #expect(WorkoutNamer.standard.name(for: mix, of: Self.workout) == "Stretch and strength")
        #expect(WorkoutNamer.standard.name(for: mix, of: Self.characterWorkout)
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
            WorkoutNamer.standard.name(for: exercises, of: Self.characterWorkout)
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
        let styles = (0 ..< 18).map { Self.workout(seed: UInt8($0)) }
        for first in Exercise.builtIn {
            for second in Exercise.builtIn {
                let exercises = first == second ? [first] : [first, second]
                let focus = WorkoutFocus(of: exercises)
                let written = focus.names(for: exercises)
                for style in styles {
                    let name = WorkoutNamer.standard.name(for: exercises, of: style) ?? ""
                    #expect((1 ... WorkoutNamer.longestName).contains(name.count), "\(name)")
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
        #expect(WorkoutNamer.standard.name(for: thrice, of: Self.workout)
            == WorkoutNamer.standard.name(for: once, of: Self.workout))
    }

    @Test("A routine keeps its style, and about a third of routines have character")
    func styleBySeed() {
        let workout = UUID()
        let first = NameStyle(of: workout)
        let again = NameStyle(of: workout)
        #expect(first == again)
        let character = (0 ..< 300).count { _ in NameStyle(of: UUID()).hasCharacter }
        #expect((60 ... 140).contains(character))
        #expect(!NameStyle(of: Self.workout).hasCharacter)
        #expect(NameStyle(of: Self.characterWorkout).hasCharacter)
    }

    @Test("A routine shows its chosen name, else its generated one")
    func shownName() throws {
        let namer = WorkoutNamer.muscleGroupsOnly
        let rows = try Exercise.builtIn(named: ["Goblet squat"])
            .map { WorkoutExercise(exercise: $0, weightUnit: .pounds) }
        #expect(namer.shownName(of: Workout(name: "Mine", exercises: rows)) == "Mine")
        #expect(namer.shownName(of: Workout(exercises: rows)) == "Legs")
        #expect(namer.shownName(of: Workout()) == nil)
    }
}
