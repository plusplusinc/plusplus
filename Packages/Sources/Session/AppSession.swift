import Foundation
import Observation
import OSLog
import WorkoutStore

/// The workout open on screen, which screen shows, the switch to another workout, and the
/// logged workout in progress on it.
///
/// It owns saving, so a switch can wait for the last edit to land before opening the next
/// workout: an edit just before a switch is never lost, and the workout opened is newer than
/// the one left.
@Observable
public final class AppSession {
    /// The workout as it was opened. Changes only on a switch, which gives a fresh screen.
    public private(set) var opened: Workout
    /// The open workout as it is now, edits included.
    public private(set) var current: Workout
    /// Opened by `openDrawer()`, which a workout in progress refuses; shut by `closeDrawer()`.
    public private(set) var isDrawerOpen = false
    /// The workout screen's open sheets, a row's and Add exercise, each through its open and close.
    public private(set) var rowSheet: RowSheet?
    public internal(set) var addExercise: AddExerciseSheet?
    /// A finger holds the drawer, through `holdDrawer(_:)`: a swipe under way.
    public private(set) var isDrawerHeld = false
    /// Where `show(_:throughDrawer:markWait:)` moved the drawer's mark, kept through the close
    /// until the drawer next shows; nil otherwise, when it marks what showed as it opened.
    public internal(set) var drawerMark: Showing?
    /// A way through the drawer's beats under way, which whatever closes it ends, and its place.
    @ObservationIgnored var throughDrawer: Task<Void, Never>?
    @ObservationIgnored var throughDrawerPlace: Showing?
    /// The clock those beats sleep on: a test steps its own.
    @ObservationIgnored var beatClock: any Clock<Duration> = ContinuousClock()
    /// Where the app is, under the drawer (`Screen`).
    public internal(set) var screen = Screen.workout
    /// The finished logged workouts as of the last read (`refreshLog()`); nil until the first.
    public internal(set) var log: WorkoutLog?
    /// The logged workout in progress on the open workout, from Start until Finish or Discard.
    public private(set) var loggedWorkout: LoggedWorkout?
    /// Every exercise there is to pick, the ones created this session included.
    public internal(set) var exercises: ExerciseList
    /// The exercises whose delete is confirmed and not yet stored
    /// (`deleteExercise(_:weightUnit:once:)`). Read only by taps, never by a view's body.
    @ObservationIgnored var deleting: Set<Exercise.ID> = []

    /// The saved workouts, latest first, as of the last read, with each workout left since.
    private var saved: [Workout] = []
    private var isSwitching = false
    /// How many times the workout showing or the list has changed, so a read that one overtook
    /// is dropped.
    @ObservationIgnored private var switches = 0

    /// Nil when the store didn't open: switching works in memory, and nothing saves.
    @ObservationIgnored let store: Store?
    /// Names a logged workout after its workout, at Start and again at Finish.
    @ObservationIgnored private let namer: WorkoutNamer
    /// Where every change to the workout goes, to be saved one at a time in the order they
    /// happened, so an older version can never land last. Only the newest unsaved one waits.
    @ObservationIgnored private var saves: AsyncStream<WorkoutSave>.Continuation
    @ObservationIgnored private var saving: Task<Void, Never>
    /// Where every change to a logged workout goes, saved in the order they happened. Each
    /// waits its turn: one logged workout's end and the next one's start can both be waiting,
    /// and keeping only the newest would drop the end, leaving the first in progress in the store.
    @ObservationIgnored
    let loggedWorkoutWrites: AsyncStream<LoggedWorkoutQueueEntry>.Continuation

    public init(
        workout: Workout,
        loggedWorkout: LoggedWorkout? = nil,
        exercises: ExerciseList = .builtIn,
        store: Store?,
        namer: WorkoutNamer,
    ) {
        self.namer = namer
        opened = workout
        current = workout
        self.loggedWorkout = loggedWorkout
        self.exercises = exercises
        self.store = store
        (saves, saving) = Self.startSaving(to: store)
        loggedWorkoutWrites = Self.startWritingLoggedWorkouts(to: store)
    }

    /// Every saved workout, latest first, with the open one first as it is now.
    public var recent: [Workout] {
        saved.withOpen(current)
    }

    /// Saves a change to the open workout.
    public func save(_ workout: Workout) {
        current = workout
        saves.yield(WorkoutSave(workout: workout, keepsEmpty: loggedWorkout != nil))
    }

    /// While a workout is in progress, the drawer stays shut: neither ++ nor a swipe opens it.
    public var isDrawerLocked: Bool {
        loggedWorkout != nil
    }

    /// Opens the drawer, unless one in progress keeps it shut or a row's sheet has been asked for.
    public func openDrawer() {
        guard !isDrawerLocked, rowSheet == nil else { return }
        startShowingDrawer()
        isDrawerOpen = true
    }

    /// Opens a row's sheet, unless the drawer is open or a finger holds it. The drawer and a
    /// row's sheet keep each other out, whichever was asked for first: the sheet covers ++ only
    /// once it starts to rise, a frame or more after it is asked for, and a ++ in between, as
    /// when a created row's sheet came up on its own, opened the drawer under it; a swipe under
    /// way asks for the drawer as ++ does, and a sheet rising mid-swipe left the drawer drawn
    /// open under it.
    ///
    /// Only a row the open workout has, of an exercise not being deleted (`isDeleting(_:)`),
    /// opens: a row tapped as it left, its removal already stored, opened an empty sheet that
    /// kept the drawer shut until swiped down, and one whose delete is confirmed would show a
    /// form for an exercise on its way out. The same ask again keeps the opening already asked
    /// for, so a double tap doesn't build the rising sheet again.
    public func openRowSheet(_ sheet: RowSheet) {
        guard !isDrawerOpen, !isDrawerHeld, canOpenSheet(of: sheet.id) else { return }
        if let rowSheet, rowSheet.id == sheet.id,
           rowSheet.opensCustomizing == sheet.opensCustomizing
        {
            return
        }
        rowSheet = sheet
    }

    /// Whether a finger holds the drawer, as the edge swipe brings it in.
    public func holdDrawer(_ held: Bool) {
        if held {
            startShowingDrawer()
        }
        isDrawerHeld = held
    }

    public func closeRowSheet() {
        rowSheet = nil
    }

    /// Closes the drawer. Mid-way through `show(_:throughDrawer:markWait:)`, as at its end or
    /// as a tap beside the drawer or a swipe closes it, the place it was going to swaps in first.
    public func closeDrawer() {
        if let place = throughDrawerPlace {
            endThroughDrawer()
            land(on: place)
        }
        isDrawerOpen = false
    }

    /// Starts a logged workout on `workout`, shown at the root, so no back button or swipe leaves
    /// it, named as the workout shows now, when `canStart(on:)` allows it.
    public func start(on workout: Workout.ID, at now: Date = .now) {
        guard canStart(on: workout) else { return }
        // The logged workout first: a screen shown at the root reads it as it is made, to open
        // on the current exercise.
        // A timed first set's "Starts in" begins as the screen lands on it (`beginCount`).
        change(.save(LoggedWorkout(workoutID: workout, workoutName: shownName, startedAt: now)))
        if screen != .workout {
            // A fresh screen at the root, opening on the workout as it is now.
            opened = current
            screen = .workout
        }
        closeDrawer()
    }

    /// Whether a Start pressed on `workout` may still start: only on the open workout, once it
    /// has an exercise, with none in progress and no switch under way. A workout switched away
    /// from, or being switched away from, starts nothing: the switch stops Start.
    public func canStart(on workout: Workout.ID) -> Bool {
        loggedWorkout == nil && !isSwitching && workout == current.id && !current.exercises.isEmpty
    }

    /// The name the open workout shows, which its logged workout keeps: empty for New workout.
    private var shownName: String {
        namer.shownName(of: current) ?? ""
    }

    /// Pauses the workout, or resumes it if paused.
    public func togglePause(at now: Date = .now) {
        guard let loggedWorkout else { return }
        change(.save(
            loggedWorkout.isPaused
                ? loggedWorkout.resuming(at: now)
                : loggedWorkout.pausing(at: now),
        ))
    }

    /// Logs `planned`, a set of `row`, at the numbers `row` plans now, or a timed set at the time
    /// its count has run (`LiveWorkout.logging`).
    public func log(_ planned: PlannedSet, of row: WorkoutExercise, at now: Date = .now) {
        guard let loggedWorkout else { return }
        let live = LiveWorkout(workout: current, loggedWorkout: loggedWorkout)
        change(.save(live.logging(planned, of: row, at: now)))
    }

    /// Extends the rest running after the last set by `seconds`, unless it is over. `override`,
    /// for the UI tests, is every rest's length (`LiveWorkout.rest(override:)`).
    public func extendRest(by seconds: Int, override: Int? = nil, at now: Date = .now) {
        changeLive { $0.extendingRest(by: seconds, override: override, at: now) }
    }

    /// Ends the rest running after the last set now, unless it is over
    /// (`LiveWorkout.skippingRest(override:at:)`).
    public func skipRest(override: Int? = nil, at now: Date = .now) {
        changeLive { $0.skippingRest(override: override, at: now) }
    }

    /// Finishes the logged workout, keeping it with the name the workout shows now, and a timed
    /// set counting logged at the time done (`LiveWorkout.finishing(at:)`).
    public func finish(at now: Date = .now) {
        guard let loggedWorkout else { return }
        var finished = LiveWorkout(workout: current, loggedWorkout: loggedWorkout)
            .finishing(at: now)
        finished.workoutName = shownName
        change(.save(finished))
        deleteIfCleared()
    }

    /// Ends the workout keeping nothing of it, as if Start never ran.
    public func discard() {
        guard let loggedWorkout else { return }
        change(.discard(loggedWorkout.id))
        deleteIfCleared()
    }

    /// The one way the logged workout changes: to what `write` stores, sent to be stored in the
    /// same call, so no change shows that a relaunch would lose. One saved in progress is the
    /// one running; one saved ended, or discarded, leaves none.
    func change(_ write: LoggedWorkoutWrite) {
        switch write {
        case let .save(changed): loggedWorkout = changed.isInProgress ? changed : nil
        case .discard: loggedWorkout = nil
        }
        loggedWorkoutWrites.yield(.write(write))
    }

    /// A workout cleared to nothing while in progress was kept; once it ends, it is deleted, as
    /// any cleared workout is.
    private func deleteIfCleared() {
        if current.isEmpty {
            saves.yield(WorkoutSave(workout: current, keepsEmpty: false))
        }
    }

    /// Reads the saved workouts again, for the Workouts screen and the Customize form's Used in.
    /// A read that fails leaves the last one, to be tried again at the next refresh; one that
    /// started before a switch is dropped, since it may be missing the workout left.
    public func refreshRecent(weightUnit: WeightUnit) async {
        guard let store else { return }
        let switchesBefore = switches
        do {
            let read = try await store.workoutsByRecency(weightUnit: weightUnit)
            guard switches == switchesBefore else { return }
            saved = read
        } catch {
            Logger.session.error("The recent workouts didn't load: \(error)")
        }
    }

    /// Pushes a saved workout onto the Workouts screen. The open one shows as it is now, edits
    /// included.
    public func open(_ id: Workout.ID, weightUnit: WeightUnit) async {
        guard !isSwitching else { return }
        guard id != current.id else {
            return show(current)
        }
        guard let store else { return }
        await switchTo {
            do {
                return try await store.openWorkout(id, weightUnit: weightUnit)
            } catch {
                Logger.session.error("The workout didn't open: \(error)")
                return nil
            }
        }
    }

    /// Pushes a new, empty workout onto the Workouts screen; an empty one open already is shown
    /// as it is. Nothing is saved for the new workout until it changes.
    public func startNew() async {
        guard !isSwitching else { return }
        guard !current.isEmpty else {
            return show(current)
        }
        await switchTo { Workout() }
    }

    /// Lets the last edit land, then pushes the workout `next` gives, if any. An edit made while
    /// `next` runs lands before the next workout shows, too. A switch already under way takes
    /// the tap. Internal so a test can hold `next`.
    func switchTo(_ next: () async -> Workout?) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        await finishSaving()
        let workout = await next()
        await finishSaving()
        if let workout {
            show(workout)
        }
    }

    private func show(_ workout: Workout, on shown: Screen = .pushedWorkout) {
        // The workout left stays in the list at its place, before its last save reads back.
        saved = recent
        // A workout put up mid-way ends the way, or its late close would land over it.
        endThroughDrawer()
        switches += 1
        opened = workout
        current = workout
        screen = shown
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
                try await store?.save(landed, keepsEmpty: loggedWorkout != nil)
            } catch {
                Logger.session.error("The workout didn't save: \(error)")
            }
        }
        (saves, saving) = Self.startSaving(to: store)
    }

    /// Returns once every change sent so far has landed in the store: the workout's edits, as a
    /// switch lets them land, then the logged workout's writes, in their order. For tests, which
    /// wait on it rather than on time.
    func writesLanded() async {
        await finishSaving()
        await loggedWorkoutWritesLanded()
    }
}

extension AppSession {
    /// Lets every edit to the open workout land, then stores `change` to the exercises,
    /// and reads the open workout and the saved ones back, so each shows what it did to their
    /// rows. The list takes `listing` only once the change is stored, so a refused or failed
    /// change shows nowhere, and a form on the exercise stays up while it saves. Refused while a
    /// switch is under way, and holds off Start and a switch while it runs. With no store,
    /// nothing changes.
    func changeExercises(
        weightUnit: WeightUnit,
        storing change: (Store) async throws -> Void,
        listing: (ExerciseList) -> ExerciseList,
    ) async {
        guard !isSwitching, let store else { return }
        isSwitching = true
        defer { isSwitching = false }
        await finishSaving()
        do {
            try await change(store)
            exercises = listing(exercises)
            // Gone only if it was left with nothing: it reads as that, under its id.
            current = try await store.workout(current.id, weightUnit: weightUnit)
                ?? Workout(id: current.id, name: current.name)
        } catch {
            Logger.session.error("The exercise change didn't save: \(error)")
        }
        await refreshRecent(weightUnit: weightUnit)
    }
}

extension AppSession {
    /// Whether the open workout has anything to delete: one with nothing saved has none, and
    /// one in progress is not deleted.
    public var canDeleteOpen: Bool {
        !current.isEmpty && loggedWorkout == nil
    }

    /// Deletes a saved workout, its logged workouts staying stored. For the open one, its last
    /// edit lands and the session takes a new, empty workout and shows Workouts, whether the
    /// deleted one was pushed or at the root, before the store deletes it, so no save can bring
    /// it back. Refused for a workout in progress, and while a switch is under way. A
    /// delete that fails leaves the workout listed.
    public func delete(_ id: Workout.ID) async {
        guard !isSwitching, loggedWorkout?.workoutID != id else { return }
        isSwitching = true
        defer { isSwitching = false }
        if id == current.id {
            await finishSaving()
            show(Workout(), on: .workouts)
        }
        do {
            try await store?.deleteWorkout(id)
        } catch {
            Logger.session.error("The workout didn't delete: \(error)")
            return
        }
        // A read of the list the delete overtook still holds the workout: dropped.
        switches += 1
        saved.removeAll { $0.id == id }
    }
}
