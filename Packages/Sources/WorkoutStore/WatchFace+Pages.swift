import Foundation

/// The Watch's left page: the workout's name, its time, and how far through it is.
public struct WatchTimePage: Equatable, Sendable {
    public var name: String
    public var time: String
    /// "4 of 9 sets done".
    public var progress: String
    public var isPaused: Bool
    /// Whether End offers Finish: only once a set is logged (`WorkoutSession.offersFinish`).
    public var offersFinish: Bool
}

/// One row of the Watch's right page: the whole workout.
public struct WatchListRow: Equatable, Sendable, Identifiable {
    public enum Dot: Equatable, Sendable {
        case done
        case current
        case toDo
    }

    public var id: WorkoutExercise.ID
    public var name: String
    /// "3 × 12 · done", "Set 2 of 3", "3 × 10 × 25 lb".
    public var detail: String
    public var dot: Dot
}

extension LiveWorkout {
    /// The left page at `now`.
    public func watchTimePage(at now: Date, locale: Locale = .current) -> WatchTimePage {
        let done = workoutSession.sets.count.formatted(.number.locale(locale))
        let total = workout.setOrder.count.formatted(.number.locale(locale))
        return WatchTimePage(
            name: workoutName,
            time: WorkoutSession.elapsedText(workoutSession.elapsed(at: now), locale: locale),
            progress: String(localized: "\(done) of \(total) sets done"),
            isPaused: workoutSession.isPaused,
            offersFinish: workoutSession.offersFinish,
        )
    }

    /// The right page's rows, the current one's detail as the set page's caption reads.
    public func watchList(locale: Locale = .current) -> [WatchListRow] {
        let finished = finishedRows
        let current = currentSet
        return workout.exercises.map { row in
            let plan = row.detailParts(locale: locale).joined(separator: " × ")
            if finished.contains(row.id) {
                return WatchListRow(
                    id: row.id,
                    name: row.exercise.name,
                    detail: plan + " · " + String(localized: "done"),
                    dot: .done,
                )
            }
            if let current, current.row == row.id {
                let word = WorkoutExercise.progressWord(inSuperset: workout.isInSuperset(row.id))
                let round = current.round.formatted(.number.locale(locale))
                let sets = row.plan.sets.formatted(.number.locale(locale))
                return WatchListRow(
                    id: row.id,
                    name: row.exercise.name,
                    detail: "\(word) \(round) of \(sets)",
                    dot: .current,
                )
            }
            return WatchListRow(id: row.id, name: row.exercise.name, detail: plan, dot: .toDo)
        }
    }

    /// The name the workout session keeps, else the workout's.
    var workoutName: String {
        workoutSession.workoutName.isEmpty ? workout.name : workoutSession.workoutName
    }
}

extension LinkEnd {
    /// The finished page's line: "9 sets in 24:10".
    public func summary(locale: Locale = .current) -> String {
        let time = WorkoutSession.elapsedText(.seconds(elapsed), locale: locale)
        let count = sets.formatted(.number.locale(locale))
        return sets == 1 ? String(localized: "1 set in \(time)")
            : String(localized: "\(count) sets in \(time)")
    }
}
