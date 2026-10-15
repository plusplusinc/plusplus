import DesignSystem
import SwiftUI
import WorkoutStore

/// An exercise row's plan, over the routine: its name centered in the bar, a row for each part it
/// has, and one wheel docked at the sheet's foot, where the thumb rests, setting whichever row is
/// selected. It opens on Sets; a tap on another row moves the wheel to it. Not its equipment,
/// which isn't set here and which the row behind already shows. At the accessibility sizes, where
/// the bar would cut a name short, the name leads the rows instead, and the rows scroll above the
/// wheel. Every value the wheel settles on changes the row at once, so it saves as it happens;
/// Close closes the sheet, losing nothing. Delete is in the More menu, not a standing button, and
/// asks first.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    /// The part the wheel sets.
    @State private var selected = PlanPart.sets
    @State private var rowsHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if dynamicTypeSize.isAccessibilitySize {
                            heading
                        }
                        VStack(spacing: Spacing.xs) {
                            ForEach(item.exercise.planParts, id: \.self, content: row)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        rowsHeight = $0
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // The bar's height over the rows, which the sheet's height includes.
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                    barHeight = $0
                }
                // Full width, so a drag anywhere across it turns the wheel, not the sheet. A new
                // wheel for each part, rather than one whose rows change under the thumb.
                PlanWheel(item: $item, part: selected)
                    .id(selected)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // In the font the exercise's name has on its row; SF Mono is the routine's title's.
                ToolbarItem(placement: .title) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(item.exercise.name)
                            .font(.ppRowTitle)
                            .foregroundStyle(.pp(.textPrimary))
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                // Close, not Cancel: every change has already saved, so nothing is lost.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                    .confirmationDialog(
                        "Delete \(item.exercise.name) from this routine?",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible,
                    ) {
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([detent])
        // One height, so there is nothing to drag to.
        .presentationDragIndicator(.hidden)
        // Opaque: through the glass, Start's bright key glowed under the last row. The routine
        // screen's own background, so the rows' fills sit on it as Add exercise does.
        .presentationBackground(Color.pp(.background))
        .hotReloadable()
    }

    /// Sized to the bar, the rows, and the wheel; at the accessibility sizes the whole screen,
    /// the rows scrolling above the wheel. The rows' height doesn't depend on the sheet's, so
    /// fitting one to the other can't loop.
    private var detent: PresentationDetent {
        guard !dynamicTypeSize.isAccessibilitySize, rowsHeight > 0 else { return .large }
        return .height((barHeight + rowsHeight + PlanWheel.height).rounded(.up))
    }

    private var heading: some View {
        Text(item.exercise.name)
            .font(.ppSheetTitle)
            .foregroundStyle(.pp(.textPrimary))
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ part: PlanPart) -> some View {
        let value = item.value(of: part, locale: locale)
        return ValueRow(
            title: item.label(of: part),
            value: value?.number ?? "",
            suffix: value?.suffix,
            amount: item.amount(of: part),
            spokenValue: item.spokenValue(of: part, locale: locale),
            isSelected: selected == part,
            identifier: "plan.\(part)",
            action: { selected = part },
        )
    }
}

#Preview {
    @Previewable @State var item = RoutineExercise(
        exercise: Exercise.builtIn[0],
        weightUnit: .pounds,
    )
    Color.pp(.background)
        .sheet(isPresented: .constant(true)) {
            ExerciseSheet(item: $item) { }
        }
}
