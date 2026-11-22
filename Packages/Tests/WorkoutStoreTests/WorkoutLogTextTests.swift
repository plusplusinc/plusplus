import Foundation
import Testing
@testable import WorkoutStore

@Suite("How Log reads")
struct WorkoutLogTextTests {
    private typealias Fixture = LogFixture
    private let locale = LogFixture.locale

    private func plain(_ text: String?) -> String? {
        text?.replacing("\u{00A0}", with: " ")
    }

    @Test("A figure: reps with weight, reps alone, a time, a pair's weight per side")
    func figures() {
        let fifty = TopSet(target: .reps(10), weight: Fixture.pounds(50))
        #expect(plain(fifty.figure(load: .bar, locale: locale)) == "10 × 50 lb")
        #expect(plain(fifty.figure(load: .pair, locale: locale)) == "10 × 50 lb/side")
        #expect(TopSet(target: .reps(10), weight: nil).figure(load: nil, locale: locale) == "10")
        #expect(TopSet(target: .time(seconds: 60), weight: nil).figure(load: nil, locale: locale)
            == "1:00")
        #expect(fifty.spokenFigure(load: .pair, locale: locale)
            == "10 reps at 50 pounds per side")
    }

    @Test("A change: up, down, same, first")
    func changes() {
        #expect(plain(Change.up(.weight(Fixture.pounds(15))).text(locale: locale)) == "+15 lb")
        #expect(Change.up(.reps(3, withWeight: false)).text(locale: locale) == "+3")
        #expect(plain(Change.up(.reps(2, withWeight: true)).text(locale: locale)) == "+2 reps")
        #expect(Change.up(.seconds(15)).text(locale: locale) == "+0:15")
        #expect(plain(Change.down(.weight(Fixture.pounds(10))).text(locale: locale))
            == "\u{2212}10 lb")
        #expect(Change.same.text(locale: locale) == "Same")
        #expect(Change.first.text(locale: locale) == "First time")
        #expect(Change.changed.text(locale: locale) == nil)
    }

    @Test("Per side, and a set short of its plan")
    func detail() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 0, [
            Fixture.set("plank", round: 1, .time(seconds: 60)),
            Fixture.set("plank", round: 2, .time(seconds: 48), planned: .time(seconds: 60)),
            Fixture.set("plank", round: 3, .time(seconds: 50), planned: .time(seconds: 60)),
        ])
        let plank = loggedWorkout.loggedExercises(in: .builtIn)[0]
        #expect(plank.detail(locale: locale)
            == "Set 2 planned at 1:00. Last set planned at 1:00.")
        let sides = Fixture.loggedWorkout(daysAgo: 0, [
            Fixture.set("side-plank", .time(seconds: 48), planned: .time(seconds: 60), side: .left),
            Fixture.set("side-plank", .time(seconds: 60), side: .right),
        ]).loggedExercises(in: .builtIn)[0]
        #expect(sides.detail(locale: locale) == "Per side. Last set planned at 1:00.")
        #expect(sides.figures(locale: locale) == "0:48/1:00")
        #expect(sides.rounds[0].spokenFigure(load: nil, locale: locale)
            == "left 48 seconds, right 1 minute")
    }

    @Test("Each row reads to VoiceOver as one sentence")
    func spokenRows() {
        let calendar = Fixture.calendar
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 2, [
            Fixture.set("pull-up", round: 1, .reps(8)),
            Fixture.set("pull-up", round: 2, .reps(6)),
        ])
        #expect(loggedWorkout.spokenLogLine(locale: locale, calendar: calendar)
            == "Thursday, November 19, 51 minutes")
        #expect(loggedWorkout.spokenLogLine(sets: 2, locale: locale, calendar: calendar)
            == "Thursday, November 19, 51 minutes, 2 sets")
        let pullUp = loggedWorkout.loggedExercises(in: .builtIn)[0]
        #expect(pullUp.spoken(change: .up(.reps(2, withWeight: false)), locale: locale)
            == "Name. Up 2 reps. 2 sets: 8 reps, 6 reps")
        #expect(Change.same.spokenText(locale: locale) == "Same as last time")
        let core = GroupRecency(group: .core, daysAgo: nil, sets: 0)
        #expect(core.spokenText(locale: locale) == "Core, 0 sets")
        let period = LogPeriod(loggedWorkouts: [], calendar: calendar, now: Fixture.now)
        #expect(period.spokenRange(locale: locale, calendar: calendar)
            == "October 25 to November 21")
    }

    @Test("A workout's line: its day and length, and its sets")
    func loggedWorkoutLine() {
        let loggedWorkout = Fixture.loggedWorkout(daysAgo: 2, [])
        let calendar = Fixture.calendar
        #expect(loggedWorkout.logLine(locale: locale, calendar: calendar)
            == "Thu, Nov 19 · 51 min")
        #expect(loggedWorkout.logLine(sets: 21, locale: locale, calendar: calendar)
            == "Thu, Nov 19 · 51 min · 21 sets")
    }
}
