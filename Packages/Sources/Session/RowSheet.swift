import WorkoutStore

/// A row's open sheet: which row, and whether it opens on Customize, as after Create. The flag
/// rides with the sheet's item: a separate state set with it read as unset in the sheet.
public struct RowSheet: Identifiable, Equatable {
    public let id: RoutineExercise.ID
    public var opensCustomizing: Bool

    public init(id: RoutineExercise.ID, opensCustomizing: Bool = false) {
        self.id = id
        self.opensCustomizing = opensCustomizing
    }
}

extension RoutineSession {
    /// Opens `sheet` once `hold` has passed, as a created row's does, if `wanted()` still says so
    /// then. Nothing opens if the wait is cancelled, as when the screen that asked goes and its
    /// task with it, or the app has left that screen or routine meanwhile: a routine popped off
    /// the Routines screen goes some 0.3 s after the pop, and a sheet set in between, with
    /// nothing to show it, kept the drawer shut on the Routines screen.
    public func openRowSheet(
        _ sheet: RowSheet,
        after hold: Duration,
        if wanted: () -> Bool,
    ) async {
        let screen = screen
        let routine = opened.id
        // A sleep that had already ended when it was cancelled resumes without throwing.
        guard await (try? Task.sleep(for: hold, tolerance: .zero)) != nil, !Task.isCancelled,
              wanted(), self.screen == screen, opened.id == routine else { return }
        openRowSheet(sheet)
    }
}
