import DesignSystem
import SwiftUI
import WorkoutStore

/// An exercise row's plan, over the routine: its name and equipment, then a stepper for each
/// part it has. Every step changes the row at once, so it saves as it happens; Done only closes
/// the sheet. Delete is in the More menu, not a standing button.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    /// The content's full height, bars included, which the sheet's detent fits.
    @State private var height: CGFloat?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    heading
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(item.exercise.planParts, id: \.self, content: row)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The content's height doesn't depend on the sheet's, so fitting one to the other
            // can't loop.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top
            } action: { _, height in
                self.height = height
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Not a confirmation action, which the system tints: green is data only.
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents(detents)
        // Opaque: through the glass, Start's bright key glowed under the last row.
        .presentationBackground(Color.pp(.surface))
        .hotReloadable()
    }

    /// Sized to its rows; at the accessibility sizes the whole screen, and the content scrolls.
    private var detents: Set<PresentationDetent> {
        guard !dynamicTypeSize.isAccessibilitySize, let height else { return [.large] }
        return [.height(height)]
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(item.exercise.name)
                .font(.ppSheetTitle)
                .foregroundStyle(.pp(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            if let equipment = item.exercise.equipmentLine {
                Text(equipment)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
    }

    private func row(_ part: PlanPart) -> some View {
        let value = item.value(of: part, locale: locale)
        let unit = WeightUnit(region: locale)
        return StepperRow(
            title: item.label(of: part),
            note: item.note(of: part),
            spokenValue: item.spokenValue(of: part, locale: locale),
            canDecrease: item.canStep(part, up: false),
            canIncrease: item.canStep(part, up: true),
            onDecrease: { item.step(part, up: false, newWeightUnit: unit) },
            onIncrease: { item.step(part, up: true, newWeightUnit: unit) },
        ) {
            StepperValue(number: value?.number, unit: value?.unit)
        }
        .accessibilityIdentifier("plan.\(part)")
    }
}
