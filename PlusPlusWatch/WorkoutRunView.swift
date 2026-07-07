import SwiftUI
import WatchKit
import PlusPlusKit

/// Wrist execution (#6, v1): walk the pre-expanded step list — big Log
/// button, date-based rest countdown with haptics, done summary. Logs
/// as planned (weight editing stays on the phone for v1); the result
/// ships to the phone as append-only history.
struct WorkoutRunView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let workout: WatchSync.PlanWorkout

    @State private var startedAt: Date?
    @State private var results: [WatchSync.StepResult] = []
    @State private var restEndsAt: Date?
    @State private var finished = false

    private var stepIndex: Int { results.count }
    private var currentStep: WatchSync.Step? {
        workout.steps.indices.contains(stepIndex) ? workout.steps[stepIndex] : nil
    }

    var body: some View {
        Group {
            if finished {
                doneView
            } else if let restEndsAt {
                restView(until: restEndsAt)
            } else if let step = currentStep {
                stepView(step)
            } else {
                doneView
            }
        }
        .navigationTitle(workout.name)
        .navigationBarBackButtonHidden(startedAt != nil && !finished)
    }

    // MARK: - Step

    private func stepView(_ step: WatchSync.Step) -> some View {
        VStack(spacing: 8) {
            Text("set \(stepIndex + 1)/\(workout.steps.count)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(step.exerciseName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(targetText(step))
                .font(.system(.body, design: .monospaced, weight: .semibold))

            Button {
                log(step)
            } label: {
                Text("Log set")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    private func targetText(_ step: WatchSync.Step) -> String {
        if step.isDuration {
            return WorkoutMetric.duration.displayText(step.targetDuration.map(Double.init))
        }
        var text = RepTarget(lower: step.targetRepsLower, upper: step.targetRepsUpper).display + " reps"
        if let weight = step.targetWeight, weight > 0 {
            text += " @ " + WorkoutMetric.weight.formatted(weight)
        }
        return text
    }

    private func log(_ step: WatchSync.Step) {
        if startedAt == nil {
            startedAt = Date()
        }
        WKInterfaceDevice.current().play(.success)
        results.append(WatchSync.StepResult(
            step: step,
            actualWeight: step.isDuration ? nil : step.targetWeight,
            actualReps: step.isDuration ? nil : step.targetRepsLower,
            actualDuration: step.isDuration ? step.targetDuration : nil,
            completedAt: Date()
        ))
        if results.count < workout.steps.count {
            restEndsAt = Date().addingTimeInterval(TimeInterval(workout.restSeconds))
        } else {
            finish()
        }
    }

    // MARK: - Rest

    private func restView(until end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, end.timeIntervalSince(context.date))
            VStack(spacing: 10) {
                Text("rest")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Button("Skip") {
                    restEndsAt = nil
                }
            }
            .onChange(of: remaining <= 0) { _, expired in
                if expired {
                    WKInterfaceDevice.current().play(.notification)
                    restEndsAt = nil
                }
            }
        }
    }

    // MARK: - Done

    private func finish() {
        let now = Date()
        store.send(WatchSync.SessionResult(
            workoutName: workout.name,
            startedAt: startedAt ?? now,
            endedAt: now,
            restSeconds: workout.restSeconds,
            steps: results
        ))
        WKInterfaceDevice.current().play(.success)
        finished = true
    }

    private var doneView: some View {
        VStack(spacing: 8) {
            Text("++")
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(.green)
            Text("\(results.count) sets logged")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Synced to your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
        }
    }
}
