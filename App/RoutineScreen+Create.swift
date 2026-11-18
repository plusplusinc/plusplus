import DesignSystem
import SwiftUI
import WorkoutStore

/// Where Add exercise's sheet is: picking from the list, or, once Create has made an exercise,
/// showing its row's own sheet at half height.
enum AddStage: Equatable {
    case picking
    case created(RoutineExercise.ID)
}

/// The beats of Create, one thing moving at a time, each starting as the one before it ends.
/// The tap drops the keyboard; at `t0`, the moment the exercise is stored, the room under the
/// list goes on and the list jumps to its end, out of sight under the full-height add sheet;
/// then the add sheet slides down (about 0.3 s), the new row enters in view on the uncovered
/// routine, just above where a half-height sheet's top rests, and the row's own sheet rises to
/// half height with Customize already pushed. One presenter shows one sheet at a time: asked up
/// while the add sheet was still going, the row's sheet appeared at once, with no rise, as the
/// other finished (iOS 27.2), so it is asked once the add sheet has gone. A feel round changes a
/// value here, nowhere else.
enum CreateLanding {
    /// From `t0` to the list's jump to its end: a moment after the room under the list goes on,
    /// since a scroll asked in the same update stopped at the old end.
    static let listJump: Duration = .milliseconds(50)
    /// From `t0` to the add sheet starting down, a moment after the jump: in the jump's own
    /// update, the jump did not land, and the list scrolled in view as the row entered.
    static let sheetDown: Duration = .milliseconds(90)
    /// From the add sheet starting down to the row's entry, as it has gone.
    static let rowEnters: Duration = .milliseconds(350)
    /// From the add sheet starting down to the row's sheet being asked up, once the row's node
    /// has landed (`RailEntry`). It rises 0.2 to 0.3 s later, the screen still while the sheet is
    /// built. Asked while the row's entry was still landing, it appeared at once, with no rise.
    static let rowSheetUp: Duration = .milliseconds(750)
    /// From `t0` to the push having landed: the system's push starts 0.06 to 0.15 s after the
    /// path is set (building both pages) and slides for about 0.36 s (measured on iOS 27.2).
    /// The system gives no completion for a `NavigationStack` push. Scrolled in the shrink, the
    /// list rose as the sheet fell, two motions.
    static let pushLength: Duration = .milliseconds(480)
    /// The sheet's shrink to half height.
    static let shrink: Animation = .snappy(duration: shrinkSeconds)
    /// From the shrink's start to the sheet resting at half height, when the row enters.
    static let shrinkLength: Duration = .seconds(shrinkSeconds)
    private static let shrinkSeconds: TimeInterval = 0.4
}

/// What the room under a created row is worked out from, recorded as it changes. A class,
/// unobserved, so recording redraws nothing.
final class SheetLanding {
    /// The add sheet's top in the window at half height, as it opened.
    var sheetTop: CGFloat?
    /// The list's frame in the window.
    var listFrame: CGRect = .zero
    var geometry: ScrollGeometry?
}

extension RoutineScreen {
    /// Whether Add exercise is showing a created row's sheet.
    var isShowingCreated: Bool {
        if case .created = adding {
            true
        } else {
            false
        }
    }

    /// Add exercise's sheet, recording its top as it opens.
    var addSheet: some View {
        picker
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                recordSheetTop($0)
            }
            // A fixed set: one worked out from `pickerDetent` was read from the opening before.
            .presentationDetents([.medium, .large], selection: $pickerDetent)
            // A created row's Customize form scrolls inside the half-height sheet.
            .presentationContentInteraction(isShowingCreated ? .scrolls : .automatic)
    }

    /// A Delete in Customize can leave the routine empty: Start and the + go down with its last
    /// row. After Create, they wait for the sheet to close (`endAdding()`).
    func settleFootAfterCustomize() {
        if !isShowingCreated {
            settleFoot(after: .zero)
        }
    }

    /// The add sheet's binding: a swipe down ends the stage as Close does.
    var isAdding: Binding<Bool> {
        Binding { adding != nil } set: { isUp in
            if !isUp {
                endAdding()
            }
        }
    }

    /// Stores a created exercise, then runs Create's beats from the moment it is stored: the
    /// room under the list goes on, the row goes in arriving, the sheet drops to half height as
    /// the row's values push in with Customize on top, and once the sheet rests the row lands
    /// just above it (`CreateLanding`).
    func create(_ created: CreatedExercise) async {
        let exercise = await session.create(created)
        // Swiped down meanwhile: the row goes in as a pick's would.
        guard adding == .picking else {
            add(exercise)
            return
        }
        landCreated(exercise)
    }

    private func landCreated(_ exercise: Exercise) {
        let t0 = ContinuousClock.now
        let swap = t0 + CreateLanding.sheetDown
        let rowEnters = swap + CreateLanding.rowEnters
        // In a workout's sequence the end is Start's room: no room, no scroll (`add`). The room
        // goes on out of sight, under the sheet, and is not followed.
        if !isMakingRoom {
            sheetRoom = roomForCreated()
            at(t0 + CreateLanding.listJump) {
                guard !isMakingRoom else { return }
                withTransaction(\.disablesAnimations, true) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
        let row = add(exercise, enteringAt: rowEnters)
        at(swap) {
            adding = nil
            createdSheet = row
            at(swap + CreateLanding.rowSheetUp) {
                editing = self.row(row)?.wrappedValue
            }
        }
    }

    /// The row sheet's binding: a swipe down closes it as Close does.
    var editedRow: Binding<RoutineExercise?> {
        Binding { editing } set: {
            if $0 == nil {
                closeEditing()
            }
        }
    }

    /// Closes a row's sheet; after Create, the room under the list closes as it goes, and Start
    /// and the + follow once it has gone.
    func closeEditing() {
        editing = nil
        guard createdSheet != nil else { return }
        createdSheet = nil
        closeSheetRoom()
        settleFoot(after: Self.exerciseSheetGone)
    }

    /// Runs `beat` at `deadline`, at once if it has come.
    private func at(_ deadline: ContinuousClock.Instant, _ beat: @escaping () -> Void) {
        guard deadline > .now else { return beat() }
        Task {
            try? await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
            beat()
        }
    }

    /// Tall enough that, scrolled to its end, the list's last row rests `Spacing.md` above the
    /// half-height sheet. None until the sheet's top is known.
    private func roomForCreated() -> CGFloat {
        guard let sheetTop = sheetLanding.sheetTop, let geometry = sheetLanding.geometry
        else { return 0 }
        let frame = sheetLanding.listFrame
        // The frame is the area between the bars; the scroll view's insets reach past it, under
        // them, so they play no part here (measured on iOS 27).
        let visibleTop = frame.minY
        let listBottom = visibleTop + geometry.containerSize.height
        let endTop = listEnd.top - visibleTop + geometry.scrolledY
        let tail = geometry.contentSize.height - endTop
        return SheetRoom.height(
            sheetTop: sheetTop,
            listBottom: listBottom,
            tail: tail,
            gap: Spacing.md,
        )
    }

    /// Ends Add exercise, by Close, a swipe down, Remove, or a Delete: after a Create, the room
    /// under the list closes as the sheet goes, the list's end held where it shows, so the rows
    /// ride down with it, and Start and the + rise or go down once the sheet has gone. A swipe
    /// down sets the sheet's binding as the finger lets go, as the sheet starts down (measured on
    /// iOS 27).
    func endAdding() {
        let wasCreated = isShowingCreated
        adding = nil
        guard wasCreated else { return }
        closeSheetRoom()
        settleFoot(after: Self.exerciseSheetGone)
    }

    /// Closes the room under the list as the sheet goes, the list's end held where it shows.
    private func closeSheetRoom() {
        guard sheetRoom > 0 else { return }
        isSheetRoomClosing = true
        withAnimation(.railChange) {
            sheetRoom = 0
        }
        at(.now + Self.sheetRoomClose) { isSheetRoomClosing = false }
    }

    /// The room's close, `railChange`'s duration, while the list's end is held.
    static let sheetRoomClose: Duration = .milliseconds(250)

    /// Records the add sheet's top once, as it opens at half height: the opening reports once,
    /// where it rests, but a drag reports every position the finger takes it to (measured on
    /// iOS 27).
    func recordSheetTop(_ top: CGFloat) {
        guard adding == .picking, pickerDetent == .medium, sheetLanding.sheetTop == nil
        else { return }
        sheetLanding.sheetTop = top
    }
}
