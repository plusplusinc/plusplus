import Foundation
import SwiftData
import PlusPlusKit

/// Operator's read side: deterministic queries rendered as terse,
/// one-entity-per-line digests. Digest text re-enters the on-device
/// model's tiny context window, so every line earns its tokens. All
/// numbers come from real fetches — the model is told to never guess.
@MainActor
struct OperatorDataService {
    let context: ModelContext
    var calendar: Calendar = .current
    var today: () -> Date = { Date() }

    // MARK: - find_items

    func findItems(
        kind: ChangeEntity,
        nameContains: String? = nil,
        muscleGroup: MuscleGroup? = nil,
        inLibraryOnly: Bool = false,
        limit: Int = 8
    ) -> String {
        let cap = max(1, min(limit, 15))
        let fragment = ChangeFilter.normalized(nameContains)
        do {
            // Fragment matching is FuzzySearch everywhere below: the
            // fragment is the user's words relayed by the model, typos
            // included. Ranked best-first so the cap keeps the likeliest
            // lines, not the first in storage order.
            switch kind {
            case .routine:
                let all = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
                let matched = fragment.map { q in FuzzySearch.ranked(all, query: q) { $0.name } } ?? all
                return digest(matched.map(routineLine), of: matched.count, kind: "routines", cap: cap, fragment: fragment)

            case .exercise:
                let all = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
                let filtered = all.filter { exercise in
                    if let muscleGroup, exercise.muscleGroup != muscleGroup { return false }
                    if inLibraryOnly, !exercise.inLibrary { return false }
                    return true
                }
                let matched = fragment.map { q in FuzzySearch.ranked(filtered, query: q) { $0.name } } ?? filtered
                return digest(matched.map(exerciseLine), of: matched.count, kind: "exercises", cap: cap, fragment: fragment)

            case .superset:
                let all = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
                var lines: [String] = []
                for routine in all {
                    for group in routine.sortedGroups where group.isSuperset {
                        let names = group.sortedExercises.compactMap { $0.exercise?.name }
                        lines.append("\(routine.name): \(names.joined(separator: " + ")) · \(group.sets) sets")
                    }
                }
                if let fragment {
                    lines = FuzzySearch.ranked(lines, query: fragment) { $0 }
                }
                return digest(lines, of: lines.count, kind: "supersets", cap: cap, fragment: fragment)

            case .library:
                let all = try context.fetch(FetchDescriptor<EquipmentLibrary>(sortBy: [SortDescriptor(\.order)]))
                let active = EquipmentLibrary.active(in: all)
                let matched = fragment.map { q in FuzzySearch.ranked(all, query: q) { $0.name } } ?? all
                let lines = matched.map { library in
                    "\(library.name) · \(library.members.count) item\(library.members.count == 1 ? "" : "s")\(library === active ? " · active" : "")"
                }
                return digest(lines, of: matched.count, kind: "libraries", cap: cap, fragment: fragment)
            }
        } catch {
            return "could not read data"
        }
    }

    private func routineLine(_ routine: Routine) -> String {
        let exerciseCount = routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        // shortLabel is THE schedule vocabulary (cards, detail header,
        // widget caption) — Operator must speak the same dialect.
        return "\(routine.name) · \(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s") · \(routine.schedule.shortLabel) · \(routine.estimateText)"
    }

    private func exerciseLine(_ exercise: Exercise) -> String {
        let profile = exercise.metricProfile
        let tracked = TrackMode.allCases.first { $0.matches(profile) }
        let trackedText = tracked?.spokenName ?? profile.metrics.map(\.rawValue).joined(separator: "+")
        var parts = [exercise.name, exercise.muscleGroup.displayName.lowercased(), trackedText]
        if !exercise.inLibrary { parts.append("catalog only") }
        return parts.joined(separator: " · ")
    }

    private func digest(_ lines: [String], of total: Int, kind: String, cap: Int, fragment: String?) -> String {
        guard total > 0 else {
            return "no matches\(fragment.map { " for \"\($0)\"" } ?? "") in \(kind)"
        }
        let shown = lines.prefix(cap)
        let header = "\(shown.count) of \(total) \(kind):"
        return ([header] + shown).joined(separator: "\n")
    }

    // MARK: - get_stats

    enum StatKind: String {
        case workoutCount, lastDone, setVolume, streak
    }

    func stats(kind: StatKind, exerciseName: String? = nil, routineName: String? = nil, days: Int? = nil) -> String {
        do {
            let sessions = try context.fetch(
                FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            ).filter { $0.endedAt != nil }
            // A typo'd or half-remembered routine name resolves to ONE
            // canonical history name first (forgiving lookup, exact
            // scoping): the count stays precise and the reply speaks the
            // canonical name, never a blend of near-matches. Unresolved
            // names keep the raw text and honestly count zero. Sessions
            // are newest-first, so ties resolve to the recent name.
            let scopeName = routineName.map { name in
                FuzzySearch.bestMatch(query: name, in: distinct(sessions.map(\.routineName))) ?? name
            }
            let scoped = scopeName.map { name in
                sessions.filter { $0.routineName.compare(name, options: .caseInsensitive) == .orderedSame }
            } ?? sessions

            switch kind {
            case .workoutCount:
                let window = days ?? 30
                let cutoff = calendar.date(byAdding: .day, value: -window, to: today()) ?? today()
                let count = scoped.filter { $0.startedAt >= cutoff }.count
                let scope = scopeName.map { " of \($0)" } ?? ""
                return "workouts\(scope) in last \(window) days: \(count)"

            case .lastDone:
                if let exerciseName {
                    // `scoped`, not `sessions`: a routineName alongside
                    // the exercise narrows the search to that routine.
                    return lastDoneExercise(named: exerciseName, sessions: scoped)
                }
                guard let last = scoped.first else {
                    return "no finished workouts\(scopeName.map { " of \($0)" } ?? "") yet"
                }
                return "\(last.routineName) last done \(dateText(last.startedAt)) · \(last.completedSetLogs.count) sets logged"

            case .setVolume:
                let window = days ?? 30
                let cutoff = calendar.date(byAdding: .day, value: -window, to: today()) ?? today()
                let windowLogs = scoped.filter { $0.startedAt >= cutoff }
                    .flatMap(\.completedSetLogs)
                // Same rule as the routine scope: resolve to one
                // canonical exercise, count only it — "benchpres" must
                // never sum Bench Press AND Incline Bench Press.
                let exercise = exerciseName.map { name in
                    FuzzySearch.bestMatch(query: name, in: distinct(windowLogs.map(\.exerciseName))) ?? name
                }
                let logs = exercise.map { name in
                    windowLogs.filter { $0.exerciseName.compare(name, options: .caseInsensitive) == .orderedSame }
                } ?? windowLogs
                let scope = exercise.map { " of \($0)" } ?? ""
                return "completed sets\(scope) in last \(window) days: \(logs.count)"

            case .streak:
                return streakText(sessions: sessions)
            }
        } catch {
            return "could not read history"
        }
    }

    private func lastDoneExercise(named name: String, sessions: [WorkoutSession]) -> String {
        for session in sessions {
            // Resolve within the session to ONE canonical name before
            // counting — a loose match must not sum sets across, say,
            // Bench Press and Overhead Press in the same session.
            let byName = Dictionary(grouping: session.completedSetLogs, by: \.exerciseName)
            guard let canonical = FuzzySearch.bestMatch(query: name, in: byName.keys.sorted()),
                  let logs = byName[canonical], !logs.isEmpty else { continue }
            var line = "\(canonical) last done \(dateText(session.startedAt)) · \(logs.count) sets"
            if let topWeight = logs.compactMap(\.actualWeight).max() {
                line += " · top \(trimmedNumber(topWeight))"
            }
            return line
        }
        return "no logged sets of \(name) yet"
    }

    /// First-appearance-ordered unique names, so bestMatch ties break
    /// toward the caller's ordering (newest history first).
    private func distinct(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// Streak = the ONE shared rule (`WidgetSnapshot.streak`), fed weekly
    /// buckets keyed by each session's END date exactly like
    /// `WidgetSnapshotWriter` — so the number Operator says and the
    /// number on the home-screen widget can never disagree. (The shared
    /// rule already holds through an empty current week: a quiet Monday
    /// is not a lapse.)
    private func streakText(sessions: [WorkoutSession]) -> String {
        guard !sessions.isEmpty else { return "no finished workouts yet" }
        let now = today()
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        var countsByWeeksAgo: [Int: Int] = [:]
        for session in sessions {
            guard let ended = session.endedAt else { continue }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: ended)?.start ?? ended
            let weeksAgo = calendar.dateComponents([.weekOfYear], from: weekStart, to: currentWeekStart).weekOfYear ?? .max
            guard weeksAgo >= 0 else { continue }
            countsByWeeksAgo[weeksAgo, default: 0] += 1
        }
        guard let oldest = countsByWeeksAgo.keys.max() else { return "no workouts in recent weeks" }
        let weeklyCounts = (0...oldest).reversed().map { countsByWeeksAgo[$0] ?? 0 }
        let weeks = WidgetSnapshot.streak(fromWeeklyCounts: weeklyCounts)
        guard weeks > 0 else { return "no workouts in recent weeks" }
        return "current streak: \(weeks) week\(weeks == 1 ? "" : "s") with a workout"
    }

    private func dateText(_ date: Date) -> String {
        let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: today())).day ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        // The formatter formats in ITS OWN zone regardless of the
        // calendar's; without this the absolute date and the relative
        // day count can disagree across the date line.
        formatter.timeZone = calendar.timeZone
        let absolute = formatter.string(from: date)
        let relative = switch daysAgo {
        case 0: "today"
        case 1: "yesterday"
        default: "\(daysAgo) days ago"
        }
        return "\(absolute) (\(relative))"
    }

    private func trimmedNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
