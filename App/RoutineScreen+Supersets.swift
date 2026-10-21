import DesignSystem
import SwiftUI
import WorkoutStore

// Supersets: drawn by a row's node, and joined and left with VoiceOver.
extension RoutineScreen {
    /// VoiceOver's superset actions on a row, none where it would do nothing.
    @ViewBuilder
    func supersetActions(_ id: RoutineExercise.ID) -> some View {
        ForEach([RoutineNeighbor.above, .below], id: \.self) { side in
            if routine.canJoin(id, side), let other = routine.neighbor(of: id, side) {
                Button("Superset with \(other.exercise.name)") { join(id, side) }
            }
        }
        if routine.isInSuperset(id) {
            Button("Move out of superset") { leaveSuperset(id) }
        }
    }

    /// A member's partners, by name, so two supersets next to each other read apart.
    func supersetValue(_ id: RoutineExercise.ID) -> String {
        routine.partnerNames(of: id).map { "In a superset with \($0)" } ?? ""
    }

    /// Drawing a superset by a drag from a row's node, by the routine's rules.
    var regroup: RailRegroup<RoutineExercise.ID> {
        RailRegroup { held, reach in
            routine.regrouped(holding: held, reaching: reach).map { regrouping in
                RailGrouping(
                    links: regrouping.routine.joinedToNext,
                    span: Set(regrouping.span),
                )
            }
        } pickUp: { held in
            Set(routine.pickedUp(holding: held))
        } commit: { held, reach in
            routine.regroup(holding: held, reaching: reach)
        }
    }

    /// Joins a row with its neighbor with VoiceOver, and says whom it's with.
    private func join(_ id: RoutineExercise.ID, _ side: RoutineNeighbor) {
        withAnimation(.railChange) {
            routine.join(id, side)
        }
        AccessibilityNotification.Announcement(supersetValue(id)).post()
    }

    private func leaveSuperset(_ id: RoutineExercise.ID) {
        withAnimation(.railChange) {
            routine.leaveSuperset(id)
        }
        AccessibilityNotification.Announcement("Out of the superset").post()
    }
}
