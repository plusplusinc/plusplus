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
public final class RoutineSession {
    /// The routine as it was opened. Changes only on a switch, which gives a fresh screen.
    public private(set) var opened: Routine
    /// The open routine as it is now, edits included.
    public private(set) var current: Routine
    public var isDrawerOpen = false
    /// Where the app is: the routine, the Routines screen, or a routine pushed on it.
    public private(set) var screen = Screen.routine
    /// The workout running the open routine, from Start until Finish or Discard.
    public private(set) var workout: Workout?

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
    /// Names a workout after its routine, at Start and again at Finish.
    @ObservationIgnored private let namer: RoutineNamer
    /// Where every change to the routine goes, to be saved one at a time in the order they
    /// happened, so an older version can never land last. Only the newest unsaved one waits.
    @ObservationIgnored private var saves: AsyncStream<RoutineSave>.Continuation
    @ObservationIgnored private var saving: Task<Void, Never>
    /// Where every change to a workout goes, saved in the order they happened. Every one waits
    /// its turn: one workout's end and the next one's start can both be waiting, and keeping
    /// only the newest would drop the end, leaving the first in progress in the store.
    @ObservationIgnored private let workoutWrites: AsyncStream<WorkoutWrite>.Continuation

    public init(
        routine: Routine,
        workout: Workout? = nil,
        store: RoutineStore?,
        namer: RoutineNamer,
    ) {
        self.namer = namer
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
        /// Every write before it has landed.
        case landed(CheckedContinuation<Void, Never>)
    }

    /// Where the app is, under the drawer.
    public enum Screen {
        /// The open routine, at the root.
        case routine
        /// The Routines screen, its list showing.
        case routines
        /// The open routine, pushed onto the Routines screen from its list.
        case pushedRoutine
    }

    /// Whether the open routine is pushed onto the Routines screen: the binding its navigation
    /// stack presents the routine with. The back button and the back swipe set it false,
    /// showing the list again. Setting it true does nothing: a push goes through `open` or
    /// `startNew`.
    public var isRoutinePushed: Bool {
        get { screen == .pushedRoutine }
        set {
            if !newValue, screen == .pushedRoutine {
                screen = .routines
            }
        }
    }

    /// Every saved routine, latest first, with the open one first as it is now.
    public var recent: [Routine] {
        saved.withOpen(current)
    }

    /// The drawer's routines: the `count` latest opened or edited, the last edited first, so
    /// opening one never moves it.
    public func recentByEdit(first count: Int) -> [Routine] {
        recent.lastEdited(first: count, editedAt: editedAt)
    }

    /// Saves a change to the open routine.
    public func save(_ routine: Routine) {
        current = routine
        editedAt[routine.id] = .now
        saves.yield(RoutineSave(routine: routine, keepsEmpty: workout != nil))
    }

    /// While a workout runs, the drawer stays shut: neither ++ nor the edge swipe opens it.
    public var isDrawerLocked: Bool {
        workout != nil
    }

    /// Starts a workout on the open routine, shown at the root, so no back button or swipe
    /// leaves it, named as the routine shows now.
    public func start(at now: Date = .now) {
        guard workout == nil else { return }
        // The workout first: a screen shown at the root reads it as it is made, to open on the
        // current exercise.
        let started = Workout(routineID: current.id, routineName: shownName, startedAt: now)
        workout = started
        workoutWrites.yield(.save(started))
        if screen != .routine {
            // A fresh screen at the root, opening on the routine as it is now.
            opened = current
            screen = .routine
        }
        isDrawerOpen = false
    }

    /// The name the open routine shows, which a workout on it keeps: empty for New routine.
    private var shownName: String {
        namer.shownName(of: current) ?? ""
    }

    /// Pauses the workout, or resumes it if paused.
    public func togglePause(at now: Date = .now) {
        guard let workout else { return }
        let changed = workout.isPaused ? workout.resuming(at: now) : workout.pausing(at: now)
        self.workout = changed
        workoutWrites.yield(.save(changed))
    }

    /// Logs `planned`, a set of `row`, at the numbers `row` plans now.
    public func log(_ planned: PlannedSet, of row: RoutineExercise, at now: Date = .now) {
        guard let workout else { return }
        let logged = workout.logging(planned, of: row, at: now)
        self.workout = logged
        workoutWrites.yield(.save(logged))
    }

    /// Finishes the workout, keeping it with the name the routine shows now.
    public func finish(at now: Date = .now) {
        guard let workout else { return }
        var finished = workout.finishing(at: now)
        finished.routineName = shownName
        self.workout = nil
        workoutWrites.yield(.save(finished))
        deleteIfCleared()
    }

    /// Ends the workout keeping nothing of it, as if Start never ran.
    public func discard() {
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
    public var showing: Showing {
        if screen == .routines {
            return .routines
        }
        return current.isEmpty ? .new : .routine
    }

    public enum Showing {
        case routines
        case routine
        case new
    }

    /// Reads the saved routines again, for the Routines screen and the drawer's next opening.
    /// A read that fails leaves the last one, to be tried again at the next refresh; one that
    /// started before a switch is dropped, since it may be missing the routine left.
    public func refreshRecent(weightUnit: WeightUnit) async {
        guard let store else { return }
        let switchesBefore = switches
        do {
            let read = try await store.routinesByRecency(weightUnit: weightUnit)
            guard switches == switchesBefore else { return }
            saved = read.routines
            // An edit still on its way to the store is newer than what it read.
            editedAt.merge(read.editedAt, uniquingKeysWith: max)
        } catch {
            Logger.session.error("The recent routines didn't load: \(error)")
        }
    }

    /// Shows the Routines screen and closes the drawer.
    public func showRoutines() {
        screen = .routines
        closeDrawer()
    }

    /// Opens a saved routine on the routine screen and closes the drawer, or, `pushed`, pushes
    /// it onto the Routines screen. The open one shows as it is now, edits included.
    public func open(_ id: Routine.ID, weightUnit: WeightUnit, pushed: Bool = false) async {
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
                Logger.session.error("The routine didn't open: \(error)")
                return nil
            }
        }
    }

    /// Opens a new, empty routine on the routine screen and closes the drawer, or, `pushed`,
    /// pushes it onto the Routines screen; an empty one open already is shown as it is. Nothing
    /// is saved for the new routine until it changes.
    public func startNew(pushed: Bool = false) async {
        guard !isSwitching else { return }
        guard !current.isEmpty else {
            show(current, pushed: pushed)
            return closeDrawer()
        }
        await switchTo(pushed: pushed) { Routine() }
    }

    /// Lets the last edit land, then shows the routine `next` gives, if any, and closes the
    /// drawer. An edit made while `next` runs lands before the next routine shows, too. A switch
    /// already under way takes the tap. Internal so a test can hold `next`.
    func switchTo(pushed: Bool, _ next: () async -> Routine?) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        await finishSaving()
        let routine = await next()
        await finishSaving()
        if let routine {
            show(routine, pushed: pushed)
        }
        closeDrawer()
    }

    private func show(_ routine: Routine, pushed: Bool) {
        // The routine left stays in the list at its place, before its last save reads back.
        saved = recent
        switches += 1
        opened = routine
        current = routine
        screen = pushed ? .pushedRoutine : .routine
    }

    private func closeDrawer() {
        isDrawerOpen = false
    }

    /// Lets the last edit land: a finished stream still hands over what it holds. An edit made
    /// while it lands reaches only `current`, so it is saved after. Then saving starts again, so
    /// no edit ever goes to a finished stream.
    private func finishSaving() async {
        var landed = current
        saves.finish()
        await saving.value
        while current != landed {
            landed = current
            do {
                try await store?.save(landed, keepsEmpty: workout != nil)
            } catch {
                Logger.session.error("The routine didn't save: \(error)")
            }
        }
        (saves, saving) = Self.startSaving(to: store)
    }

    /// Returns once every change sent so far has landed in the store: the routine's edits, as a
    /// switch lets them land, then the workout's writes, in their order. For tests, which wait on
    /// it rather than on time.
    func writesLanded() async {
        await finishSaving()
        await withCheckedContinuation { done in workoutWrites.yield(.landed(done)) }
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
                    Logger.session.error("The routine didn't save: \(error)")
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
                    case let .landed(done): done.resume()
                    }
                } catch {
                    Logger.session.error("The workout didn't save: \(error)")
                }
            }
        }
        return continuation
    }
}
