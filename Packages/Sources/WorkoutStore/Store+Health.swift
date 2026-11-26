import Foundation
import OSLog
import SwiftData

/// What Apple Health is owed, read from the stored workouts alone: no list is kept beside them.
extension Store {
    /// Every finished logged workout Health has no id for and can have as it is
    /// (`LoggedWorkout.healthWithheld`), the earliest finish first, a tie by id. Each withheld
    /// one stays stored without an id, so every catch-up looks at it again.
    public func owedToHealth() throws -> [LoggedWorkout] {
        let unsent = FetchDescriptor<StoredWorkout>(
            predicate: #Predicate { $0.endedAt != nil && $0.healthWorkoutID == nil },
            sortBy: [SortDescriptor(\.endedAt), SortDescriptor(\.id)],
        )
        let read = try modelContext.fetch(unsent).map(\.loggedWorkout)
        let owed = read.filter { $0.healthWithheld == nil }
        if owed.count < read.count {
            Logger.storage.notice("\(read.count - owed.count) workouts withheld from Apple Health")
        }
        return owed
    }

    /// Keeps `healthID` as the Health workout saved for the logged workout `id`; nothing if it
    /// is gone. The one write of the id: a save of a logged workout never changes it.
    public func markInHealth(_ id: LoggedWorkout.ID, as healthID: UUID) throws {
        guard let stored = try storedLoggedWorkout(id: id) else { return }
        stored.update(\.healthWorkoutID, to: healthID)
        try modelContext.save()
    }
}
