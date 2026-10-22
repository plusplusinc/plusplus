import DesignSystem
import SwiftUI
import WorkoutStore

/// Every saved routine, most recently opened or edited first, each by its name.
/// Tapping one pushes it on the routine screen; + pushes a new one.
struct RoutinesScreen: View {
    @Bindable var session: RoutineSession
    let namer: RoutineNamer

    /// The order the rows are drawn in, taken only while the list is out of sight or as it
    /// shows, so a routine opened from it moves to the top unseen, not as it slides away.
    @State private var order: [Routine.ID] = []
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Routines")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Spacing.md)
                    ForEach(shown, content: row)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
            }
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .onAppear(perform: takeOrder)
            .onDisappear(perform: takeOrder)
            .navigationDestination(isPresented: $session.isRoutinePushed) {
                // Each routine opened gives a fresh screen: scroll, sheets, and title.
                RoutineScreen(session: session, namer: namer, isPushed: true)
                    .id(session.opened.id)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MenuButton(session: session)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New routine", systemImage: "plus") {
                        Task { await session.startNew(pushed: true) }
                    }
                    .hiddenBehindDrawer()
                }
            }
        }
        .task {
            await session.refreshRecent(weightUnit: weightUnit)
            takeOrder()
        }
        .hotReloadable()
    }

    private func row(_ routine: Routine) -> some View {
        Button {
            Task { await session.open(routine.id, weightUnit: weightUnit, pushed: true) }
        } label: {
            NameRow(namer.listedName(of: routine))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routines.row")
    }

    private var shown: [Routine] {
        session.recent.held(in: order)
    }

    private func takeOrder() {
        order = session.recent.map(\.id)
    }

    private var weightUnit: WeightUnit {
        WeightUnit(region: locale)
    }
}

#Preview {
    RoutinesScreen(
        session: RoutineSession(routine: Routine(name: "Upper body"), store: nil),
        namer: .muscleGroupsOnly,
    )
}

extension RoutineNamer {
    /// A routine's name where routines are listed: the name it shows, else New routine.
    func listedName(of routine: Routine) -> String {
        shownName(of: routine) ?? RoutineScreen.defaultName
    }
}
