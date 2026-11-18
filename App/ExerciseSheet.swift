import DesignSystem
import SwiftUI
import WorkoutStore

/// A routine row's own sheet: its values (`ExerciseValues`) on a stack, half height as it opens.
/// The More menu's Customize… pushes the exercise's Customize form inside the sheet (its back
/// chevron returns to the values, the change showing); Close and Remove close the sheet.
struct ExerciseSheet<Customize: View>: View {
    @Binding var item: RoutineExercise
    /// The names of the exercises in a superset with it, which share its round count, or nil.
    let partners: String?
    /// The values it steps, in order (`Routine.sheetParts(of:)`).
    let parts: [SheetPart]
    /// Its superset's rest; nil for a plain row.
    var rounds: RoundSteps?
    /// The exercise's Customize form; its closure goes back to the sheet.
    @ViewBuilder let customize: (_ back: @escaping () -> Void) -> Customize
    let onDelete: () -> Void
    /// Whether it opens with Customize pushed, as after Create.
    var opensCustomizing = false

    @State private var isCustomizing = false
    @State private var detent = PresentationDetent.medium
    /// The height the sheet grew to, to fit a row as it opened; a detent from then on, so the
    /// sheet stays there while it's open.
    @State private var fitted: CGFloat?
    /// The sheet's height inside its safe area, which a `.height` detent measures.
    @State private var sheetHeight: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseValues(
                item: $item,
                partners: partners,
                parts: parts,
                rounds: rounds,
                onClose: { dismiss() },
                onCustomize: { isCustomizing = true },
                onRemove: {
                    dismiss()
                    onDelete()
                },
                fit: growth,
            )
            .navigationDestination(isPresented: $isCustomizing) {
                customize { isCustomizing = false }
            }
        }
        .onAppear {
            if opensCustomizing {
                // Pushed before the first frame, with no push to see.
                withTransaction(\.disablesAnimations, true) { isCustomizing = true }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { sheetHeight = $0 }
        .presentationDetents(detents, selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.background))
    }

    private var detents: Set<PresentationDetent> {
        var detents: Set<PresentationDetent> = [.medium, .large]
        if let fitted {
            detents.insert(.height(fitted))
        }
        return detents
    }

    /// Below the large height, the sheet grows to fit a row as it opens; at large, it can't.
    private var growth: ((CGFloat) -> Void)? {
        detent == .large ? nil : { fit($0) }
    }

    /// At the medium height an open ruler sat near the screen's bottom edge, under the thumb's
    /// reach, and the rows under it were cut off. Any row that opens with the sheet below large
    /// grows it by what its content now overflows, in the row's own motion; the system holds a
    /// height past large to large. The content's size is the open row's from the first frame of
    /// its animation, so this lands a layout pass after the tap, not after the row has opened.
    /// In a sheet the scroll view's container already excludes the bar and the home indicator
    /// (measured on iOS 27), so the overflow alone is what the sheet grows by.
    private func fit(_ overflow: CGFloat) {
        let height = sheetHeight + overflow
        fitted = height
        withAnimation(ValueRow.motion) {
            detent = .height(height)
        }
    }
}
