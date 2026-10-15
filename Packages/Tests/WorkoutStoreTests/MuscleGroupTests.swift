import Testing
@testable import WorkoutStore

@Suite("Muscle groups")
struct MuscleGroupTests {
    @Test("Every built-in has the muscle group the table gives it")
    func builtInGroups() {
        let expected: [MuscleGroup: Set<String>] = [
            .chest: [
                "Push-up", "Ring push-up", "Dumbbell bench press", "Incline dumbbell press",
                "Barbell bench press", "Ring dip", "Doorway chest stretch",
            ],
            .back: [
                "Pull-up", "Chin-up", "Inverted row", "Dumbbell row", "Barbell row", "Dead hang",
                "Child\u{2019}s pose", "Cat-cow", "Thoracic rotation",
            ],
            .shoulders: [
                "Overhead press", "Barbell overhead press", "Lateral raise", "Face pull",
                "Band pull-apart", "Cross-body shoulder stretch", "Band shoulder dislocate",
            ],
            .arms: ["Biceps curl", "Hammer curl", "Triceps extension"],
            .legs: [
                "Goblet squat", "Barbell back squat", "Bulgarian split squat", "Reverse lunge",
                "Step-up", "Calf raise", "Romanian deadlift", "Barbell deadlift",
                "Kettlebell swing", "Glute bridge", "Balance board hold",
                "Kneeling hip flexor stretch", "Hamstring stretch", "Pigeon stretch",
                "Calf stretch", "World\u{2019}s greatest stretch",
            ],
            .core: [
                "Plank", "Side plank", "Dead bug", "Hanging knee raise", "Pallof press",
                "Turkish get-up", "Farmer\u{2019}s carry",
            ],
        ]
        let actual = Dictionary(grouping: Exercise.builtIn, by: \.muscleGroup)
            .mapValues { Set($0.map(\.name)) }
        #expect(actual == expected)
    }

    @Test("Every muscle group has a display name, in body order")
    func names() {
        #expect(MuscleGroup.allCases.map(\.name) == [
            "Chest", "Back", "Shoulders", "Arms", "Legs", "Core",
        ])
    }

    @Test("No groups have no name")
    func noGroups() {
        #expect(MuscleGroup.routineName(for: []) == nil)
    }

    @Test("One group is its name, however many exercises work it")
    func oneGroup() {
        #expect(MuscleGroup.routineName(for: [.legs]) == "Legs")
        #expect(MuscleGroup.routineName(for: [.legs, .legs, .legs]) == "Legs")
    }

    @Test("Two groups are named in body order, not the order they were added")
    func twoGroups() {
        #expect(MuscleGroup.routineName(for: [.chest, .back]) == "Chest and back")
        #expect(MuscleGroup.routineName(for: [.back, .chest]) == "Chest and back")
        #expect(MuscleGroup.routineName(for: [.core, .legs, .core]) == "Legs and core")
    }

    @Test("Three or more groups are Full body")
    func manyGroups() {
        #expect(MuscleGroup.routineName(for: [.chest, .back, .legs]) == "Full body")
        #expect(MuscleGroup.routineName(for: MuscleGroup.allCases) == "Full body")
    }
}
