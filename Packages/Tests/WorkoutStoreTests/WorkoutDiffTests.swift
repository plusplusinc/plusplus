import Foundation
import Testing
@testable import WorkoutStore

@Suite("Diff over the period")
struct WorkoutDiffTests {
    private typealias Fixture = LogFixture

    private func progress(_ workoutSessions: [WorkoutSession]) -> [DiffItem] {
        WorkoutLog(workoutSessions: workoutSessions)
            .diff(in: .builtIn, now: Fixture.now, calendar: Fixture.calendar)
    }

    private func bench(_ daysAgo: Int, _ pounds: Double, id: String = "bench") -> WorkoutSession {
        Fixture.workoutSession(
            daysAgo: daysAgo,
            [Fixture.set(id, .reps(8), Fixture.pounds(pounds))],
        )
    }

    @Test("An exercise in one workout is left out, and in two is in")
    func twoWorkoutSessions() {
        #expect(progress([bench(1, 135)]).isEmpty)
        #expect(progress([bench(1, 135), bench(3, 135)]).count == 1)
    }

    @Test("A workout on the period's first day, Sunday Oct 25, counts and the day before doesn't")
    func window() {
        #expect(progress([bench(1, 150), bench(27, 135)]).count == 1)
        #expect(progress([bench(1, 150), bench(28, 135)]).isEmpty)
    }

    @Test("A workout started after now, as a clock set back leaves one, is out, as History's is")
    func afterNow() {
        #expect(progress([bench(1, 150), bench(-1, 135)]).isEmpty)
    }

    @Test("Per side follows the newest workout's sets, as the name does")
    func perSideFromNewest() throws {
        let sided = Fixture.workoutSession(
            daysAgo: 1,
            [Fixture.set("bench", .reps(8), Fixture.pounds(50), side: .left)],
        )
        let item = try #require(progress([sided, bench(5, 50)]).first)
        #expect(item.isPerSide)
        let unsided = try #require(progress([bench(1, 50), Fixture.workoutSession(
            daysAgo: 5,
            [Fixture.set("bench", .reps(8), Fixture.pounds(50), side: .left)],
        )]).first)
        #expect(!unsided.isPerSide)
    }

    @Test("First is the oldest in the window, latest the newest")
    func firstAndLatest() throws {
        let item = try #require(progress([bench(1, 150), bench(10, 140), bench(20, 135)]).first)
        #expect(item.first.weight == Fixture.pounds(135))
        #expect(item.latest.weight == Fixture.pounds(150))
        #expect(item.change == .up(.weight(Fixture.pounds(15))))
    }

    @Test("Gains come first, then the rest, each most recently done first")
    func order() {
        let items = progress([
            bench(1, 135, id: "same-new"), bench(5, 135, id: "same-new"),
            bench(2, 150, id: "up-old"), bench(6, 135, id: "up-old"),
            bench(3, 130, id: "down"), bench(7, 135, id: "down"),
            bench(0, 140, id: "up-new"), bench(8, 135, id: "up-new"),
        ])
        #expect(items.map(\.id) == ["up-new", "up-old", "same-new", "down"])
    }
}
