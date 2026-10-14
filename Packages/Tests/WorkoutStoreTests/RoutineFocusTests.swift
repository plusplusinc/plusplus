import Testing
@testable import WorkoutStore

@Suite("Routine focus")
struct RoutineFocusTests {
    private static func focus(_ names: String...) throws -> RoutineFocus {
        try RoutineFocus(of: names.map { name in
            try #require(Exercise.builtIn.first { $0.name == name }, "No built-in \(name)")
        })
    }

    @Test("Three in five stretches is mobility")
    func mobility() throws {
        #expect(try Self.focus("Cat-cow", "Child\u{2019}s pose", "Pigeon stretch", "Goblet squat")
            == .mobility)
        #expect(try Self.focus("Pigeon stretch") == .mobility)
    }

    @Test("A group doing three in five of the strength work is the focus")
    func dominantGroup() throws {
        #expect(try Self.focus("Goblet squat", "Reverse lunge", "Plank", "Hamstring stretch")
            == .group(.legs))
        #expect(try Self.focus("Pull-up", "Pull-up", "Dead hang") == .group(.back))
    }

    @Test("Two groups sharing the work are a pair, in body order")
    func pair() throws {
        #expect(try Self.focus("Pull-up", "Barbell bench press") == .pair(.chest, .back))
        #expect(try Self.focus("Dead hang", "Glute bridge", "Doorway chest stretch")
            == .pair(.back, .legs))
    }

    @Test("Wider spreads are named for the parts of the body they cover")
    func regions() throws {
        #expect(try Self.focus("Push-up", "Overhead press", "Triceps extension") == .upperBody)
        #expect(try Self.focus("Dumbbell row", "Dumbbell bench press", "Farmer\u{2019}s carry")
            == .upperBodyAndCore)
        #expect(try Self.focus("Goblet squat", "Push-up", "Dumbbell row", "Plank") == .fullBody)
    }

    @Test("Every built-in stretch is marked as one, and nothing else is")
    func stretches() {
        #expect(Set(Exercise.builtIn.filter(\.isStretch).map(\.name)) == [
            "Kneeling hip flexor stretch", "Hamstring stretch", "Pigeon stretch", "Calf stretch",
            "Child\u{2019}s pose", "Cat-cow", "World\u{2019}s greatest stretch",
            "Thoracic rotation", "Doorway chest stretch", "Cross-body shoulder stretch",
            "Band shoulder dislocate",
        ])
    }
}
