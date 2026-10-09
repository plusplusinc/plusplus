import DesignSystem
import SwiftUI

/// The screen the app launches into: a new, empty routine.
///
/// The name lives only in memory for now. The app deliberately creates no `ModelContainer` yet:
/// storage wiring lives in `WorkoutStoreContainer` and gets connected when there is a data model
/// worth connecting.
struct RoutineScreen: View {
    @State private var name = Self.defaultName
    @ObserveHotReload private var hotReload

    private static let markWidth: CGFloat = 20
    /// A plus sits on the font's math axis, about a point below the middle of its line, so the
    /// mark is lifted to look centered in the round button.
    private static let markLift: CGFloat = 1

    private static let defaultName = String(localized: "New routine")

    var body: some View {
        NavigationStack {
            ScrollView {
                // The title's touch target already adds space below its text, so a small gap
                // leaves the button about 16pt under the name.
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    EditableTitle(
                        text: $name,
                        defaultText: Self.defaultName,
                        accessibilityLabel: "Routine name",
                        accessibilityHint: "Renames the routine.",
                    )
                    // The exercise picker is a later slice.
                    Button("Add exercise", systemImage: "plus") { }
                        .buttonStyle(.key)
                }
                .padding(.horizontal, Spacing.md)
            }
            .background(Color.pp(.background))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // The drawer is a later slice.
                    Button { } label: {
                        Text(verbatim: "++")
                            .font(.ppMark)
                            .foregroundStyle(.pp(.accent))
                            // The glass sizes itself to its label. Reserving less width than
                            // the mark's advance draws the mark large in a compact button.
                            .fixedSize()
                            .frame(width: Self.markWidth)
                            .offset(y: -Self.markLift)
                    }
                    .accessibilityLabel("Menu")
                }
            }
        }
        .hotReloadable()
    }
}

#Preview {
    RoutineScreen()
}
