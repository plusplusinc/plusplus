import Foundation

/// An exercise done in two or more workouts in the last 4 weeks: its top set in the oldest of
/// them and in the newest, and the change between.
public struct ProgressItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// As the newest workout logged it.
    public let name: String
    /// As it is now, for its load; nil for one since deleted.
    public let exercise: Exercise?
    public let isPerSide: Bool
    public let first: TopSet
    public let latest: TopSet
    public let change: Change
    let lastDone: Date
}

extension WorkoutLog {
    /// The days Progress looks back over.
    public static let progressDays = 28

    /// Every exercise in two or more workouts in the last 4 weeks. Gains first, then the rest;
    /// inside each, the most recently done first, a tie A to Z.
    public func progress(in list: ExerciseList, now: Date, calendar: Calendar) -> [ProgressItem] {
        let recent = within(days: Self.progressDays, of: now, calendar: calendar)
        return history(of: recent, in: list)
            .filter { $0.topSets.count >= 2 }
            .map { history in
                let first = history.topSets[0]
                let latest = history.topSets[history.topSets.count - 1]
                return ProgressItem(
                    id: history.id,
                    name: history.name,
                    exercise: history.exercise,
                    isPerSide: history.isPerSide,
                    first: first,
                    latest: latest,
                    change: latest.change(from: first),
                    lastDone: history.lastDone,
                )
            }
            .sorted { one, other in
                if one.change.isUp != other.change.isUp {
                    return one.change.isUp
                }
                if one.lastDone != other.lastDone {
                    return one.lastDone > other.lastDone
                }
                return one.name.localizedStandardCompare(other.name) == .orderedAscending
            }
    }
}
