import Testing
import Foundation
@testable import PlusPlusKit

@Suite("WorkoutCalendarLink")
struct WorkoutCalendarLinkTests {
    @Test("Web URL round-trips a simple name")
    func webRoundTrip() {
        let url = WorkoutCalendarLink.webURL(forRoutineNamed: "Push Day")
        #expect(url?.absoluteString == "https://plusplus.fit/start/Push%20Day")
        #expect(url.flatMap(WorkoutCalendarLink.routineName(from:)) == "Push Day")
    }

    @Test("App-scheme URL round-trips a simple name")
    func appRoundTrip() {
        let url = WorkoutCalendarLink.appURL(forRoutineNamed: "Push Day")
        #expect(url?.absoluteString == "plusplus://start/Push%20Day")
        #expect(url.flatMap(WorkoutCalendarLink.routineName(from:)) == "Push Day")
    }

    @Test("A slash in the name survives as one segment")
    func slashInName() {
        for url in [WorkoutCalendarLink.webURL(forRoutineNamed: "Push / Pull"),
                    WorkoutCalendarLink.appURL(forRoutineNamed: "Push / Pull")] {
            let decoded = url.flatMap(WorkoutCalendarLink.routineName(from:))
            #expect(decoded == "Push / Pull")
        }
    }

    @Test("Unicode names round-trip")
    func unicodeName() {
        let url = WorkoutCalendarLink.webURL(forRoutineNamed: "Leg Day 🦵")
        #expect(url.flatMap(WorkoutCalendarLink.routineName(from:)) == "Leg Day 🦵")
    }

    @Test("A trailing slash is tolerated on the web form")
    func trailingSlash() {
        let url = URL(string: "https://plusplus.fit/start/Push%20Day/")!
        #expect(WorkoutCalendarLink.routineName(from: url) == "Push Day")
    }

    @Test("Non-start links are rejected")
    func rejectsOthers() {
        let cases = [
            "https://plusplus.fit/r#0abc",
            "https://plusplus.fit/github/connected",
            "https://example.com/start/Push",
            "plusplus://today",
            "plusplus://r#0abc",
        ]
        for raw in cases {
            let url = URL(string: raw)!
            #expect(WorkoutCalendarLink.routineName(from: url) == nil, "\(raw) should not parse")
            #expect(!WorkoutCalendarLink.isStartLink(url))
        }
    }

    @Test("Empty or whitespace names don't build a link")
    func rejectsEmptyName() {
        #expect(WorkoutCalendarLink.webURL(forRoutineNamed: "") == nil)
        #expect(WorkoutCalendarLink.webURL(forRoutineNamed: "   ") == nil)
    }
}

@Suite("WorkoutCalendarPlan")
struct WorkoutCalendarPlanTests {
    private func input(_ name: String, _ schedule: RoutineSchedule, minutes: Int = 45) -> WorkoutCalendarPlan.Input {
        WorkoutCalendarPlan.Input(name: name, schedule: schedule, estimatedMinutes: minutes)
    }

    @Test("Only weekday schedules produce events")
    func onlyWeekdays() {
        let events = WorkoutCalendarPlan.events(
            for: [
                input("Push", .weekdays([2, 4, 6])),
                input("Rolling", .frequency(times: 3, perDays: 7)),
                input("Whenever", .unscheduled),
            ],
            startHour: 7, startMinute: 0
        )
        #expect(events.count == 1)
        #expect(events.first?.routineName == "Push")
        #expect(events.first?.weekdays == [2, 4, 6])
    }

    @Test("Weekdays are normalized and sorted")
    func normalizedDays() {
        // 9 is out of range and dropped by RoutineSchedule.normalized.
        let events = WorkoutCalendarPlan.events(
            for: [input("Mix", .weekdays([6, 2, 9, 4]))],
            startHour: 18, startMinute: 30
        )
        #expect(events.first?.weekdays == [2, 4, 6])
        #expect(events.first?.startHour == 18)
        #expect(events.first?.startMinute == 30)
    }

    @Test("Duration is the estimate, floored to the minimum")
    func durationFloor() {
        let events = WorkoutCalendarPlan.events(
            for: [
                input("Short", .weekdays([2]), minutes: 10),
                input("Long", .weekdays([3]), minutes: 55),
            ],
            startHour: 7, startMinute: 0,
            minimumDurationMinutes: 30
        )
        let byName = Dictionary(uniqueKeysWithValues: events.map { ($0.routineName, $0.durationMinutes) })
        #expect(byName["Short"] == 30)
        #expect(byName["Long"] == 55)
    }

    @Test("Fingerprint changes when any calendar-visible field changes")
    func fingerprintSensitivity() {
        let base = WorkoutCalendarEvent(routineName: "Push", weekdays: [2, 4], startHour: 7, startMinute: 0, durationMinutes: 45)
        let differentDays = WorkoutCalendarEvent(routineName: "Push", weekdays: [2, 4, 6], startHour: 7, startMinute: 0, durationMinutes: 45)
        let differentTime = WorkoutCalendarEvent(routineName: "Push", weekdays: [2, 4], startHour: 18, startMinute: 0, durationMinutes: 45)
        let differentDuration = WorkoutCalendarEvent(routineName: "Push", weekdays: [2, 4], startHour: 7, startMinute: 0, durationMinutes: 60)
        #expect(base.fingerprint != differentDays.fingerprint)
        #expect(base.fingerprint != differentTime.fingerprint)
        #expect(base.fingerprint != differentDuration.fingerprint)
        // Identical inputs are stable.
        let same = WorkoutCalendarEvent(routineName: "Push", weekdays: [4, 2], startHour: 7, startMinute: 0, durationMinutes: 45)
        #expect(base.fingerprint == same.fingerprint)
    }
}
