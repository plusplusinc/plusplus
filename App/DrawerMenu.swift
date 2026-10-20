import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, and Routines, which shows every routine, with the routine
/// last opened and New under it. The item for what's showing is marked; one always is.
struct DrawerMenu: View {
    let session: RoutineSession
    let namer: RoutineNamer

    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(verbatim: "PlusPlus")
                    .ppFixedTitleFont()
                    .foregroundStyle(.pp(.textPrimary))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                    .padding(.horizontal, Spacing.sm)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button("Routines", systemImage: "rectangle.stack") {
                        session.showRoutines()
                    }
                    .buttonStyle(.drawer(isSelected: session.showing == .routines))
                    routines
                        .padding(.leading, Spacing.lg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
        }
        .background { Color.pp(.background).ignoresSafeArea() }
        // The drawer is built as it opens, so these run on each opening.
        .task { isTitleFocused = true }
        .task { await session.refreshRecent(weightUnit: weightUnit) }
        .hotReloadable()
    }

    /// The routine last opened, then New.
    private var routines: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // A later card puts the upcoming scheduled routine between these two.
            if let last = session.recent.first {
                Button(namer.shownName(of: last) ?? String(localized: "New routine")) {
                    Task { await session.open(last.id, weightUnit: weightUnit) }
                }
                .buttonStyle(.drawer(isSelected: session.showing == .routine, isNested: true))
            }
            Button("New", systemImage: "plus") {
                Task { await session.startNew() }
            }
            .buttonStyle(.drawer(isSelected: session.showing == .new, isNested: true))
            .accessibilityLabel("New routine")
        }
    }

    private var weightUnit: WeightUnit {
        WeightUnit(region: locale)
    }
}

#Preview {
    DrawerMenu(
        session: RoutineSession(routine: Routine(name: "Upper body"), store: nil),
        namer: .muscleGroupsOnly,
    )
}
