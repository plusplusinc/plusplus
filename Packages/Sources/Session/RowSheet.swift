import Foundation
import WorkoutStore

/// A row's open sheet: which row, and whether it opens on Customize, as after Create. The flag
/// rides with the sheet's item: a separate state set with it read as unset in the sheet.
public struct RowSheet: Identifiable {
    public let id: WorkoutExercise.ID
    public var opensCustomizing: Bool
    /// Whether Customize opens with the name selected to type over, as after a Create with
    /// nothing typed.
    public var namesIt: Bool
    /// This opening's own identity, which the sheet's content takes, so every opening starts
    /// from fresh state. A sheet asked for while the last one was still going down came up with
    /// the last one's state: on the form its Customize had pushed, the last exercise's name in
    /// it (measured on iOS 27, with the system's sheet slowed).
    public let opening = UUID()

    public init(id: WorkoutExercise.ID, opensCustomizing: Bool = false, namesIt: Bool = false) {
        self.id = id
        self.opensCustomizing = opensCustomizing
        self.namesIt = namesIt
    }
}

extension AppSession {
    /// Opens `sheet` once `hold` has passed, as a created row's does, if `wanted()` still says so
    /// then. Nothing opens if the wait is cancelled, as when the screen that asked goes and its
    /// task with it, or the app has left that screen or workout meanwhile: a workout popped off
    /// the Workouts screen goes some 0.3 s after the pop, and a sheet set in between, with
    /// nothing to show it, kept the drawer shut on the Workouts screen.
    public func openRowSheet(
        _ sheet: RowSheet,
        after hold: Duration,
        if wanted: () -> Bool,
    ) async {
        guard await stays(after: hold, if: wanted) else { return }
        openRowSheet(sheet)
    }

    /// Waits out `hold` and says whether `wanted()` still holds and the app is still on the
    /// screen and workout it was on: false if the wait was cancelled, as when the screen that
    /// waits goes and its task with it. `wanted()` is read first, so a change it makes counts.
    func stays(after hold: Duration, if wanted: () -> Bool = { true }) async -> Bool {
        let screen = screen
        let workout = opened.id
        // A sleep that had already ended when it was cancelled resumes without throwing.
        guard await (try? Task.sleep(for: hold, tolerance: .zero)) != nil, !Task.isCancelled
        else { return false }
        return wanted() && self.screen == screen && opened.id == workout
    }
}
