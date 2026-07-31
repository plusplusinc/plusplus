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
                    let planned = plan.routines.filter { $0.isQuickStart != true }
                    let quick = plan.routines.filter { $0.isQuickStart == true }
                    List {
                        ForEach(Array(planned.enumerated()), id: \.offset) { _, routine in
                            NavigationLink {
                                WorkoutRunView(routine: routine)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routine.name)
                                        .font(.headline)
                                    Text("\(routine.steps.count) \(routine.sessionModality.primary.workUnit?.plural ?? "sets")")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        // The spontaneous sports (#513): one tap opens the
                        // run, the first log starts the session — the
                        // wrist no longer needs the phone to go for a run.
                        if !quick.isEmpty {
                            Section("Quick start") {
                                ForEach(Array(quick.enumerated()), id: \.offset) { _, routine in
                                    NavigationLink {
                                        WorkoutRunView(routine: routine)
                                    } label: {
                                        // The sport alone — a one-step
                                        // scratch plan has no count worth
                                        // naming (#514's count-of-one).
                                        Text(routine.name)
                                            .font(.headline)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("++")
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(WatchTheme.accent)
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
