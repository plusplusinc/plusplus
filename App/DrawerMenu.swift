import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, and Routines, which shows every routine.
struct DrawerMenu: View {
    let session: RoutineSession

    @AccessibilityFocusState private var isTitleFocused: Bool
    @ObserveHotReload private var hotReload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(verbatim: "PlusPlus")
                    .ppDrawerTitleFont()
                    .foregroundStyle(.pp(.textPrimary))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                Button("Routines", systemImage: "rectangle.stack") {
                    session.showRoutines()
                }
                .buttonStyle(.drawer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
        }
        .background { Color.pp(.background).ignoresSafeArea() }
        // The drawer is built as it opens, so this runs on each opening.
        .task { isTitleFocused = true }
        .hotReloadable()
    }
}

#Preview {
    DrawerMenu(session: RoutineSession(routine: Routine(name: "Upper body"), store: nil))
}
