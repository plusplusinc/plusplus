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
///    still syncs up to iCloud/Google). Removal takes every event with it;
///    the reconcile only ever touches this calendar, never the user's own
///    events; the user gets a native off-switch (hide/delete it).
///  - **One idempotent `reconcile`, not per-edit hooks.** It computes the
///    desired event set and reconciles it against what's actually in the
///    calendar. Every transition (routine deleted, rescheduled, retimed,
///    unscheduled, feature toggled) falls out of the same diff, and running
///    it on every foreground/background heals anything a hook missed.
///
/// **Identity is the calendar TITLE, not its identifier** (#346). iOS
/// reassigns a calendar's `calendarIdentifier` once it syncs to an
/// iCloud/Google account, so a stored identifier stops resolving even
/// though the calendar is right there. The first cut trusted the stored
/// identifier: the drifted lookup read as "user deleted it," the feature
/// turned itself off, and re-enabling created a SECOND "++ Workouts"
/// calendar while orphaning the first (the app only ever remembered one
/// identifier). So we now find our calendar by title, consolidate any
/// strays into one, match events by the routine link they carry (event
/// identifiers drift too), and remove EVERY "++ Workouts" calendar on
/// disable.
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
    /// True when access was granted but no calendar source would host the
    /// "++ Workouts" calendar (rare) — the toggle reverts and the UI says so.
    private(set) var unavailable = false

    private let store = EKEventStore()
    /// Guards against overlapping passes (foreground + a settings edit
    /// firing together).
    private var isReconciling = false
    /// Coalesces the rapid binding writes a time picker emits while the
    /// user drags, so the events rebuild once when the drag settles.
    private var timeDebounce: Task<Void, Never>?

    private init() {
        isEnabled = CalendarSyncSettings.isEnabled
    }

    // MARK: - Access

    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - User actions

    /// Turn the feature on: request access, then populate. Leaves the
    /// toggle off if access is denied or no calendar can be created — this
    /// is the ONE path allowed to create the "++ Workouts" calendar.
    func enable(routines: [Routine]) async {
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            calendarLog.error("Calendar access request failed: \(error.localizedDescription)")
            granted = false
        }
        accessDenied = !granted
        unavailable = false
        guard granted else {
            CalendarSyncSettings.isEnabled = false
            isEnabled = false
            return
        }
        CalendarSyncSettings.isEnabled = true
        isEnabled = true
        await reconcile(routines: routines, allowCreate: true)
        // No calendar could be created (no writable source) — revert the
        // toggle rather than sit on silently for nothing.
        if CalendarSyncSettings.calendarIdentifier == nil {
            CalendarSyncSettings.isEnabled = false
            isEnabled = false
            unavailable = true
        }
    }

    /// Turn the feature off and remove everything. Removes EVERY
    /// "++ Workouts" calendar, not just the last-remembered one, so a
    /// duplicate left by the old identifier bug (or one the user made) can't
    /// survive as an orphan.
    func disableAndRemove() async {
        timeDebounce?.cancel()
        var allRemoved = true
        for calendar in ourCalendars() {
            do {
                try store.removeCalendar(calendar, commit: true)
            } catch {
                calendarLog.error("Removing a ++ Workouts calendar failed: \(error.localizedDescription)")
                allRemoved = false
            }
        }
        // Only forget our state once the calendars are actually gone; if a
        // removal threw (e.g. access revoked mid-session) keep the pointer
        // so a later pass finishes the job.
        if allRemoved {
            CalendarSyncSettings.clear()
        } else {
            CalendarSyncSettings.isEnabled = false
        }
        isEnabled = false
        accessDenied = false
        unavailable = false
    }

    /// A new preferred time from Settings. Debounced: a time picker writes
    /// its binding on every detent, and each change re-fingerprints every
    /// event, so without this a single drag would delete-and-recreate the
    /// whole set many times over.
    func updateTime(hour: Int, minute: Int, routines: [Routine]) {
        CalendarSyncSettings.hour = hour
        CalendarSyncSettings.minute = minute
        timeDebounce?.cancel()
        timeDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await reconcile(routines: routines)
        }
    }

    // MARK: - Reconcile (the spine)

    /// Make the calendar match the routines. Safe to call anytime; a
    /// no-op when the feature is off. Called on every foreground and
    /// background so external changes and missed edits self-heal.
    func reconcile(routines: [Routine], allowCreate: Bool = false) async {
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

        let ours = ourCalendars()
        // Deleting "++ Workouts" is a documented off-switch (the Settings
        // caption and the event notes both say so). On a PASSIVE pass, if
        // we once created a calendar and now NONE by that title exist,
        // honor the deletion and turn the feature off. Keyed on "no
        // calendar by title exists", NOT "the stored id stopped resolving":
        // Apple documents that a full sync loses the identifier, and the
        // old code misread that drift as a deletion (#346). The enable path
        // (`allowCreate`) skips this so re-enabling after a delete rebuilds.
        if ours.isEmpty, !allowCreate, CalendarSyncSettings.calendarIdentifier != nil {
            await disableAndRemove()
            return
        }

        guard let calendar = resolvedCalendar(ours: ours, allowCreate: allowCreate) else {
            if allowCreate {
                calendarLog.error("No calendar source would host ++ Workouts.")
            }
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

        // Match against the events ACTUALLY in the calendar, keyed by the
        // routine link they carry — not by stored event identifiers, which
        // drift with the same sync that moves the calendar's id (#346).
        let existing = existingManagedEvents(in: calendar)
        var cache = CalendarSyncSettings.managedEvents

        // 1. Remove events whose routine dropped out of the desired set
        //    (deleted, unscheduled, or switched to frequency mode).
        for (name, event) in existing where desiredByName[name] == nil {
            removeEvent(event)
            cache[name] = nil
        }

        // 2. Create or update the desired events. An event that's present
        //    and unchanged (matching fingerprint) is left alone; anything
        //    missing or changed is (re)built.
        for spec in desired {
            if let event = existing[spec.routineName] {
                if cache[spec.routineName]?.fingerprint == spec.fingerprint {
                    continue
                }
                removeEvent(event)
            }
            if let identifier = makeEvent(spec, in: calendar) {
                cache[spec.routineName] = .init(eventIdentifier: identifier, fingerprint: spec.fingerprint)
            } else {
                cache[spec.routineName] = nil
            }
        }

        // Drop cache entries no longer backed by a desired routine.
        cache = cache.filter { desiredByName[$0.key] != nil }
        CalendarSyncSettings.managedEvents = cache
    }

    // MARK: - Calendar resolution

    /// Every event calendar titled "++ Workouts". The title is our durable
    /// handle; the identifier is not (#346).
    private func ourCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.title == CalendarSyncSettings.calendarTitle }
    }

    /// The one calendar to manage. Consolidates any strays (deleting the
    /// extras), re-points the stored identifier if it drifted, and creates
    /// a fresh calendar only when none exist and `allowCreate` is set (the
    /// enable path). When the calendar set changes — a consolidation or a
    /// re-point — the event cache is cleared so the surviving calendar is
    /// rebuilt from the current schedule rather than trusting stale entries.
    private func resolvedCalendar(ours: [EKCalendar], allowCreate: Bool) -> EKCalendar? {
        guard let canonical = canonicalCalendar(ours) else {
            guard allowCreate else { return nil }
            return createCalendar()
        }
        var changed = false
        for extra in ours where extra.calendarIdentifier != canonical.calendarIdentifier {
            do {
                try store.removeCalendar(extra, commit: true)
                changed = true
            } catch {
                calendarLog.error("Consolidating a duplicate ++ Workouts calendar failed: \(error.localizedDescription)")
            }
        }
        if CalendarSyncSettings.calendarIdentifier != canonical.calendarIdentifier {
            CalendarSyncSettings.calendarIdentifier = canonical.calendarIdentifier
            changed = true
        }
        if changed {
            CalendarSyncSettings.managedEvents = [:]
        }
        return canonical
    }

    /// Prefer the calendar the stored identifier still points at; otherwise
    /// a deterministic pick so repeated runs agree on the survivor.
    private func canonicalCalendar(_ ours: [EKCalendar]) -> EKCalendar? {
        if let id = CalendarSyncSettings.calendarIdentifier,
           let match = ours.first(where: { $0.calendarIdentifier == id }) {
            return match
        }
        return ours.sorted { $0.calendarIdentifier < $1.calendarIdentifier }.first
    }

    /// Create the "++ Workouts" calendar in the best available source.
    private func createCalendar() -> EKCalendar? {
        for source in candidateSources() {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = CalendarSyncSettings.calendarTitle
            calendar.source = source
            // Brand green, matching the ++ mark.
            calendar.cgColor = UIColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1).cgColor
            do {
                try store.saveCalendar(calendar, commit: true)
                CalendarSyncSettings.calendarIdentifier = calendar.calendarIdentifier
                CalendarSyncSettings.managedEvents = [:]
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

    // MARK: - Events

    /// One event per routine currently in our calendar, keyed by the
    /// routine name carried in each event's start link. Found by scanning
    /// the calendar rather than by stored identifier, so a synced event
    /// whose id drifted is still matched to its routine (#346).
    ///
    /// Two collapses happen here: a recurring series shows up as several
    /// occurrences in the window, deduped to one by `eventIdentifier`; and
    /// if the pre-#346 bug left MORE THAN ONE series for the same routine,
    /// the extras are removed so only one survives. A weekly series always
    /// has an occurrence inside the 21-day window.
    private func existingManagedEvents(in calendar: EKCalendar) -> [String: EKEvent] {
        let now = Date()
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let end = cal.date(byAdding: .day, value: 21, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])

        // Occurrences → one representative per series, and it must be the
        // EARLIEST occurrence: `removeEvent` deletes with `.futureEvents`,
        // which only takes the given occurrence and later ones, so removing
        // from a mid-series occurrence would strand the earlier ones as
        // ghosts. An event with no identifier can't be a managed series, so
        // skip it rather than mint a fake key that would split one series.
        var seriesByID: [String: EKEvent] = [:]
        for occurrence in store.events(matching: predicate) {
            guard let id = occurrence.eventIdentifier else { continue }
            if let kept = seriesByID[id] {
                if occurrence.startDate < kept.startDate { seriesByID[id] = occurrence }
            } else {
                seriesByID[id] = occurrence
            }
        }
        // One series per routine; remove any stray duplicate series.
        var result: [String: EKEvent] = [:]
        for event in seriesByID.values.sorted(by: { $0.startDate < $1.startDate }) {
            guard let url = event.url,
                  let name = WorkoutCalendarLink.routineName(from: url) else { continue }
            if result[name] == nil {
                result[name] = event
            } else {
                removeEvent(event)
            }
        }
        return result
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
        event.notes = "Tap the link to start this workout in PlusPlus. These events are managed automatically. To stop them, turn off Calendar in PlusPlus, or delete the \u{201C}\(CalendarSyncSettings.calendarTitle)\u{201D} calendar."
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

    private func removeEvent(_ event: EKEvent) {
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
