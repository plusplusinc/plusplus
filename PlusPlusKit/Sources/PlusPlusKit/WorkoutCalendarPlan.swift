import Foundation

/// The pure schedule→calendar-event mapping (#333). Given the routines
/// and a preferred time of day, it says which recurring calendar events
/// SHOULD exist. The app maps each `WorkoutCalendarEvent` onto an
/// EventKit event (EventKit is unavailable here and in Linux CI, so this
/// stays platform-pure and testable); the reconcile diff on the app side
/// keys off `fingerprint` to tell "unchanged" from "needs updating".
///
/// Only FIXED-WEEKDAY schedules produce events in v1. A rolling
/// frequency ("3×/7d") floats against the last completion and has no
/// fixed recurrence rule; unscheduled routines have no days at all. Both
/// are simply absent from the desired set, so the reconcile removes any
/// event a routine used to have when its schedule changes to one of
/// those modes.
public struct WorkoutCalendarEvent: Equatable, Sendable {
    /// Identity is the name (#32); it is also the deep-link key and the
    /// event title.
    public let routineName: String
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday), sorted —
    /// the weekly recurrence's days.
    public let weekdays: [Int]
    public let startHour: Int
    public let startMinute: Int
    /// Event length in minutes.
    public let durationMinutes: Int

    public init(routineName: String, weekdays: [Int], startHour: Int, startMinute: Int, durationMinutes: Int) {
        // Trim to match the name that survives a deep-link round trip
        // (`WorkoutCalendarLink` percent-encodes a trimmed name). Otherwise
        // a routine named " Legs " keys the desired set as " Legs " while
        // the event scanned back out of the calendar keys as "Legs", and
        // every reconcile would needlessly remove-and-recreate it.
        self.routineName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.weekdays = weekdays.sorted()
        self.startHour = startHour
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
    }

    /// A stable token over every field that affects the calendar event.
    /// The reconcile stores it alongside the created event's identifier;
    /// a mismatch means the event must be updated (or recreated).
    public var fingerprint: String {
        let days = weekdays.map(String.init).joined(separator: ",")
        return "\(routineName)|\(days)|\(startHour):\(startMinute)|\(durationMinutes)"
    }
}

public enum WorkoutCalendarPlan {
    /// One input routine: its name, its schedule, and its own estimated
    /// length in minutes (the app passes `Routine.estimatedSeconds / 60`).
    public struct Input: Equatable, Sendable {
        public let name: String
        public let schedule: RoutineSchedule
        public let estimatedMinutes: Int

        public init(name: String, schedule: RoutineSchedule, estimatedMinutes: Int) {
            self.name = name
            self.schedule = schedule
            self.estimatedMinutes = estimatedMinutes
        }
    }

    /// The desired events for a set of routines. Duration is the
    /// routine's own estimate, floored so a nearly-empty routine still
    /// reserves a sensible block.
    public static func events(
        for routines: [Input],
        startHour: Int,
        startMinute: Int,
        minimumDurationMinutes: Int = 30
    ) -> [WorkoutCalendarEvent] {
        routines.compactMap { routine in
            guard case .weekdays(let days) = routine.schedule.normalized, !days.isEmpty else {
                return nil
            }
            return WorkoutCalendarEvent(
                routineName: routine.name,
                weekdays: days.sorted(),
                startHour: startHour,
                startMinute: startMinute,
                durationMinutes: max(minimumDurationMinutes, routine.estimatedMinutes)
            )
        }
    }
}
