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
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    /// Finished sessions, for "last time" lookups on the set screen.
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil })
    private var finishedSessions: [WorkoutSession]
    /// For Save-as-routine's unique-name check (#239).
    @Query(sort: \Routine.order) private var allRoutines: [Routine]

    // Ad-hoc sessions (#239): the empty stage adds the first exercise;
    // the finish screen offers to keep the whole thing as a routine.
    @State private var showingAddExercise = false
    @State private var pickerFilterState = ExerciseFilterState()
    @State private var showingSaveAsRoutine = false
    @State private var routineNameDraft = ""
    @State private var savedRoutineName: String?
    @State private var restAlertsDenied = false
    /// Latched when THIS session finishes (a live @Query count could
    /// render a frame stale — swift-reviewer).
    @State private var isFirstEverFinish = false

    /// When set, we're resting until this instant (date-based; backgrounding
    /// can't drift it).
    @State private var restEndDate: Date?
    /// The just-logged set, held on screen ~0.75 s so the "+1" beat has
    /// time to play before rest/finish takes the view (Dave, build-42:
    /// the instant swap ate the flourish). Data commits immediately —
    /// only the VIEW lingers. Nil outside the beat.
    @State private var lingeringLog: SetLog?
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
            } else if let displayLog = lingeringLog ?? session.currentLog {
                // While `lingeringLog` holds, the just-completed set's
                // screen stays up for the +1 beat — SAME structural
                // branch and .id as before the log, so the burst view
                // survives and animates instead of being remounted.
                if let restEndDate, lingeringLog == nil {
                    VStack(spacing: 0) {
                        RestView(
                            endDate: restEndDate,
                            totalSeconds: session.restSeconds,
                            upNext: displayLog,
                            onAddTime: { extendRest(by: 30) },
                            onEnd: { endRest() }
                        )
                        // A decline used to be silent — at the gym it
                        // read as a broken timer (#246). Facts only.
                        if restAlertsDenied {
                            Text("rest-over alerts are off — notifications for PlusPlus are disabled in iOS Settings")
                                .transition(.opacity)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textFaint)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 10)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: restAlertsDenied)
                } else {
                    SetLoggingView(
                        session: session,
                        log: displayLog,
                        lastTime: WorkoutSession.lastPerformance(matching: displayLog, in: finishedSessions),
                        routineNotes: completedSets == 0 ? session.routine?.notes : nil,
                        burstCount: burstCount,
                        onComplete: { completeCurrentSet(displayLog) }
                    )
                    .id(displayLog.order)
                    // The lingering screen is a FREEZE FRAME: steppers
                    // mutating an already-committed set would bypass
                    // carry-forward, and a wheel opened mid-beat gets
                    // torn down when rest takes the view
                    // (swift-reviewer).
                    .allowsHitTesting(lingeringLog == nil)
                }
            } else if totalSets == 0 {
                // A scratch session before its first exercise: no logs
                // exist, but auto-finishing here would commit a 0-set
                // session (the empty-staging bug class, hunt round 1).
                emptyStage
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
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView(filterState: pickerFilterState) { exercise in
                session.appendExercise(exercise, context: modelContext)
            }
        }
        .alert("Save as routine", isPresented: $showingSaveAsRoutine) {
            TextField("Name", text: $routineNameDraft)
            Button("Save") {
                if let routine = session.saveAsRoutine(
                    named: routineNameDraft,
                    among: allRoutines,
                    context: modelContext
                ) {
                    savedRoutineName = routine.name
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today's exercises, sets, and weights become the template.")
        }
        .interactiveDismissDisabled()
        .task {
            RestActivityController.shared.beginSession(routineName: session.routineName)
            // Prefetch so the denied caption is already placed when the
            // first rest renders instead of nudging the countdown.
            RestNotifier.shared.notificationsDenied { restAlertsDenied = $0 }
        }
        // Island / Lock Screen rest controls (#157): LiveActivityIntents
        // run in this process and post here — same mutations as the
        // on-screen buttons.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusAdjustRest)) { note in
            guard let raw = note.object as? String,
                  let adjustment = RestAdjustment(rawValue: raw) else { return }
            switch adjustment {
            case .addThirty: extendRest(by: 30)
            case .skip: endRest()
            }
        }
    }

    // MARK: - Rest controls (shared by RestView buttons and the island)

    private func extendRest(by seconds: TimeInterval) {
        guard let current = restEndDate, let currentLog = session.currentLog else { return }
        let extended = current.addingTimeInterval(seconds)
        restEndDate = extended
        RestNotifier.shared.scheduleRestEnd(
            at: extended,
            exerciseName: currentLog.exerciseName,
            setNumber: currentLog.setNumber
        )
    }

    private func endRest() {
        guard restEndDate != nil else { return }
        restEndDate = nil
        RestNotifier.shared.cancelPending()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // No End once finished (#246): its dialog there offered
            // ONLY destructive Discard — a stray delete affordance on
            // an append-only record, one mistap from erasing a first
            // workout. Done is the exit.
            if !session.isFinished {
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
            }

            Spacer()

            Button {
                showingOverview = true
            } label: {
                HStack(spacing: 7) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        // "set 1/0" is nonsense on an empty scratch
                        // session — elapsed alone carries that state.
                        Text(totalSets == 0
                            ? elapsedText(at: context.date)
                            : "set \(min(completedSets + 1, max(totalSets, 1)))/\(totalSets) · \(elapsedText(at: context.date))")
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

    /// Block-style set progress (Quiet Arcade, mock 08): one block per
    /// set of the CURRENT exercise's block, synced with the "SET N OF
    /// M" kicker — session-wide position lives in the header pill.
    /// Hidden when finished (the purple screen has its own bars) and
    /// before a scratch session's first exercise.
    @ViewBuilder
    private var progressBar: some View {
        if !session.isFinished, let log = lingeringLog ?? session.currentLog {
            let block = session.sortedSetLogs.filter {
                $0.groupIndex == log.groupIndex && $0.exerciseName == log.exerciseName
            }
            BlockBar(total: block.count, filled: block.filter(\.isCompleted).count, fill: Theme.accent)
        }
    }

    // MARK: - Actions

    /// The +1 beat plays only where a human is watching — under UI test
    /// the transition is immediate (the delay would slow every logging
    /// flow and quiescence-block nothing observable).
    private static let playsLogBeat = !CommandLine.arguments.contains("--uitest-reset")

    private func completeCurrentSet(_ log: SetLog) {
        // Taps during the beat are the double-log class — the button is
        // still on screen while the view lingers.
        guard lingeringLog == nil else { return }
        session.complete(log)
        burstCount += 1
        // Mid-workout sets thud; .success is saved for the finish so
        // the purple screen has its own physical beat (#216).
        let hasNext = session.nextPendingLog != nil
        if hasNext {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        if hasNext {
            // Rest STARTS now (endDate anchored at log time, the
            // notification scheduled now) even though its screen waits
            // out the beat — the countdown stays honest.
            // The permission ask lives in the notifier — the first
            // ARMED notification asks and arms on grant (#246). This
            // refresh keeps the denied caption honest per rest.
            RestNotifier.shared.notificationsDenied { restAlertsDenied = $0 }
            let endDate = Date().addingTimeInterval(TimeInterval(session.restSeconds))
            restEndDate = endDate
            if let upNext = session.currentLog {
                RestNotifier.shared.scheduleRestEnd(
                    at: endDate,
                    exerciseName: upNext.exerciseName,
                    setNumber: upNext.setNumber
                )
            }
        }

        // Duration sets have no +1 (their dock is the auto-timer; the
        // timer reaching zero IS the flourish) — no beat to wait for.
        guard Self.playsLogBeat, log.exerciseType != .duration else {
            if !hasNext { finishSession(dismissAfter: false) }
            return
        }
        lingeringLog = log
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.75))
            lingeringLog = nil
            // A discard during the beat deletes the session — nothing
            // left to finish (touching a deleted @Model is the crash
            // class the delete paths pop screens to avoid).
            guard !session.isDeleted else { return }
            // The finish stamp waits out the beat too — endedAt lands
            // when the screen changes. Preconditions RE-CHECKED at
            // fire time, not trusted from log time (the StartFlash
            // rule): a redo reopening a set mid-beat must not get
            // stamped into a finished record.
            if session.nextPendingLog == nil && !session.isFinished {
                finishSession(dismissAfter: false)
            }
        }
    }

    private func finishSession(dismissAfter: Bool = true) {
        RestNotifier.shared.cancelPending()
        if !session.isFinished {
            isFirstEverFinish = finishedSessions.isEmpty
            session.finish()
            // Phone-logged sessions reach Health here; watch imports are
            // recorded by the wrist's own live session (#90).
            HealthRecorder.record(session)
        }
        if dismissAfter {
            dismiss()
        }
    }

    // MARK: - Empty stage (#239)

    /// A scratch session before its first exercise. The picker appends
    /// solo blocks; from the first log onward the normal set screen owns
    /// the flow (its overview sheet carries the same add affordance).
    private var emptyStage: some View {
        VStack(spacing: 14) {
            Text("SCRATCH WORKOUT")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(Theme.textSecondary)
            Text("Nothing on the bar yet")
                .font(.system(.title3, weight: .bold))
            Text("Add exercises as you go — when you finish, the whole thing can become a routine.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showingAddExercise = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .semibold))
                    Text("Add exercise")
                        .font(.system(.footnote, weight: .semibold))
                }
                // Creation is green (#202).
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong)
                )
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("addExerciseToSessionButton")
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Done

    /// Workout Complete, Quiet Arcade: the diff tally is the
    /// centerpiece — per-exercise movement against the previous
    /// session in the hue jobs, with a bold net row — then the week
    /// block bar and (when one is real) a ★ new-best line. All
    /// numbers real; no XP, no levels.
    private var finishedView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        // Completion purple (#201) — the workout just merged.
                        .foregroundStyle(Theme.done)
                        .symbolEffect(.bounce, options: .nonRepeating, value: completeBounce)
                        .onAppear { completeBounce = true }
                        .padding(.top, 18)
                    Text("Workout Complete")
                        .font(.system(.title3, weight: .bold))
                    Text("\(session.routineName.lowercased()) · \(completedSets) \(completedSets == 1 ? "set" : "sets") · \(finalElapsedText)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)

                    if !diffTally.isEmpty {
                        tallyCard(diffTally)
                            .padding(.horizontal, 20)
                    }

                    // The week bar with THIS session already counted;
                    // the ★ line rides the caption when a lift beat its
                    // own history (a real number or nothing at all).
                    if weekPlanNow.planned > 0 {
                        VStack(spacing: 8) {
                            BlockBar(total: weekPlanNow.planned, filled: weekPlanNow.completed)
                            weekCaptionText
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding(.horizontal, 20)
                    } else if let best = newBestLine {
                        Text(best)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }

                    // Where the record actually lives (#246): the repo
                    // path returns as provenance once sync (#23) makes
                    // the file real.
                    Text("\(Image(systemName: "arrow.right")) saved to your Today timeline")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                    // The one forward-looking line the moment can carry
                    // (#246): the calendar fact, no button, no
                    // exclamation. "next up · Pull Day — thu" with the
                    // fact in ink (mock 10).
                    if let next = nextOccurrenceLine {
                        next.font(.system(.caption, design: .monospaced))
                    }
                    if isFirstEverFinish {
                        Text("widgets can show your schedule without opening the app — long-press the home screen to add one")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    // A scratch session that produced real work can
                    // graduate to a template (#239). Sessions started
                    // from a routine never see this — their template
                    // already exists. The saved confirmation is checked
                    // FIRST: a successful save sets session.routine,
                    // which would otherwise hide the very feedback
                    // naming the routine (swift-reviewer catch).
                    if let savedRoutineName {
                        Text("Saved to Routines · \(savedRoutineName)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 4)
                    } else if session.routine == nil && completedSets > 0 {
                        Button {
                            routineNameDraft = ""
                            showingSaveAsRoutine = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(.caption, weight: .semibold))
                                Text("Save as routine")
                                    .font(.system(.footnote, weight: .semibold))
                            }
                            // Creation is green (#202).
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.controlRadius)
                                    .strokeBorder(Theme.borderStrong)
                            )
                        }
                        .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                        .accessibilityIdentifier("saveAsRoutineButton")
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
            .accessibilityIdentifier("sessionDoneButton")
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var finalElapsedText: String {
        let elapsed = max(0, Int((session.endedAt ?? Date()).timeIntervalSince(session.startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: - The diff tally

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    /// This week's counts with the just-finished session included —
    /// the same WeekPlan math as Today's header, so the two bars agree.
    private var weekPlanNow: (completed: Int, planned: Int) {
        WeekPlan.counts(routines: allRoutines, sessions: finishedSessions, today: Date(), calendar: Calendar.current)
    }

    private struct TallyLine: Identifiable {
        let name: String
        let delta: RoutineDiff.Delta
        var id: String { name }
    }

    /// Exercise names in this session, first-appearance order.
    private var sessionExerciseNames: [String] {
        var names: [String] = []
        for log in session.completedSetLogs where !names.contains(log.exerciseName) {
            names.append(log.exerciseName)
        }
        return names
    }

    /// Per-exercise movement vs the previous performance: this
    /// session's top completed set (weight with THAT set's reps — the
    /// Today-diff rule; mixed maxima describe sets that never
    /// happened) against the newest OTHER session's top set.
    private var diffTally: [TallyLine] {
        sessionExerciseNames.compactMap { name in
            let mine = session.completedSetLogs.filter { $0.exerciseName == name }
            guard let last = mine.last else { return nil }
            let top = mine.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) } ?? last
            let target = RoutineDiff.Target(
                name: name,
                isDuration: last.exerciseType == .duration,
                weight: top.actualWeight,
                reps: top.actualReps ?? last.actualReps,
                durationSeconds: last.actualDuration
            )
            return TallyLine(name: name, delta: RoutineDiff.delta(target: target, prior: prior(for: name)))
        }
    }

    /// The previous performance of an exercise — newest finished
    /// session other than this one that completed it, as its top set.
    private func prior(for name: String) -> RoutineDiff.Prior? {
        let candidates = finishedSessions
            .filter { $0 !== session }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        for other in candidates {
            let matches = other.completedSetLogs.filter { $0.exerciseName == name }
            guard let last = matches.last else { continue }
            let top = matches.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) } ?? last
            return RoutineDiff.Prior(
                weight: top.actualWeight,
                reps: top.actualReps ?? last.actualReps,
                durationSeconds: last.actualDuration
            )
        }
        return nil
    }

    private func tallyCard(_ lines: [TallyLine]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(lines) { line in
                HStack(spacing: 8) {
                    Text(line.name.lowercased())
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    deltaText(line.delta)
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                }
            }
            Divider().overlay(Theme.border)
            HStack(spacing: 8) {
                Text("net")
                    .font(.system(.footnote, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                netText
                    .font(.system(.footnote, design: .monospaced, weight: .bold))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private func deltaText(_ delta: RoutineDiff.Delta) -> Text {
        switch delta {
        case .new:
            return Text("new").foregroundStyle(Theme.accent)
        case .unchanged:
            return Text("=").foregroundStyle(Theme.textFaint)
        default:
            let text = RoutineDiff.summary(deltas: [delta], weightUnit: weightUnit).first?.text ?? ""
            return Text(text).foregroundStyle(Theme.accent)
        }
    }

    /// The bold total — the same aggregation as Today's summary line.
    private var netText: Text {
        let segments = RoutineDiff.summary(deltas: diffTally.map(\.delta), weightUnit: weightUnit)
        var result = Text("")
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result = result + Text(" · ").foregroundStyle(Theme.textFaint)
            }
            let color: Color = switch segment.kind {
            case .up, .new: Theme.accent
            case .down: Theme.textSecondary
            case .unchanged: Theme.textFaint
            }
            result = result + Text(segment.text).foregroundStyle(color)
        }
        return result
    }

    /// "3 of 4 sessions this week · ★ bench 135 lb — new best".
    private var weekCaptionText: Text {
        let plan = weekPlanNow
        var text = Text("\(plan.completed) of \(plan.planned) session\(plan.planned == 1 ? "" : "s") this week")
            .foregroundStyle(Theme.textFaint)
        if let best = newBestLine {
            text = text + Text(" · ").foregroundStyle(Theme.textFaint)
                + Text(best).foregroundStyle(Theme.accent)
        }
        return text
    }

    /// The heaviest lift this session that beat that exercise's own
    /// all-time top weight — only when there WAS a previous best to
    /// beat (day one everything is "a best"; saying so is noise).
    private var newBestLine: String? {
        var best: (name: String, weight: Double)?
        for name in sessionExerciseNames {
            let mine = session.completedSetLogs
                .filter { $0.exerciseName == name }
                .compactMap(\.actualWeight)
            guard let top = mine.max(), top > 0 else { continue }
            let priorTop = finishedSessions
                .filter { $0 !== session }
                .flatMap(\.completedSetLogs)
                .filter { $0.exerciseName == name }
                .compactMap(\.actualWeight)
                .max()
            guard let priorTop, top > priorTop else { continue }
            if best == nil || top > best!.weight {
                best = (name, top)
            }
        }
        guard let best else { return nil }
        return "★ \(best.name.lowercased()) \(WorkoutMetric.weight.displayText(best.weight, weightUnit: weightUnit)) — new best"
    }

    /// The soonest next occurrence across every scheduled routine —
    /// the same fact the rest-day caption speaks, computed here with
    /// THIS session already counted. "next up · " faint, the routine
    /// and day in ink (mock 10).
    private var nextOccurrenceLine: Text? {
        let calendar = Calendar.current
        let today = Date()
        var best: (date: Date, name: String)?
        for routine in allRoutines {
            let completions = recentCompletions(of: routine)
            let state = routine.schedule.dueState(
                lastCompleted: completions.last,
                previousCompleted: completions.previous,
                today: today,
                calendar: calendar
            )
            if case .notDue(let next) = state {
                if best == nil || next < best!.date {
                    best = (next, routine.name)
                }
            }
        }
        guard let best else { return nil }
        let day = best.date.formatted(.dateTime.weekday(.abbreviated)).lowercased()
        // Beyond the coming week the bare weekday would lie by
        // omission — add the plain date (mirrors Today's rest-day
        // caption, #267).
        var fact = "\(best.name) — \(day)"
        if let weekBoundary = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: today)),
           best.date > weekBoundary {
            fact += " · " + best.date.formatted(.dateTime.month(.abbreviated).day()).lowercased()
        }
        return Text("next up · ").foregroundStyle(Theme.textFaint)
            + Text(fact).foregroundStyle(Theme.textPrimary)
    }

    /// The two most recent completions (#267: `.previous` feeds the
    /// Kit's banking rule). Identity match wins; the name fallback
    /// applies ONLY when no reference survives — the same rule as
    /// TodayView's recentCompletions, so this screen and Today can't
    /// disagree about "next".
    private func recentCompletions(of routine: Routine) -> (last: Date?, previous: Date?) {
        let identityMatches = finishedSessions.filter { $0.routine === routine }
        let pool = identityMatches.isEmpty
            ? finishedSessions.filter { $0.routine == nil && $0.routineName == routine.name }
            : identityMatches
        let dates = pool.compactMap(\.endedAt).sorted(by: >)
        return (dates.first, dates.count > 1 ? dates[1] : nil)
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
                    // SUPERSET moved onto the chips row (mock 08) —
                    // the kicker keeps the set count alone.
                    Text("SET \(log.setNumber) OF \(setsTotal)")
                        .foregroundStyle(Theme.accent)
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

                    // Weight/reps sets carry target + last INSIDE the
                    // value cards now (mock 08); this line survives
                    // only for duration sets, which have no cards.
                    if log.exerciseType == .duration {
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
                    }

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

    // MARK: - Stage (mock 08)
    // The WEIGHT card dominates — big value with the live delta, two
    // full-width stepper keys, the carry-forward note inside — and
    // REPS rides beneath as a compact row with square ±1 keys. The
    // thumb tweaks mid-screen and logs at the bottom.

    /// The effective weight step, for the stepper key labels ("−5" /
    /// "+5"): per-equipment override first, then the unit's step.
    private var weightStep: Double {
        log.exercise?.weightStepOverride ?? weightUnit.step
    }

    /// "last 130 · +5" — the previous top set's weight and the live
    /// delta against it (mock 08, in the weight card's corner). Green
    /// only while it's an increment: a deload renders neutral
    /// (anti-shame, the RoutineDiff rule — the mock's always-green
    /// annotation predates it). Nil without a prior.
    private var weightDeltaAnnotation: (text: String, color: Color)? {
        guard let last = lastTime?.actualWeight, last > 0 else { return nil }
        let current = log.actualWeight ?? log.targetWeight ?? last
        let delta = current - last
        let deltaText = delta == 0
            ? "="
            : (delta > 0 ? "+" : "−") + WorkoutMetric.weight.formatted(abs(delta))
        return (
            "last \(WorkoutMetric.weight.formatted(last)) · \(deltaText)",
            delta > 0 ? Theme.accent : Theme.textFaint
        )
    }

    private var stage: some View {
        VStack(spacing: 12) {
            weightCard
            repsRow
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
                // Logging is a scalar — the range editor's "Up to"
                // wheel was a dead control here (#246).
                RepTargetWheelSheet(
                    target: RepTarget(lower: log.actualReps ?? log.targetRepsLower, upper: nil),
                    showsUpperWheel: false
                ) { newTarget in
                    log.actualReps = newTarget.lower
                }
            }
        }
    }

    /// Mock 08's dominant WEIGHT card: mono label, big value opening
    /// the wheel, the live "last · Δ" in data green at the value's
    /// side, two full-width 56 pt stepper keys, and the carry-forward
    /// note inside the card (faint — a mechanic note, not a delta;
    /// rendered only while it's true, honesty over the mock's
    /// always-on copy).
    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEIGHT")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .kerning(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    wheel = .weight
                } label: {
                    (Text(WorkoutMetric.weight.formatted(log.actualWeight ?? log.targetWeight))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        + Text(" \(weightUnit.symbol)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        // Digits roll like an odometer, directional
                        // with the raw value (#216).
                        .contentTransition(.numericText(value: log.actualWeight ?? log.targetWeight ?? 0))
                        .animation(.easeOut(duration: 0.15), value: log.actualWeight ?? log.targetWeight)
                }
                .accessibilityIdentifier("logWeightValue")
                Spacer(minLength: 8)
                if let annotation = weightDeltaAnnotation {
                    Text(annotation.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(annotation.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: annotation.text)
                }
            }
            HStack(spacing: 10) {
                stepperKey("−\(WorkoutMetric.weight.formatted(weightStep))", height: 56, identifier: "logWeightDecrement") {
                    log.actualWeight = WorkoutMetric.weight.decremented(log.actualWeight ?? log.targetWeight, weightUnit: weightUnit, stepOverride: log.exercise?.weightStepOverride)
                }
                stepperKey("+\(WorkoutMetric.weight.formatted(weightStep))", height: 56, identifier: "logWeightIncrement") {
                    log.actualWeight = WorkoutMetric.weight.incremented(log.actualWeight ?? log.targetWeight, weightUnit: weightUnit, stepOverride: log.exercise?.weightStepOverride)
                }
            }
            if session.weightCarriesForward(from: log) {
                Text("new weight carries to your remaining sets")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    /// Mock 08's compact REPS row: label · value · plain-ink target
    /// (green never colors a prescription), square ±1 keys trailing.
    /// No card — the weight owns the stage.
    private var repsRow: some View {
        HStack(spacing: 12) {
            Text("REPS")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .kerning(0.7)
            Button {
                wheel = .reps
            } label: {
                Text((log.actualReps ?? log.targetRepsLower).map(String.init) ?? "—")
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(log.actualReps ?? log.targetRepsLower ?? 0)))
                    .animation(.easeOut(duration: 0.15), value: log.actualReps ?? log.targetRepsLower)
            }
            .accessibilityIdentifier("logRepsValue")
            if log.targetReps.lower != nil {
                Text("target \(log.targetReps.display)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            stepperKey("−1", height: 48, width: 48, identifier: "logRepsDecrement") {
                log.actualReps = max(1, (log.actualReps ?? log.targetRepsLower ?? 11) - 1)
            }
            stepperKey("+1", height: 48, width: 48, identifier: "logRepsIncrement") {
                log.actualReps = (log.actualReps ?? log.targetRepsLower ?? 9) + 1
            }
        }
        .padding(.horizontal, 2)
    }

    /// One raised stepper key with a mono step label ("−5"/"+5" say
    /// what one press buys — the ± icons didn't). Full-width when no
    /// width is given.
    private func stepperKey(_ label: String, height: CGFloat, width: CGFloat? = nil, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: height)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey(cornerRadius: 12))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Log dock
    // Log set stands alone: a full 28 pt of clear air above it, nothing
    // adjacent to mis-hit.

    private var logDock: some View {
        VStack(spacing: 0) {
            ZStack {
                Button(action: onComplete) {
                    Text("Log set")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                .accessibilityIdentifier("completeSetButton")

                PlusOneBurst(trigger: burstCount)
                    .offset(y: -40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)

            // "1 of 3 logged · rest 90s auto" (mock 08): the block's
            // tally plus what happens at the log — plain facts.
            Text("\(loggedLine) · rest \(WorkoutMetric.rest.displayText(Double(session.restSeconds))) auto")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            // UP NEXT (mock 08): where the rotation goes after this
            // block — the same fact the rest screen carries, visible
            // before the finger commits.
            if let upNext = upNextLine {
                VStack(alignment: .leading, spacing: 3) {
                    Divider().overlay(Theme.border)
                    Text("UP NEXT")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .kerning(0.8)
                        .padding(.top, 8)
                    upNext
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .padding(.bottom, 12)
    }

    /// "no sets logged yet" / "1 of 3 logged" — this block's tally.
    private var loggedLine: String {
        let logged = session.sortedSetLogs.filter {
            $0.groupIndex == log.groupIndex && $0.exerciseName == log.exerciseName && $0.isCompleted
        }.count
        return logged == 0 ? "no sets logged yet" : "\(logged) of \(setsTotal) logged"
    }

    /// The next pending log after this one: a superset partner gets
    /// its name + prescription, a plain next set just its number.
    private var upNextLine: Text? {
        guard let next = session.sortedSetLogs.first(where: { !$0.isCompleted && $0.order != log.order }) else {
            return nil
        }
        if next.exerciseName == log.exerciseName {
            return Text("\(next.exerciseName) — set \(next.setNumber)")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        let detail: String
        if next.exerciseType == .duration {
            detail = WorkoutMetric.duration.displayText(next.targetDuration.map(Double.init))
        } else {
            var parts = "\(next.targetReps.display) reps"
            if let weight = next.targetWeight {
                parts += " @ \(WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit))"
            }
            detail = parts
        }
        return Text("\(next.exerciseName) — ")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            + Text(detail)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
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

/// "A · BENCH → B · ROW" rotation chips (mock 08): lettered mono
/// capsules, the current member an INVERSE INK fill — mid-action it's
/// "where you are", a position in the rotation, not a selection being
/// made — the next member outlined, and the SUPERSET legend riding
/// the row's trailing edge.
private struct SupersetChips: View {
    let names: [String]
    let current: String

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Text("→")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }
                Text("\(letter(index)) · \(name.uppercased())")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(name == current ? Theme.onPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(name == current ? Theme.primaryFill : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(name == current ? Color.clear : Theme.borderStrong, lineWidth: 1))
            }
            Spacer(minLength: 6)
            Text("SUPERSET")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.textFaint)
        }
    }

    private func letter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + index % 26)))
    }
}

/// The "+1" popped on each logged set (Quiet Arcade, replacing the
/// mitosis "+"): a mono green +1 rises ~30 pt from the key's top edge,
/// scaling 0.7 → 1.25 while it fades, 0.7 s ease-out, one-shot per
/// trigger bump. Real number, real increment — the whole brand in one
/// flourish.
private struct PlusOneBurst: View {
    let trigger: Int
    @State private var animating = false

    var body: some View {
        Text("+1")
            .font(.system(.body, design: .monospaced, weight: .bold))
            .foregroundStyle(Theme.accent)
            .scaleEffect(animating ? 1.25 : 0.7)
            .offset(y: animating ? -30 : 0)
            .opacity(animating ? 0 : (trigger > 0 ? 1 : 0))
            .animation(.easeOut(duration: 0.7), value: animating)
            .onChange(of: trigger) { _, _ in
                animating = false
                withAnimation(.easeOut(duration: 0.7)) {
                    animating = true
                }
            }
            .allowsHitTesting(false)
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
        // No haptic here: completeCurrentSet owns set-completion
        // feedback now (impact mid-workout, .success only at the
        // finish) — a second buzz doubled every timed set.
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
/// runs out — the only ticking view on the rest screen. Quiet Arcade:
/// 52 pt mono countdown over 12 recharge blocks draining with the
/// clock (live progress, so accent green), UP NEXT as a card with its
/// target in plain ink, +30s as a secondary key and Skip rest as the
/// primary one.
private struct RestView: View {
    let endDate: Date
    /// The configured rest length — the recharge blocks' denominator
    /// (an extension can push `remaining` past it; the blocks cap full).
    let totalSeconds: Int
    let upNext: SetLog
    let onAddTime: () -> Void
    let onEnd: () -> Void

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))

            VStack(spacing: 20) {
                Text("REST")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .kerning(1)

                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText(countsDown: true))

                rechargeBlocks(remaining: remaining)

                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .kerning(0.8)
                    Text("\(upNext.exerciseName) — set \(upNext.setNumber)")
                        .font(.system(.body, weight: .semibold))
                    // Values in plain ink (the handoff's rule): the next
                    // prescription is a fact, not a delta — green stays
                    // on movement.
                    if let target = upNextTarget {
                        target
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
                .padding(.horizontal, 20)

                // Skip gets the wider share (the mock's 1 : 1.4 = 5:7
                // of the row): ending rest is the primary intent,
                // extending is the hedge.
                GeometryReader { proxy in
                    HStack(spacing: 10) {
                        Button(action: onAddTime) {
                            Text("+30s")
                                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: (proxy.size.width - 10) * 5 / 12)
                                .frame(height: 52)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
                        }
                        .buttonStyle(.raisedKey())
                        .accessibilityIdentifier("extendRestButton")
                        Button(action: onEnd) {
                            Text("Skip rest")
                                .font(.system(.subheadline, weight: .bold))
                                .foregroundStyle(Theme.onPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.raisedPrimaryKey())
                        .accessibilityIdentifier("skipRestButton")
                    }
                }
                .frame(height: 56)
                .padding(.horizontal, 20)
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

    /// 12 blocks draining left-to-right as the rest runs out.
    private func rechargeBlocks(remaining: Int) -> some View {
        let filled = min(12, Int((Double(remaining) / Double(max(totalSeconds, 1)) * 12).rounded(.up)))
        return HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < filled ? Theme.accent : Theme.surfaceRaised)
                    .frame(width: 17, height: 17)
            }
        }
        .animation(.easeOut(duration: 0.15), value: filled)
    }

    /// "10 reps @ 135 lb" — weight value in ink, the rest faint.
    private var upNextTarget: Text? {
        if upNext.exerciseType == .duration {
            guard let seconds = upNext.targetDuration else { return nil }
            return Text(WorkoutMetric.duration.displayText(Double(seconds)))
                .foregroundStyle(Theme.textPrimary)
        }
        var result: Text?
        if upNext.targetReps.lower != nil {
            result = Text("\(upNext.targetReps.display) reps").foregroundStyle(Theme.textFaint)
        }
        if let weight = upNext.targetWeight {
            let weightValue = Text(WorkoutMetric.weight.displayText(weight, weightUnit: weightUnit))
                .foregroundStyle(Theme.textPrimary)
            if let existing = result {
                result = existing + Text(" @ ").foregroundStyle(Theme.textFaint) + weightValue
            } else {
                result = weightValue
            }
        }
        return result
    }
}
