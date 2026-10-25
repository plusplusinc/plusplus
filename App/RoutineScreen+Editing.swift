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

    func delete(_ id: RoutineExercise.ID) {
        withAnimation(.railChange) {
            routine.remove(id)
        }
    }

    /// Adds a picked exercise. Its row takes its place as the sheet starts down, moving Add
    /// exercise, but enters only where it can be seen: a moment into the sheet's slide when
    /// everything still fits, and otherwise once a scroll to the end has brought the row and Add
    /// exercise into view. The scroll waits for the row's place: asked for while the row went in,
    /// it stopped at the end the list had before. Once Start is pressed, it enters where it is,
    /// with no scroll: the end is then Start's room under the list, out of sight, and a scroll to
    /// it took the list off the screen just as Start went to land on the first exercise.
    func add(_ exercise: Exercise) {
        let row = RoutineExercise(exercise: exercise, weightUnit: WeightUnit(region: locale))
        arriving = row.id
        entering = row.id
        isOpeningPlace = true
        // The row goes in with no space yet, so nothing moves; its fade, of a row that draws
        // nothing yet, times the entry a moment into the sheet's slide: the line barely moves
        // at first, and the sheet has cleared all but the screen's foot by the time it shows.
        withAnimation(.linear(duration: 0.1)) {
            routine.exercises.append(row)
        } completion: {
            probe("add completion arriving=\(arriving == row.id) endInView=\(isEndInView) makingRoom=\(isMakingRoom)")
            guard arriving == row.id else { return }
            guard !isEndInView, !isMakingRoom else { return letArrivingEnter(row) }
            probe("add scroll to bottom")
            withAnimation(.railChange, completionCriteria: .logicallyComplete) {
                scrollPosition.scrollTo(edge: .bottom)
            } completion: {
                probe("add scroll completion makingRoom=\(isMakingRoom)")
                letArrivingEnter(row)
            }
        }
    }

    /// While an added row's place opens past the visible area, scrolls with it, a frame at a
    /// time, so Add exercise stays put on screen as the line grows above it. The place opens
    /// with the list's end in view, so the end is where the scroll stays. Not once Start is
    /// pressed: its room under the list grows the content too, and following that took the
    /// list off the screen, as `add` says.
    func keepEndInView(from old: ScrollGeometry, to new: ScrollGeometry) {
        guard isOpeningPlace, !isMakingRoom, !isScrollingByHand,
              new.contentSize.height > old.contentSize.height
        else { return }
        guard new.endY > new.scrolledY else { return }
        probe("keepEndInView to \(f(new.endY)) from \(f(new.scrolledY))")
        withTransaction(\.disablesAnimations, true) {
            scrollPosition.scrollTo(y: new.endY)
        }
    }

    /// Whether the list's end, Add exercise, is in view, below the area between the bars.
    static func endIsInView(of geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height
            <= (geometry.scrolledY + geometry.containerSize.height).rounded(.up)
    }

    /// Lets `row` enter, unless a later add has taken its place as the arriving row.
    func letArrivingEnter(_ row: RoutineExercise) {
        guard arriving == row.id else { return }
        var transaction = Transaction()
        transaction.isRailEntry = true
        // A later add, its row arriving, keeps the scroll in step for its own place.
        probe("letArrivingEnter")
        transaction.addAnimationCompletion {
            probe("entry completion makingRoom=\(isMakingRoom)")
            isOpeningPlace = arriving != nil
            if entering == row.id {
                entering = nil
            }
        }
        withTransaction(transaction) {
            arriving = nil
        }
    }
}
