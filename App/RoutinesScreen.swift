import DesignSystem
import SwiftUI
import WorkoutStore

/// Every saved routine, most recently opened or edited first, each its name over its equipment.
/// Tapping one opens it on the routine screen; + opens a new one.
struct RoutinesScreen: View {
    let session: RoutineSession
    let namer: RoutineNamer

    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Routines")
                        .ppScreenTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Spacing.md)
                    ForEach(session.recent) { routine in
                        if routine.id != session.recent.first?.id {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MenuButton(session: session)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New routine", systemImage: "plus") {
                        Task { await session.startNew() }
                    }
                }
            }
        }
        .task { await session.refreshRecent(weightUnit: weightUnit) }
        .hotReloadable()
    }

    private func row(_ routine: Routine) -> some View {
        Button {
            Task { await session.open(routine.id, weightUnit: weightUnit) }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // A later card puts the routine's schedule trailing, beside the name.
                Text(namer.shownName(of: routine) ?? String(localized: "New routine"))
                    .font(.ppRoutineName)
                    .foregroundStyle(.pp(.textPrimary))
                    .multilineTextAlignment(.leading)
                let equipment = routine.exercises.map(\.exercise).equipment
                if !equipment.isEmpty {
                    Capsules(equipment.map(\.name))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routines.row")
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
