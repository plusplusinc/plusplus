import Foundation
import PlusPlusKit

/// The Today tab's at-a-glance state, driving its dynamic bar icon
/// (2026-07-24, Dave's ask): a fresh install's onboarding steps and each
/// day's scheduled workouts are "things to do today", and the tab icon
/// says whether any are outstanding, all handled, or the day was simply
/// empty. Three reads:
///
/// - `.toDo` — an open DASHED circle: something is on today's plate.
///   Onboarding steps still unfinished, or a workout scheduled (or
///   carried over) for today that hasn't been done.
/// - `.done` — a FILLED circle with a checkmark: the day's work is
///   handled. Today's scheduled workout completed, OR (Dave's ask names
///   the three onboarding items as "stuff to do") every setup step is
///   finished. The onboarding checkmark persists through the bounded
///   window between finishing setup and the first-ever logged workout —
///   the same window in which the timeline still shows the completed
///   setup cards — so the two surfaces agree; the first workout flips the
///   store past setup and normal day-by-day scheduling takes over.
/// - `.clear` — a plain open circle: today never had anything on it. A
///   rest day, nothing scheduled, no setup pending.
///
/// Pure and shared: `RootTabView` reads it for the tab icon, which must
/// stay live even when Today isn't the front tab, so it can't wait on
/// `TodayView`'s body to publish it. The due math mirrors `TodayView`'s
/// (same `dueState` call, same `scheduleAnchor`, same completion pairing)
/// so the icon and the timeline can never disagree — the app-side
/// precedent is `WeekPlan`, which likewise computes over `[Routine]` /
/// `[WorkoutSession]`.
enum TodayStatus: Equatable {
    case toDo
    case done
    case clear

    /// The SF Symbol the Today tab wears in this state.
    var systemImage: String {
        switch self {
        case .toDo: return "circle.dashed"
        case .done: return "checkmark.circle.fill"
        case .clear: return "circle"
        }
    }

    /// `equipmentDone` is `SetupState.equipmentDone` (a stored flag — owning
    /// nothing is a valid choice, so it can't be derived). Routine and
    /// schedule steps are derived live from `routines`.
    static func current(
        routines: [Routine],
        sessions rawSessions: [WorkoutSession],
        equipmentDone: Bool,
        today: Date,
        calendar: Calendar
    ) -> TodayStatus {
        // Only finished sessions count as history / completions; an
        // in-flight session hasn't landed. (Mirrors TodayView's `sessions`
        // query, which already filters `endedAt != nil` — the extra filter
        // keeps this correct if a caller passes an unfiltered array.)
        let sessions = rawSessions.filter { $0.endedAt != nil }

        // A fresh install has no finished sessions: the three setup steps
        // ARE today's tasks (matching `TodayView.setupActive`). Steps left
        // to do is `.toDo`; all steps done falls through to the scheduled
        // work below, so a routine that became due during setup reads as
        // the next thing to do rather than a premature checkmark.
        if sessions.isEmpty {
            let routineDone = !routines.isEmpty
            let scheduleDone = routines.contains { $0.schedule.normalized != .unscheduled }
            guard equipmentDone && routineDone && scheduleDone else { return .toDo }
        }

        let work = scheduledWork(routines: routines, sessions: sessions, today: today, calendar: calendar)
        if work.outstanding { return .toDo }
        if work.occursToday && work.satisfiedToday { return .done }
        // Setup is complete but no workout has ever been logged (still the
        // onboarding era): the three setup steps WERE the work and they're
        // done, so show the checkmark rather than an empty rest-day circle.
        // Deliberately spans the whole pre-first-workout window — the
        // timeline shows the completed setup cards across the same span (see
        // the `.done` note above). With no session, `work` can never be
        // satisfiedToday, so this is the only path to the onboarding-done
        // checkmark.
        if sessions.isEmpty { return .done }
        return .clear
    }

    /// Where today's scheduled work stands, in one pass over the routines.
    /// - `outstanding`: a routine is actionable today — due (startable or
    ///   an empty repair card), or a carried-over miss with content.
    /// - `occursToday`: today is one of some routine's occurrences.
    /// - `satisfiedToday`: today's occurrence has been met (completed today,
    ///   or banked early).
    private static func scheduledWork(
        routines: [Routine],
        sessions: [WorkoutSession],
        today: Date,
        calendar: Calendar
    ) -> (outstanding: Bool, occursToday: Bool, satisfiedToday: Bool) {
        var outstanding = false
        var occursToday = false
        var satisfiedToday = false

        for routine in routines {
            let schedule = routine.schedule.normalized
            guard schedule != .unscheduled else { continue }

            let completions = recentCompletions(of: routine, in: sessions)
            let state = schedule.dueState(
                lastCompleted: completions.last,
                previousCompleted: completions.previous,
                today: today,
                addedOn: routine.scheduleAnchor,
                calendar: calendar
            )
            let hasExercises = !routine.groups.isEmpty
            let completedToday = completions.last.map { calendar.isDate($0, inSameDayAs: today) } ?? false

            switch state {
            case .due:
                // Due today, whether startable (dueRoutines) or an empty
                // repair card (dueButEmptyRoutines) — both are "to do".
                outstanding = true
            case .missed:
                // A carried-over miss surfaces on Today only with content
                // (missedEntries filters out empty routines — nothing to
                // make up).
                if hasExercises { outstanding = true }
            case .notDue, .unscheduled:
                break
            }

            if isWeekdayOccurrence(schedule: schedule, on: today, calendar: calendar) {
                occursToday = true
                // Today is a scheduled weekday. Met early (a completion
                // before today banked it) or completed today both read as
                // this day being handled; only `.due`/`.missed` (caught
                // above as outstanding) leave it open.
                if completedToday { satisfiedToday = true }
                else if case .notDue = state { satisfiedToday = true }
            } else if completedToday {
                // Frequency schedules have no calendar day — a completion
                // today satisfies today's rolling slot.
                occursToday = true
                satisfiedToday = true
            }
        }

        return (outstanding, occursToday, satisfiedToday)
    }

    /// The two most recent completions of a routine, mirroring
    /// `TodayView.recentCompletions`: `.last` drives due-ness, `.previous`
    /// lets the Kit tell an extra session from a make-up. Identity match
    /// wins; the name fallback applies only when no session references this
    /// routine (two routines sharing a name must not satisfy each other's
    /// schedules).
    private static func recentCompletions(of routine: Routine, in sessions: [WorkoutSession]) -> (last: Date?, previous: Date?) {
        let identityMatches = sessions.filter { $0.routine === routine }
        let pool = identityMatches.isEmpty
            ? sessions.filter { $0.routineName == routine.name }
            : identityMatches
        let dates = pool.compactMap(\.endedAt).sorted(by: >)
        return (dates.first, dates.count > 1 ? dates[1] : nil)
    }

    /// Whether `day` is one of a weekday schedule's marked days. Frequency
    /// schedules float (no calendar occurrence day) and always answer false
    /// here — their "today" is handled via a completion-today check.
    private static func isWeekdayOccurrence(schedule: RoutineSchedule, on day: Date, calendar: Calendar) -> Bool {
        if case .weekdays(let days) = schedule {
            return days.contains(calendar.component(.weekday, from: day))
        }
        return false
    }
}
