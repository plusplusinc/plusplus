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
        let over = WorkoutFilter(length: LengthRange.Preset.over40.range)
        #expect(over.passes(Self.summary(300 * 60, [.legs], [])))
        #expect(!over.passes(Self.summary(40 * 60, [.legs], [])))
        let top = WorkoutFilter(length: LengthRange(lower: 0, upper: 90))
        #expect(!top.passes(Self.summary(95 * 60, [.legs], [])))
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
        #expect(LengthRange.Preset.under20.range == LengthRange(lower: 0, upper: 15))
        #expect(LengthRange.Preset.over40.range == LengthRange(lower: 45, upper: nil))
        #expect(!WorkoutFilter(length: .full).isOn)
        #expect(LengthRange.lowerValues.last == 90)
        #expect(LengthRange.upperValues.suffix(2) == [90, nil])
    }

    @Test("Labels and the count read the choice")
    func labels() {
        #expect(WorkoutFilter(muscleGroups: [.legs]).muscleLabel == "Legs")
        #expect(WorkoutFilter(muscleGroups: [.back, .chest]).muscleLabel == "Chest, Back")
        #expect(WorkoutFilter(length: LengthRange(lower: 25, upper: 45)).lengthLabel == "25–45 min")
        #expect(WorkoutFilter(length: LengthRange.Preset.under20.range)
            .lengthLabel == "< 20 min")
        #expect(WorkoutFilter(length: LengthRange(lower: 45, upper: nil))
            .lengthLabel == "> 40 min")
        #expect(WorkoutFilter(length: LengthRange(lower: 50, upper: nil)).lengthLabel == "50+ min")
        #expect(WorkoutFilter(length: LengthRange(lower: 30, upper: 30)).lengthLabel == "30 min")
        #expect(WorkoutFilter(length: .full).lengthLabel == nil)
        #expect(WorkoutFilter.countText(0) == "0 workouts")
        #expect(WorkoutFilter.countText(1) == "1 workout")
        #expect(WorkoutFilter.countText(2) == "2 workouts")
    }
}
