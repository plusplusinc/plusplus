import Testing
@testable import WorkoutStore

@Suite("Exercise filters")
struct ExerciseFilterTests {
    private let list = ExerciseList.builtIn

    private func names(_ filter: ExerciseFilter, _ query: String = "") -> [String] {
        list.filtered(by: filter, matching: query).matches.map(\.name)
    }

    @Test("An empty filter leaves the list as it is")
    func emptyFilter() {
        #expect(!ExerciseFilter().isOn)
        #expect(names(ExerciseFilter()) == list.all.map(\.name))
    }

    @Test("A muscle filter shows what works any chosen group, mainly or along the way")
    func muscleAnyOf() {
        let shown = Set(names(ExerciseFilter(muscleGroups: [.back, .chest])))
        #expect(shown.isSuperset(of: ["Pull-up", "Push-up", "Farmer\u{2019}s carry"]))
        #expect(shown.contains("Romanian deadlift"))
        #expect(!shown.contains("Biceps curl"))
        #expect(!shown.contains("Calf raise"))
    }

    @Test("Those that mainly work a chosen group come first, A to Z within each")
    func mainlyFirst() throws {
        let shown = names(ExerciseFilter(muscleGroups: [.back]))
        let carry = try #require(shown.firstIndex(of: "Farmer\u{2019}s carry"))
        let deadlift = try #require(shown.firstIndex(of: "Romanian deadlift"))
        #expect(carry < deadlift)
    }

    @Test("A created exercise matches by its checked groups, as a main match")
    func createdByGroups() {
        let created = CreatedExercise(name: "Zebra press", muscleGroups: [.arms])
        let list = ExerciseList(created: [created])
        let shown = list.filtered(by: ExerciseFilter(muscleGroups: [.arms]), matching: "")
            .matches.map(\.name)
        #expect(shown.contains("Zebra press"))
        let strength = list.filtered(by: ExerciseFilter(kind: .strength), matching: "")
        #expect(strength.matches.contains { $0.name == "Zebra press" })
    }

    @Test("Kind shows one kind; the balance exercise is Strength")
    func kind() {
        let stretches = list.filtered(by: ExerciseFilter(kind: .stretch), matching: "").matches
        #expect(!stretches.isEmpty)
        #expect(stretches.allSatisfy { $0.kind == .stretch })
        #expect(names(ExerciseFilter(kind: .strength)).contains("Balance board hold"))
    }

    @Test("Picking the chosen kind again clears it; picking another replaces it")
    func toggleKind() {
        var filter = ExerciseFilter()
        filter.toggle(.stretch)
        #expect(filter.kind == .stretch)
        filter.toggle(.strength)
        #expect(filter.kind == .strength)
        filter.toggle(.strength)
        #expect(filter.kind == nil)
    }

    @Test("Equipment shows what needs nothing beyond the chosen pieces, and no bodyweight one")
    func equipment() {
        let shown = Set(names(ExerciseFilter(equipment: [.piece(.dumbbells)])))
        #expect(shown.contains("Biceps curl"))
        #expect(!shown.contains("Dumbbell row"))
        #expect(!shown.contains("Push-up"))
    }

    @Test("Bodyweight exercises show only with No equipment chosen")
    func bodyweight() {
        let alone = list.filtered(by: ExerciseFilter(equipment: [.none]), matching: "").matches
        #expect(alone.contains { $0.name == "Push-up" })
        #expect(alone.allSatisfy { $0.equipment.isEmpty })
        let both = Set(names(ExerciseFilter(equipment: [.none, .piece(.dumbbells)])))
        #expect(both.isSuperset(of: ["Push-up", "Biceps curl"]))
    }

    @Test("Every filter and the search must hold together")
    func together() {
        let filter = ExerciseFilter(muscleGroups: [.back, .chest], kind: .stretch)
        let shown = names(filter)
        #expect(shown.contains("Cat-cow"))
        #expect(!shown.contains("Pull-up"))
        let searched = names(filter, "cat")
        #expect(searched.contains("Cat-cow"))
        #expect(!searched.contains("Child\u{2019}s pose"))
    }

    @Test("A button reads its choices in display order, both for two, a count past two")
    func labels() {
        #expect(ExerciseFilter().muscleLabel == nil)
        #expect(ExerciseFilter(muscleGroups: [.back, .chest]).muscleLabel == "Chest, Back")
        #expect(ExerciseFilter(muscleGroups: [.back, .chest, .core]).muscleLabel == "3 muscles")
        #expect(ExerciseFilter(kind: .stretch).kindLabel == "Stretch")
        let two = ExerciseFilter(equipment: [.piece(.bench), .piece(.dumbbells)])
        #expect(two.equipmentLabel == "Dumbbells, Bench")
        let three = ExerciseFilter(equipment: [.piece(.bench), .none, .piece(.dumbbells)])
        #expect(three.equipmentLabel == "No equipment +2")
    }

    @Test("Every muscle belongs to the group it is worked under")
    func muscleGroups() {
        let groups: [ExerciseTags.Muscle: MuscleGroup] = [
            .chest: .chest, .lats: .back, .upperBack: .back, .lowerBack: .back,
            .frontDelts: .shoulders, .sideDelts: .shoulders, .rearDelts: .shoulders,
            .biceps: .arms, .triceps: .arms, .forearms: .arms, .hipFlexors: .legs, .glutes: .legs,
            .quads: .legs, .hamstrings: .legs, .calves: .legs, .abs: .core, .obliques: .core,
        ]
        for (muscle, group) in groups {
            #expect(muscle.group == group)
        }
    }

    @Test("Exercises one piece short go under that piece, never also in the matches")
    func alsoNeeds() throws {
        let chest = list.filtered(
            by: ExerciseFilter(muscleGroups: [.chest], equipment: [.piece(.dumbbells)]),
            matching: "",
        )
        #expect(chest.matches.isEmpty)
        let bench = try #require(chest.alsoNeeds.first)
        #expect(bench.piece == .bench)
        #expect(Set(bench.exercises.map(\.name))
            .isSuperset(of: ["Dumbbell bench press", "Incline dumbbell press"]))
        let back = list.filtered(
            by: ExerciseFilter(muscleGroups: [.back], equipment: [.piece(.dumbbells)]),
            matching: "",
        )
        let shown = Set(back.matches.map(\.id))
        #expect(back.alsoNeeds.allSatisfy { section in
            section.exercises.allSatisfy { !shown.contains($0.id) }
        })
    }

    @Test("Sections run by how many exercises each holds, most first")
    func alsoNeedsOrder() {
        let counts = list.filtered(
            by: ExerciseFilter(equipment: [.piece(.dumbbells)]),
            matching: "",
        ).alsoNeeds.map(\.exercises.count)
        #expect(!counts.isEmpty)
        #expect(counts == counts.sorted(by: >))
    }

    @Test("Only No equipment chosen has no Also needs")
    func noEquipmentHasNoSections() {
        let filtered = list.filtered(by: ExerciseFilter(equipment: [.none]), matching: "")
        #expect(filtered.alsoNeeds.isEmpty)
    }

    @Test("Create carries the groups, then the equipment, bodyweight alone by name, never the kind")
    func carriedLine() {
        #expect(ExerciseFilter(
            muscleGroups: [.back, .chest],
            kind: .strength,
            equipment: [.piece(.bench), .piece(.dumbbells)],
        ).carriedLine == "Chest, Back, Dumbbells, Bench")
        #expect(ExerciseFilter(muscleGroups: [.chest], equipment: [.none])
            .carriedLine == "Chest, Bodyweight")
        #expect(ExerciseFilter(kind: .stretch).carriedLine == nil)
        // No equipment beside a piece carries only the piece, so the line names only the piece.
        let both = ExerciseFilter(equipment: [.none, .piece(.band)])
        #expect(both.carriedEquipment == [.band])
        #expect(both.carriedLine == "Band")
    }

    @Test("An unnamed exercise takes the first name no exercise has")
    func unusedName() {
        let base = ExerciseList.unnamedExerciseName
        #expect(list.unusedName(base) == base)
        let taken = ExerciseList(created: [CreatedExercise(name: base, muscleGroups: [])])
        #expect(taken.unusedName(base) == "\(base) 2")
    }
}
