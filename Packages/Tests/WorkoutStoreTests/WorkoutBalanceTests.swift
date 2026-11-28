import Foundation
import Testing
@testable import WorkoutStore

@Suite("Balance: every group's sets, and the groups not worked lately")
struct WorkoutBalanceTests {
    private typealias Fixture = LogFixture

    private func balance(
        _ loggedWorkouts: [WorkoutSession],
        in list: ExerciseList = .builtIn,
    ) -> Balance {
        WorkoutLog(loggedWorkouts: loggedWorkouts)
            .balance(in: list, now: Fixture.now, calendar: Fixture.calendar)
    }

    private func core(_ daysAgo: Int) -> WorkoutSession {
        Fixture.loggedWorkout(daysAgo: daysAgo, [Fixture.set("plank", .time(seconds: 30))])
    }

    private func group(_ group: MuscleGroup, in balance: Balance) -> GroupRecency? {
        balance.groups.first { $0.group == group }
    }

    private func missed(_ balance: Balance) -> [MuscleGroup] {
        balance.groups.filter(\.isMissed).map(\.group)
    }

    @Test("A group worked 13 days ago is not missed, and 14 is")
    func twoWeeks() {
        #expect(!missed(balance([core(13)])).contains(.core))
        #expect(missed(balance([core(14)])).contains(.core))
    }

    @Test("A group counts its sets since the period's first day, a per-side round once")
    func setCounts() {
        let sides = Fixture.loggedWorkout(daysAgo: 3, [
            Fixture.set("plank", round: 1, .time(seconds: 30), side: .left),
            Fixture.set("plank", round: 1, .time(seconds: 30), side: .right),
            Fixture.set("plank", round: 2, .time(seconds: 30), side: .left),
        ])
        let balance = balance([core(1), sides, core(27), core(28)])
        #expect(group(.core, in: balance)?.sets == 4)
        #expect(group(.chest, in: balance)?.sets == 0)
        #expect(balance.mostSets == 4)
        #expect(group(.core, in: balance)?.spokenText(locale: Fixture.locale)
            == "Core, 4 sets")
        #expect(group(.chest, in: balance)?.spokenText(locale: Fixture.locale)
            == "Chest, 0 sets")
    }

    @Test("Groups run fewest sets first, ties in declaration order")
    func order() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 1, [
            Fixture.set("plank", round: 1, .reps(5)),
            Fixture.set("plank", round: 2, .reps(5)),
            Fixture.set("pull-up", .reps(5)),
        ])
        #expect(balance([loggedWorkout]).groups.map(\.group)
            == [.chest, .shoulders, .arms, .legs, .back, .core])
        #expect(balance([]).groups.map(\.group) == MuscleGroup.allCases)
        #expect(balance([]).mostSets == 0)
    }

    @Test("A created exercise counts toward each group it checks, a gone one toward none")
    func createdAndGone() {
        let created = CreatedExercise(name: "Thing", muscleGroups: [.chest, .back])
        let list = ExerciseList(created: [created])
        let loggedWorkouts = [
            Fixture.loggedWorkout(daysAgo: 1, [Fixture.set(created.id, .reps(5))]),
            Fixture.loggedWorkout(daysAgo: 1, [Fixture.set("gone", .reps(5))]),
        ]
        let balance = balance(loggedWorkouts, in: list)
        #expect(missed(balance).sorted { $0.rawValue < $1.rawValue }
            == [.arms, .core, .legs, .shoulders])
        #expect(group(.back, in: balance)?.sets == 1)
    }
}
