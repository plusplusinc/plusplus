import Observation
import OSLog
import WorkoutStore

/// The routine open on screen, and the switch to another from the drawer.
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
    /// The saved routines, latest first, as of the drawer's last opening.
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

    /// Every saved routine, latest first, with the open one first as it is now.
    var recent: [Routine] {
        saved.withOpen(current)
    }

    /// Saves a change to the open routine.
    func save(_ routine: Routine) {
        current = routine
        saves.yield(routine)
    }

    /// Reads the saved routines again, as the drawer opens.
    func refreshRecent(weightUnit: WeightUnit) async {
        guard let store else { return }
        do {
            saved = try await store.routinesByRecency(weightUnit: weightUnit)
        } catch {
            Logger.app.error("The recent routines didn't load: \(error)")
        }
    }

    /// Opens a saved routine and closes the drawer; on the open one, only closes it.
    func open(_ id: Routine.ID, weightUnit: WeightUnit) async {
        guard id != current.id else { return closeDrawer() }
        guard let store, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        await finishSaving()
        do {
            if let routine = try await store.openRoutine(id, weightUnit: weightUnit) {
                show(routine)
            }
        } catch {
            Logger.app.error("The routine didn't open: \(error)")
        }
        (saves, saving) = Self.startSaving(to: store)
        closeDrawer()
    }

    /// Opens a new, empty routine and closes the drawer; on an empty one, only closes it.
    /// Nothing is saved for the new routine until it changes.
    func startNew() async {
        guard !current.isEmpty else { return closeDrawer() }
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        await finishSaving()
        show(Routine())
        (saves, saving) = Self.startSaving(to: store)
        closeDrawer()
    }

    private func show(_ routine: Routine) {
        opened = routine
        current = routine
    }

    private func closeDrawer() {
        isDrawerOpen = false
    }

    /// Lets the last edit land: a finished stream still hands over what it holds.
    private func finishSaving() async {
        saves.finish()
        await saving.value
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
