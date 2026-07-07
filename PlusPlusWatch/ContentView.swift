import SwiftUI
import PlusPlusKit

/// Workout list on the wrist: whatever the phone last pushed. The ++
/// mark and mono metadata keep the quiet-terminal voice at 40 mm.
struct ContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.plan, !plan.workouts.isEmpty {
                    List(plan.workouts) { workout in
                        NavigationLink {
                            WorkoutRunView(workout: workout)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.headline)
                                Text("\(workout.steps.count) sets")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("++")
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Open PlusPlus on your iPhone to sync workouts.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("++")
        }
    }
}
