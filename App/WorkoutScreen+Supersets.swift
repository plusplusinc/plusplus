import DesignSystem
import SwiftUI
import WorkoutStore

// Supersets: drawn by a row's node, and joined and left with VoiceOver.
extension WorkoutScreen {
    /// VoiceOver's superset actions on a row, none where it would do nothing.
    @ViewBuilder
    func supersetActions(_ id: WorkoutExercise.ID) -> some View {
        ForEach([WorkoutNeighbor.above, .below], id: \.self) { side in
            if workout.canJoin(id, side), let other = workout.neighbor(of: id, side) {
                Button("Superset with \(other.exercise.name)") { join(id, side) }
            }
        }
        if workout.isInSuperset(id) {
            Button("Move out of superset") { leaveSuperset(id) }
        }
    }

    /// A member's partners, by name, so two supersets next to each other read apart.
    func supersetValue(_ id: WorkoutExercise.ID) -> String {
        workout.partnerNames(of: id).map { "In a superset with \($0)" } ?? ""
    }

    /// Drawing a superset by a drag from a row's node, by the workout's rules.
    var regroup: RailRegroup<WorkoutExercise.ID> {
        RailRegroup { held, reach in
            workout.regrouped(holding: held, reaching: reach).map { regrouping in
                RailGrouping(
                    links: regrouping.workout.joinedToNext,
                    span: Set(regrouping.span),
                )
            }
        } pickUp: { held in
            Set(workout.pickedUp(holding: held))
        } commit: { held, reach in
            workout.regroup(holding: held, reaching: reach)
        }
    }

    /// Joins a row with its neighbor with VoiceOver, and says whom it's with.
    private func join(_ id: WorkoutExercise.ID, _ side: WorkoutNeighbor) {
        withAnimation(.railChange) {
            workout.join(id, side)
        }
        AccessibilityNotification.Announcement(supersetValue(id)).post()
    }

    private func leaveSuperset(_ id: WorkoutExercise.ID) {
        withAnimation(.railChange) {
            workout.leaveSuperset(id)
        }
        AccessibilityNotification.Announcement("Out of the superset").post()
    }
}
