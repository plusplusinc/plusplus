import DesignSystem
import SwiftUI
import WorkoutStore

/// Editing the rows: the sheet's binding, moves, deletes, and adds.
extension RoutineScreen {
    /// The row with this id, bound by id rather than by index, so a sheet still showing it
    /// never reads past the end of the rows once it is deleted.
    func row(_ id: RoutineExercise.ID) -> Binding<RoutineExercise>? {
        guard let current = routine.exercises.first(where: { $0.id == id }) else { return nil }
        return Binding {
            routine.exercises.first { $0.id == id } ?? current
        } set: { item in
            routine.update(item)
        }
    }

    /// The rest of `id`'s superset, read and stepped on every member; nil for a plain row.
    func roundSteps(of id: RoutineExercise.ID) -> RoundSteps? {
        guard routine.isInSuperset(id) else { return nil }
        return RoundSteps(
            value: {
                (
                    routine.restAfterRoundText(of: id, locale: locale),
                    routine.spokenRestAfterRound(of: id, locale: locale),
                )
            },
            seconds: { Double(routine.restAfterRound(of: id) ?? 0) },
            canStep: { routine.canStepRestAfterRound(of: id, by: $0) },
            step: { routine.stepRestAfterRound(of: id, by: $0) },
            set: { routine.setRestAfterRound($0, of: id) },
            isAuto: Binding {
                routine.isRoundAuto(of: id)
            } set: { isAuto in
                routine.setRoundAuto(isAuto, of: id)
            },
            change: (routine.exercises.filter { $0.id == id } + routine.partners(of: id))
                .restChange,
        )
    }

    /// Moves a row dropped on the rail, in the rail's transaction, so the order changes as the
    /// card settles into its gap; it saves once, as any change does.
    func move(_ id: RoutineExercise.ID, to slot: RailSlot<RoutineExercise.ID>) {
        routine.move(id, to: RoutineSlot(slot))
    }

    /// Moves a row one place with VoiceOver's Move up or Move down, and says which row it
    /// passed.
    func step(_ id: RoutineExercise.ID, to slot: RoutineSlot, wentUp: Bool) {
        withAnimation(.railChange) {
            routine.move(id, to: slot)
        }
        if let announcement = routine.moveAnnouncement(for: id, wentUp: wentUp) {
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// Removes a row. The last one takes Start down and the + with it after `footDelay`: at once
    /// from a swipe, and from the exercise sheet's Remove once the sheet has gone.
    func delete(_ id: RoutineExercise.ID, footDelay: Duration = .zero) {
        withAnimation(.railChange) {
            routine.remove(id)
        }
        settleFoot(after: footDelay)
    }

    /// A row's sheet, its More menu's Customize… pushing the exercise's form inside it. Each
    /// change shows in the routine behind it as it is stored; a Delete there takes the row and
    /// shuts the sheet.
    @ViewBuilder
    func exerciseSheet(_ opened: RowSheet) -> some View {
        let id = opened.id
        if let item = row(id) {
            ExerciseSheet(
                item: item,
                partners: routine.partnerNames(of: id),
                parts: routine.sheetParts(of: id),
                rounds: roundSteps(of: id),
                customize: { back in
                    CustomizeScreen(
                        id: item.wrappedValue.exercise.id,
                        session: session,
                        namer: namer,
                        onStored: {
                            showStoredRoutine()
                            if row(id) == nil {
                                editing = nil
                            }
                        },
                        back: back,
                    )
                },
                onDelete: { delete(id, footDelay: Self.exerciseSheetGone) },
                opensCustomizing: opened.opensCustomizing,
            )
        }
    }

    /// Add exercise's sheet. A created exercise is stored before its row is added, so the
    /// routine's save that names it lands after it; then the sheet closes and the row goes in as
    /// a pick's does, even if the sheet was swiped down meanwhile, and once it has landed its own
    /// sheet opens on Customize (`showCreated(_:)`).
    var picker: some View {
        ExercisePicker(
            exercises: session.exercises,
            onPick: addPicked,
            // Full height with search, in the field's own transaction (decided 2026-11-17).
            onSearchOpen: { pickerDetent = .large },
            onCreate: { made in
                let exercise = await session.create(made)
                isPicking = false
                add(exercise, landed: showCreated)
            },
            routineCount: { session.routines(using: $0).count },
            onDelete: { id in
                await session.deleteExercise(id, weightUnit: WeightUnit(region: locale))
                showStoredRoutine()
            },
            customize: { id, back in
                CustomizeScreen(
                    id: id,
                    session: session,
                    namer: namer,
                    onStored: showStoredRoutine,
                    back: back,
                )
            },
        )
    }

    /// Shuts the picker and adds what was picked there. A second tap while the sheet goes down
    /// keeps the first.
    func addPicked(_ exercise: Exercise) {
        guard isPicking else { return }
        isPicking = false
        add(exercise)
    }

    /// Adds a picked exercise. Its row takes its place at the rail's end as the sheet starts down,
    /// but enters only where it can be seen: a moment into the sheet's slide when everything
    /// still fits, and otherwise once the sheet has gone and a scroll to the end has brought the
    /// row and the list's end into view. The scroll waits for the row's place: asked for while
    /// the row went in, it stopped at the end the list had before. Once Start is pressed, it
    /// enters where it is, with no scroll: the end is then Start's room under the list, out of
    /// sight, and a scroll to it took the list off the screen just as Start went to land on the
    /// first exercise. `landed` runs once the row has landed.
    func add(_ exercise: Exercise, landed: @escaping (RoutineExercise.ID) -> Void = { _ in }) {
        let added = ContinuousClock.now
        let row = RoutineExercise(exercise: exercise, weightUnit: WeightUnit(region: locale))
        arriving = row.id
        entering = row.id
        endFollow = .waiting
        // The row goes in with no space yet, so nothing moves; its fade, of a row that draws
        // nothing yet, times the entry a moment into the sheet's slide: the line barely moves
        // at first, and the sheet has cleared all but the screen's foot by the time it shows.
        withAnimation(.linear(duration: RailArrival.appendFade)) {
            routine.exercises.append(row)
        }
        settleFoot(after: Self.pickerGone)
        // Beats on deadlines, not this animation's completion, which once never came, and the
        // row stayed arriving for good (`RailArrival`).
        Task {
            await RailArrival.play {
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

    /// After Create, a beat after its row has landed, the row's own sheet comes up, as a tap on
    /// the row brings it, already on Customize: the row is seen landing, then its sheet rises.
    /// Not if a sheet is up by then, or the row has gone.
    private func showCreated(_ id: RoutineExercise.ID) {
        Task {
            try? await Task.sleep(for: .seconds(Self.landingHold), tolerance: .zero)
            guard editing == nil, !isPicking, row(id) != nil else { return }
            editing = RowSheet(id: id, opensCustomizing: true)
        }
    }
}

/// A row's open sheet: which row, and whether it opens on Customize, as after Create. The flag
/// rides with the sheet's item: a separate state set with it read as unset in the sheet.
struct RowSheet: Identifiable {
    let id: RoutineExercise.ID
    var opensCustomizing = false
}

extension RoutineScreen {
    /// Once the picker has gone, scrolls the list to its end, the added row's place, and returns
    /// as it lets the row enter, unless the end is in view or Start's room is opening. On
    /// deadlines, not the scroll's completion or its phase: the phase reported idle only about
    /// 0.3 s after the list had stopped, and the row waited on a still list.
    private func reachEnd(added: ContinuousClock.Instant) async {
        endFollow = .ready
        guard !isEndInView, !isMakingRoom else { return }
        try? await Task.sleep(until: added + Self.pickerGone, tolerance: .zero, clock: .continuous)
        // Start pressed meanwhile: the row enters where it is.
        guard !isMakingRoom else { return }
        withAnimation(.railChange) {
            scrollPosition.scrollTo(edge: .bottom)
        }
        try? await Task.sleep(for: Self.scrollLanding, tolerance: .zero)
    }

    /// From a pick to the picker sheet's dismissal having slid it away, when the scroll to the
    /// list's end starts, so it runs in view, and when the first exercise's Start rises with the
    /// + (`settleFoot(after:)`). Tuned to where the append animation's completion
    /// used to start it, late behind the dismissal: 0.43 to 0.47 s into the sheet's slide.
    static let pickerGone: Duration = .milliseconds(500)

    /// From the scroll's start to the row's entry, where the scroll's completion used to let it
    /// go. The entry's growth shows once the scroll has landed, as it did then.
    static let scrollLanding: Duration = .milliseconds(30)

    /// While an added row's place opens past the visible area, scrolls with it, a frame at a
    /// time, so the list's end stays put on screen as the line grows above it. The place opens
    /// with the list's end in view, so the end is where the scroll stays. Not once Start is
    /// pressed: its room under the list grows the content too, and following that took the
    /// list off the screen, as `add` says.
    ///
    /// From the place's first growth on (`EndFollow.following`), it follows the end on any
    /// change while short of it, not only on a growth: a growth is reported before the scroll
    /// view has taken it, so a scroll to the new end can stop at the old one, and once a frame's
    /// growth got no scroll at all, every later one stopped short and the list rested short of
    /// its end, the last row under the + (at AX5, 394 against an end at 435). The change a short
    /// scroll makes is followed in turn, to the end the scroll view has by then.
    func keepEndInView(from old: ScrollGeometry, to new: ScrollGeometry) {
        guard let follow = endFollow, !isMakingRoom, !isScrollingByHand,
              new.endY > new.scrolledY else { return }
        if follow != .following {
            guard new.contentSize.height > old.contentSize.height else { return }
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
    private func hasEntered(_ row: RoutineExercise) {
        if arriving == nil {
            endFollow = nil
        }
        if entering == row.id {
            entering = nil
        }
    }
}
