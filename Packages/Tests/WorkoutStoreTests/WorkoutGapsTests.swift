import Foundation
import Testing
@testable import WorkoutStore

@Suite("Gaps: groups not worked lately, and exercises not moving")
struct WorkoutGapsTests {
    private typealias Fixture = LogFixture

    private func gaps(_ workouts: [Workout], in list: ExerciseList = .builtIn) -> Gaps {
        WorkoutLog(workouts: workouts).gaps(in: list, now: Fixture.now, calendar: Fixture.calendar)
    }

    private func core(_ daysAgo: Int) -> Workout {
        Fixture.workout(daysAgo: daysAgo, [Fixture.set("plank", .time(seconds: 30))])
    }

    private func group(_ group: MuscleGroup, in gaps: Gaps) -> GroupRecency? {
        gaps.groups.first { $0.group == group }
    }

    @Test("A group worked 13 days ago is not listed, and 14 is")
    func twoWeeks() {
        #expect(!gaps([core(13)]).notWorkedLately.map(\.group).contains(.core))
        #expect(gaps([core(14)]).notWorkedLately.map(\.group).contains(.core))
    }

    @Test("16 days reads its days, 28 or never reads no sets in 4 weeks")
    func text() {
        #expect(group(.core, in: gaps([core(16)]))?.text(locale: Fixture.locale) == "16 days ago")
        #expect(group(.core, in: gaps([core(28)]))?.text(locale: Fixture.locale)
            == "No sets in 4 weeks")
        #expect(group(.chest, in: gaps([core(1)]))?.text(locale: Fixture.locale)
            == "No sets in 4 weeks")
    }

    @Test("Every group has its last date and which of four weeks had a set")
    func weeks() {
        let core = group(.core, in: gaps([core(2), core(16)]))
        #expect(core?.weeks == [true, false, true, false])
        #expect(core?.daysAgo == 2)
        #expect(gaps([]).groups.count == MuscleGroup.allCases.count)
    }

    @Test("A created exercise counts toward each group it checks, a gone one toward none")
    func createdAndGone() {
        let created = CreatedExercise(name: "Thing", muscleGroups: [.chest, .back])
        let list = ExerciseList(created: [created])
        let workouts = [
            Fixture.workout(daysAgo: 1, [Fixture.set(created.id, .reps(5))]),
            Fixture.workout(daysAgo: 1, [Fixture.set("gone", .reps(5))]),
        ]
        let missed = gaps(workouts, in: list).notWorkedLately.map(\.group)
        #expect(missed == [.shoulders, .arms, .legs, .core])
    }

    @Test("Three workouts the same is not moving; two, or three with one different, is not")
    func notMoving() {
        let same = [core(1), core(3), core(5)]
        #expect(gaps(same).notMoving.map(\.workouts) == [3])
        #expect(gaps([core(1), core(3)]).notMoving.isEmpty)
        let longer = Fixture.workout(daysAgo: 3, [Fixture.set("plank", .time(seconds: 45))])
        #expect(gaps([core(1), longer, core(5)]).notMoving.isEmpty)
    }

    @Test("Neither part gives the empty reading")
    func empty() {
        let all = [
            "dumbbell-bench-press",
            "pull-up",
            "overhead-press",
            "biceps-curl",
            "goblet-squat",
            "plank",
        ]
        let workout = Fixture.workout(daysAgo: 1, all.map { Fixture.set($0, .reps(5)) })
        #expect(gaps([workout]).isEmpty)
    }
}
