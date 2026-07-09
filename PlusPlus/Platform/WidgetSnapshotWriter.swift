import Foundation
import SwiftData
import WidgetKit
import PlusPlusKit

/// Publishes the widget snapshot (#147): due-ness, routine names, and
/// streak numbers into the App Group, then pokes WidgetKit. Called on
/// launch and on backgrounding — the same moments the watch plan
/// pushes — so the Home Screen never shows yesterday's due list for
/// long.
enum WidgetSnapshotWriter {
    @MainActor
    static func write(container: ModelContainer) {
        let context = container.mainContext
        guard let routines = try? context.fetch(FetchDescriptor<Routine>(
            sortBy: [SortDescriptor(\.order)]
        )) else { return }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let finished = sessions.filter { $0.endedAt != nil }

        let calendar = Calendar.current
        let today = Date()

        // The two most recent completions (#267): `.previous` feeds the
        // Kit's banking rule — same identity-wins-else-name pool as
        // TodayView's recentCompletions.
        func recentCompletions(of routine: Routine) -> (last: Date?, previous: Date?) {
            let identity = finished.filter { $0.routine === routine }
            let pool = identity.isEmpty
                ? finished.filter { $0.routineName == routine.name }
                : identity
            let dates = pool.compactMap(\.endedAt).sorted(by: >)
            return (dates.first, dates.count > 1 ? dates[1] : nil)
        }

        var due: [WidgetSnapshot.DueRoutine] = []
        var scheduled: [WidgetSnapshot.ScheduledRoutine] = []
        for routine in routines where !routine.groups.isEmpty {
            let completions = recentCompletions(of: routine)
            // Everything schedulable ships with its schedule so the
            // widget can compute due-ness at ANY date (#159) — the
            // frozen `due` list below stays as the old-snapshot fallback.
            scheduled.append(.init(
                name: routine.name,
                exerciseCount: routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count },
                scheduleData: routine.scheduleData,
                lastCompleted: completions.last,
                previousCompleted: completions.previous
            ))
            let state = routine.schedule.dueState(
                lastCompleted: completions.last,
                previousCompleted: completions.previous,
                today: today,
                calendar: calendar
            )
            guard state == .due else { continue }
            // No "due" vocabulary anywhere (#172): a routine's presence
            // IS the statement. The caption is the schedule's own label.
            due.append(.init(
                name: routine.name,
                caption: routine.schedule.shortLabel,
                exerciseCount: routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
            ))
        }

        // Weekly buckets, oldest first; streak = consecutive non-zero
        // weeks ending now (this week counts if it has a session).
        var weeklyCounts = [Int](repeating: 0, count: 12)
        for session in finished {
            guard let ended = session.endedAt else { continue }
            let weeksAgo = calendar.dateComponents(
                [.weekOfYear],
                from: calendar.dateInterval(of: .weekOfYear, for: ended)?.start ?? ended,
                to: calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            ).weekOfYear ?? .max
            if weeksAgo >= 0 && weeksAgo < 12 {
                weeklyCounts[11 - weeksAgo] += 1
            }
        }
        // One streak rule for writer and widget roll-forward (#159).
        let streak = WidgetSnapshot.streak(fromWeeklyCounts: weeklyCounts)

        WidgetSnapshot(
            generatedAt: today,
            routineNames: routines.map(\.name),
            due: due,
            streakWeeks: streak,
            weeklyCounts: weeklyCounts,
            scheduled: scheduled
        ).save()

        WidgetCenter.shared.reloadAllTimelines()
    }
}
