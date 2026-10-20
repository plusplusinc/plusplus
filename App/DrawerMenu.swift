import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, and Routines, which shows every routine, with three routines
/// under it and New, an action, last: each routine's node, and New's plus, sit in the column of
/// Routines' icon. The place showing is marked; one always is. An untouched new routine showing
/// is the first of the three, then the two last opened or edited; otherwise they are the three
/// last opened or edited, the last edited first.
///
/// Nothing in it changes while any of it shows: its rows and the mark are taken as it starts to
/// show and held until it has fully closed, so a tap that switches routines, or a swipe, never
/// moves a row under the finger. The next opening shows them as they are then.
struct DrawerMenu: View {
    let session: RoutineSession
    let namer: RoutineNamer

    /// The rows and the mark as the drawer started to show. The drawer is in the hierarchy only
    /// while it shows, so this is taken anew each time it starts to.
    @State private var held: Contents?
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
                    .buttonStyle(.drawer(isSelected: contents.showing == .routines))
                    routines
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
        }
        // The drawer is built as it starts to show, so these run each time it does, before its
        // first frame.
        .onAppear { held = contents }
        .task { isTitleFocused = true }
        .hotReloadable()
    }

    /// The new routine showing, if one is, then the routines last opened or edited, three in
    /// all, then New.
    private var routines: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // A later card will put the upcoming scheduled routine at the top of these.
            if contents.showing == .new {
                newRoutine
            }
            ForEach(contents.routines) { routine in
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

    /// What the drawer draws: as it started to show, or, before then, as the session is now.
    private var contents: Contents {
        held ?? Contents(session)
    }

    private func isShowing(_ routine: Routine) -> Bool {
        contents.showing == .routine && routine.id == contents.openID
    }

    /// The drawer's routines and its mark, taken from the session at one moment.
    private struct Contents {
        let showing: RoutineSession.Showing
        let openID: Routine.ID
        /// Three rows in all: an untouched new routine showing takes the place of the third.
        let routines: [Routine]

        init(_ session: RoutineSession) {
            showing = session.showing
            openID = session.current.id
            routines = session.recentByEdit(first: showing == .new ? 2 : 3)
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
