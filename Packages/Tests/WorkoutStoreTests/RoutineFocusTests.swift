import Foundation
import Testing
@testable import WorkoutStore

@Suite("Routine focus")
struct RoutineFocusTests {
    private static func focus(_ names: String...) throws -> RoutineFocus {
        try RoutineFocus(of: names.map { name in
            try #require(Exercise.builtIn.first { $0.name == name }, "No built-in \(name)")
        })
    }

    @Test("Seven in ten stretches is mobility, and fewer is the strength work")
    func mobility() throws {
        #expect(try Self.focus("Cat-cow", "Child\u{2019}s pose", "Pigeon stretch", "Goblet squat")
            == .mobility(.back))
        #expect(try Self.focus("Pigeon stretch") == .mobility(.lowerBody))
        let stretchesAndStrength = try Self.focus(
            "Cat-cow",
            "Child\u{2019}s pose",
            "Pigeon stretch",
            "Goblet squat",
            "Barbell bench press",
        )
        #expect(stretchesAndStrength == .pair(.chest, .legs))
    }

    @Test("A group doing three in five of the strength work is the focus")
    func dominantGroup() throws {
        #expect(try Self.focus("Goblet squat", "Reverse lunge", "Plank", "Hamstring stretch")
            == .group(.legs))
        #expect(try Self.focus("Pull-up", "Pull-up", "Dead hang") == .group(.back))
    }

    @Test("Two groups sharing the work are a pair, in body order")
    func pair() throws {
        #expect(try Self.focus("Pull-up", "Goblet squat") == .pair(.back, .legs))
        #expect(try Self.focus("Dead hang", "Glute bridge", "Doorway chest stretch")
            == .pair(.back, .legs))
    }

    @Test("Wider spreads are named for the parts of the body they cover")
    func regions() throws {
        #expect(try Self.focus("Pull-up", "Barbell bench press") == .upperBody)
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

    @Test("Upper body two in three pushing is a push, pulling a pull")
    func pushAndPull() throws {
        #expect(try Self.focus("Push-up", "Overhead press") == .push)
        #expect(try Self
            .focus("Push-up", "Overhead press", "Triceps extension", "Pull-up") == .push)
        #expect(try Self.focus("Pull-up", "Barbell row", "Face pull", "Biceps curl") == .pull)
        #expect(try Self.focus("Dumbbell row", "Dumbbell bench press") == .upperBody)
    }

    @Test("Mobility is named for where two in three of its stretches are felt")
    func stretchRegions() throws {
        #expect(try Self.focus(
            "Doorway chest stretch",
            "Cross-body shoulder stretch",
            "Band shoulder dislocate",
            "Thoracic rotation",
        ) == .mobility(.upperBody))
        #expect(try Self.focus(
            "Cat-cow",
            "Child\u{2019}s pose",
            "Pigeon stretch",
            "Hamstring stretch",
            "World\u{2019}s greatest stretch",
        ) == .mobility(.wholeBody))
    }

    @Test("A bare group gets its day, and a group or muscle the work doesn't use gives way")
    func checked() throws {
        let core = try ["Plank", "Dead bug"].map { name in
            try #require(Exercise.builtIn.first { $0.name == name })
        }
        let focus = RoutineFocus(of: core)
        #expect(focus.checked("Core", against: core) == "Core day")
        #expect(focus.checked("Steady core", against: core) == "Steady core")
        #expect(focus.checked("Legs and core", against: core) == "Core day")
        let pushUps = try ["Push-up", "Ring dip"].map { name in
            try #require(Exercise.builtIn.first { $0.name == name })
        }
        #expect(RoutineFocus(of: pushUps).checked("Chest and triceps", against: pushUps)
            == "Chest and triceps")
        let row = try [#require(Exercise.builtIn.first { $0.name == "Dumbbell row" })]
        #expect(RoutineFocus(of: row).checked("Back and biceps", against: row) == "Back day")
    }
}
