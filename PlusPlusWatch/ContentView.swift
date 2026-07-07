import SwiftUI
import PlusPlusKit

/// Routine list on the wrist: whatever the phone last pushed. The ++
/// mark and mono metadata keep the quiet-terminal voice at 40 mm.
struct ContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.plan, !plan.routines.isEmpty {
                    // Positional identity, not name-keyed: routine names
                    // aren't unique, and duplicate Identifiable IDs make
                    // ForEach misbehave (bug hunt A6).
                    List(Array(plan.routines.enumerated()), id: \.offset) { _, routine in
                        NavigationLink {
                            WorkoutRunView(routine: routine)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name)
                                    .font(.headline)
                                Text("\(routine.steps.count) sets")
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
                        Text("Open PlusPlus on your iPhone to sync routines.")
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
