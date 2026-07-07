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

        func lastCompleted(of routine: Routine) -> Date? {
            let identity = finished.filter { $0.routine === routine }
            let pool = identity.isEmpty
                ? finished.filter { $0.routineName == routine.name }
                : identity
            return pool.compactMap(\.endedAt).max()
        }

        var due: [WidgetSnapshot.DueRoutine] = []
        for routine in routines where !routine.groups.isEmpty {
            let state = routine.schedule.dueState(
                lastCompleted: lastCompleted(of: routine),
                today: today,
                calendar: calendar
            )
            guard state == .due else { continue }
            let caption: String
            if let since = routine.schedule.dueSince(
                lastCompleted: lastCompleted(of: routine),
                today: today,
                calendar: calendar
            ), !calendar.isDateInToday(since) {
                caption = "due since " + since.formatted(.dateTime.weekday(.abbreviated)).lowercased()
            } else {
                caption = "due today"
            }
            due.append(.init(
                name: routine.name,
                caption: caption,
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
        var streak = 0
        for count in weeklyCounts.reversed() {
            if count > 0 { streak += 1 } else if streak > 0 || count == 0 { break }
        }
        // The current week shouldn't break a streak just because it's
        // Monday morning: an empty current week defers to last week.
        if streak == 0, weeklyCounts.count >= 2, weeklyCounts[11] == 0 {
            for count in weeklyCounts.dropLast().reversed() {
                if count > 0 { streak += 1 } else { break }
            }
        }

        WidgetSnapshot(
            generatedAt: today,
            routineNames: routines.map(\.name),
            due: due,
            streakWeeks: streak,
            weeklyCounts: weeklyCounts
        ).save()

        WidgetCenter.shared.reloadAllTimelines()
    }
}
