import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// Editing the rows: the sheet's binding, moves, deletes, and adds.
extension WorkoutScreen {
    /// The row whose values are open in a sheet, kept by the session, which keeps it and the
    /// drawer apart.
    var editing: RowSheet? {
        session.rowSheet
    }

    /// The row with this id, bound by id rather than by index, so a sheet still showing it
    /// never reads past the end of the rows once it is deleted.
    func row(_ id: WorkoutExercise.ID) -> Binding<WorkoutExercise>? {
        guard let current = workout.exercises.first(where: { $0.id == id }) else { return nil }
        return Binding {
            workout.exercises.first { $0.id == id } ?? current
        } set: { item in
            workout.update(item)
        }
    }

    /// The rest of `id`'s superset, read and stepped on every member; nil for a plain row.
    func roundSteps(of id: WorkoutExercise.ID) -> RoundSteps? {
        guard workout.isInSuperset(id) else { return nil }
        return RoundSteps(
            value: {
                (
                    workout.restAfterRoundText(of: id, locale: locale),
                    workout.spokenRestAfterRound(of: id, locale: locale),
                )
            },
            seconds: { Double(workout.restAfterRound(of: id) ?? 0) },
            canStep: { workout.canStepRestAfterRound(of: id, by: $0) },
            step: { workout.stepRestAfterRound(of: id, by: $0) },
            set: { workout.setRestAfterRound($0, of: id) },
            isAuto: Binding {
                workout.isRoundAuto(of: id)
            } set: { isAuto in
                workout.setRoundAuto(isAuto, of: id)
            },
            change: (workout.exercises.filter { $0.id == id } + workout.partners(of: id))
                .restChange,
        )
    }

    /// Moves a row dropped on the rail, in the rail's transaction, so the order changes as the
    /// card settles into its gap; it saves once, as any change does.
    func move(_ id: WorkoutExercise.ID, to slot: RailSlot<WorkoutExercise.ID>) {
        workout.move(id, to: WorkoutSlot(slot))
    }

    /// Moves a row one place with VoiceOver's Move up or Move down, and says which row it
    /// passed.
    func step(_ id: WorkoutExercise.ID, to slot: WorkoutSlot, wentUp: Bool) {
        withAnimation(.railChange) {
            workout.move(id, to: slot)
        }
        if let announcement = workout.moveAnnouncement(for: id, wentUp: wentUp) {
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// Removes a row. The last one takes Start down and the + with it after `footDelay`: at once
    /// from a swipe, and from the exercise sheet's Remove once the sheet has gone.
    func delete(_ id: WorkoutExercise.ID, footDelay: Duration = .zero) {
        withAnimation(.railChange) {
            workout.remove(id)
        }
        settleFoot(after: footDelay)
    }

    /// A row's sheet, its More menu's Customize… pushing the exercise's form inside it. Each
    /// change shows in the workout behind it as it is stored; a Delete there shuts the sheet,
    /// still on the form, and then takes the exercise's rows (`deleteExercise(_:closing:)`).
    @ViewBuilder
    func exerciseSheet(_ opened: RowSheet) -> some View {
        let id = opened.id
        if let item = row(id) {
            ExerciseSheet(
                item: item,
                partners: workout.partnerNames(of: id),
                parts: workout.sheetParts(of: id),
                rounds: roundSteps(of: id),
                customize: {
                    let exercise = item.wrappedValue.exercise.id
                    CustomizeScreen(
                        id: exercise,
                        session: session,
                        namer: namer,
                        onStored: { showStoredWorkout() },
                        onDelete: { await deleteExercise(exercise, closing: .rowSheet) },
                        focusesName: opened.namesIt,
                    )
                },
                onDelete: { delete(id, footDelay: Self.exerciseSheetGone) },
                opensCustomizing: opened.opensCustomizing,
            )
        }
    }

    /// Add exercise's sheet. A created exercise is stored before its row is added, so the
    /// workout's save that names it lands after it; then the sheet closes and the row goes in as
    /// a pick's does, even if the sheet was swiped down meanwhile, and once it has landed its own
    /// sheet opens on Customize (`showCreated()`). Its list is narrowed by the open workout's
    /// kept filter (`AppSession.addExerciseFilter`), written there as it changes; each opening
    /// is its own otherwise (`AddExerciseSheet.id`), so search starts empty.
    func picker(_ opening: AddExerciseSheet) -> some View {
        ExercisePicker(
            exercises: leavingExercise.map(session.exercises.removing) ?? session.exercises,
            filter: Bindable(session).addExerciseFilter,
            onPick: addPicked,
            // Full height with search (decided 2026-11-17) and with a filter's tap (decided
            // 2026-11-22), in the tap's own transaction: at medium height the sheet went out of
            // sight under a filter's sheet of chips.
            onExpand: { pickerDetent = .large },
            onCreate: { made, needsName in
                let wasIdle = phase == .idle
                let exercise = await session.create(made)
                // Only this opening: swiped down and opened again meanwhile, the new one stays.
                if session.addExercise?.id == opening.id {
                    session.closeAddExercise()
                }
                add(exercise) {
                    createdWait = CreatedWait(row: $0, wasIdle: wasIdle, needsName: needsName)
                }
            },
            deleteMessage: { id in
                DeleteQuestion.message(
                    workoutCount: session.workouts(using: id).count,
                    usedByOpenWorkout: session.openWorkoutUses(id),
                )
            },
            onDelete: { await deleteExercise($0, closing: .nothing) },
            customize: { id, back in
                CustomizeScreen(
                    id: id,
                    session: session,
                    namer: namer,
                    onStored: { showStoredWorkout() },
                    onDelete: { await deleteExercise(id, closing: .pop(back: back)) },
                )
            },
        )
        .id(opening.id)
        // A fixed set: one worked out from `pickerDetent` was read from the opening before.
        .presentationDetents([.medium, .large], selection: $pickerDetent)
    }

    /// Add exercise, up while the session holds an opening; swiped down, it closes there.
    var addExerciseOpening: Binding<AddExerciseSheet?> {
        Binding { session.addExercise } set: {
            if $0 == nil {
                session.closeAddExercise()
            }
        }
    }

    /// Shuts the picker and adds what was picked there. A second tap while the sheet goes down
    /// keeps the first. One whose delete is confirmed, still listed until its row's beat, adds
    /// nothing.
    func addPicked(_ exercise: Exercise) {
        guard session.addExercise != nil, !session.isDeleting(exercise.id) else { return }
        session.closeAddExercise()
        add(exercise)
    }

    /// Adds a picked or created exercise. Its row takes its place at the rail's end as the sheet
    /// starts down, but enters only where it can be seen, and `addPause` after the list comes to
    /// rest there, so the scroll and the row read one after the other: when everything still
    /// fits, `addPause` after the wait that follows the append, as the sheet finishes its
    /// slide; otherwise once the sheet has gone and a scroll to the end (`endScroll`) has
    /// landed with the row's place and the list's end in view. The scroll waits for the row's
    /// place: asked for while the row went in, it stopped at the end the list had before. Once
    /// Start is pressed, it enters where it is, with no scroll: the end is then Start's room
    /// under the list, out of sight, and a scroll to it took the list off the screen just as
    /// Start went to land on the first exercise. `landed` runs once the row has landed.
    func add(_ exercise: Exercise, landed: @escaping (WorkoutExercise.ID) -> Void = { _ in }) {
        let added = ContinuousClock.now
        let row = WorkoutExercise(exercise: exercise, weightUnit: WeightUnit(region: locale))
        arriving = row.id
        entering = row.id
        // Under Start's room or a move's, the row enters where it is (`keepEndInView`).
        endFollow = isMakingRoom ? nil : .waiting
        // The row goes in with no space yet, so nothing moves; its fade, of a row that draws
        // nothing yet, starts the wait for the list's end a moment into the sheet's slide.
        withAnimation(.linear(duration: RailArrival.appendFade)) {
            workout.exercises.append(row)
        }
        settleFoot(after: Self.pickerGone)
        // Beats on deadlines, not this animation's completion, which once never came, and the
        // row stayed arriving for good (`RailArrival`).
        Task {
            await RailArrival.play(pausing: Self.addPause) {
                arriving == row.id
            } reachEnd: {
                await reachEnd(added: added)
            } enter: {
                letArrivingEnter()
            } entered: {
                hasEntered(row)
                landed(row.id)
            }
        }
    }

    /// After Create, `createdHold` after its row has landed, the row's own sheet comes up, as a
    /// tap on the row brings it, already on Customize: the row is seen landing, then its sheet
    /// rises. Not if a sheet is up by then, a later add's row is still going in, or the row has
    /// gone, or Start was pressed since the Create (`wasIdle` and no longer idle): the sheet
    /// rose over the first exercise growing, and the press says the workout comes first. A
    /// Create during a workout still opens it, as a tap on the row there does. The drawer and
    /// the sheet keep each other out as a tap's sheet does (`AppSession.openRowSheet(_:)`).
    /// The wait is the screen's own task (`createdWait`), so it ends with the screen, and the
    /// session drops it if the app has left this screen or workout by then.
    func showCreated() async {
        guard let wait = createdWait else { return }
        let id = wait.row
        await session.openRowSheet(
            RowSheet(id: id, opensCustomizing: true, namesIt: wait.needsName),
            after: Self.createdHold,
        ) {
            editing == nil && session.addExercise == nil && entering == nil && row(id) != nil
                && (!wait.wasIdle || phase == .idle)
        }
        if !Task.isCancelled, createdWait == wait {
            createdWait = nil
        }
    }

    /// Once the picker has gone, scrolls the list to its end, the added row's place, and returns
    /// as the scroll lands, unless the end is in view or Start's room is opening, when it returns
    /// at once, the room leaving the in-step scroll off (`keepEndInView`). On deadlines, not the
    /// scroll's
    /// completion or its phase: the phase reported idle only about 0.3 s after the list had
    /// stopped, and the row waited on a still list.
    private func reachEnd(added: ContinuousClock.Instant) async {
        guard !isMakingRoom else { return }
        endFollow = .ready
        guard !isEndInView else { return }
        try? await Task.sleep(until: added + Self.pickerGone, tolerance: .zero, clock: .continuous)
        // Start pressed meanwhile: the row enters where it is.
        guard !isMakingRoom else { return }
        withAnimation(Self.endScroll) {
            scrollPosition.scrollTo(edge: .bottom)
        }
        try? await Task.sleep(for: Self.scrollLanding, tolerance: .zero)
    }

    /// How long the scroll to the list's end takes for an added row: a little longer than
    /// `.railChange`'s 0.25 s, which felt fast here (decided 2026-11-18).
    private static let endScrollLength = 0.35
    static let endScroll = Animation.snappy(duration: endScrollLength)

    /// From a pick to the picker sheet's dismissal having slid it away, when the scroll to the
    /// list's end starts, so it runs in view, and when the first exercise's Start rises with the
    /// + (`settleFoot(after:)`). Tuned to where the append animation's completion
    /// used to start it, late behind the dismissal: 0.43 to 0.47 s into the sheet's slide.
    static let pickerGone: Duration = .milliseconds(500)

    /// A breath between the list resting at its end, the picker sheet gone, and the added row
    /// showing, so each reads as one thing after the other.
    static let addPause: Duration = .milliseconds(250)

    /// From the scroll's start to its landing, `endScroll`'s length; `addPause` follows it.
    static let scrollLanding: Duration = .seconds(endScrollLength)

    /// How long a created row rests after landing before its sheet rises: a little past its
    /// node giving up its blue, so the arrival is over before the next thing moves.
    static let createdHold: Duration = .milliseconds(500)

    /// How long a new workout made from the Workouts list's filters rests, once its push has
    /// settled, before its Add exercise rises by itself (`AddExerciseOnArrival`). Kept the beat
    /// the maintainer tried, which waited 0.9 s from the screen's task: UIKit reports the push
    /// settled 0.5 s after that task starts (iOS 27 simulator).
    static let arrivedHold: Duration = .milliseconds(400)

    /// While an added row's place opens past the visible area, scrolls with it, a frame at a
    /// time, so the list's end stays put on screen as the line grows above it. The place opens
    /// with the list's end in view, so the end is where the scroll stays. Not once Start is
    /// pressed: its room under the list grows the content too, and following that took the
    /// list off the screen, as `add` says. Start's room and a move's turn it off, not only
    /// pause it (`pressStart()`, `add`): left on, it woke as Start's room went, with the landing's
    /// room still under
    /// the list, and scrolled the list into that (Xcode Cloud runs 495 and 499).
    ///
    /// From the place's first growth on (`EndFollow.following`), it follows the end on any
    /// change while short of it, not only on a growth: a growth is reported before the scroll
    /// view has taken it, so a scroll to the new end can stop at the old one, and once a frame's
    /// growth got no scroll at all, every later one stopped short and the list rested short of
    /// its end, the last row under the + (at AX5, 394 against an end at 435). The change a short
    /// scroll makes is followed in turn, to the end the scroll view has by then.
    func keepEndInView(from old: ScrollExtent, to new: ScrollExtent) {
        guard let follow = endFollow, !isMakingRoom, !isScrollingByHand,
              new.endY > new.scrolledY else { return }
        if follow != .following {
            guard new.contentHeight > old.contentHeight else { return }
            if follow == .ready {
                endFollow = .following
            }
        }
        withTransaction(\.disablesAnimations, true) {
            scrollPosition.scrollTo(y: new.endY)
        }
    }

    /// Where the in-step scroll is while an added row's place opens. Until the row is in, the
    /// picker still going and the keyboard with it, and until the place first grows, while
    /// `add` animates the list to its end, the scroll follows only a growth, so changes of the
    /// visible area and that animation run as they are. From the first growth, it follows any
    /// change short of the end.
    enum EndFollow {
        case waiting
        case ready
        case following
    }

    /// Whether the list's end, the room it leaves for the floating +, is in view, below the area
    /// between the bars.
    static func endIsInView(of geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height
            <= (geometry.scrolledY + geometry.containerSize.height).rounded(.up)
    }

    /// Lets the arriving row enter, in the transaction that times its entry.
    private func letArrivingEnter() {
        var transaction = Transaction()
        transaction.isRailEntry = true
        withTransaction(transaction) {
            arriving = nil
        }
    }

    /// Once `row` has landed it takes taps and VoiceOver reaches it. A later add, its row
    /// arriving, keeps the scroll in step for its own place.
    private func hasEntered(_ row: WorkoutExercise) {
        if arriving == nil {
            endFollow = nil
        }
        if entering == row.id {
            entering = nil
        }
    }
}

/// A created row that has landed, its sheet waiting out `createdHold`, and whether the workout
/// was idle at the Create, so a Start pressed since keeps the sheet down.
struct CreatedWait: Equatable {
    let row: WorkoutExercise.ID
    let wasIdle: Bool
    /// Made with nothing typed, so Customize opens with its name to type over.
    var needsName = false
}

/// Opens Add exercise on a new workout made from the Workouts list's filters, once its push has
/// settled and the empty workout has rested `arrivedHold`, so it is seen arrive before the
/// sheet rises; a sheet that rose with the push read as too quick. Timed from UIKit's word that
/// the push is over (`onScreenArrival(_:)`), not from a wait from the push's start, which
/// under load let the sheet rise while the push still slid in. The wait is the screen's task,
/// so leaving before it ends opens nothing (`AppSession.takeAddExerciseOnShow(after:)`).
struct AddExerciseOnArrival: ViewModifier {
    let session: AppSession
    @State private var hasArrived = false

    func body(content: Content) -> some View {
        content
            .onScreenArrival { hasArrived = true }
            .task(id: hasArrived) {
                guard hasArrived else { return }
                await session.takeAddExerciseOnShow(after: WorkoutScreen.arrivedHold)
            }
    }
}
