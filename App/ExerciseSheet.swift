import DesignSystem
import SwiftUI
import WorkoutStore

/// An exercise row's plan, over the routine: its name centered in the bar, then a row for each
/// part it has, the label leading and the value trailing. Not its equipment, which isn't set here
/// and which the row behind already shows. At the accessibility sizes, where the bar would cut a
/// name short, the name leads the content instead. It opens with every row closed; a tap on a
/// row opens its wheel in the gap under it, closing any other, and a tap on it again closes it.
/// The sheet opens with room for its rows and one open wheel, empty at its foot while every row
/// is closed, and drags up to the full screen. Only the person moves it, so a wheel opening never
/// moves the sheet's top or the rows above it, only pushes the rows below down, into that room.
/// Where even that height won't fit on the screen, the rows scroll.
/// Every value the wheel settles on changes the row at once, so it saves as it happens; Close
/// closes the sheet, losing nothing. Delete is in the More menu, not a standing button, and asks
/// first.
struct ExerciseSheet: View {
    @Binding var item: RoutineExercise
    /// The screen's height under the status bar, which the sheet's first height stays below.
    let room: CGFloat
    let onDelete: () -> Void

    /// The part whose wheel is open.
    @State private var open: PlanPart?
    /// Whether a wheel is opening or closing, until it's done.
    @State private var isMoving = false
    @State private var rowsHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    /// The bar, the rows with every wheel closed, and one wheel: the sheet's first height.
    @State private var fittedHeight: CGFloat?
    /// Whether the person dragged the sheet to the full screen.
    @State private var isLarge = false
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
                        VStack(spacing: Spacing.xs) {
                            ForEach(item.exercise.planParts, id: \.self) {
                                row($0, scroller: scroller)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        rowsHeight = height
                        measureFittedHeight()
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationBarTitleDisplayMode(.inline)
                // The bar's height over the content, which the sheet's height includes.
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { inset in
                    barHeight = inset
                    measureFittedHeight()
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
        .presentationDragIndicator(.visible)
        // Opaque: through the glass, Start's bright key glowed under the last row. The routine
        // screen's own background, so the rows' fills sit on it as Add exercise does.
        .presentationBackground(Color.pp(.background))
        .hotReloadable()
    }

    /// The sheet's first height: the bar, the rows less the open wheel if any, and one wheel.
    /// Measured only with no wheel moving: measured as one opened or closed, the rows' height
    /// would take each height on the way. The rows' height doesn't depend on the sheet's, so
    /// fitting one to the other can't loop.
    private func measureFittedHeight() {
        guard !isMoving, rowsHeight > 0 else { return }
        let closedRows = open == nil ? rowsHeight : rowsHeight - PlanWheel.height
        fittedHeight = (barHeight + closedRows + PlanWheel.height).rounded(.up)
    }

    /// Opens `part`'s wheel, closing any other, or with nil closes the open one. Where the rows
    /// scroll, an opened wheel past the foot then scrolls up just far enough to show: asked as it
    /// opened, the scroll view went by the wheel's height before it grew, and didn't move. At the
    /// sheet's first height the wheel is always in view. With Reduce Motion a wheel appears and
    /// goes at once.
    private func show(_ part: PlanPart?, scroller: ScrollViewProxy) {
        guard part != open else { return }
        isMoving = true
        // Done once the spring has fully settled, not when it's logically complete: measured in
        // its last tail, the height came out a point off, and the sheet twitched.
        withAnimation(reduceMotion ? nil : .snappy, completionCriteria: .removed) {
            open = part
        } completion: {
            isMoving = false
            if let part {
                withAnimation(reduceMotion ? nil : .snappy) { scroller.scrollTo(part) }
            }
        }
    }

    /// Fitted to the rows and a wheel, or the full screen; until the rows are measured, the full
    /// screen alone.
    private var detents: Set<PresentationDetent> {
        guard let fitted else { return [.large] }
        return [fitted, .large]
    }

    /// The rows and a wheel, kept below the full screen, where the rows scroll instead.
    private var fitted: PresentationDetent? {
        fittedHeight.map { .height(min($0, room - Spacing.xl)) }
    }

    /// The person's choice of the two, which nothing in the sheet changes.
    private var detent: Binding<PresentationDetent> {
        Binding {
            guard !isLarge, let fitted else { return .large }
            return fitted
        } set: {
            isLarge = $0 == .large
        }
    }

    private var heading: some View {
        Text(item.exercise.name)
            .font(.ppSheetTitle)
            .foregroundStyle(.pp(.textPrimary))
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ part: PlanPart, scroller: ScrollViewProxy) -> some View {
        let value = item.value(of: part, locale: locale)
        return ValueRow(
            title: item.label(of: part),
            value: value?.number ?? "",
            suffix: value?.suffix,
            amount: item.amount(of: part),
            spokenValue: item.spokenValue(of: part, locale: locale),
            isOpen: open == part,
            identifier: "plan.\(part)",
            onToggle: { show(open == part ? nil : part, scroller: scroller) },
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
            ExerciseSheet(item: $item, room: 800) { }
        }
}
