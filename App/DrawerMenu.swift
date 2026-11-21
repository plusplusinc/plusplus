import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, then Routines, showing its list in place of the screen
/// showing. It is marked while it shows; while a routine shows, it isn't.
///
/// The mark doesn't change while any of it shows: it is taken as the drawer starts to show and
/// held until it has fully closed, so a tap that switches places never moves the mark under the
/// finger before the drawer slides away.
struct DrawerMenu: View {
    let session: RoutineSession

    /// The place showing as the drawer started to show. The drawer is in the hierarchy only
    /// while it shows, so this is taken anew each time it starts to.
    @State private var held: RoutineSession.Showing?
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        let showing = held ?? session.showing
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Tapping the title closes the drawer, as a tap on the screen beside it does.
                Button {
                    session.closeDrawer()
                } label: {
                    Text(verbatim: "PlusPlus")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Closes the menu")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .padding(.horizontal, Spacing.sm)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button("Routines", systemImage: "checklist") {
                        session.showRoutines()
                    }
                    .buttonStyle(.drawer(isSelected: showing == .routines))
                    Button("Log", systemImage: "book.closed") {
                        session.showLog()
                    }
                    .buttonStyle(.drawer(isSelected: showing == .log))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
        }
        // The drawer is built as it starts to show, so this runs each time it does, before its
        // first frame.
        .onAppear { held = session.showing }
        .task { isTitleFocused = true }
    }
}

#Preview {
    DrawerMenu(
        session: RoutineSession(
            routine: Routine(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
    )
}
