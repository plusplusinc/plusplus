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

    /// Frozen at first render: the phone re-pushes the plan on every
    /// backgrounding, and a live session must not have its step list
    /// swapped out underneath it (@State survives the parent's
    /// re-renders; the init value applies only once).
    @State private var routine: WatchSync.PlanRoutine

    init(routine: WatchSync.PlanRoutine) {
        _routine = State(initialValue: routine)
    }

    @State private var startedAt: Date?
    @State private var results: [WatchSync.StepResult] = []
    @State private var restEndsAt: Date?
    @State private var finished = false

    private var stepIndex: Int { results.count }
    private var currentStep: WatchSync.Step? {
        routine.steps.indices.contains(stepIndex) ? routine.steps[stepIndex] : nil
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
        .navigationTitle(routine.name)
        .navigationBarBackButtonHidden(startedAt != nil && !finished)
        // If the system pops us mid-session (plan row vanished after a
        // rename/delete on the phone), the logged sets still count:
        // partial history beats lost history, and the phone-side
        // (name, startedAt) dedupe makes a later resend harmless.
        .onDisappear {
            if startedAt != nil && !finished && !results.isEmpty {
                finish()
            }
        }
    }

    // MARK: - Step

    private func stepView(_ step: WatchSync.Step) -> some View {
        VStack(spacing: 8) {
            Text("set \(stepIndex + 1)/\(routine.steps.count)")
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

            // The early exit: logged sets ship as a partial session
            // (append-only history keeps what happened); an untouched
            // session just leaves.
            Button {
                if results.isEmpty {
                    dismiss()
                } else {
                    finish()
                }
            } label: {
                Text(results.isEmpty ? "Leave" : "End early")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
        if results.count < routine.steps.count {
            let end = Date().addingTimeInterval(TimeInterval(routine.restSeconds))
            restEndsAt = end
            // The in-app haptic only fires while the app is frontmost;
            // with the wrist down the app suspends, so a local
            // notification carries the "rest over" signal (no
            // HKWorkoutSession in v1 — Health is deferred, #90).
            WatchRestNotifier.schedule(at: end, exerciseName: routine.steps[results.count].exerciseName)
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
                    WatchRestNotifier.cancel()
                    restEndsAt = nil
                }
            }
            .onChange(of: remaining <= 0) { _, expired in
                if expired {
                    WKInterfaceDevice.current().play(.notification)
                    WatchRestNotifier.cancel()
                    restEndsAt = nil
                }
            }
        }
    }

    // MARK: - Done

    private func finish() {
        WatchRestNotifier.cancel()
        let now = Date()
        store.send(WatchSync.SessionResult(
            routineName: routine.name,
            startedAt: startedAt ?? now,
            endedAt: now,
            restSeconds: routine.restSeconds,
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
