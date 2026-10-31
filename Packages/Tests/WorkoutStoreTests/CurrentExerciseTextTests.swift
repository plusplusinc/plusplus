import Foundation
import Testing
@testable import WorkoutStore

/// How the current exercise reads: its set, and its numbers apart from their units.
@Suite("Current exercise text")
struct CurrentExerciseTextTests {
    private static let locale = Locale(identifier: "en_US")

    private static func row(_ name: String, target: SetTarget? = nil) throws -> RoutineExercise {
        let exercise = try Exercise.builtIn(named: name)
        var plan = exercise.defaultPlan(in: .pounds)
        plan.target = target ?? plan.target
        return RoutineExercise(exercise: exercise, plan: plan)
    }

    private static func figures(_ row: RoutineExercise) -> [String] {
        row.figures(locale: locale).map { "\($0.number) \($0.unit)" }
    }

    @Test("Set, or round in a superset")
    func progress() throws {
        let row = try Self.row("Dumbbell row")
        #expect(row.progressText(set: 1, inSuperset: false, locale: Self.locale) == "Set 1 of 3")
        #expect(row.progressText(set: 2, inSuperset: true, locale: Self.locale)
            == "Round 2 of 3")
    }

    @Test("Reps, time, and weight, each with what it counts")
    func figures() throws {
        let rowing = try Self.row("Dumbbell row")
        let weight = try #require(rowing.plan.weight).number(locale: Self.locale)
        #expect(Self.figures(rowing) == ["10 reps per side", "\(weight) lb"])
        #expect(try Self.figures(Self.row("Biceps curl")).last?.hasSuffix(" lb/side") == true)
        #expect(try Self.figures(Self.row("Push-up")) == ["10 reps"])
        #expect(try Self.figures(Self.row("Push-up", target: .time(seconds: 150)))
            == ["2:30 min"])
        #expect(try Self.figures(Self.row("Push-up", target: .time(seconds: 45)))
            == ["45 s"])
    }

    @Test("With a side named, the reps or time drop per side; a pair's weight keeps its /side")
    func figuresOnASide() throws {
        let rowing = try Self.row("Dumbbell row")
        let weight = try #require(rowing.plan.weight).number(locale: Self.locale)
        #expect(rowing.figures(side: .left, locale: Self.locale).map { "\($0.number) \($0.unit)" }
            == ["10 reps", "\(weight) lb"])
        #expect(rowing.spokenFigures(side: .right, locale: Self.locale)
            == "10 reps, \(weight) pounds")
        #expect(Side.left.text == "Left")
    }

    @Test("A row's progress in words: done sets of its sets")
    func spokenProgressReads() {
        #expect(spokenProgress(done: 2, total: 3, locale: Self.locale) == "2 of 3 sets done")
        #expect(spokenProgress(done: 0, total: 1, locale: Self.locale) == "0 of 1 set done")
    }

    @Test("Spoken, in words")
    func spoken() throws {
        let row = try Self.row("Push-up", target: .reps(1))
        #expect(row.spokenFigures(locale: Self.locale) == "1 rep")
    }
}
