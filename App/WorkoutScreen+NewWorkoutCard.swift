import DesignSystem
import Session
import SwiftUI
import WorkoutStore

extension WorkoutScreen {
    /// What the rail draws after its last row: the new workout's card while it shows
    /// (`NewWorkoutCard`), where the first exercise goes and then under the last, and the
    /// floating +'s room, whose top is where a tap below the list opens Add exercise.
    var railEnd: some View {
        VStack(spacing: Spacing.md) {
            session.newWorkoutCard.map(newWorkoutCard)
            FloatingButtonRoom()
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .global).minY
                } action: { listEnd.top = $0 }
        }
    }

    private func newWorkoutCard(_ card: NewWorkoutCard) -> some View {
        FilterExerciseCard(
            filterWords: card.filterWords,
            items: card.exercises.map { FilterExerciseCard.Item(id: $0.id, name: $0.name) },
            onAdd: { addFromCard($0, on: card) },
            onClose: {
                withAnimation(.railChange) { session.closeNewWorkoutCard() }
            },
            onMore: { openPicker() },
        )
        .transition(.opacity)
    }

    /// Adds the tapped exercise as a pick adds it, and takes it off the card at the tap.
    private func addFromCard(_ id: Exercise.ID, on card: NewWorkoutCard) {
        guard let exercise = card.exercises.first(where: { $0.id == id }) else { return }
        withAnimation(.railChange) { session.useCardExercise(id) }
        add(exercise)
    }
}
