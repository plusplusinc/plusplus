import DesignSystem
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title and its routines, New routine first, then the five most
/// recently opened or edited.
struct DrawerMenu: View {
    let session: RoutineSession
    let namer: RoutineNamer

    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    private static let recentCount = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: "PlusPlus")
                        .ppDrawerTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Spacing.sm)
                    Text("Routines")
                        .font(.ppRowDetail)
                        .foregroundStyle(.pp(.textSecondary))
                        .accessibilityAddTraits(.isHeader)
                    Button("New routine", systemImage: "plus") {
                        Task { await session.startNew() }
                    }
                    .buttonStyle(.key)
                    ForEach(session.recent.prefix(Self.recentCount)) { routine in
                        Button {
                            Task { await session.open(routine.id, weightUnit: weightUnit) }
                        } label: {
                            Label {
                                Text(namer
                                    .shownName(of: routine) ?? String(localized: "New routine"))
                                    .lineLimit(1)
                            } icon: {
                                // Holds the rail column, so names line up with New routine's.
                                Image(systemName: "plus").hidden()
                            }
                        }
                        .buttonStyle(.key)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
            .background { Color.pp(.background).ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: session.isDrawerOpen) {
            guard session.isDrawerOpen else { return }
            await session.refreshRecent(weightUnit: weightUnit)
        }
        .hotReloadable()
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
