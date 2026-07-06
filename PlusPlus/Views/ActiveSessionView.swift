import SwiftUI
import SwiftData
import PlusPlusKit

/// The at-the-gym screen: walks through a session's set logs one at a time,
/// logging actuals, with a rest countdown between sets. Presented full
/// screen; leaving mid-session requires an explicit finish or discard.
struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSession

    /// Finished sessions, for "last time" lookups on the set screen.
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil })
    private var finishedSessions: [WorkoutSession]

    /// When set, we're resting until this instant. Date-based so
    /// backgrounding the app keeps the countdown honest. Only the rest
    /// screen ticks a clock — the set screen renders statically so taps
    /// never race a re-render.
    @State private var restEndDate: Date?
    @State private var showingExitDialog = false

    private var totalSets: Int { session.sortedSetLogs.count }
    private var completedSets: Int { session.completedSetLogs.count }

    var body: some View {
        NavigationStack {
            Group {
                if session.isFinished {
                    finishedView
                } else if let currentLog = session.nextPendingLog {
                    if let restEndDate {
                        RestView(
                            endDate: restEndDate,
                            upNext: currentLog,
                            onAddTime: {
                                let extended = restEndDate.addingTimeInterval(15)
                                self.restEndDate = extended
                                RestNotifier.shared.scheduleRestEnd(
                                    at: extended,
                                    exerciseName: currentLog.exerciseName,
                                    setNumber: currentLog.setNumber
                                )
                            },
                            onEnd: {
                                self.restEndDate = nil
                                RestNotifier.shared.cancelPending()
                            }
                        )
                    } else {
                        SetLoggingView(
                            log: currentLog,
                            lastTime: WorkoutSession.lastPerformance(matching: currentLog, in: finishedSessions),
                            // Workout intent shows once, on the first set —
                            // it's context, not per-set chrome.
                            workoutNotes: completedSets == 0 ? session.workout?.notes : nil,
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
                    RestNotifier.shared.cancelPending()
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
        .task {
            // First workout start is when the permission makes sense.
            RestNotifier.shared.requestAuthorizationIfNeeded()
        }
    }

    private func completeCurrentSet(_ log: SetLog) {
        log.completedAt = Date()
        if let upNext = session.nextPendingLog {
            let endDate = Date().addingTimeInterval(TimeInterval(session.restSeconds))
            restEndDate = endDate
            RestNotifier.shared.scheduleRestEnd(
                at: endDate,
                exerciseName: upNext.exerciseName,
                setNumber: upNext.setNumber
            )
        } else {
            finishSession(dismissAfter: false)
        }
    }

    private func finishSession(dismissAfter: Bool = true) {
        RestNotifier.shared.cancelPending()
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
                .foregroundStyle(Theme.accent)
            Text("Workout Complete")
                .font(.title2.bold())
            Text("\(completedSets) \(completedSets == 1 ? "set" : "sets") logged")
                .foregroundStyle(.secondary)
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .accessibilityIdentifier("sessionDoneButton")
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Set Logging

private struct SetLoggingView: View {
    @Bindable var log: SetLog
    let lastTime: SetLog?
    let workoutNotes: String?
    let setPosition: Int
    let totalSets: Int
    let onComplete: () -> Void

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

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
                    if let lastTime {
                        Text("Last time: \(lastTime.resultSummary(weightUnit: weightUnit))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let workoutNotes {
                        Text(workoutNotes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
                ProgressView(value: Double(setPosition - 1), total: Double(totalSets))
                    .tint(Theme.accent)
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
            .tint(Theme.accent)
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
            return "Target: \(WorkoutMetric.duration.displayText(Double(seconds)))"
        }
        var parts: [String] = []
        if log.targetReps.lower != nil {
            parts.append("\(log.targetReps.display) reps")
        }
        if let weight = log.targetWeight {
            parts.append("@ \(WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit))")
        }
        return parts.isEmpty ? "Set \(log.setNumber)" : "Target: " + parts.joined(separator: " ")
    }
}

// MARK: - Rest

/// The only ticking view in the session: renders the countdown and ends
/// itself (via `onEnd`) when the clock runs out.
private struct RestView: View {
    let endDate: Date
    let upNext: SetLog
    let onAddTime: () -> Void
    let onEnd: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))

            VStack(spacing: 24) {
                Text("Rest")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text(timeString(remaining))
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
                    Button("Skip Rest", action: onEnd)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .accessibilityIdentifier("skipRestButton")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: remaining) { _, newValue in
                if newValue <= 0 { onEnd() }
            }
            .onAppear {
                if remaining <= 0 { onEnd() }
            }
        }
    }

    private func timeString(_ remaining: Int) -> String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

