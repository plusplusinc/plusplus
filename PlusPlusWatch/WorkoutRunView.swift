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
    /// The current rest's configured length — the recharge blocks'
    /// denominator (per-block overrides make it vary between sets).
    @State private var currentRestTotal = 90
    @State private var finished = false

    /// One HealthKit workout session per run view (#90). @Observable in
    /// @State: stable storage across re-renders, and the live bpm
    /// readings re-render the step/rest views as they arrive.
    @State private var health = WatchWorkoutController()

    private var stepIndex: Int { results.count }
    private var currentStep: WatchSync.Step? {
        routine.steps.indices.contains(stepIndex) ? routine.steps[stepIndex] : nil
    }

    /// The run's pace/distance denomination (an outdoor routine is
    /// homogeneous, so the first step's unit speaks for it).
    private var runUnit: DistanceUnit { routine.steps.first?.distanceUnit ?? .miles }

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
        // The HK session starts as soon as the routine is opened —
        // runtime + heart rate from the first set, not the first log. An
        // all-outdoor routine runs as a GPS running session for live pace.
        .onAppear { health.start(outdoorRun: routine.isOutdoorRun, unit: runUnit) }
        // If the system pops us mid-session (plan row vanished after a
        // rename/delete on the phone), the logged sets still count:
        // partial history beats lost history, and the phone-side
        // (name, startedAt) dedupe makes a later resend harmless.
        .onDisappear {
            if startedAt != nil && !finished && !results.isEmpty {
                finish()
            } else {
                // Browsed in and left without logging: no workout
                // happened, so nothing reaches Health. No-op if finish()
                // already saved the HK session.
                health.discard()
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

            // Live heart rate from the workout session, accent while
            // it sits inside the step's target band; the resolved
            // band (phone-side zone math) rides along as a fact.
            if let heart = heartLine(for: step) {
                heart
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
            }

            // Live GPS pace on an outdoor run, accent while meeting the
            // step's pace target — same treatment as the heart line.
            if let pace = paceLine(for: step) {
                pace
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
            }

            // The wrist's one big commit, in the phone's grammar: a
            // cream raised key (actions are ink/cream — green stays on
            // data), sinking onto its plate.
            Button {
                log(step)
            } label: {
                Text("Log set")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(WatchTheme.primaryFill, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(WatchRaisedKeyStyle())

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
        // Flexible-metric steps (a rower's distance/damper) carry their
        // targets in extraTargets — the shared Kit line renders them
        // exactly like the phone's up-next card.
        if let extras = step.extraTargets, !extras.isEmpty {
            let values = MetricValues.fromRaw(extras)
            var metrics = Array(values.keys)
            if step.targetWeight != nil { metrics.append(.weight) }
            if step.targetRepsLower != nil { metrics.append(.reps) }
            if step.targetDuration != nil { metrics.append(.duration) }
            let profile = MetricProfile(metrics, distanceUnit: step.distanceUnit ?? .meters)
            let line = MetricSummary.line(
                profile: profile,
                repsText: step.targetRepsLower != nil
                    ? RepTarget(lower: step.targetRepsLower, upper: step.targetRepsUpper).display
                    : nil
            ) { metric in
                switch metric {
                case .weight: step.targetWeight
                case .reps: step.targetRepsLower.map(Double.init)
                case .duration: step.targetDuration.map(Double.init)
                default: values[metric]
                }
            }
            if let line { return line }
        }
        if step.isDuration {
            return WorkoutMetric.duration.displayText(step.targetDuration.map(Double.init))
        }
        var text = RepTarget(lower: step.targetRepsLower, upper: step.targetRepsUpper).display + " reps"
        if let weight = step.targetWeight, weight > 0 {
            text += " @ " + WorkoutMetric.weight.formatted(weight)
        }
        return text
    }

    /// "♥ 128 · 114–132" — the live reading (accent while in the
    /// step's band) plus the target band when the step carries one.
    /// nil when there's neither a reading nor a target.
    private func heartLine(for step: WatchSync.Step) -> Text? {
        let band: ClosedRange<Int>? = {
            guard let lower = step.targetHeartRateLowerBPM,
                  let upper = step.targetHeartRateUpperBPM else { return nil }
            return min(lower, upper)...max(lower, upper)
        }()
        var line: Text?
        if let bpm = health.latestBPM {
            let inBand = band.map { $0.contains(bpm) } ?? false
            line = Text("\(Image(systemName: "heart.fill")) \(bpm)")
                .foregroundStyle(inBand ? WatchTheme.accent : .secondary)
        }
        if let band {
            let bandText = Text("\(band.lowerBound)–\(band.upperBound)")
                .foregroundStyle(.secondary)
            line = line.map { $0 + Text(" · ").foregroundStyle(.secondary) + bandText } ?? bandText
        }
        return line
    }

    /// "🏃 8:30 /mi · 9:00" — live GPS pace, accent while meeting the
    /// step's pace target (pace improves DOWN, so actual ≤ target); the
    /// target trails as a fact. nil without a reading.
    private func paceLine(for step: WatchSync.Step) -> Text? {
        guard let pace = health.livePaceSeconds else { return nil }
        let target = step.extraTargets?[WorkoutMetric.pace.rawValue]
        let meeting = target.map { pace <= $0 } ?? false
        var line = Text("\(Image(systemName: "figure.run")) \(WorkoutMetric.pace.formatted(pace)) \(runUnit.paceLabel)")
            .foregroundStyle(meeting ? WatchTheme.accent : .secondary)
        if let target {
            line = line + Text(" · \(WorkoutMetric.pace.formatted(target))").foregroundStyle(.secondary)
        }
        return line
    }

    /// "♥ 128  🏃 8:30 /mi" — the rest screen's recovery vitals, quiet
    /// (no target judgment). nil when neither reading is live.
    private var restVitalsLine: Text? {
        var line: Text?
        if let bpm = health.latestBPM {
            line = Text("\(Image(systemName: "heart.fill")) \(bpm)")
        }
        if let pace = health.livePaceSeconds {
            let paceText = Text("\(Image(systemName: "figure.run")) \(WorkoutMetric.pace.formatted(pace)) \(runUnit.paceLabel)")
            line = line.map { $0 + Text("  ") + paceText } ?? paceText
        }
        return line
    }

    private func log(_ step: WatchSync.Step) {
        let now = Date()
        if startedAt == nil {
            startedAt = now
            // Originate (or resume) the mirrored session on first log (#322).
            store.live.beginIfNeeded(routine: routine, startedAt: now)
        }
        WKInterfaceDevice.current().play(.success)
        let weight = step.isDuration ? nil : step.targetWeight
        let reps = step.isDuration ? nil : step.targetRepsLower
        let duration = step.isDuration ? step.targetDuration : nil
        results.append(WatchSync.StepResult(
            step: step,
            actualWeight: weight,
            actualReps: reps,
            actualDuration: duration,
            completedAt: now
        ))
        // Mirror the logged set to the phone (its execution order is the
        // step's index in the shared plan).
        store.live.logged(index: results.count - 1, weight: weight, reps: reps, duration: duration, extras: step.extraTargets ?? [:], at: now)
        if results.count < routine.steps.count {
            // The just-logged block's rest override (interval blocks)
            // wins over the routine default — same rule as the phone.
            let restLength = step.restSecondsOverride ?? routine.restSeconds
            currentRestTotal = restLength
            let end = now.addingTimeInterval(TimeInterval(restLength))
            restEndsAt = end
            store.live.restStarted(endsAt: end, total: restLength)
            // The in-app haptic only fires while the app is frontmost;
            // with the wrist down the app suspends, so a local
            // notification carries the "rest over" signal.
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
                // The phone's recharge blocks at wrist scale: live
                // progress, so accent green, draining with the clock.
                rechargeBlocks(remaining: remaining)
                // Recovery at a glance — no band judgment during rest.
                // On a run, pace joins it while a walk break keeps moving
                // (it drops out when you stand still).
                if let vitals = restVitalsLine {
                    vitals
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Button {
                    WatchRestNotifier.cancel()
                    restEndsAt = nil
                    store.live.restEnded()
                } label: {
                    Text("Skip")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(WatchTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(WatchRaisedKeyStyle())
            }
            .onChange(of: remaining <= 0) { _, expired in
                if expired {
                    WKInterfaceDevice.current().play(.notification)
                    WatchRestNotifier.cancel()
                    restEndsAt = nil
                    store.live.restEnded()
                }
            }
        }
    }

    /// 12 blocks draining left-to-right — the rest length is the
    /// denominator, so a long rest and a short one both read as one
    /// full recharge.
    private func rechargeBlocks(remaining: TimeInterval) -> some View {
        let total = max(currentRestTotal, 1)
        let filled = min(12, Int((remaining / Double(total) * 12).rounded(.up)))
        return HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filled ? WatchTheme.accent : WatchTheme.surfaceRaised)
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .animation(.easeOut(duration: 0.15), value: filled)
    }

    // MARK: - Done

    private func finish() {
        WatchRestNotifier.cancel()
        health.finish()
        let now = Date()
        // Tell the phone the mirrored session is done (#322). The full
        // SessionResult below still ships as the durable history import;
        // the op just closes the live session promptly.
        store.live.finished(at: now)
        store.send(WatchSync.SessionResult(
            routineName: routine.name,
            startedAt: startedAt ?? now,
            endedAt: now,
            restSeconds: routine.restSeconds,
            steps: results,
            // The wrist's own live-builder summary — the phone stamps
            // it onto the imported session (nil when Health said no).
            averageHeartRate: health.averageBPM,
            maxHeartRate: health.maxBPM
        ))
        WKInterfaceDevice.current().play(.success)
        finished = true
    }

    private var doneView: some View {
        VStack(spacing: 8) {
            // Completion is purple (#201) — the workout just merged;
            // the ++ mark stays brand green.
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(WatchTheme.done)
            Text("\(results.count) sets logged")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Synced to your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(WatchTheme.onPrimary)
                    .padding(.horizontal, 20)
                    .frame(height: 34)
                    .background(WatchTheme.primaryFill, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(WatchRaisedKeyStyle())
        }
    }
}
