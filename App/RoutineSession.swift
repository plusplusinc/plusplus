import Foundation
import Observation
import OSLog
import WorkoutStore

/// The routine open on screen, which screen shows, the switch to another routine, and the
/// workout running it.
///
/// It owns saving, so a switch can wait for the last edit to land before opening the next
/// routine: an edit just before a switch is never lost, and the routine opened is newer than
/// the one left.
@Observable
final class RoutineSession {
    /// The routine as it was opened. Changes only on a switch, which gives a fresh screen.
    private(set) var opened: Routine
    /// The open routine as it is now, edits included.
    private(set) var current: Routine
    var isDrawerOpen = false
    /// The screen the drawer slides aside: the routine, or the list of routines.
    private(set) var screen = Screen.routine
    /// Whether the open routine is pushed onto the Routines screen, opened from its list. Its
    /// back button and back swipe set this false, showing the list again.
    var isRoutinePushed = false
    /// The workout running the open routine, from Start until Finish or Discard.
    private(set) var workout: Workout?

    /// The saved routines, latest first, as of the last read, with each routine left since.
    private var saved: [Routine] = []
    /// When each routine was last edited, as of the last read, with each edit made since.
    private var editedAt: [Routine.ID: Date] = [:]
    private var isSwitching = false
    /// How many times the routine showing has changed, so a read that a switch overtook is
    /// dropped.
    @ObservationIgnored private var switches = 0

    /// Nil when the store didn't open: switching works in memory, and nothing saves.
    @ObservationIgnored private let store: RoutineStore?
    /// Where every change to the routine goes, to be saved one at a time in the order they
    /// happened, so an older version can never land last. Only the newest unsaved one waits.
    @ObservationIgnored private var saves: AsyncStream<RoutineSave>.Continuation
    @ObservationIgnored private var saving: Task<Void, Never>
    /// Where every change to a workout goes, saved in the order they happened. Every one waits
    /// its turn: one workout's end and the next one's start can both be waiting, and keeping
    /// only the newest would drop the end, leaving the first in progress in the store.
    @ObservationIgnored private let workoutWrites: AsyncStream<WorkoutWrite>.Continuation

    init(routine: Routine, workout: Workout? = nil, store: RoutineStore?) {
        opened = routine
        current = routine
        self.workout = workout
        self.store = store
        (saves, saving) = Self.startSaving(to: store)
        workoutWrites = Self.startWritingWorkouts(to: store)
    }

    /// A routine to save, and whether to keep it once it is empty, as while its workout runs.
    private struct RoutineSave {
        let routine: Routine
        let keepsEmpty: Bool
    }

    private enum WorkoutWrite {
        case save(Workout)
        case discard(Workout.ID)
    }

    enum Screen {
        case routine
        case routines
    }

    /// Every saved routine, latest first, with the open one first as it is now.
    var recent: [Routine] {
        saved.withOpen(current)
    }

    /// The drawer's routines: the `count` latest opened or edited, the last edited first, so
    /// opening one never moves it.
    func recentByEdit(first count: Int) -> [Routine] {
        recent.lastEdited(first: count, editedAt: editedAt)
    }

    /// Saves a change to the open routine.
    func save(_ routine: Routine) {
        current = routine
        editedAt[routine.id] = .now
        saves.yield(RoutineSave(routine: routine, keepsEmpty: workout != nil))
    }

    /// While a workout runs, the drawer stays shut: neither ++ nor the edge swipe opens it.
    var isDrawerLocked: Bool {
        workout != nil
    }

    /// Starts a workout on the open routine, shown at the root, so no back button or swipe
    /// leaves it. `routineName` is the name it shows.
    func start(routineName: String, at now: Date = .now) {
        guard workout == nil else { return }
        // The workout first: a screen shown at the root reads it as it is made, to open on the
        // current exercise.
        let started = Workout(routineID: current.id, routineName: routineName, startedAt: now)
        workout = started
        workoutWrites.yield(.save(started))
        if screen != .routine || isRoutinePushed {
            opened = current
            screen = .routine
            isRoutinePushed = false
        }
        isDrawerOpen = false
    }

    /// Pauses the workout, or resumes it if paused.
    func togglePause(at now: Date = .now) {
        guard let workout else { return }
        let changed = workout.isPaused ? workout.resuming(at: now) : workout.pausing(at: now)
        self.workout = changed
        workoutWrites.yield(.save(changed))
    }

    /// Finishes the workout, keeping it with the name the routine shows now.
    func finish(routineName: String, at now: Date = .now) {
        guard let workout else { return }
        var finished = workout.finishing(at: now)
        finished.routineName = routineName
        self.workout = nil
        workoutWrites.yield(.save(finished))
        deleteIfCleared()
    }

    /// Ends the workout keeping nothing of it, as if Start never ran.
    func discard() {
        guard let workout else { return }
        self.workout = nil
        workoutWrites.yield(.discard(workout.id))
        deleteIfCleared()
    }

    /// A routine cleared to nothing while its workout ran was kept for it; once the workout
    /// ends, it is deleted, as any cleared routine is.
    private func deleteIfCleared() {
        if current.isEmpty {
            saves.yield(RoutineSave(routine: current, keepsEmpty: false))
        }
    }

    /// What the drawer marks as showing: the Routines screen, the open routine, or a new one.
    var showing: Showing {
        if screen == .routines, !isRoutinePushed {
            return .routines
        }
        return current.isEmpty ? .new : .routine
    }

    enum Showing {
        case routines
        case routine
        case new
    }

    /// Reads the saved routines again, for the Routines screen and the drawer's next opening.
    /// A read that fails leaves the last one, to be tried again at the next refresh; one that
    /// started before a switch is dropped, since it may be missing the routine left.
    func refreshRecent(weightUnit: WeightUnit) async {
        guard let store else { return }
        let switchesBefore = switches
        do {
            let read = try await store.routinesByRecency(weightUnit: weightUnit)
            guard switches == switchesBefore else { return }
            saved = read.routines
            // An edit still on its way to the store is newer than what it read.
            editedAt.merge(read.editedAt, uniquingKeysWith: max)
        } catch {
            Logger.app.error("The recent routines didn't load: \(error)")
        }
    }

    /// Shows the Routines screen and closes the drawer.
    func showRoutines() {
        screen = .routines
        isRoutinePushed = false
        closeDrawer()
    }

    /// Opens a saved routine on the routine screen and closes the drawer, or, `pushed`, pushes
    /// it onto the Routines screen. The open one shows as it is now, edits included.
    func open(_ id: Routine.ID, weightUnit: WeightUnit, pushed: Bool = false) async {
        guard !isSwitching else { return }
        guard id != current.id else {
            show(current, pushed: pushed)
            return closeDrawer()
        }
        guard let store else { return }
        await switchTo(pushed: pushed) {
            do {
                return try await store.openRoutine(id, weightUnit: weightUnit)
            } catch {
                Logger.app.error("The routine didn't open: \(error)")
                return nil
            }
        }
    }

    /// Opens a new, empty routine on the routine screen and closes the drawer, or, `pushed`,
    /// pushes it onto the Routines screen; an empty one open already is shown as it is. Nothing
    /// is saved for the new routine until it changes.
    func startNew(pushed: Bool = false) async {
        guard !isSwitching else { return }
        guard !current.isEmpty else {
            show(current, pushed: pushed)
            return closeDrawer()
        }
        await switchTo(pushed: pushed) { Routine() }
    }

    /// Lets the last edit land, then shows the routine `next` gives, if any, and closes the
    /// drawer. A switch already under way takes the tap.
    private func switchTo(pushed: Bool, _ next: () async -> Routine?) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        await finishSaving()
        if let routine = await next() {
            show(routine, pushed: pushed)
        }
        (saves, saving) = Self.startSaving(to: store)
        closeDrawer()
    }

    private func show(_ routine: Routine, pushed: Bool) {
        // The routine left stays in the list at its place, before its last save reads back.
        saved = recent
        switches += 1
        opened = routine
        current = routine
        screen = pushed ? .routines : .routine
        isRoutinePushed = pushed
    }

    private func closeDrawer() {
        isDrawerOpen = false
    }

    /// Lets the last edit land: a finished stream still hands over what it holds. An edit made
    /// while it lands reaches only `current`, so it is saved after.
    private func finishSaving() async {
        var landed = current
        saves.finish()
        await saving.value
        while current != landed {
            landed = current
            do {
                try await store?.save(landed, keepsEmpty: workout != nil)
            } catch {
                Logger.app.error("The routine didn't save: \(error)")
            }
        }
    }

    private static func startSaving(
        to store: RoutineStore?,
    ) -> (AsyncStream<RoutineSave>.Continuation, Task<Void, Never>) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: RoutineSave.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let task = Task {
            for await version in stream {
                do {
                    try await store?.save(version.routine, keepsEmpty: version.keepsEmpty)
                } catch {
                    Logger.app.error("The routine didn't save: \(error)")
                }
            }
        }
        return (continuation, task)
    }

    private static func startWritingWorkouts(
        to store: RoutineStore?,
    ) -> AsyncStream<WorkoutWrite>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(
            of: WorkoutWrite.self,
            bufferingPolicy: .unbounded,
        )
        Task {
            for await write in stream {
                do {
                    switch write {
                    case let .save(workout): try await store?.save(workout)
                    case let .discard(id): try await store?.discardWorkout(id)
                    }
                } catch {
                    Logger.app.error("The workout didn't save: \(error)")
                }
            }
        }
        return continuation
    }
}
