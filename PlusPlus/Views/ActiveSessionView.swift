import SwiftUI
import SwiftData
import PlusPlusKit

/// The at-the-gym screen, v2 (#65/#66): End + set-counter pills, a
/// segment progress bar, big stepper cards, weight carry-forward, a
/// duration auto-timer, and a session overview with jump/redo. Presented
/// full screen; leaving mid-session requires an explicit finish/discard.
/// Only leaf views tick clocks (the elapsed pill, the rest screen, the
/// timer card) — the logging screen renders statically so taps never
/// race a re-render.
struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSession

    /// Finished sessions, for "last time" lookups on the set screen.
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil })
    private var finishedSessions: [WorkoutSession]

    /// When set, we're resting until this instant (date-based; backgrounding
    /// can't drift it).
    @State private var restEndDate: Date?
    @State private var showingExitDialog = false
    @State private var showingOverview = false
    @State private var burstCount = 0
    /// Flips on appear of the finished screen to fire the checkmark's
    /// one-shot bounce.
    @State private var completeBounce = false

    private var totalSets: Int { session.sortedSetLogs.count }
    private var completedSets: Int { session.completedSetLogs.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if session.isFinished {
                finishedView
            } else if let currentLog = session.currentLog {
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
                        session: session,
                        log: currentLog,
                        lastTime: WorkoutSession.lastPerformance(matching: currentLog, in: finishedSessions),
                        routineNotes: completedSets == 0 ? session.routine?.notes : nil,
                        burstCount: burstCount,
                        onComplete: { completeCurrentSet(currentLog) }
                    )
                    .id(currentLog.order)
                }
            } else {
                finishedView
                    .onAppear { finishSession(dismissAfter: false) }
            }
        }
        .background(Theme.background)
        .confirmationDialog("End this workout?", isPresented: $showingExitDialog, titleVisibility: .visible) {
            if completedSets > 0 && !session.isFinished {
                Button("Finish workout") {
                    finishSession()
                }
            }
            Button("Discard workout", role: .destructive) {
                RestNotifier.shared.cancelPending()
                modelContext.delete(session)
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            if completedSets > 0 {
                Text("Finish keeps the \(completedSets) logged \(completedSets == 1 ? "set" : "sets"); Discard deletes the session.")
            } else {
                Text("Nothing has been logged yet.")
            }
        }
        .sheet(isPresented: $showingOverview) {
            SessionOverviewSheet(session: session) {
                restEndDate = nil
                RestNotifier.shared.cancelPending()
            }
            .presentationDetents([.fraction(0.88)])
        }
        .interactiveDismissDisabled()
        .task {
            // First routine start is when the permission makes sense.
            RestNotifier.shared.requestAuthorizationIfNeeded()
            RestActivityController.shared.beginSession(routineName: session.routineName)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                showingExitDialog = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark").font(.system(.caption, weight: .semibold))
                    Text("End").font(.system(.footnote, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
            }
            .accessibilityIdentifier("exitSessionButton")

            Spacer()

            Button {
                showingOverview = true
            } label: {
                HStack(spacing: 7) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("set \(min(completedSets + 1, max(totalSets, 1)))/\(totalSets) · \(elapsedText(at: context.date))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
            }
            .accessibilityIdentifier("sessionOverviewButton")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func elapsedText(at date: Date) -> String {
        let reference = session.endedAt ?? date
        let elapsed = max(0, Int(reference.timeIntervalSince(session.startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let done = CGFloat(completedSets) / CGFloat(max(totalSets, 1))
            let current = session.isFinished ? 0 : 1 / CGFloat(max(totalSets, 1))
            HStack(spacing: 0) {
                Rectangle().fill(Theme.accent)
                    .frame(width: proxy.size.width * done)
                PulsingSegment()
                    .frame(width: proxy.size.width * current)
                Spacer(minLength: 0)
            }
            .background(Theme.border)
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.4), value: completedSets)
    }

    // MARK: - Actions

    private func completeCurrentSet(_ log: SetLog) {
        session.complete(log)
        burstCount += 1
        haptic()

        if session.nextPendingLog != nil {
            let endDate = Date().addingTimeInterval(TimeInterval(session.restSeconds))
            restEndDate = endDate
            if let upNext = session.currentLog {
                RestNotifier.shared.scheduleRestEnd(
                    at: endDate,
                    exerciseName: upNext.exerciseName,
                    setNumber: upNext.setNumber
                )
            }
        } else {
            finishSession(dismissAfter: false)
        }
    }

    private func haptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func finishSession(dismissAfter: Bool = true) {
        RestNotifier.shared.cancelPending()
        if !session.isFinished {
            session.finish()
            // Phone-logged sessions reach Health here; watch imports are
            // recorded by the wrist's own live session (#90).
            HealthRecorder.record(session)
        }
        if dismissAfter {
            dismiss()
        }
    }

    // MARK: - Done

    private var finishedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.primaryFill)
                .symbolEffect(.bounce, options: .nonRepeating, value: completeBounce)
                .onAppear { completeBounce = true }
            Text("Workout Complete")
                .font(.system(.title3, weight: .bold))
            Text("\(completedSets) \(completedSets == 1 ? "set" : "sets") · \(finalElapsedText)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Text("\(Image(systemName: "arrow.right")) \(historyPathText)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 36)
                    .frame(height: 48)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            .accessibilityIdentifier("sessionDoneButton")
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finalElapsedText: String {
        let elapsed = max(0, Int((session.endedAt ?? Date()).timeIntervalSince(session.startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    /// Where this session will land in the routines repo — the same naming
    /// FileLayout uses, shown as provenance on the done screen.
    private var historyPathText: String {
        let (year, stamp) = FileLayout.utcDateParts(of: session.startedAt)
        return "\(FileLayout.historyDirectory)/\(year)/\(stamp)-\(Slug.make(session.routineName)).json"
    }
}

/// The current-set sliver of the progress bar, pulsing.
private struct PulsingSegment: View {
    /// XCUITest waits for app quiescence before every event, and an
    /// endless animation means quiescence never arrives — so the sliver
    /// holds still under --uitest-reset.
    private static let animated = !CommandLine.arguments.contains("--uitest-reset")

    @State private var dim = false

    var body: some View {
        Rectangle()
            .fill(Theme.accent)
            .opacity(dim ? 0.45 : 1)
            .onAppear {
                guard Self.animated else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

// MARK: - Set logging

private struct SetLoggingView: View {
    let session: WorkoutSession
    @Bindable var log: SetLog
    let lastTime: SetLog?
    let routineNotes: String?
    let burstCount: Int
    let onComplete: () -> Void

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @State private var wheel: LogWheel?

    private enum LogWheel: String, Identifiable {
        case weight, reps
        var id: String { rawValue }
    }

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    /// Sets in this exercise's block (same group + name).
    private var setsTotal: Int {
        session.sortedSetLogs.filter {
            $0.groupIndex == log.groupIndex && $0.exerciseName == log.exerciseName
        }.count
    }

    /// Superset rotation chips: unique exercise names in this log's group,
    /// in rotation order. Empty when the group is solo.
    private var supersetNames: [String] {
        var names: [String] = []
        for other in session.sortedSetLogs where other.groupIndex == log.groupIndex {
            if !names.contains(other.exerciseName) { names.append(other.exerciseName) }
        }
        return names.count > 1 ? names : []
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    (Text("SET \(log.setNumber) OF \(setsTotal)")
                        .foregroundStyle(Theme.accent)
                        + (supersetNames.isEmpty
                            ? Text("")
                            : (Text(" · ") + Text(Image(systemName: "square.on.square")) + Text(" SUPERSET"))
                                .foregroundStyle(Theme.textSecondary)))
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                        .kerning(0.7)
                        .padding(.top, 20)

                    Text(log.exerciseName)
                        .font(.system(.title, weight: .bold))
                        .padding(.top, 6)

                    if !supersetNames.isEmpty {
                        SupersetChips(names: supersetNames, current: log.exerciseName)
                            .padding(.top, 10)
                    }

                    HStack(spacing: 12) {
                        Text(targetDescription)
                        if let lastTime {
                            (Text("last ").foregroundStyle(Theme.textSecondary)
                                + Text(lastTime.resultSummary(weightUnit: weightUnit))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary))
                        }
                    }
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)

                    if let routineNotes {
                        Text(routineNotes)
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                            .padding(.top, 14)
                    }

                    if let notes = log.exercise?.notes {
                        NotesBlock(notes)
                            .padding(.top, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }

            if log.exerciseType == .duration {
                durationDock
            } else {
                stage
                logDock
            }
        }
    }

    // MARK: - Stage
    // The set's adjustable values ARE the screen: two big columns —
    // value up top, its −/+ pair directly beneath — occupying the
    // middle so the thumb tweaks mid-screen and logs at the bottom,
    // with enough air between the two that neither is ever an
    // accident.

    private var stage: some View {
        HStack(alignment: .top, spacing: 12) {
            valueColumn(
                label: "WEIGHT",
                value: WorkoutMetric.weight.formatted(log.actualWeight ?? log.targetWeight),
                unit: weightUnit.symbol,
                identifier: "logWeight",
                onTap: { wheel = .weight },
                onDec: { log.actualWeight = WorkoutMetric.weight.decremented(log.actualWeight ?? log.targetWeight, weightUnit: weightUnit, stepOverride: log.exercise?.weightStepOverride) },
                onInc: { log.actualWeight = WorkoutMetric.weight.incremented(log.actualWeight ?? log.targetWeight, weightUnit: weightUnit, stepOverride: log.exercise?.weightStepOverride) }
            )
            valueColumn(
                label: "REPS",
                value: (log.actualReps ?? log.targetRepsLower).map(String.init) ?? "—",
                unit: nil,
                identifier: "logReps",
                onTap: { wheel = .reps },
                onDec: { log.actualReps = max(1, (log.actualReps ?? log.targetRepsLower ?? 11) - 1) },
                onInc: { log.actualReps = (log.actualReps ?? log.targetRepsLower ?? 9) + 1 }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .sheet(item: $wheel) { which in
            switch which {
            case .weight:
                MetricWheelSheet(
                    metric: .weight,
                    weightUnit: weightUnit,
                    value: Binding(
                        get: { log.actualWeight ?? log.targetWeight },
                        set: { log.actualWeight = $0 }
                    )
                )
            case .reps:
                RepTargetWheelSheet(
                    target: RepTarget(lower: log.actualReps ?? log.targetRepsLower, upper: nil)
                ) { newTarget in
                    log.actualReps = newTarget.lower
                }
            }
        }
    }

    private func valueColumn(
        label: String,
        value: String,
        unit: String?,
        identifier: String,
        onTap: @escaping () -> Void,
        onDec: @escaping () -> Void,
        onInc: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .kerning(0.7)
                .padding(.top, 14)
            Button(action: onTap) {
                (Text(value)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    + Text(unit.map { " \($0)" } ?? "")
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityIdentifier("\(identifier)Value")
            .padding(.top, 2)
            .padding(.horizontal, 8)

            HStack(spacing: 8) {
                Button(action: onDec) {
                    Image(systemName: "minus")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                }
                .accessibilityIdentifier("\(identifier)Decrement")
                Button(action: onInc) {
                    Image(systemName: "plus")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                }
                .accessibilityIdentifier("\(identifier)Increment")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    // MARK: - Log dock
    // Log set stands alone: a full 28 pt of clear air above it, nothing
    // adjacent to mis-hit.

    private var logDock: some View {
        VStack(spacing: 0) {
            if session.weightCarriesForward(from: log) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.right")
                        .font(.system(.caption, weight: .semibold))
                    Text("new weight carries to your remaining \(log.exerciseName) sets")
                        .font(.system(.footnote))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            ZStack {
                Button(action: onComplete) {
                    HStack(spacing: 9) {
                        Text("+").font(.system(.title3, design: .monospaced, weight: .semibold))
                        Text("Log set").font(.system(.body, weight: .bold))
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
                .accessibilityIdentifier("completeSetButton")

                MitosisBurst(trigger: burstCount)
                    .offset(y: -44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
    }

    private var durationDock: some View {
        VStack(spacing: 10) {
            DurationTimerCard(log: log) {
                onComplete()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var targetDescription: String {
        if log.exerciseType == .duration {
            guard let seconds = log.targetDuration else { return "set \(log.setNumber)" }
            return "target \(WorkoutMetric.duration.displayText(Double(seconds)))"
        }
        var parts: [String] = []
        if log.targetReps.lower != nil {
            parts.append("\(log.targetReps.display) reps")
        }
        if let weight = log.targetWeight {
            parts.append("@ \(WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit))")
        }
        return parts.isEmpty ? "set \(log.setNumber)" : "target " + parts.joined(separator: " ")
    }
}

/// "Band Pulses → Y's and T's" rotation chips, current one highlighted.
private struct SupersetChips: View {
    let names: [String]
    let current: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Text("→")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }
                Text(name)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(name == current ? Theme.selected : Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(name == current ? Theme.selectedRing : Theme.borderStrong, lineWidth: 1))
            }
        }
    }
}

/// The "+" mitosis rep played on each logged set: two glyphs split apart
/// and fade, re-triggered by bumping `trigger`.
private struct MitosisBurst: View {
    let trigger: Int
    @State private var animating = false

    var body: some View {
        ZStack {
            glyph.offset(x: animating ? -9 : 0)
            glyph.offset(x: animating ? 9 : 0)
        }
        .opacity(animating ? 0 : (trigger > 0 ? 1 : 0))
        .animation(.easeOut(duration: 0.85), value: animating)
        .onChange(of: trigger) { _, _ in
            animating = false
            withAnimation(.easeOut(duration: 0.85)) {
                animating = true
            }
        }
        .allowsHitTesting(false)
    }

    private var glyph: some View {
        Text("+")
            .font(.system(.title3, design: .monospaced, weight: .bold))
            .foregroundStyle(Theme.accent)
            .shadow(color: Theme.accent.opacity(0.5), radius: 12)
    }
}

// MARK: - Duration auto-timer

/// AUTO TIMER card (#66): counts down from the target, pauses/resets, and
/// logs the set automatically at zero (or logs elapsed via "log now").
/// Date-based like the rest timer; pausing stores the remaining interval.
private struct DurationTimerCard: View {
    @Bindable var log: SetLog
    let onComplete: () -> Void

    @State private var endDate: Date?
    @State private var pausedRemaining: TimeInterval?

    private var totalSeconds: Int {
        max(1, log.actualDuration ?? log.targetDuration ?? 30)
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let remaining = remainingSeconds(at: context.date)
                    VStack(spacing: 2) {
                        Text("AUTO TIMER")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .kerning(0.8)
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                        ProgressView(value: Double(totalSeconds - remaining), total: Double(totalSeconds))
                            .tint(Theme.accent)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }
                    .padding(.vertical, 11)
                    .onChange(of: remaining) { _, newValue in
                        if newValue <= 0 && endDate != nil {
                            expire()
                        }
                    }
                }

                Divider().overlay(Theme.border)

                HStack(spacing: 0) {
                    Button(action: togglePause) {
                        HStack(spacing: 6) {
                            Image(systemName: pausedRemaining != nil ? "play.fill" : "pause.fill")
                                .font(.system(.caption, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                            Text(pausedRemaining != nil ? "Resume" : "Pause")
                                .font(.system(.footnote, weight: .bold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .animation(.default, value: pausedRemaining != nil)
                    }
                    Divider().frame(height: 46).overlay(Theme.border)
                    Button(action: reset) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(.caption, weight: .bold))
                            Text("Reset")
                                .font(.system(.footnote, weight: .bold))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))

            HStack(spacing: 8) {
                Text("Logs automatically at 0:00")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
                Text("·").foregroundStyle(Theme.borderStrong)
                Button("log now") { logNow() }
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("completeSetButton")
            }
            .frame(height: 40)
        }
        .onAppear(perform: start)
        .onDisappear {
            RestNotifier.shared.cancelPending()
        }
    }

    private func remainingSeconds(at date: Date) -> Int {
        if let pausedRemaining {
            return max(0, Int(pausedRemaining.rounded(.up)))
        }
        guard let endDate else { return totalSeconds }
        return max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
    }

    private func start() {
        let end = Date().addingTimeInterval(TimeInterval(totalSeconds))
        endDate = end
        pausedRemaining = nil
        RestNotifier.shared.scheduleTimerEnd(at: end, exerciseName: log.exerciseName)
    }

    private func togglePause() {
        if let remaining = pausedRemaining {
            let end = Date().addingTimeInterval(remaining)
            endDate = end
            pausedRemaining = nil
            RestNotifier.shared.scheduleTimerEnd(at: end, exerciseName: log.exerciseName)
        } else if let endDate {
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
            RestNotifier.shared.cancelPending()
        }
    }

    private func reset() {
        start()
    }

    private func expire() {
        endDate = nil
        if log.actualDuration == nil { log.actualDuration = log.targetDuration }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete()
    }

    private func logNow() {
        let elapsed: Int
        if let pausedRemaining {
            elapsed = totalSeconds - Int(pausedRemaining.rounded(.up))
        } else if let endDate {
            elapsed = totalSeconds - max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        } else {
            elapsed = totalSeconds
        }
        endDate = nil
        RestNotifier.shared.cancelPending()
        log.actualDuration = max(1, elapsed)
        onComplete()
    }
}

// MARK: - Rest

/// Renders the countdown and ends itself (via `onEnd`) when the clock
/// runs out — the only ticking view on the rest screen.
private struct RestView: View {
    let endDate: Date
    let upNext: SetLog
    let onAddTime: () -> Void
    let onEnd: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))

            VStack(spacing: 24) {
                Text("REST")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .kerning(1)

                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 64, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText(countsDown: true))

                VStack(spacing: 4) {
                    Text("UP NEXT")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .kerning(0.5)
                    Text("\(upNext.exerciseName) — set \(upNext.setNumber)")
                        .font(.system(.body, weight: .semibold))
                }

                HStack(spacing: 10) {
                    Button(action: onAddTime) {
                        Text("+15s")
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 24)
                            .frame(height: 48)
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.borderStrong))
                    }
                    Button(action: onEnd) {
                        Text("Skip rest")
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 26)
                            .frame(height: 48)
                            .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
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
}
