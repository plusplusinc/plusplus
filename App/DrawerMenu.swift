import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, and Routines, which shows every routine, with three routines
/// under it and New, an action, last: each routine's node, and New's plus, sit in the column of
/// Routines' icon. The place showing is marked; one always is. An untouched new routine showing
/// is the first of the three, then the two last opened or edited; otherwise they are the three
/// last opened or edited, the last edited first.
struct DrawerMenu: View {
    let session: RoutineSession
    let namer: RoutineNamer

    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Tapping the title closes the drawer, as a tap on the screen beside it does.
                Button {
                    session.isDrawerOpen = false
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
                    Button("Routines", systemImage: "rectangle.stack") {
                        session.showRoutines()
                    }
                    .buttonStyle(.drawer(isSelected: session.showing == .routines))
                    routines
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
        }
        // The drawer is built as it opens, so these run on each opening.
        .task { isTitleFocused = true }
        .task { await session.refreshRecent(weightUnit: weightUnit) }
        .hotReloadable()
    }

    /// The new routine showing, if one is, then the routines last opened or edited, three in
    /// all, then New.
    private var routines: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // A later card will put the upcoming scheduled routine at the top of these.
            if isNewShowing {
                newRoutine
            }
            ForEach(session.recentByEdit(first: savedCount)) { routine in
                Button {
                    Task { await session.open(routine.id, weightUnit: weightUnit) }
                } label: {
                    Label {
                        Text(namer.listedName(of: routine))
                    } icon: {
                        DrawerNode(isLit: isShowing(routine))
                    }
                }
                .buttonStyle(.drawer(isSelected: isShowing(routine), isNested: true))
            }
            // An action, never marked: what it makes shows as the row above.
            Button("New", systemImage: "plus") {
                Task { await session.startNew() }
            }
            .buttonStyle(.drawer(isSelected: false, isNested: true))
        }
    }

    /// The untouched new routine showing, named as its title is, in the title's placeholder gray.
    /// Saved once it changes, it lists as any routine; left untouched, it goes.
    private var newRoutine: some View {
        Button {
            Task { await session.startNew() }
        } label: {
            Label {
                Text(RoutineScreen.defaultName)
                    .foregroundStyle(.pp(.textSecondary))
            } icon: {
                DrawerNode(isLit: true)
            }
        }
        .buttonStyle(.drawer(isSelected: true, isNested: true))
    }

    private var isNewShowing: Bool {
        session.showing == .new
    }

    /// Three rows in all: the new one showing takes the place of the third.
    private var savedCount: Int {
        isNewShowing ? Self.recentCount - 1 : Self.recentCount
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
