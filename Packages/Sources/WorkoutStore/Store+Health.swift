import Foundation
import OSLog
import SwiftData

/// What Apple Health is owed, read from the stored workouts alone: no list is kept beside them.
extension Store {
    /// Every finished workout session Health has no id for and can have as it is
    /// (`WorkoutSession.healthWithheld`), the earliest finish first, a tie by id. Each withheld
    /// one stays stored without an id, so every catch-up looks at it again. The sets come in the
    /// same fetch: a workout with no stored type takes its type from them.
    public func owedToHealth() throws -> [WorkoutSession] {
        var unsent = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.healthWorkoutID == nil },
            sortBy: [SortDescriptor(\.endedAt), SortDescriptor(\.id)],
        )
        unsent.relationshipKeyPathsForPrefetching = [\.sets]
        let read = try modelContext.fetch(unsent).map(\.workoutSession)
        let owed = read.filter { $0.healthWithheld == nil }
        if owed.count < read.count {
            Logger.storage.notice("\(read.count - owed.count) workouts withheld from Apple Health")
        }
        return owed
    }

    /// Which of the workout sessions `ids` the store still holds: a delete of one of these never
    /// landed.
    public func heldWorkoutSessions(among ids: [WorkoutSession.ID]) throws
        -> Set<WorkoutSession.ID>
    {
        let held =
            FetchDescriptor<StoredWorkoutSession>(predicate: #Predicate { ids.contains($0.id) })
        return try Set(modelContext.fetch(held).map(\.id))
    }

    /// Keeps `healthID` as the Health workout saved for the workout session `id`; nothing if it
    /// is gone. The one write of the id: a save of a workout session never changes it.
    public func markInHealth(_ id: WorkoutSession.ID, as healthID: UUID) throws {
        guard let stored = try storedWorkoutSession(id: id) else { return }
        stored.update(\.healthWorkoutID, to: healthID)
        try modelContext.save()
    }
}
