import DesignSystem
import SwiftUI
import WorkoutStore

/// An exercise row's plan, over the routine: its name and equipment, then a stepper for each
/// part it has. Every step, and every typed number once typing ends, changes the row at once, so
/// it saves as it happens; Done ends typing and closes the sheet. Delete is in the More menu, not
/// a standing button.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    /// The part whose number is being typed.
    @FocusState private var typing: PlanPart?
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
                // A tap anywhere but a number or a key ends typing, as the keyboard's check does.
                .contentShape(.rect)
                .onTapGesture { typing = nil }
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
                    Button("Done", systemImage: "checkmark") {
                        typing = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done typing", systemImage: "checkmark") { typing = nil }
                    }
                }
            }
        }
        .presentationDetents(detents)
        // Opaque: through the glass, Start's bright key glowed under the last row.
        .presentationBackground(Color.pp(.surface))
        .hotReloadable()
    }

    /// A key tapped while typing ends typing, keeping what was typed, rather than stepping a
    /// value about to be replaced.
    private func step(_ part: PlanPart, up: Bool) {
        guard typing == nil else {
            typing = nil
            return
        }
        item.step(part, up: up, newWeightUnit: WeightUnit(region: locale))
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
            onDecrease: { step(part, up: false) },
            onIncrease: { step(part, up: true) },
            isTyping: typing == part,
            onType: { typing = part },
        ) {
            NumberField(
                value: value?.number,
                unit: value?.unit,
                typingUnit: part == .weight ? (item.plan.weight?.unit ?? unit).rawValue : nil,
                typesDecimal: item.typesDecimal(part),
                accessibilityLabel: item.label(of: part),
                focus: $typing,
                id: part,
                filter: { item.filtered($0, for: part) },
                typedText: { item.typedText($0, for: part) },
                onCommit: { item.commit(typed: $0, into: part, newWeightUnit: unit) },
            )
        }
        .accessibilityIdentifier("plan.\(part)")
    }
}
