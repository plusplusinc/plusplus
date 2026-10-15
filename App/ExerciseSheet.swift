import DesignSystem
import SwiftUI
import WorkoutStore

/// An exercise row's plan, over the routine: its name centered in the bar, then a row for each
/// part it has, its value in a capsule. Not its equipment, which isn't set here and which the row
/// behind already shows. At the accessibility sizes, where the bar would cut a name short, the
/// name leads the content instead. A tap on a value opens
/// its wheel under it, one at a time; a tap on it again, or on the sheet's empty space, closes
/// it. Every value the wheel settles on changes the row at once, so it saves as it happens; Close
/// closes the sheet, losing nothing. Delete is in the More menu, not a standing button, and asks
/// first.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    let onDelete: () -> Void

    /// The part whose wheel is open.
    @State private var open: PlanPart?
    /// The content's full height with every wheel closed, bars included, which the sheet's
    /// smaller detent fits; the larger fits one wheel more.
    @State private var closedHeight: CGFloat?
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if dynamicTypeSize.isAccessibilitySize {
                        heading
                    }
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(item.exercise.planParts, id: \.self, content: row)
                    }
                    // With Reduce Motion a wheel appears and goes at once.
                    .animation(reduceMotion ? nil : .snappy, value: open)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A tap anywhere but a value or its wheel closes the wheel.
                .contentShape(.rect)
                .onTapGesture { open = nil }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
            // The content's height doesn't depend on the sheet's, so fitting one to the other
            // can't loop.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                (geometry.contentSize.height + geometry.contentInsets.top).rounded(.up)
            } action: { _, height in
                // Measured with no wheel open: the open detent is this and a wheel.
                guard open == nil else { return }
                closedHeight = height
            }
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
        .presentationDetents(detents, selection: detent)
        // Its two heights follow the wheel; there is nothing to drag to.
        .presentationDragIndicator(.hidden)
        // Opaque: through the glass, Start's bright key glowed under the last row. The routine
        // screen's own background, so the sheet's boxes and keys sit on it as Add exercise does.
        .presentationBackground(Color.pp(.background))
        .hotReloadable()
    }

    /// Sized to its rows, and to one wheel more while one is open; at the accessibility sizes
    /// the whole screen, and the content scrolls.
    private var detents: Set<PresentationDetent> {
        guard !dynamicTypeSize.isAccessibilitySize, let closedHeight else { return [.large] }
        return [.height(closedHeight), .height(closedHeight + PlanWheel.height)]
    }

    /// The open detent while a wheel is open, the closed one otherwise; moving between them is
    /// the system's own glide, so the bar doesn't jump. Dragging the sheet down to the closed one
    /// closes the wheel.
    private var detent: Binding<PresentationDetent> {
        Binding {
            guard !dynamicTypeSize.isAccessibilitySize, let closedHeight else { return .large }
            return .height(open == nil ? closedHeight : closedHeight + PlanWheel.height)
        } set: { detent in
            if let closedHeight, detent == .height(closedHeight) {
                open = nil
            }
        }
    }

    private var heading: some View {
        Text(item.exercise.name)
            .font(.ppSheetTitle)
            .foregroundStyle(.pp(.textPrimary))
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ part: PlanPart) -> some View {
        let value = item.value(of: part, locale: locale)
        return PickerRow(
            title: item.label(of: part),
            note: item.note(of: part),
            value: value?.number ?? "",
            unit: value?.unit,
            amount: item.amount(of: part),
            spokenValue: item.spokenValue(of: part, locale: locale),
            isOpen: open == part,
            identifier: "plan.\(part)",
            onToggle: { open = open == part ? nil : part },
            wheel: { PlanWheel(item: $item, part: part) },
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
