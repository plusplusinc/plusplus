import SwiftUI
import SwiftData

/// The at-the-gym screen: walks through a session's set logs one at a time,
/// logging actuals, with a rest countdown between sets. Presented full
/// screen; leaving mid-session requires an explicit finish or discard.
struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSession

    /// When set and in the future, we're resting until this instant.
    /// Date-based so backgrounding the app keeps the countdown honest.
    @State private var restEndDate: Date?
    @State private var showingExitDialog = false

    private var totalSets: Int { session.sortedSetLogs.count }
    private var completedSets: Int { session.completedSetLogs.count }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .navigationTitle(session.workoutName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit", systemImage: "xmark") {
                        showingExitDialog = true
                    }
                    .accessibilityIdentifier("exitSessionButton")
                }
            }
            .confirmationDialog("End this workout?", isPresented: $showingExitDialog, titleVisibility: .visible) {
                if completedSets > 0 && !session.isFinished {
                    Button("Finish Workout") {
                        finishSession()
                    }
                }
                Button("Discard Workout", role: .destructive) {
                    modelContext.delete(session)
                    dismiss()
                }
                Button("Keep Going", role: .cancel) {}
            } message: {
                if completedSets > 0 {
                    Text("Finish keeps the \(completedSets) logged \(completedSets == 1 ? "set" : "sets"); Discard deletes the session.")
                } else {
                    Text("Nothing has been logged yet.")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if session.isFinished {
            finishedView
        } else if let currentLog = session.nextPendingLog {
            if let restEndDate, restEndDate > now {
                RestView(
                    endDate: restEndDate,
                    now: now,
                    upNext: currentLog,
                    onAddTime: { self.restEndDate = restEndDate.addingTimeInterval(15) },
                    onSkip: { self.restEndDate = nil }
                )
            } else {
                SetLoggingView(
                    log: currentLog,
                    setPosition: completedSets + 1,
                    totalSets: totalSets,
                    onComplete: { completeCurrentSet(currentLog) }
                )
            }
        } else {
            finishedView
                .onAppear { finishSession(dismissAfter: false) }
        }
    }

    private func completeCurrentSet(_ log: SetLog) {
        log.completedAt = Date()
        if session.nextPendingLog != nil {
            restEndDate = Date().addingTimeInterval(TimeInterval(session.restSeconds))
        } else {
            finishSession(dismissAfter: false)
        }
    }

    private func finishSession(dismissAfter: Bool = true) {
        if !session.isFinished {
            session.finish()
        }
        if dismissAfter {
            dismiss()
        }
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
            Text("Workout Complete")
                .font(.title2.bold())
            Text("\(completedSets) \(completedSets == 1 ? "set" : "sets") logged")
                .foregroundStyle(.secondary)
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .accessibilityIdentifier("sessionDoneButton")
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Set Logging

private struct SetLoggingView: View {
    @Bindable var log: SetLog
    let setPosition: Int
    let totalSets: Int
    let onComplete: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set \(setPosition) of \(totalSets)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(log.exerciseName)
                        .font(.title2.bold())
                    Text(targetDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                ProgressView(value: Double(setPosition - 1), total: Double(totalSets))
                    .tint(.indigo)
            }

            Section("Log this set") {
                if log.exerciseType == .duration {
                    MetricRow(metric: .duration, value: intMetricBinding($log.actualDuration))
                } else {
                    MetricRow(metric: .weight, value: $log.actualWeight)
                    MetricRow(metric: .reps, value: intMetricBinding($log.actualReps))
                }
            }
        }
        .onAppear(perform: prefillFromTarget)
        .onChange(of: log.order) {
            prefillFromTarget()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onComplete()
            } label: {
                Label("Complete Set", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .accessibilityIdentifier("completeSetButton")
            .padding()
            .background(.bar)
        }
    }

    /// Sets start prefilled with the plan's targets, so a set that went as
    /// planned is a single tap.
    private func prefillFromTarget() {
        if log.exerciseType == .duration {
            if log.actualDuration == nil { log.actualDuration = log.targetDuration }
        } else {
            if log.actualWeight == nil { log.actualWeight = log.targetWeight }
            if log.actualReps == nil { log.actualReps = log.targetRepsLower }
        }
    }

    private var targetDescription: String {
        if log.exerciseType == .duration {
            guard let seconds = log.targetDuration else { return "Set \(log.setNumber)" }
            return "Target: \(seconds) sec"
        }
        var parts: [String] = []
        if log.targetReps.lower != nil {
            parts.append("\(log.targetReps.display) reps")
        }
        if let weight = log.targetWeight {
            parts.append("@ \(WorkoutMetric.weight.formatted(weight)) lb")
        }
        return parts.isEmpty ? "Set \(log.setNumber)" : "Target: " + parts.joined(separator: " ")
    }
}

// MARK: - Rest

private struct RestView: View {
    let endDate: Date
    let now: Date
    let upNext: SetLog
    let onAddTime: () -> Void
    let onSkip: () -> Void

    private var remaining: Int {
        max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Rest")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(timeString)
                .font(.system(size: 64, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))

            VStack(spacing: 4) {
                Text("Up next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(upNext.exerciseName) — set \(upNext.setNumber)")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Button("+15s", action: onAddTime)
                    .buttonStyle(.bordered)
                Button("Skip Rest", action: onSkip)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .accessibilityIdentifier("skipRestButton")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeString: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Bridges optional Int storage to MetricRow's Double interface.
private func intMetricBinding(_ source: Binding<Int?>) -> Binding<Double?> {
    Binding(
        get: { source.wrappedValue.map(Double.init) },
        set: { source.wrappedValue = $0.map { Int($0.rounded()) } }
    )
}
