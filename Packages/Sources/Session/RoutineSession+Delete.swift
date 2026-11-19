import OSLog
import WorkoutStore

extension RoutineSession {
    /// Whether the open routine has anything to delete: one with nothing saved has none, and
    /// the one a workout runs on is not deleted.
    public var canDeleteOpen: Bool {
        !current.isEmpty && workout == nil
    }

    /// Deletes a saved routine, its finished workouts staying stored. The open one is deleted
    /// once its last edit has landed, so no save brings it back, and the session then holds a
    /// new, empty routine and shows the Routines screen, whether the deleted one was pushed or
    /// at the root. Refused for the routine a workout runs on, and while a switch is under way.
    /// A delete that fails leaves everything as it was.
    public func delete(_ id: Routine.ID) async {
        guard !isSwitching, workout?.routineID != id else { return }
        isSwitching = true
        defer { isSwitching = false }
        let isOpen = id == current.id
        // A read of the list started before the delete may still hold the routine: dropped.
        switches += 1
        if isOpen {
            await finishSaving()
        }
        do {
            try await store?.deleteRoutine(id)
        } catch {
            Logger.session.error("The routine didn't delete: \(error)")
            return
        }
        switches += 1
        saved.removeAll { $0.id == id }
        if isOpen {
            let new = Routine()
            opened = new
            current = new
            screen = .routines
        }
    }
}
