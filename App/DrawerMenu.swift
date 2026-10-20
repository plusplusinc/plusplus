import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, and Routines, which shows every routine, with the three
/// routines last opened or edited and New under it. The item for what's showing is marked;
/// one always is.
struct DrawerMenu: View {
    let session: RoutineSession
    let namer: RoutineNamer

    /// The order the routines are drawn in, taken as the drawer opens, so the one tapped moves
    /// to the top on the next opening, not as the drawer slides shut.
    @State private var order: [Routine.ID] = []
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
        .task {
            order = session.recent.map(\.id)
            await session.refreshRecent(weightUnit: weightUnit)
            order = session.recent.map(\.id)
        }
        .hotReloadable()
    }

    /// The routines last opened or edited, up to three, then New.
    private var routines: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // A later card makes the last of these the upcoming scheduled routine.
            ForEach(session.recent.held(in: order).prefix(Self.recentCount)) { routine in
                Button(namer.shownName(of: routine) ?? String(localized: "New routine")) {
                    Task { await session.open(routine.id, weightUnit: weightUnit) }
                }
                .buttonStyle(.drawer(isSelected: isShowing(routine), isNested: true))
            }
            Button("New", systemImage: "plus") {
                Task { await session.startNew() }
            }
            .buttonStyle(.drawer(isSelected: session.showing == .new, isNested: true))
            .accessibilityLabel("New routine")
        }
    }

    private static let recentCount = 3

    private func isShowing(_ routine: Routine) -> Bool {
        session.showing == .routine && routine.id == session.current.id
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
