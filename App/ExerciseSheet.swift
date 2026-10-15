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
    /// Whether a wheel is rolling up, until it's gone.
    @State private var isClosing = false
    @State private var rowsHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
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
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if dynamicTypeSize.isAccessibilitySize {
                            heading
                        }
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            ForEach(item.exercise.planParts, id: \.self, content: row)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The rows' own height: laid out from the bottom, the scroll view reports its
                    // content as tall as itself, and the sheet would have fitted that.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        rowsHeight = height
                        measureClosedHeight()
                    }
                    // A tap anywhere but a value or its wheel closes the wheel.
                    .contentShape(.rect)
                    .onTapGesture { show(nil) }
                }
                // A new text size changes the rows' height, measured only with no wheel open.
                .onChange(of: dynamicTypeSize) { show(nil) }
                // At the accessibility sizes, where the content scrolls, an opened wheel is
                // scrolled into view under its row.
                .onChange(of: open) { _, part in
                    guard dynamicTypeSize.isAccessibilitySize, let part else { return }
                    withAnimation(reduceMotion ? nil : .snappy) {
                        scroller.scrollTo(part, anchor: .bottom)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // Laid out from the bottom, which stays put on the screen: a wheel opening or
                // closing
                // moves the rows above it and the sheet's top, never the rows below. At the
                // accessibility sizes, where the content scrolls, it stays anchored at its top, so
                // a
                // tapped row never slides out of view.
                .defaultScrollAnchor(
                    dynamicTypeSize.isAccessibilitySize ? .top : .bottom,
                    for: .alignment,
                )
                .defaultScrollAnchor(
                    dynamicTypeSize.isAccessibilitySize ? .top : .bottom,
                    for: .sizeChanges,
                )
                .navigationBarTitleDisplayMode(.inline)
                // The bar's height over the content, which the sheet's height includes. Not the
                // scroll view's content inset, which laying out from the bottom grows to fill.
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { inset in
                    barHeight = inset
                    measureClosedHeight()
                }
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

    /// The sheet's closed height: the rows and the bar. The rows' height doesn't depend on the
    /// sheet's, so fitting one to the other can't loop. Measured only with no wheel open or
    /// closing, since the open detent is this and a wheel: measured as a wheel rolled up, it took
    /// each height on the way, and the sheet jumped up before it came down.
    private func measureClosedHeight() {
        guard open == nil, !isClosing, rowsHeight > 0 else { return }
        closedHeight = (rowsHeight + barHeight).rounded(.up)
    }

    /// Opens `part`'s wheel, closing any other, or with nil closes the open one. With Reduce
    /// Motion a wheel appears and goes at once.
    private func show(_ part: PlanPart?) {
        guard part != open else { return }
        isClosing = part == nil
        withAnimation(reduceMotion ? nil : .snappy) {
            open = part
        } completion: {
            isClosing = false
        }
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
                show(nil)
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
            onToggle: { show(open == part ? nil : part) },
            wheel: { PlanWheel(item: $item, part: part) },
        )
        .id(part)
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
