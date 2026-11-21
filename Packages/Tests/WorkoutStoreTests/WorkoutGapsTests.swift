import Foundation
import Testing
@testable import WorkoutStore

@Suite("Gaps: every group's sets, the groups not worked lately, and exercises not moving")
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

    private func missed(_ gaps: Gaps) -> [MuscleGroup] {
        gaps.groups.filter(\.isMissed).map(\.group)
    }

    @Test("A group worked 13 days ago is not missed, and 14 is")
    func twoWeeks() {
        #expect(!missed(gaps([core(13)])).contains(.core))
        #expect(missed(gaps([core(14)])).contains(.core))
    }

    @Test("A group counts its sets since the period's first day, a per-side round once")
    func setCounts() {
        let sides = Fixture.workout(daysAgo: 3, [
            Fixture.set("plank", round: 1, .time(seconds: 30), side: .left),
            Fixture.set("plank", round: 1, .time(seconds: 30), side: .right),
            Fixture.set("plank", round: 2, .time(seconds: 30), side: .left),
        ])
        let gaps = gaps([core(1), sides, core(27), core(28)])
        #expect(group(.core, in: gaps)?.sets == 4)
        #expect(group(.chest, in: gaps)?.sets == 0)
        #expect(gaps.mostSets == 4)
        #expect(group(.core, in: gaps)?.spokenText(locale: Fixture.locale)
            == "Core, 4 sets")
        #expect(group(.chest, in: gaps)?.spokenText(locale: Fixture.locale)
            == "Chest, 0 sets")
    }

    @Test("Groups run fewest sets first, ties in declaration order")
    func order() {
        let workout = Fixture.workout(daysAgo: 1, [
            Fixture.set("plank", round: 1, .reps(5)),
            Fixture.set("plank", round: 2, .reps(5)),
            Fixture.set("pull-up", .reps(5)),
        ])
        #expect(gaps([workout]).groups.map(\.group)
            == [.chest, .shoulders, .arms, .legs, .back, .core])
        #expect(gaps([]).groups.map(\.group) == MuscleGroup.allCases)
        #expect(gaps([]).mostSets == 0)
    }

    @Test("A created exercise counts toward each group it checks, a gone one toward none")
    func createdAndGone() {
        let created = CreatedExercise(name: "Thing", muscleGroups: [.chest, .back])
        let list = ExerciseList(created: [created])
        let workouts = [
            Fixture.workout(daysAgo: 1, [Fixture.set(created.id, .reps(5))]),
            Fixture.workout(daysAgo: 1, [Fixture.set("gone", .reps(5))]),
        ]
        let gaps = gaps(workouts, in: list)
        #expect(missed(gaps).sorted { $0.rawValue < $1.rawValue }
            == [.arms, .core, .legs, .shoulders])
        #expect(group(.back, in: gaps)?.sets == 1)
    }

    @Test("Three workouts the same is not moving; two, or three with one different, is not")
    func notMoving() {
        let same = [core(1), core(3), core(5)]
        #expect(gaps(same).notMoving.map(\.workouts) == [3])
        #expect(gaps([core(1), core(3)]).notMoving.isEmpty)
        let longer = Fixture.workout(daysAgo: 3, [Fixture.set("plank", .time(seconds: 45))])
        #expect(gaps([core(1), longer, core(5)]).notMoving.isEmpty)
    }
}
