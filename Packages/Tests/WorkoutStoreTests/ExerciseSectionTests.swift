import Testing
@testable import WorkoutStore

/// The A to Z list's letter headings, which the section index lists.
@Suite("Exercise sections")
struct ExerciseSectionTests {
    private static func exercises(_ names: [String]) -> [Exercise] {
        names.map { Exercise(created: CreatedExercise(name: $0, muscleGroups: [])) }
    }

    @Test("Only letters some name starts with get a heading, an accent under its letter")
    func letters() {
        let sections = Self.exercises(["apple", "Avocado", "Élan", "Egg", "Zucchini"]).lettered()
        #expect(sections.map(\.letter) == ["A", "E", "Z"])
        #expect(sections.map { $0.exercises.map(\.name) } == [
            ["apple", "Avocado"], ["Élan", "Egg"], ["Zucchini"],
        ])
    }

    @Test("A name starting with no letter goes under #, last")
    func other() {
        let sections = Self.exercises(["3-point plank", "💪 curl", "Bench", "Squat"]).lettered()
        #expect(sections.map(\.letter) == ["B", "S", ExerciseSection.otherLetter])
        #expect(sections.last?.exercises.map(\.name) == ["3-point plank", "💪 curl"])
    }

    @Test("The built-ins' headings are their letters in order, every exercise under one")
    func builtIns() {
        let sections = ExerciseList.builtIn.all.lettered()
        #expect(sections.map(\.letter) == sections.map(\.letter).sorted())
        #expect(sections.flatMap(\.exercises) == ExerciseList.builtIn.all)
    }
}
