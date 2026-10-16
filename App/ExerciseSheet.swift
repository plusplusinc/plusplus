import DesignSystem
import SwiftUI
import WorkoutStore

/// A routine row's values, a `ValueRow` for each part its exercise has, under the exercise's
/// equipment. A row's stepper opens one at a time. Changes apply as they're made; Delete is in
/// the menu.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    @State private var open: PlanPart?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        let equipment = [item.exercise].equipment
                        if !equipment.isEmpty {
                            Capsules(equipment.map(\.name))
                                .padding(.bottom, Spacing.sm)
                        }
                        ForEach(item.exercise.planParts, id: \.self) { part in
                            ValueRow(
                                label: item.label(of: part),
                                value: item.value(of: part, locale: locale),
                                spokenValue: item.spokenValue(of: part, locale: locale),
                                isOpen: open == part,
                                canDecrease: item.canStep(part, by: -1),
                                canIncrease: item.canStep(part, by: 1),
                                onToggle: { toggle(part, scroller) },
                                onStep: { item.step(part, by: $0) },
                            )
                            .id(part)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                }
            }
            .background(Color.pp(.background))
            .navigationTitle(item.exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.background))
        .hotReloadable()
    }

    /// Opens or closes a part's stepper. Once one has opened, the sheet scrolls only as far as
    /// it takes to show the whole row, its keys below its edge included, so a row in view stays
    /// put.
    private func toggle(_ part: PlanPart, _ scroller: ScrollViewProxy) {
        let opening = open != part
        withAnimation(ValueRow.motion) {
            open = opening ? part : nil
        } completion: {
            guard opening, open == part else { return }
            withAnimation(ValueRow.motion) {
                scroller.scrollTo(part)
            }
        }
    }
}

#Preview {
    @Previewable @State var item = RoutineExercise(
        exercise: Exercise.builtIn.first { $0.load == .pair && $0.isPerSide } ?? Exercise
            .builtIn[0],
        weightUnit: .pounds,
    )
    Color.pp(.background)
        .sheet(isPresented: .constant(true)) {
            ExerciseSheet(item: $item) { }
        }
}
