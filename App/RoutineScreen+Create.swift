import DesignSystem
import SwiftUI
import WorkoutStore

/// Where Add exercise's sheet is: picking from the list, or, once Create has made an exercise,
/// showing its row's own sheet at half height.
enum AddStage: Equatable {
    case picking
    case created(RoutineExercise.ID)
}

/// The beats of Create, each a deadline from `t0`, the moment the exercise is stored: the sheet
/// drops to half height with the exercise's Customize form pushed inside it, and the routine
/// behind lands the new row just above the sheet's top. A feel round changes a constant here or
/// moves a line in `landCreated(_:)`, nowhere else.
enum CreateLanding {
    /// The room under the list's end goes on, out of sight under the full-height sheet.
    static let roomOn: Duration = .zero
    /// The sheet's detent goes to half height.
    static let sheetDrop: Duration = .zero
    /// The row's values, with Customize on top, push in.
    static let push: Duration = .zero
    /// The sheet rests at half height and the keyboard has gone: the list scrolls to its end if
    /// the end isn't in view, then lets the row go (`RoutineScreen.scrollLanding` later).
    static let sheetAtHalf: Duration = .milliseconds(500)
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
        // In a workout's sequence the end is Start's room: no room, no scroll (`add`).
        if !isMakingRoom {
            at(t0 + CreateLanding.roomOn) { sheetRoom = roomForCreated() }
        }
        let row = add(exercise, created: t0)
        adding = .created(row)
        at(t0 + CreateLanding.sheetDrop) {
            withAnimation(.snappy) {
                pickerDetent = .medium
            }
        }
        at(t0 + CreateLanding.push) {
            pickerPath = [.values(row), .customize(exercise.id)]
        }
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
        if sheetRoom > 0 {
            isSheetRoomClosing = true
            withAnimation(.railChange) {
                sheetRoom = 0
            }
            at(.now + Self.sheetRoomClose) { isSheetRoomClosing = false }
        }
        settleFoot(after: Self.exerciseSheetGone)
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
