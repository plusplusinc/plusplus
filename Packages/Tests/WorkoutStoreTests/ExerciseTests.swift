import Foundation
import Testing
@testable import WorkoutStore

@Suite("Exercises")
struct ExerciseTests {
    private static func builtIn(_ name: String) throws -> Exercise {
        try #require(Exercise.builtIn.first { $0.name == name }, "No built-in named \(name)")
    }

    @Test("There are 49 built-in exercises with unique ids and names")
    func builtInCount() {
        let all = Exercise.builtIn
        #expect(all.count == 49)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.name)).count == all.count)
    }

    @Test("Every built-in has the spec's name and equipment line, and nothing else is built in")
    func builtInList() {
        // The slice's list, A to Z, with the line each row shows; nil is bodyweight, no line.
        let expected: [(String, String?)] = [
            ("Balance board hold", "Balance board"),
            ("Band pull-apart", "Band"),
            ("Band shoulder dislocate", "Band"),
            ("Barbell back squat", "Barbell"),
            ("Barbell bench press", "Barbell, bench"),
            ("Barbell deadlift", "Barbell"),
            ("Barbell overhead press", "Barbell"),
            ("Barbell row", "Barbell"),
            ("Biceps curl", "Dumbbells"),
            ("Bulgarian split squat", "Dumbbells, bench"),
            ("Calf raise", "Dumbbells"),
            ("Calf stretch", nil),
            ("Cat-cow", nil),
            ("Child\u{2019}s pose", nil),
            ("Chin-up", "Pull-up bar"),
            ("Cross-body shoulder stretch", nil),
            ("Dead bug", nil),
            ("Dead hang", "Pull-up bar"),
            ("Doorway chest stretch", nil),
            ("Dumbbell bench press", "Dumbbells, bench"),
            ("Dumbbell row", "Dumbbells, bench"),
            ("Face pull", "Band"),
            ("Farmer\u{2019}s carry", "Dumbbells"),
            ("Glute bridge", nil),
            ("Goblet squat", "Kettlebell"),
            ("Hammer curl", "Dumbbells"),
            ("Hamstring stretch", nil),
            ("Hanging knee raise", "Pull-up bar"),
            ("Incline dumbbell press", "Dumbbells, bench"),
            ("Inverted row", "Rings"),
            ("Kettlebell swing", "Kettlebell"),
            ("Kneeling hip flexor stretch", nil),
            ("Lateral raise", "Dumbbells"),
            ("Overhead press", "Dumbbells"),
            ("Pallof press", "Band"),
            ("Pigeon stretch", nil),
            ("Plank", nil),
            ("Pull-up", "Pull-up bar"),
            ("Push-up", nil),
            ("Reverse lunge", "Dumbbells"),
            ("Ring dip", "Rings"),
            ("Ring push-up", "Rings"),
            ("Romanian deadlift", "Dumbbells"),
            ("Side plank", nil),
            ("Step-up", "Dumbbells, bench"),
            ("Thoracic rotation", nil),
            ("Triceps extension", "Dumbbells"),
            ("Turkish get-up", "Kettlebell"),
            ("World\u{2019}s greatest stretch", nil),
        ]
        let actual = Exercise.builtIn.map { "\($0.name) | \($0.equipmentLine ?? "-")" }
        #expect(actual == expected.map { "\($0.0) | \($0.1 ?? "-")" })
    }

    @Test("Built-ins are sorted A to Z")
    func builtInSorted() {
        let names = Exercise.builtIn.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(names.first == "Balance board hold")
        #expect(names.last == "World\u{2019}s greatest stretch")
    }

    @Test("Bodyweight exercises have no equipment line")
    func bodyweightHasNoLine() throws {
        for name in ["Push-up", "Plank", "Child\u{2019}s pose", "Glute bridge"] {
            #expect(try Self.builtIn(name).equipmentLine == nil)
        }
        let bodyweight = Set(Exercise.builtIn.filter(\.equipment.isEmpty).map(\.name))
        #expect(bodyweight == [
            "Push-up", "Glute bridge", "Plank", "Side plank", "Dead bug",
            "Kneeling hip flexor stretch", "Hamstring stretch", "Pigeon stretch", "Calf stretch",
            "Child\u{2019}s pose", "Cat-cow", "World\u{2019}s greatest stretch",
            "Thoracic rotation",
            "Doorway chest stretch", "Cross-body shoulder stretch",
        ])
    }

    @Test(
        "Equipment lines follow the spec",
        arguments: [
            ("Dumbbell bench press", "Dumbbells, bench"),
            ("Barbell bench press", "Barbell, bench"),
            ("Goblet squat", "Kettlebell"),
            ("Dead hang", "Pull-up bar"),
            ("Balance board hold", "Balance board"),
            ("Face pull", "Band"),
        ],
    )
    func equipmentLines(name: String, line: String) throws {
        #expect(try Self.builtIn(name).equipmentLine == line)
    }

    @Test("An equipment line orders by equipment, capitalizing only the first")
    func lineOrder() {
        #expect(Exercise(id: "a", name: "A", equipment: [.bench, .dumbbells]).equipmentLine
            == "Dumbbells, bench")
        #expect(Exercise(id: "b", name: "B", equipment: [.rings, .band, .kettlebell]).equipmentLine
            == "Kettlebell, band, rings")
    }

    @Test("Every equipment has a display name")
    func equipmentNames() {
        #expect(Equipment.allCases.map(\.name) == [
            "Dumbbells", "Kettlebell", "Barbell", "Bench", "Band", "Pull-up bar", "Rings",
            "Balance board",
        ])
    }

    @Test("Search is case-insensitive and matches anywhere in the name")
    func searchMatches() {
        #expect(Exercise.builtIn.matching("PRESS").map(\.name) == [
            "Barbell bench press", "Barbell overhead press", "Dumbbell bench press",
            "Incline dumbbell press", "Overhead press", "Pallof press",
        ])
        #expect(Exercise.builtIn.matching("curl").map(\.name) == [
            "Biceps curl", "Hammer curl",
        ])
    }

    @Test("An empty or blank query matches everything")
    func emptyQuery() {
        #expect(Exercise.builtIn.matching("") == Exercise.builtIn)
        #expect(Exercise.builtIn.matching("  ") == Exercise.builtIn)
    }

    @Test("A query with no match finds nothing")
    func noMatch() {
        #expect(Exercise.builtIn.matching("zzz").isEmpty)
    }

    @Test("Search ignores spaces, hyphens, and apostrophes of either kind")
    func punctuation() {
        for query in ["pullup", "pull up", "PULL-UP", "Pull\u{2010}up"] {
            #expect(Exercise.builtIn.matching(query).map(\.name) == ["Pull-up"])
        }
        #expect(Exercise.builtIn.matching("push up").map(\.name) == ["Push-up", "Ring push-up"])
        for query in ["farmer's", "farmer\u{2019}s", "farmers", "FARMERS CARRY"] {
            #expect(Exercise.builtIn.matching(query).map(\.name) == ["Farmer\u{2019}s carry"])
        }
    }

    @Test("A query of only punctuation matches everything, as a blank one does")
    func punctuationOnly() {
        #expect(Exercise.builtIn.matching(" - ") == Exercise.builtIn)
    }

    @Test("Each routine exercise is its own instance")
    func duplicateInstances() throws {
        let squat = try Self.builtIn("Goblet squat")
        let first = RoutineExercise(exercise: squat)
        let second = RoutineExercise(exercise: squat)
        #expect(first.id != second.id)
    }
}
