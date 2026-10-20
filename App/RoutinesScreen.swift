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
                    let routines = shown
                    ForEach(routines) { routine in
                        if routine.id != routines.first?.id {
                            Hairline()
                        }
                        row(routine)
                    }
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
            // A later card puts the routine's schedule trailing, beside the name.
            Text(namer.shownName(of: routine) ?? String(localized: "New routine"))
                .font(.ppRoutineName)
                .foregroundStyle(.pp(.textPrimary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routines.row")
    }

    /// The routines as they are now, in the order taken; one not in it yet goes first.
    private var shown: [Routine] {
        let place = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return session.recent.enumerated()
            .sorted { (place[$0.element.id] ?? $0.offset - order.count)
                < (place[$1.element.id] ?? $1.offset - order.count)
            }
            .map(\.element)
    }

    private func takeOrder() {
        order = session.recent.map(\.id)
    }

    private var weightUnit: WeightUnit {
        WeightUnit(region: locale)
    }
}

/// The thinnest line the screen can draw, between rows.
private struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(.pp(.borderStrong))
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

#Preview {
    RoutinesScreen(
        session: RoutineSession(routine: Routine(name: "Upper body"), store: nil),
        namer: .muscleGroupsOnly,
    )
}
