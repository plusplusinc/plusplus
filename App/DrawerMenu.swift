import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title and its routines, New routine first, then the five most
/// recently opened or edited, then All routines.
struct DrawerMenu: View {
    let session: RoutineSession
    let namer: RoutineNamer

    @AppStorage(Self.routinesExpandedKey) private var isRoutinesExpanded = true
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    /// Where the Routines heading's choice is kept, so it lasts across launches.
    static let routinesExpandedKey = "routinesExpanded"
    private static let recentCount = 5

    /// The one screen the drawer pushes.
    private enum Screen: Hashable {
        case allRoutines
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: "PlusPlus")
                        .ppDrawerTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isTitleFocused)
                        .padding(.bottom, Spacing.xs)
                    DrawerHeading("Routines", isExpanded: $isRoutinesExpanded)
                    if isRoutinesExpanded {
                        routines
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
            .background { Color.pp(.background).ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            // What the pushed screen's back button reads.
            .navigationTitle(Text(verbatim: "PlusPlus"))
            .navigationDestination(for: Screen.self) { _ in
                AllRoutines(session: session, namer: namer)
            }
        }
        // The drawer is built as it opens, so this runs on each opening.
        .task {
            isTitleFocused = true
            await session.refreshRecent(weightUnit: weightUnit)
        }
        .hotReloadable()
    }

    private var routines: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button("New routine", systemImage: "plus") {
                Task { await session.startNew() }
            }
            .buttonStyle(.key)
            ForEach(session.recent.prefix(Self.recentCount)) { routine in
                Button {
                    Task { await session.open(routine.id, weightUnit: weightUnit) }
                } label: {
                    Label {
                        Text(name(of: routine))
                            .lineLimit(1)
                    } icon: {
                        // Holds the rail column, so names line up with New routine's.
                        Image(systemName: "plus").hidden()
                    }
                }
                .buttonStyle(.key)
            }
            NavigationLink(value: Screen.allRoutines) {
                Label {
                    HStack {
                        Text("All routines")
                        Spacer(minLength: Spacing.sm)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.pp(.textSecondary))
                            .accessibilityHidden(true)
                    }
                } icon: {
                    Image(systemName: "list.bullet")
                }
            }
            .buttonStyle(.key)
        }
    }

    private func name(of routine: Routine) -> String {
        namer.shownName(of: routine) ?? String(localized: "New routine")
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
