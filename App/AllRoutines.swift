import DesignSystem
import SwiftUI
import WorkoutStore

/// Every saved routine, most recently opened or edited first, each its name over how many
/// exercises it holds. Tapping one opens it.
struct AllRoutines: View {
    let session: RoutineSession
    let namer: RoutineNamer

    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        List(session.recent) { routine in
            Button {
                Task { await session.open(routine.id, weightUnit: WeightUnit(region: locale)) }
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(namer.shownName(of: routine) ?? String(localized: "New routine"))
                        .font(.ppRowTitle)
                        .foregroundStyle(.pp(.textPrimary))
                    Text("^[\(routine.exercises.count) exercise](inflect: true)")
                        .font(.ppRowDetail)
                        .foregroundStyle(.pp(.textSecondary))
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.pp(.surface))
        }
        .scrollContentBackground(.hidden)
        .background { Color.pp(.background).ignoresSafeArea() }
        .navigationTitle("All routines")
        .navigationBarTitleDisplayMode(.inline)
        .hotReloadable()
    }
}

#Preview {
    NavigationStack {
        AllRoutines(
            session: RoutineSession(routine: Routine(name: "Upper body"), store: nil),
            namer: .muscleGroupsOnly,
        )
    }
}
