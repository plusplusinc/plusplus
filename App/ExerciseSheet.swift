import DesignSystem
import SwiftUI
import WorkoutStore

/// An exercise row's plan, over the routine: its name centered in the bar with its equipment
/// under it, then a stepper for each part it has. At the accessibility sizes, where the bar would
/// cut a name short, both lead the content instead. The parts are compact rows, their keys
/// repeating while held. Every step, and every typed number once typing ends, changes the row at
/// once, so it saves as it happens; Close ends typing and closes the sheet, losing nothing. Delete
/// is in the More menu, not a standing button, and asks first.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    /// The part whose number is being typed.
    @FocusState private var typing: PlanPart?
    /// The content's full height, bars included, which the sheet's detent fits.
    @State private var height: CGFloat?
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if dynamicTypeSize.isAccessibilitySize {
                        heading
                    } else if let equipment = item.exercise.equipmentLine {
                        // Under the title in the bar, quiet.
                        equipmentLine(equipment).frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(item.exercise.planParts, id: \.self, content: row)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A tap anywhere but a number or a key ends typing; a tap on another number
                // moves it there. The keyboard has no accessory: Done keeps what was typed.
                .contentShape(.rect)
                .onTapGesture { typing = nil }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
            // The content's height doesn't depend on the sheet's, so fitting one to the other
            // can't loop.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                (geometry.contentSize.height + geometry.contentInsets.top).rounded(.up)
            } action: { _, height in
                // Held while typing, so the sheet doesn't refit as the keyboard moves it.
                guard typing == nil else { return }
                self.height = height
            }
            .toolbar {
                // In the routine's bar title's font, as it plays the same part.
                ToolbarItem(placement: .title) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(item.exercise.name)
                            .font(.ppInlineTitle)
                            .foregroundStyle(.pp(.textPrimary))
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                // Close, not Cancel: every change has already saved, so nothing is lost.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        typing = nil
                        dismiss()
                    }
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
        .presentationDetents(detents)
        // Opaque: through the glass, Start's bright key glowed under the last row. The routine
        // screen's own background, so the sheet's boxes and keys sit on it as Add exercise does.
        .presentationBackground(Color.pp(.background))
        .hotReloadable()
    }

    /// A key tapped while typing ends typing, keeping what was typed, rather than stepping a
    /// value about to be replaced.
    private func step(_ part: PlanPart, up: Bool) {
        guard typing == nil else {
            typing = nil
            return
        }
        item.step(part, up: up)
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
            if let equipment = item.exercise.equipmentLine {
                equipmentLine(equipment)
            }
        }
        // One heading, "name, equipment", as a row reads.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func equipmentLine(_ equipment: String) -> some View {
        Text(equipment)
            .font(.ppRowDetail)
            .foregroundStyle(.pp(.textSecondary))
    }

    private func row(_ part: PlanPart) -> some View {
        let value = item.value(of: part, locale: locale)
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
            value: {
                NumberField(
                    value: value?.number ?? "",
                    amount: item.amount(of: part),
                    unit: value?.unit,
                    typingUnit: part == .weight ? item.plan.weight?.unit.rawValue : nil,
                    typesDecimal: part == .weight,
                    accessibilityLabel: item.label(of: part),
                    focus: $typing,
                    id: part,
                    filter: { item.filtered($0, for: part) },
                    typedText: { item.typedText($0, for: part) },
                    onCommit: { item.commit(typed: $0, into: part) },
                )
            },
        )
        .accessibilityIdentifier("plan.\(part)")
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
