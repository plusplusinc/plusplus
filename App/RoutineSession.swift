import Observation
import OSLog
import WorkoutStore

/// The routine open on screen, which screen shows, and the switch to another routine.
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
    /// The saved routines, latest first, as of the last read, with each routine left since.
    private var saved: [Routine] = []
    private var isSwitching = false

    /// Nil when the store didn't open: switching works in memory, and nothing saves.
    @ObservationIgnored private let store: RoutineStore?
    /// Where every change to the routine goes, to be saved one at a time in the order they
    /// happened, so an older version can never land last. Only the newest unsaved one waits.
    @ObservationIgnored private var saves: AsyncStream<Routine>.Continuation
    @ObservationIgnored private var saving: Task<Void, Never>

    init(routine: Routine, store: RoutineStore?) {
        opened = routine
        current = routine
        self.store = store
        (saves, saving) = Self.startSaving(to: store)
    }

    enum Screen {
        case routine
        case routines
    }

    /// Every saved routine, latest first, with the open one first as it is now.
    var recent: [Routine] {
        saved.withOpen(current)
    }

    /// Saves a change to the open routine.
    func save(_ routine: Routine) {
        current = routine
        saves.yield(routine)
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

    /// Reads the saved routines again, as the Routines screen and the drawer show.
    func refreshRecent(weightUnit: WeightUnit) async {
        guard let store else { return }
        do {
            saved = try await store.routinesByRecency(weightUnit: weightUnit)
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
                try await store?.save(landed)
            } catch {
                Logger.app.error("The routine didn't save: \(error)")
            }
        }
    }

    private static func startSaving(
        to store: RoutineStore?,
    ) -> (AsyncStream<Routine>.Continuation, Task<Void, Never>) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Routine.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let task = Task {
            for await version in stream {
                do {
                    try await store?.save(version)
                } catch {
                    Logger.app.error("The routine didn't save: \(error)")
                }
            }
        }
        return (continuation, task)
    }
}
