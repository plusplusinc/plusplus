import Foundation
import OSLog
import SwiftData

/// What Apple Health is owed, read from the stored workouts alone: no list is kept beside them.
extension Store {
    /// Every finished logged workout Health has no id for and can have as it is
    /// (`LoggedWorkout.healthWithheld`), the earliest finish first, a tie by id. Each withheld
    /// one stays stored without an id, so every catch-up looks at it again. The sets come in the
    /// same fetch: a workout with no stored type takes its type from them.
    public func owedToHealth() throws -> [LoggedWorkout] {
        var unsent = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.healthWorkoutID == nil },
            sortBy: [SortDescriptor(\.endedAt), SortDescriptor(\.id)],
        )
        unsent.relationshipKeyPathsForPrefetching = [\.sets]
        let read = try modelContext.fetch(unsent).map(\.loggedWorkout)
        let owed = read.filter { $0.healthWithheld == nil }
        if owed.count < read.count {
            Logger.storage.notice("\(read.count - owed.count) workouts withheld from Apple Health")
        }
        return owed
    }

    /// Which of the logged workouts `ids` the store still holds: a delete of one of these never
    /// landed.
    public func heldLoggedWorkouts(among ids: [LoggedWorkout.ID]) throws -> Set<LoggedWorkout.ID> {
        let held =
            FetchDescriptor<StoredWorkoutSession>(predicate: #Predicate { ids.contains($0.id) })
        return try Set(modelContext.fetch(held).map(\.id))
    }

    /// Keeps `healthID` as the Health workout saved for the logged workout `id`; nothing if it
    /// is gone. The one write of the id: a save of a logged workout never changes it.
    public func markInHealth(_ id: LoggedWorkout.ID, as healthID: UUID) throws {
        guard let stored = try storedLoggedWorkout(id: id) else { return }
        stored.update(\.healthWorkoutID, to: healthID)
        try modelContext.save()
    }
}
