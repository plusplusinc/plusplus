import SwiftUI
import WatchKit
import WatchConnectivity
import PlusPlusKit

/// Wrist execution. Since #513 the screen RENDERS THE REDUCER: step
/// index, completion, rest, pause and lifecycle all read the journaled
/// live-session state, so a set logged on the phone advances the wrist,
/// a phone finish closes this view, a relaunch resumes at the first
/// incomplete step, and both devices stop clobbering each other's logs.
/// What stays LOCAL is what only this wrist knows: the measured results
/// (per-step HR, GPS splits) it ships home at finish.
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
    /// When the CURRENT step's work began — set as its screen appears, so
    /// a logged effort records how long it actually took rather than how
    /// long it was prescribed. Rest sits on its own screen, so a step's
    /// clock never includes the recovery before it.
    @State private var stepStartedAt: Date?
    /// The measured cumulative distance as this step began. Subtracting it
    /// from the running total is what gives one piece its own split
    /// instead of the whole session's.
    @State private var distanceAtStepStart: Double?
    /// What THIS WRIST measured, by step index (#513) — the reducer is
    /// the shared truth for completion, but only the wrist knows a set's
    /// HR window and GPS split, and only for the sets it logged itself.
    @State private var measuredByIndex: [Int: WatchSync.StepResult] = [:]
    /// Whether the current countdown is a transition — a different
    /// exercise or block up next (#369) — so the label says "switch".
    /// The op can't carry the flavor, so a phone-authored rest says
    /// "rest" (accepted, stage-3 review).
    @State private var currentRestIsTransition = false
    @State private var finished = false
    /// The PHONE closed the session (discard) — suppresses the
    /// onDisappear partial-finish, which would resurrect a discarded
    /// session through the import.
    @State private var closedRemotely = false

    /// One HealthKit workout session per run view (#90). @Observable in
    /// @State: stable storage across re-renders, and the live bpm
    /// readings re-render the step/rest views as they arrive.
    @State private var health = WatchWorkoutController()

    /// The reducer state, only while it is the session THIS WRIST is
    /// authoring — a displaced foreign session renders nothing here.
    private var authoringState: LiveSession.State? {
        guard let state = store.live.state,
              store.live.authoringSessionId == state.sessionId else { return nil }
        return state
    }

    /// The step list the session actually holds: the reducer's (which
    /// follows the phone's mid-session appends/swaps/removes via
    /// `.stepsChanged`) once authoring, the frozen plan before. A plan
    /// RE-PUSH still never swaps a live list — only deliberate ops do.
    private var activeSteps: [WatchSync.Step] { authoringState?.steps ?? routine.steps }

    /// Where the session is: the shared cursor, except that a cursor
    /// parked on an already-completed slot (the phone jumped there, then
    /// a set landed) yields to the first incomplete step.
    private var stepIndex: Int {
        guard let state = authoringState else { return measuredByIndex.count }
        if state.log(at: state.currentIndex)?.completedAt == nil { return state.currentIndex }
        return state.firstIncompleteIndex
    }

    private var completedCount: Int {
        authoringState?.completedCount ?? measuredByIndex.count
    }

    private var currentStep: WatchSync.Step? {
        activeSteps.indices.contains(stepIndex) ? activeSteps[stepIndex] : nil
    }

    /// The run's pace/distance denomination (an outdoor routine is
    /// homogeneous, so the first step's unit speaks for it).
    private var runUnit: DistanceUnit { routine.steps.first?.distanceUnit ?? .miles }

    /// How far THIS step covered, measured. nil indoors (nothing is
    /// collected) and nil for a non-positive delta — standing still for a
    /// whole piece is not a distance, the same positive-measurement gate
    /// the phone's run summary applies.
    private func measuredStepDistance() -> Double? {
        guard let total = health.totalDistance else { return nil }
        let delta = total - (distanceAtStepStart ?? 0)
        return delta > 0 ? delta : nil
    }

    var body: some View {
        Group {
            if finished {
                doneView
            } else if authoringState?.isPaused == true {
                pausedView
            } else if let restEnd = authoringState?.restEndsAt,
                      restEnd.timeIntervalSinceNow > -1 {
                // An EXPIRED journaled rest (a relaunch mid-rest, the
                // emit that would have cleared it lost to suspension)
                // falls through to the step — never a 0:00 screen.
                restView(until: restEnd)
            } else if let step = currentStep {
                stepView(step)
            } else {
                doneView
            }
        }
        .navigationTitle(routine.name)
        .navigationBarBackButtonHidden(startedAt != nil && !finished)
        // The HK session starts as soon as the routine is opened —
        // runtime + heart rate from the first set, not the first log.
        // Adoption seats the shared cursor BEFORE any log (#513):
        // resume-after-relaunch and both-devices handoff both land here.
        .onAppear {
            store.live.adoptIfPresent(routine: routine)
            if authoringState != nil { startedAt = authoringState?.startedAt }
            health.start(modality: routine.sessionModality, unit: runUnit)
        }
        // The PHONE can close the session under us now that we render the
        // shared state (#513): a finish ships our measured share home; a
        // discard means discarded EVERYWHERE — sending a result would
        // resurrect the session through the import.
        .onChange(of: authoringState?.isFinished) { _, ended in
            guard ended == true, !finished else { return }
            finishClosedByPhone()
        }
        .onChange(of: authoringState?.discarded) { _, discarded in
            guard discarded == true, !finished else { return }
            closedRemotely = true
            WatchRestNotifier.cancel()
            health.discard()
            store.live.releaseAuthoring()
            dismiss()
        }
        // If the system pops us mid-session (plan row vanished after a
        // rename/delete on the phone), the logged sets still count:
        // partial history beats lost history, and the sessionId dedupe
        // makes a later resend harmless.
        .onDisappear {
            if startedAt != nil && !finished && !closedRemotely && !measuredByIndex.isEmpty {
                finish()
            } else if !finished {
                // Browsed in and left without logging: no workout
                // happened, so nothing reaches Health. No-op if finish()
                // already saved the HK session.
                health.discard()
            }
        }
    }

    /// The phone finished the shared session; the wrist's share of the
    /// record still goes home (the import MERGES it — HR, splits — and
    /// the phone-authoring guard means the finish itself is respected,
    /// never repeated).
    private func finishClosedByPhone() {
        WatchRestNotifier.cancel()
        health.finish()
        if !measuredByIndex.isEmpty {
            let sessionId = store.live.authoringSessionId
            store.send(WatchSync.SessionResult(
                routineName: authoringState?.routineName ?? routine.name,
                startedAt: authoringState?.startedAt ?? startedAt ?? Date(),
                endedAt: authoringState?.endedAt ?? Date(),
                restSeconds: routine.restSeconds,
                steps: builtResults(),
                averageHeartRate: health.averageBPM,
                maxHeartRate: health.maxBPM,
                sessionId: sessionId
            ))
        }
        store.live.releaseAuthoring()
        finished = true
    }

    /// The phone is holding the workout (#512/#513): the wrist shows the
    /// hold rather than a rest that can't tick or a key that shouldn't
    /// log. End early stays available — ending is not logging.
    private var pausedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Paused on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if measuredByIndex.isEmpty { dismiss() } else { finish() }
            } label: {
                Text(measuredByIndex.isEmpty ? "Leave" : "End early")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Step

    private func stepView(_ step: WatchSync.Step) -> some View {
        VStack(spacing: 8) {
            // The plan's own noun — pieces on an erg, reps on the track.
            // Absent where the sport counts nothing, on a plan pushed by
            // a phone that predates modalities, and at a count of ONE —
            // a single-effort run is not "rep 1/1" (#514).
            if let unit = step.workUnit, activeSteps.count > 1 {
                Text("\(unit.singular) \(stepIndex + 1)/\(activeSteps.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(step.exerciseName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            // An untargeted effort states nothing rather than "— reps"
            // (#514) — CardioHero's say-nothing rule, on the wrist.
            if !targetText(step).isEmpty {
                Text(targetText(step))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
            }

            // Live heart rate from the workout session, accent while
            // it sits inside the step's target band; the resolved
            // band (phone-side zone math) rides along as a fact.
            if let heart = heartLine(for: step) {
                heart
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .accessibilityLabel("Heart rate")
                    .accessibilityValue(health.latestBPM.map { "\($0) beats per minute" } ?? "")
            }

            // What this step has actually covered, against what it asked
            // for. The wrist was MEASURING this the whole time (it is what
            // a logged piece records) and never showed it, so a rower
            // pulling a 500 had no way to know how far in they were.
            if let distance = distanceLine(for: step) {
                distance
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .accessibilityLabel("Distance")
            }

            // Live GPS pace on an outdoor run, accent while meeting the
            // step's pace target — same treatment as the heart line.
            if let pace = paceLine(for: step) {
                pace
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .accessibilityLabel("Pace")
                    .accessibilityValue(health.livePaceSeconds.map { "\(WorkoutMetric.pace.formatted($0)) \(runUnit.paceLabel)" } ?? "")
            }

            // The wrist's one big commit, in the phone's grammar: a
            // cream raised key (actions are ink/cream — green stays on
            // data), sinking onto its plate. A count of one drops the
            // noun — "Log", never "Log rep", about a single run (#514).
            Button {
                log(step)
            } label: {
                Text(activeSteps.count > 1 ? (step.workUnit.map { "Log \($0.singular)" } ?? "Log") : "Log")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(WatchTheme.primaryFill, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(WatchRaisedKeyStyle())

            // The early exit: logged sets ship as a partial session
            // (append-only history keeps what happened); an untouched
            // session just leaves. The extra top gap is the rest
            // screen's own adjacency lesson (#514): a commit key and an
            // end-the-workout key must not sit one slip apart.
            Button {
                if measuredByIndex.isEmpty {
                    dismiss()
                } else {
                    finish()
                }
            } label: {
                Text(measuredByIndex.isEmpty ? "Leave" : "End early")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        // The step's own clock and odometer start when its screen does.
        // Re-entering the same step (a rest ending) restarts neither —
        // the id keeps this to genuine step changes.
        .onAppear {
            stepStartedAt = Date()
            if distanceAtStepStart == nil { distanceAtStepStart = health.totalDistance }
        }
        .id(stepIndex)
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
        // An untargeted effort (a quick-started run: no reps, no weight,
        // no extras) says NOTHING rather than "— reps" (#514).
        guard step.targetRepsLower != nil || step.targetRepsUpper != nil else { return "" }
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

    /// "1,240 m · 500 m" — this step's measured distance beside its
    /// target, the distance going accent once the target is met. Mirrors
    /// the pace line's grammar exactly (live value first, target after the
    /// separator). nil when nothing is measuring, which is every indoor
    /// step and every strength one.
    private func distanceLine(for step: WatchSync.Step) -> Text? {
        guard let covered = measuredStepDistance() else { return nil }
        let unit = step.distanceUnit ?? health.distanceUnit
        let target = step.extraTargets?[WorkoutMetric.distance.rawValue]
        let reached = target.map { covered >= $0 } ?? false
        var line = Text("\(Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")) \(WorkoutMetric.distance.displayText(covered, distanceUnit: unit))")
            .foregroundStyle(reached ? WatchTheme.accent : .secondary)
        if let target {
            line = line + Text(" · \(WorkoutMetric.distance.displayText(target, distanceUnit: unit))").foregroundStyle(.secondary)
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
        // Capture the slot BEFORE the emit advances the shared cursor.
        let index = stepIndex
        if startedAt == nil {
            startedAt = now
            // Originate (or resume) the mirrored session on first log (#322).
            store.live.beginIfNeeded(routine: routine, startedAt: now)
        }
        WKInterfaceDevice.current().play(.success)
        // Load and reps are the user's ASSERTION — tapping Log is the
        // claim that the prescribed set happened, and the wrist has no
        // way to measure otherwise (editing stays on the phone).
        let weight = step.isDuration ? nil : step.targetWeight
        let reps = step.isDuration ? nil : step.targetRepsLower

        // Everything below is MEASURED, and measurement beats the plan.
        // This is the fix for the wrist recording your target as your
        // result: a 500 m piece rowed to 412 m logged as 500 m.
        let elapsed = stepStartedAt.map { now.timeIntervalSince($0) }
        let stepDistance = measuredStepDistance()
        let unit = step.distanceUnit ?? health.distanceUnit
        var measured: [WorkoutMetric: Double] = [:]
        if let stepDistance { measured[.distance] = stepDistance }
        if let split = LoggedActuals.pace(distance: stepDistance, elapsedSeconds: elapsed, unit: unit) {
            measured[.pace] = split
        }
        let extras = LoggedActuals.extras(
            planned: MetricValues.fromRaw(step.extraTargets),
            measured: measured
        )
        // A timed hold ran for as long as it ran. Falling back to the
        // target only when the step was never timed keeps a plan pushed
        // by an older phone behaving as it did.
        let duration = step.isDuration
            ? (elapsed.map { Int($0.rounded()) } ?? step.targetDuration)
            : nil

        measuredByIndex[index] = WatchSync.StepResult(
            step: step,
            actualWeight: weight,
            actualReps: reps,
            actualDuration: duration,
            extraActuals: MetricValues.toRaw(extras),
            // The wrist wears the sensor, so it is the device that
            // actually knows what this step cost. Per STEP, not per
            // session — the builder's own statistics are the wrong window.
            averageHeartRate: health.stepAverageBPM,
            maxHeartRate: health.stepMaxBPM,
            completedAt: now
        )
        distanceAtStepStart = health.totalDistance
        health.beginStep()
        // Mirror the logged set to the phone — at the SHARED cursor's
        // slot, not a local count (#513): the phone may have logged sets
        // of this session too, and each log lands where it happened.
        store.live.logged(index: index, weight: weight, reps: reps, duration: duration, extras: MetricValues.toRaw(extras) ?? [:], at: now)
        // The emit already folded into the reducer, so the shared state
        // answers "what's next" — including sets the PHONE completed.
        let nextIndex = authoringState?.firstIncompleteIndex ?? measuredByIndex.count
        if nextIndex < activeSteps.count {
            // A new round of the same block rests — the just-logged
            // block's override (interval blocks) wins over the routine
            // default, same rule as the phone. Moving to a different
            // exercise or block is the shorter transition (#369); a plan
            // from a pre-transition phone (nil) rests everywhere.
            let next = activeSteps[nextIndex]
            let newRoundOfSameBlock = next.groupIndex == step.groupIndex && next.setNumber != step.setNumber
            let restLength = newRoundOfSameBlock
                ? (step.restSecondsOverride ?? routine.restSeconds)
                : (routine.transitionSeconds ?? step.restSecondsOverride ?? routine.restSeconds)
            // A 0-second transition means no countdown at all.
            if restLength > 0 {
                currentRestIsTransition = !newRoundOfSameBlock && routine.transitionSeconds != nil
                let end = now.addingTimeInterval(TimeInterval(restLength))
                store.live.restStarted(endsAt: end, total: restLength)
                // The in-app haptic only fires while the app is frontmost;
                // with the wrist down the app suspends, so a local
                // notification carries the "rest over" signal.
                WatchRestNotifier.schedule(at: end, exerciseName: next.exerciseName, isTransition: currentRestIsTransition)
            }
        } else {
            finish()
        }
    }

    // MARK: - Rest

    private func restView(until end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, end.timeIntervalSince(context.date))
            VStack(spacing: 10) {
                Text(currentRestIsTransition ? "switch" : "rest")
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
                    // Fires for PHONE-authored rests too now that the
                    // screen renders the shared rest (#513) — the haptic
                    // parity the assessment called B9.
                    WKInterfaceDevice.current().play(.notification)
                    WatchRestNotifier.cancel()
                    store.live.restEnded()
                }
            }
        }
    }

    /// 12 blocks draining left-to-right — the rest length is the
    /// denominator, so a long rest and a short one both read as one
    /// full recharge.
    private func rechargeBlocks(remaining: TimeInterval) -> some View {
        // The shared rest carries its own denominator (#513) — a phone
        // ±15s adjustment re-emits restStarted with the new total.
        let total = max(authoringState?.restTotal ?? 90, 1)
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

    /// The result's step list, index-faithful (#513): the wrist's own
    /// measured entries where it logged, the reducer's slots where the
    /// PHONE logged (their actuals, no wrist measurements to claim), and
    /// bare incompletes for what never happened — so the phone's import
    /// can walk it by order whatever mix of devices did the work.
    private func builtResults() -> [WatchSync.StepResult] {
        guard let state = authoringState else {
            // Never originated on this wrist: the measured map is dense
            // 0..n by construction (the pre-#513 shape).
            return (0..<measuredByIndex.count).compactMap { measuredByIndex[$0] }
        }
        return state.steps.enumerated().map { index, step in
            if let mine = measuredByIndex[index] { return mine }
            let slot = state.log(at: index)
            return WatchSync.StepResult(
                step: step,
                actualWeight: slot?.actualWeight,
                actualReps: slot?.actualReps,
                actualDuration: slot?.actualDuration,
                extraActuals: (slot?.extras.isEmpty ?? true) ? nil : slot?.extras,
                completedAt: slot?.completedAt
            )
        }
    }

    private func finish() {
        WatchRestNotifier.cancel()
        health.finish()
        let now = Date()
        // ⚠️ Capture BEFORE the finished op — it clears the authoring id.
        // The result carries the same identity the ops carried, so the
        // phone's import keys on it instead of (name, startedAt) (#511).
        let sessionId = store.live.authoringSessionId
        let steps = builtResults()
        // Tell the phone the mirrored session is done (#322). The full
        // SessionResult below still ships as the durable history import;
        // the op just closes the live session promptly.
        store.live.finished(at: now)
        store.send(WatchSync.SessionResult(
            routineName: authoringState?.routineName ?? routine.name,
            startedAt: authoringState?.startedAt ?? startedAt ?? now,
            endedAt: now,
            restSeconds: routine.restSeconds,
            steps: steps,
            // The wrist's own live-builder summary — the phone stamps
            // it onto the imported session (nil when Health said no).
            averageHeartRate: health.averageBPM,
            maxHeartRate: health.maxBPM,
            sessionId: sessionId
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
            // The PLAN's resolved noun (one plan, one noun — a first-step
            // read gets a mixed plan wrong), through the same
            // count-of-one refusal every phone record surface applies: a
            // walk logged from the wrist used to say "1 set logged",
            // which is the exact line #491 removed from the phone.
            if let counted = WorkUnit.summaryCount(routine.sessionModality.primary.workUnit, completedCount) {
                Text("\(counted) logged")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // Honest about delivery (#514): reachable means the live op
            // just landed; otherwise the queue delivers when the phone
            // is next in range — "synced" would be a claim, not a fact.
            Text(WCSession.default.isReachable ? "Synced to your iPhone." : "On its way to your iPhone.")
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
