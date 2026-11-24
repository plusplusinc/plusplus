import Testing
@testable import WorkoutStore

/// The Workouts list's filters over a workout's summary.
@Suite("Workout filter")
struct WorkoutFilterTests {
    private static func summary(
        _ seconds: Int,
        _ groups: [MuscleGroup],
        _ equipment: [Equipment],
    ) -> WorkoutSummary {
        WorkoutSummaryTests.summary(seconds: seconds, groups: groups, equipment: equipment)
    }

    @Test("Off, the filter passes every workout, one with no summary included")
    func off() {
        #expect(WorkoutFilter().passes(nil))
        #expect(WorkoutFilter().passes(Self.summary(1800, [.legs], [])))
        #expect(!WorkoutFilter(muscleGroups: [.legs]).passes(nil))
    }

    @Test("Muscle passes a workout that mainly works a chosen group")
    func muscle() throws {
        let filter = WorkoutFilter(muscleGroups: [.legs, .core])
        #expect(filter.passes(Self.summary(1800, [.chest, .legs], [])))
        #expect(!filter.passes(Self.summary(1800, [.chest, .back], [])))
        // A goblet squat works core only along the way: no workout of it passes Core.
        let squat = try #require(Workout(exercises: [.builtIn("Goblet squat")]).summary)
        #expect(!WorkoutFilter(muscleGroups: [.core]).passes(squat))
        #expect(WorkoutFilter(muscleGroups: [.legs]).passes(squat))
    }

    @Test("Equipment passes a workout whose every piece is chosen; bodyweight never counts")
    func equipment() {
        let dumbbells = WorkoutFilter(equipment: [.piece(.dumbbells)])
        #expect(dumbbells.passes(Self.summary(1800, [.legs], [.dumbbells])))
        #expect(!dumbbells.passes(Self.summary(1800, [.legs], [.dumbbells, .bench])))
        #expect(dumbbells.passes(Self.summary(1800, [.legs], [])))
        let none = WorkoutFilter(equipment: [.none])
        #expect(none.passes(Self.summary(1800, [.legs], [])))
        #expect(!none.passes(Self.summary(1800, [.legs], [.dumbbells])))
    }

    @Test("Length holds both ends on the shown minutes; the top means no upper limit")
    func length() {
        let range = WorkoutFilter(length: LengthRange.Preset.twentyToForty.range)
        #expect(range.passes(Self.summary(40 * 60, [.legs], [])))
        #expect(range.passes(Self.summary(20 * 60, [.legs], [])))
        #expect(!range.passes(Self.summary(45 * 60, [.legs], [])))
        let over = WorkoutFilter(length: LengthRange.Preset.from40.range)
        #expect(over.passes(Self.summary(300 * 60, [.legs], [])))
        #expect(over.passes(Self.summary(40 * 60, [.legs], [])))
        #expect(!over.passes(Self.summary(35 * 60, [.legs], [])))
        let top = WorkoutFilter(length: LengthRange(lower: 0, upper: 90))
        #expect(!top.passes(Self.summary(95 * 60, [.legs], [])))
    }

    @Test("Muscle and Length together pass only a workout that passes both")
    func muscleAndLength() {
        let filter = WorkoutFilter(
            muscleGroups: [.legs],
            length: LengthRange.Preset.twentyToForty.range,
        )
        #expect(filter.passes(Self.summary(30 * 60, [.legs], [.dumbbells])))
        #expect(!filter.passes(Self.summary(30 * 60, [.chest], [])), "In the range, no legs")
        #expect(!filter.passes(Self.summary(50 * 60, [.legs], [])), "Legs, past the range")
    }

    @Test("A range carries its other end past a crossing, and knows its presets")
    func lengthRange() {
        var range = LengthRange.full
        range.setUpper(40)
        range.setLower(20)
        #expect(range.preset == .twentyToForty)
        range.setLower(50)
        #expect(range.upper == 50)
        range.setUpper(25)
        #expect(range.lower == 25)
        range.setUpper(nil)
        range.setLower(90)
        #expect(range.upper == nil)
        #expect(LengthRange(lower: 20, upper: 45).preset == nil)
        #expect(LengthRange.Preset.upTo20.range == LengthRange(lower: 0, upper: 20))
        #expect(LengthRange.Preset.from40.range == LengthRange(lower: 40, upper: nil))
        #expect(!WorkoutFilter(length: .full).isOn)
        #expect(LengthRange.lowerValues.last == 90)
        #expect(LengthRange.upperValues.suffix(2) == [90, nil])
    }

    @Test("The upper end never reaches 0, so no range reads \"≤ 0 min\"")
    func upperNeverZero() {
        #expect(LengthRange.upperValues.first == 5)
        #expect(LengthRange.lowerValues.first == 0)
        var range = LengthRange(lower: 20, upper: 40)
        range.setUpper(0)
        #expect(range.upper == 5)
        #expect(range.lower == 5, "The lower end is carried down to it")
        #expect(LengthRange(lower: 0, upper: 0).upper == 5)
        range.setLower(0)
        #expect(range.label == "≤ 5 min")
        #expect(LengthRange.Preset.allCases.allSatisfy { ($0.range.upper ?? 5) >= 5 })
    }

    /// Workouts of built-ins: dumbbells and a bench; dumbbells, a bench, and a barbell; a
    /// kettlebell alone; dumbbells and a kettlebell; nothing.
    private static func workouts() throws -> [Workout] {
        try [
            Workout(
                name: "Bench",
                exercises: [.builtIn("Dumbbell bench press"), .builtIn("Lateral raise")],
            ),
            Workout(
                name: "Two short",
                exercises: [.builtIn("Barbell bench press"), .builtIn("Biceps curl")],
            ),
            Workout(name: "Kettlebell", exercises: [.builtIn("Kettlebell swing")]),
            Workout(name: "Legs", exercises: [.builtIn("Goblet squat"), .builtIn("Reverse lunge")]),
            Workout(name: "Rows", exercises: [.builtIn("Dumbbell row")]),
        ]
    }

    private static func filtered(_ filter: WorkoutFilter) throws -> FilteredWorkouts {
        try filter.filtered(workouts(), summary: \.summary)
    }

    @Test("A workout one piece short goes under that piece, never also in the matches")
    func alsoNeeds() throws {
        let dumbbells = try Self.filtered(WorkoutFilter(equipment: [.piece(.dumbbells)]))
        #expect(dumbbells.matches.isEmpty)
        let sections = dumbbells.alsoNeeds.map { ($0.piece, $0.items.map(\.name)) }
        #expect(sections.map(\.0) == [.bench, .kettlebell])
        #expect(sections.first?.1 == ["Bench", "Rows"])
        #expect(sections.last?.1 == ["Legs"])
        // Two pieces short is in no section; a workout using no chosen piece neither.
        let named = Set(sections.flatMap(\.1))
        #expect(!named.contains("Two short"))
        #expect(!named.contains("Kettlebell"))
        let both = try Self.filtered(WorkoutFilter(equipment: [.piece(.dumbbells), .piece(.bench)]))
        #expect(both.matches.map(\.name) == ["Bench", "Rows"])
        #expect(both.alsoNeeds.map(\.piece) == [.kettlebell, .barbell])
    }

    @Test("A workout that fails Muscle or Length is in no section")
    func alsoNeedsKeepsTheOtherFilters() throws {
        let chest = try Self.filtered(WorkoutFilter(
            muscleGroups: [.chest],
            equipment: [.piece(.dumbbells)],
        ))
        #expect(chest.alsoNeeds.flatMap(\.items).map(\.name) == ["Bench"])
        let bench = try #require(Self.workouts().first?.summary)
        let short = LengthRange(lower: bench.minutes + 5, upper: nil)
        let long = try Self.filtered(WorkoutFilter(equipment: [.piece(.dumbbells)], length: short))
        #expect(!long.alsoNeeds.flatMap(\.items).map(\.name).contains("Bench"))
    }

    /// The Workouts list's entries under `filter`, each as it reads: a name, "+", or "needs".
    private static func listed(_ filter: WorkoutFilter) throws -> [String] {
        try WorkoutsItem.items(filtered(filter), filter: filter).map { item in
            switch item {
            case let .workout(workout): workout.name
            case .create: "+"
            case let .needs(piece): "needs \(piece)"
            }
        }
    }

    @Test("Create workout ends the matches, before Also needs, only while a filter is on")
    func createRowPlace() throws {
        #expect(try !Self.listed(WorkoutFilter()).contains("+"))
        #expect(try Self.listed(WorkoutFilter(equipment: [.piece(.dumbbells), .piece(.bench)]))
            .prefix(3) == ["Bench", "Rows", "+"])
        // Nothing matches: Create comes first, over the sections.
        #expect(try Self.listed(WorkoutFilter(equipment: [.piece(.dumbbells)])) == [
            "+", "needs bench", "Bench", "Rows", "needs kettlebell", "Legs",
        ])
        // Nothing matches and nothing is a piece short: Create alone.
        #expect(try Self.listed(WorkoutFilter(muscleGroups: [.chest], equipment: [.none])) == ["+"])
        // Length counts as a filter on, though it carries nothing to Add exercise.
        let length = WorkoutFilter(length: LengthRange(lower: 0, upper: 90))
        #expect(try Self.listed(length).last == "+")
        #expect(try Self.listed(length).count == Self.workouts().count + 1)
    }

    @Test("No equipment alone has no sections")
    func noEquipmentHasNoSections() throws {
        #expect(try Self.filtered(WorkoutFilter(equipment: [.none])).alsoNeeds.isEmpty)
        #expect(try Self.filtered(WorkoutFilter()).alsoNeeds.isEmpty)
    }

    @Test("Labels and the count read the choice")
    func labels() {
        #expect(WorkoutFilter(muscleGroups: [.legs]).muscleLabel == "Legs")
        #expect(WorkoutFilter(muscleGroups: [.back, .chest]).muscleLabel == "Chest, Back")
        #expect(WorkoutFilter(length: LengthRange(lower: 25, upper: 45)).lengthLabel == "25–45 min")
        #expect(LengthRange.Preset.allCases.map(\.range.label) == [
            "≤ 20 min",
            "20–40 min",
            "≥ 40 min",
        ])
        #expect(WorkoutFilter(length: LengthRange(lower: 50, upper: nil)).lengthLabel == "≥ 50 min")
        #expect(WorkoutFilter(length: LengthRange(lower: 0, upper: 25)).lengthLabel == "≤ 25 min")
        #expect(WorkoutFilter(length: LengthRange(lower: 30, upper: 30)).lengthLabel == "30 min")
        #expect(WorkoutFilter(length: .full).lengthLabel == nil)
        #expect(WorkoutFilter.countText(0) == "0 workouts")
        #expect(WorkoutFilter.countText(1) == "1 workout")
        #expect(WorkoutFilter.countText(2) == "2 workouts")
    }

    @Test("VoiceOver hears a length in words, never a ≤ or ≥: 'or less', 'or more', 'to'")
    func spokenLength() {
        #expect(WorkoutFilter(length: LengthRange(lower: 0, upper: 20))
            .lengthSpoken == "20 minutes or less")
        #expect(WorkoutFilter(length: LengthRange(lower: 40, upper: nil))
            .lengthSpoken == "40 minutes or more")
        #expect(WorkoutFilter(length: LengthRange(lower: 25, upper: 45))
            .lengthSpoken == "25 to 45 minutes")
        #expect(WorkoutFilter(length: LengthRange(lower: 30, upper: 30))
            .lengthSpoken == "30 minutes")
        #expect(WorkoutFilter(length: .full).lengthSpoken == nil)
    }
}
