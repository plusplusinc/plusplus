import Foundation
import EventKit
import SwiftData
import OSLog
import UIKit
import PlusPlusKit

private let calendarLog = Logger(subsystem: "com.davidcole.plusplus", category: "calendar-sync")

/// Writes scheduled workouts into the user's calendar and keeps them in
/// step with the routines (#333). The pure "which events should exist"
/// logic lives in `WorkoutCalendarPlan` (Linux-tested); this is the thin
/// EventKit glue.
///
/// Two design choices carry the whole feature:
///  - **A dedicated "++ Workouts" calendar.** Every event lives in a
///    calendar PlusPlus owns, created in the user's default source (so it
///    still syncs up to iCloud/Google). Removal is one `removeCalendar`;
///    the reconcile only ever touches this calendar, never the user's own
///    events; the user gets a native off-switch (hide/delete it).
///  - **One idempotent `reconcile`, not per-edit hooks.** It computes the
///    desired event set and diffs against `managedEvents`. Every
///    transition (routine deleted, rescheduled, retimed, unscheduled,
///    feature toggled) falls out of the same diff, and running it on
///    every foreground/background heals anything a hook missed.
///
/// `@MainActor` because it reads SwiftData `Routine` models and drives UI
/// state; the EventKit calls are cheap (a handful of events) and the
/// `requestFullAccess` await suspends rather than blocking.
@Observable @MainActor
final class CalendarSyncCoordinator {
    static let shared = CalendarSyncCoordinator()

    /// Mirrors `CalendarSyncSettings.isEnabled` for the Settings toggle.
    private(set) var isEnabled: Bool
    /// True when the feature is on but the OS hasn't granted full
    /// calendar access — the UI points the user to iOS Settings.
    private(set) var accessDenied = false

    private let store = EKEventStore()
    /// Guards against overlapping passes (foreground + a settings edit
    /// firing together).
    private var isReconciling = false

    private init() {
        isEnabled = CalendarSyncSettings.isEnabled
    }

    // MARK: - Access

    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - User actions

    /// Turn the feature on: request access, then populate. Leaves the
    /// toggle off if access is denied.
    func enable(routines: [Routine]) async {
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            calendarLog.error("Calendar access request failed: \(error.localizedDescription)")
            granted = false
        }
        accessDenied = !granted
        guard granted else {
            CalendarSyncSettings.isEnabled = false
            isEnabled = false
            return
        }
        CalendarSyncSettings.isEnabled = true
        isEnabled = true
        await reconcile(routines: routines)
    }

    /// Turn the feature off and remove everything: deleting our calendar
    /// takes every event with it.
    func disableAndRemove() async {
        if let id = CalendarSyncSettings.calendarIdentifier,
           let calendar = store.calendar(withIdentifier: id) {
            do {
                try store.removeCalendar(calendar, commit: true)
            } catch {
                calendarLog.error("Removing ++ Workouts calendar failed: \(error.localizedDescription)")
            }
        }
        CalendarSyncSettings.clear()
        isEnabled = false
        accessDenied = false
    }

    /// A new preferred time from Settings: persist and re-time every event.
    func updateTime(hour: Int, minute: Int, routines: [Routine]) async {
        CalendarSyncSettings.hour = hour
        CalendarSyncSettings.minute = minute
        await reconcile(routines: routines)
    }

    // MARK: - Reconcile (the spine)

    /// Make the calendar match the routines. Safe to call anytime; a
    /// no-op when the feature is off. Called on every foreground and
    /// background so external changes and missed edits self-heal.
    func reconcile(routines: [Routine]) async {
        guard CalendarSyncSettings.isEnabled else { return }
        guard !isReconciling else { return }
        guard Self.hasFullAccess else {
            // Enabled but access was revoked in iOS Settings: surface it,
            // don't thrash.
            accessDenied = true
            return
        }
        accessDenied = false
        isReconciling = true
        defer { isReconciling = false }

        guard let calendar = ensureCalendar() else {
            calendarLog.error("Could not obtain the ++ Workouts calendar; skipping reconcile.")
            return
        }

        let desired = WorkoutCalendarPlan.events(
            for: routines.map {
                WorkoutCalendarPlan.Input(
                    name: $0.name,
                    schedule: $0.schedule,
                    estimatedMinutes: max(1, $0.estimatedSeconds / 60)
                )
            },
            startHour: CalendarSyncSettings.hour,
            startMinute: CalendarSyncSettings.minute
        )
        let desiredByName = Dictionary(desired.map { ($0.routineName, $0) }, uniquingKeysWith: { first, _ in first })

        var managed = CalendarSyncSettings.managedEvents

        // 1. Remove events whose routine dropped out of the desired set
        //    (deleted, unscheduled, or switched to frequency mode).
        for (name, record) in managed where desiredByName[name] == nil {
            removeEvent(record.eventIdentifier)
            managed[name] = nil
        }

        // 2. Create or update the desired events. Unchanged-and-present
        //    events are left alone; a fingerprint mismatch or a
        //    user-deleted event is rebuilt.
        for event in desired {
            if let existing = managed[event.routineName],
               existing.fingerprint == event.fingerprint,
               store.event(withIdentifier: existing.eventIdentifier) != nil {
                continue
            }
            if let existing = managed[event.routineName] {
                removeEvent(existing.eventIdentifier)
            }
            if let identifier = makeEvent(event, in: calendar) {
                managed[event.routineName] = .init(eventIdentifier: identifier, fingerprint: event.fingerprint)
            } else {
                managed[event.routineName] = nil
            }
        }

        CalendarSyncSettings.managedEvents = managed
    }

    // MARK: - EventKit helpers

    /// Our calendar, created on first use. Prefers the default calendar's
    /// source so it syncs to the user's account; falls back to a local
    /// source when the account won't host an app-created calendar.
    private func ensureCalendar() -> EKCalendar? {
        if let id = CalendarSyncSettings.calendarIdentifier,
           let existing = store.calendar(withIdentifier: id) {
            return existing
        }
        // A fresh calendar means any remembered events are gone with the
        // old one — start the map clean.
        CalendarSyncSettings.managedEvents = [:]

        for source in candidateSources() {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = CalendarSyncSettings.calendarTitle
            calendar.source = source
            // Brand green, matching the ++ mark.
            calendar.cgColor = UIColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1).cgColor
            do {
                try store.saveCalendar(calendar, commit: true)
                CalendarSyncSettings.calendarIdentifier = calendar.calendarIdentifier
                return calendar
            } catch {
                calendarLog.notice("Source \(source.title) rejected the calendar; trying the next.")
            }
        }
        return nil
    }

    /// Sources to try, best first: the account the default calendar lives
    /// in, then any local source, then anything writable.
    private func candidateSources() -> [EKSource] {
        var ordered: [EKSource] = []
        if let preferred = store.defaultCalendarForNewEvents?.source, preferred.sourceType != .birthdays {
            ordered.append(preferred)
        }
        for source in store.sources where source.sourceType == .local {
            if !ordered.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) {
                ordered.append(source)
            }
        }
        for source in store.sources where !ordered.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) {
            if source.sourceType != .birthdays {
                ordered.append(source)
            }
        }
        return ordered
    }

    /// Build one recurring event and return its identifier.
    private func makeEvent(_ spec: WorkoutCalendarEvent, in calendar: EKCalendar) -> String? {
        guard let start = Self.firstOccurrence(weekdays: spec.weekdays, hour: spec.startHour, minute: spec.startMinute) else {
            return nil
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        // Neutral title, no obligation vocabulary (#172) — a block the
        // user opted into, not a nag.
        event.title = "++ \(spec.routineName)"
        event.url = WorkoutCalendarLink.webURL(forRoutineNamed: spec.routineName)
        event.notes = "Tap the link to start this workout in PlusPlus. Managed by the app — turn off in Settings, or delete the \u{201C}\(CalendarSyncSettings.calendarTitle)\u{201D} calendar."
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(spec.durationMinutes * 60))
        event.recurrenceRules = [Self.recurrenceRule(weekdays: spec.weekdays)]
        do {
            try store.save(event, span: .futureEvents, commit: true)
            return event.eventIdentifier
        } catch {
            calendarLog.error("Saving event for \(spec.routineName) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func removeEvent(_ identifier: String) {
        guard let event = store.event(withIdentifier: identifier) else { return }
        do {
            try store.remove(event, span: .futureEvents, commit: true)
        } catch {
            calendarLog.error("Removing an event failed: \(error.localizedDescription)")
        }
    }

    /// A weekly rule over the scheduled weekdays. `EKWeekday.rawValue`
    /// (Sunday = 1 … Saturday = 7) matches `Calendar` weekday numbers, so
    /// `RoutineSchedule`'s day set maps straight across.
    private static func recurrenceRule(weekdays: [Int]) -> EKRecurrenceRule {
        let days = weekdays
            .compactMap { EKWeekday(rawValue: $0) }
            .map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: days,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }

    /// The soonest date on or after now that lands on a scheduled weekday
    /// at the preferred time — the recurrence anchor. If today matches but
    /// its time has already passed, the next matching day is used.
    static func firstOccurrence(
        weekdays: [Int],
        hour: Int,
        minute: Int,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let days = Set(weekdays)
        guard !days.isEmpty else { return nil }
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            guard days.contains(calendar.component(.weekday, from: day)) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let candidate = calendar.date(from: comps) else { continue }
            if offset > 0 || candidate >= now { return candidate }
            // Today, but the time is past — fall through to the next match.
        }
        return nil
    }
}
