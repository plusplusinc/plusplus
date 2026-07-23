import SwiftUI
import SwiftData
import CoreLocation
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
    /// Latched when THIS session finishes (a live @Query count could
    /// render a frame stale — swift-reviewer).
    @State private var isFirstEverFinish = false

    /// When set, we're resting until this instant (date-based; backgrounding
    /// can't drift it).
    @State private var restEndDate: Date?
    /// The configured length of the CURRENT rest — the just-completed
    /// block's override when it has one (interval blocks), else the
    /// session default. Captured at log time with the end date so the
    /// recharge blocks' denominator matches the countdown they drain.
    @State private var restTotalSeconds = 90
    /// Whether the current countdown is a TRANSITION — the session moved
    /// to a different exercise or block (#369) — so the screen says
    /// SWITCH instead of REST. Captured at log time with the length.
    @State private var restIsTransition = false
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
    /// Live heart rate from Health while the session runs (watch or
    /// chest strap on; nothing otherwise). Plain @Observable class in
    /// @State: stable across re-renders.
    @State private var heartRate = HeartRateMonitor()
    /// Live pace + distance from GPS during an outdoor run. Engaged only
    /// while the current exercise is outdoor; same @State discipline.
    @State private var location = RunLocationMonitor()
    /// The outdoor exercise the meter is currently tracking (group+name).
    /// The meter re-bases when this changes so each exercise measures its
    /// OWN distance/pace — but persists across the rounds of one exercise.
    @State private var outdoorExerciseKey: String?

    private var totalSets: Int { session.sortedSetLogs.count }

    /// The set whose screen is up (the lingering freeze-frame, else the
    /// live current). What "the active exercise" means for live vitals.
    private var activeLog: SetLog? { lingeringLog ?? session.currentLog }
    /// Whether the active exercise is a GPS-trackable outdoor run — the
    /// gate for engaging location and showing live pace. Read off the
    /// DECODED snapshot profile (never a reconstructed one).
    private var isOutdoorNow: Bool { activeLog?.metricProfile.isOutdoor == true }
    /// The active run's pace/distance denomination.
    private var runUnit: DistanceUnit { activeLog?.metricProfile.distanceUnit ?? .miles }
    /// Identity of the active exercise's block — the re-base key.
    private var activeExerciseKey: String? {
        activeLog.map { "\($0.groupIndex)·\($0.exerciseName)" }
    }

    /// Point the location meter at the active exercise: start (or re-base
    /// to a fresh meter) when it's a new outdoor exercise, keep it running
    /// across that exercise's rounds, and stop when the exercise isn't
    /// outdoor. Called wherever the active log or workout state changes.
    private func syncLocation() {
        guard !session.isFinished, session.isWorkoutStarted, isOutdoorNow,
              let key = activeExerciseKey else {
            location.stop()
            outdoorExerciseKey = nil
            return
        }
        guard key != outdoorExerciseKey else { return }
        // New outdoor exercise → re-base so its distance starts at zero
        // (stop() clears the prior exercise's readings).
        location.stop()
        location.start(from: session.effectiveStart, unit: runUnit)
        outdoorExerciseKey = key
    }
    private var completedSets: Int { session.completedSetLogs.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if session.isFinished {
                finishedView
            } else if session.isPaused {
                // Paused takes the screen from the logging/rest flow —
                // the clock is banked and held until Resume.
                pausedView
            } else if let displayLog = lingeringLog ?? session.currentLog {
                // While `lingeringLog` holds, the just-completed set's
                // screen stays up for the +1 beat — SAME structural
                // branch and .id as before the log, so the burst view
                // survives and animates instead of being remounted.
                if let restEndDate, lingeringLog == nil {
                    // The rest-over cue is the wrist (watch haptics) and the
                    // Live Activity countdown, not a phone notification
                    // (#322) — so no "alerts are off" caption here anymore.
                    RestView(
                        endDate: restEndDate,
                        totalSeconds: restTotalSeconds,
                        isTransition: restIsTransition,
                        upNext: displayLog,
                        heartRate: heartRate,
                        location: isOutdoorNow ? location : nil,
                        runUnit: runUnit,
                        onAddTime: { extendRest(by: 30) },
                        onEnd: { endRest() }
                    )
                } else {
                    SetLoggingView(
                        session: session,
                        log: displayLog,
                        lastTime: WorkoutSession.lastPerformance(matching: displayLog, in: finishedSessions),
                        routineNotes: completedSets == 0 ? session.routine?.notes : nil,
                        burstCount: burstCount,
                        heartRate: heartRate,
                        location: isOutdoorNow ? location : nil,
                        onComplete: { completeCurrentSet(displayLog) }
                    )
                    .id(displayLog.order)
                    // The lingering screen is a FREEZE FRAME: steppers
                    // mutating an already-committed set would bypass
                    // carry-forward, and a wheel opened mid-beat gets
                    // torn down when rest takes the view
                    // (swift-reviewer).
                    .allowsHitTesting(lingeringLog == nil)
                    // "Don't start the timer until the first exercise is
                    // started" (Dave): an ad-hoc session's clock engages
                    // when its first set screen appears. Routine sessions
                    // engaged at start, so this is a no-op for them.
                    .onAppear { engageClockIfNeeded() }
                }
            } else if totalSets == 0 {
                // A scratch session before its first exercise: no logs
                // exist, but auto-finishing here would commit a 0-set
                // session (the empty-staging bug class, hunt round 1).
                emptyStage
            } else if session.routine == nil {
                // An ad-hoc session's "plan" is only what's been added so
                // far, so running out of pending sets does NOT mean done —
                // finishing is the user's call (device report 2026-07-23:
                // the workout ended the moment the first added exercise
                // completed). Routine sessions keep the auto-finish below;
                // their plan ending IS the finish.
                stagedWorkDoneStage
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
                LiveMirror.shared.discarded(session)
                WorkoutActivityController.shared.end()
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
            // A live rest/transition countdown (either sets restEndDate) makes
            // the not-yet-done exercises pulse green in the overview (#421).
            SessionOverviewSheet(session: session, isResting: restEndDate != nil) {
                endRest()
            }
            .presentationDetents([.fraction(0.88)])
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView(filterState: pickerFilterState, onConfigured: { config in
                session.appendExercise(config: config, context: modelContext)
            })
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
            // Start the whole-session Live Activity and the watch mirror
            // (#322). Not for a finished record opened from history.
            if !session.isFinished {
                LiveMirror.shared.begin(session)
                let log = session.currentLog
                WorkoutActivityController.shared.begin(
                    routineName: session.routineName,
                    exerciseName: log?.exerciseName ?? session.routineName,
                    setNumber: log?.setNumber ?? 1,
                    setsCompleted: completedSets,
                    totalSets: totalSets,
                    startedAt: session.effectiveStart
                )
            }
            // HR monitoring rides the workout clock: a routine session
            // has already started, so it begins now; an ad-hoc session
            // waits for its first exercise (engageClockIfNeeded).
            if !session.isFinished, session.isWorkoutStarted {
                heartRate.start(from: session.effectiveStart)
                syncLocation()
            }
            // The session's FIRST exercise announces here (no key change
            // to observe); later exercises ride activeExerciseKey below.
            announceVoiceCue()
        }
        .onDisappear {
            heartRate.stop()
            location.stop()
            VoiceCueSpeaker.shared.stop()
            CountdownCue.shared.stop()
        }
        // GPS pauses with the workout clock (HR keeps its passive query) —
        // no distance banked across a pause, and the battery rests.
        .onChange(of: session.isPaused) { _, paused in
            paused ? location.pause() : location.resume()
        }
        // Re-point the meter as the active exercise changes: a new outdoor
        // exercise re-bases (its own distance), the same exercise's next
        // round keeps accumulating, a non-outdoor exercise stops it. The
        // voice cue rides the same identity: the key flips to the up-next
        // exercise the moment its transition starts, so the cue plays
        // while the user is racking over, not mid-set.
        .onChange(of: activeExerciseKey) {
            syncLocation()
            announceVoiceCue()
        }
        // A WATCH-driven finish swaps this screen to the purple record
        // while a cue may still be talking — the phone-side finish path
        // stops speech inside finishSession, but the mirror path never
        // passes through there (swift-reviewer).
        .onChange(of: session.isFinished) { _, finished in
            if finished {
                VoiceCueSpeaker.shared.stop()
                CountdownCue.shared.stop()
            }
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
        // A WATCH-initiated rest (live mirror, #322) reflected onto the
        // open phone view — the countdown appears/clears here too.
        // The mirror op is kind-agnostic, so a watch-initiated pause
        // always reads REST here (#369 deferred the kind op-field).
        .onReceive(NotificationCenter.default.publisher(for: LiveMirror.restChanged)) { note in
            if let endsAt = note.object as? Date {
                restTotalSeconds = max(1, Int(endsAt.timeIntervalSinceNow.rounded()))
                restIsTransition = false
                restEndDate = endsAt
            } else {
                restEndDate = nil
            }
        }
    }

    // MARK: - Rest controls (shared by RestView buttons and the island)

    private func extendRest(by seconds: TimeInterval) {
        guard let current = restEndDate, let currentLog = session.currentLog else { return }
        let extended = current.addingTimeInterval(seconds)
        restEndDate = extended
        reflectRest(endDate: extended, upNext: currentLog)
    }

    private func endRest() {
        guard restEndDate != nil else { return }
        restEndDate = nil
        LiveMirror.shared.restEnded(in: session)
        syncActivityWorking()
    }

    /// Reflects an active rest on the Live Activity + the watch mirror.
    private func reflectRest(endDate: Date, upNext: SetLog) {
        WorkoutActivityController.shared.resting(
            upNextExercise: upNext.exerciseName,
            upNextSet: upNext.setNumber,
            setsCompleted: completedSets,
            totalSets: totalSets,
            restEnd: endDate,
            isTransition: restIsTransition
        )
        LiveMirror.shared.restStarted(endsAt: endDate, total: restTotalSeconds, in: session)
    }

    /// Voice cues (opt-in, Settings → VOICE CUES): the active exercise's
    /// cue line speaks once as its block starts. Dedup keys on session
    /// identity + block (`startedAt` is persisted, so a remount of this
    /// view can't re-announce within one app run); everything else —
    /// mode, catalog coverage, UI-test inertness — gates inside the
    /// speaker, which only evaluates the refresher scan when the mode
    /// asks for it.
    private func announceVoiceCue() {
        guard !session.isFinished, let log = activeLog, let key = activeExerciseKey else { return }
        VoiceCueSpeaker.shared.announce(
            exerciseNamed: log.exerciseName,
            dedupKey: "\(session.startedAt.timeIntervalSince1970)·\(key)",
            isRefresher: isVoiceCueRefresher(log)
        )
    }

    /// Refresher mode's model knowledge: an exercise deserves a spoken
    /// reminder when it's new to you or you haven't done it in a month
    /// — no completed set with this snapshot name in any finished
    /// session inside the window, and none earlier in THIS session (a
    /// second block of the same exercise is not a refresher).
    private func isVoiceCueRefresher(_ log: SetLog) -> Bool {
        let name = log.exerciseName
        if session.completedSetLogs.contains(where: { $0.exerciseName == name }) { return false }
        let cutoff = Date().addingTimeInterval(-TimeInterval(VoiceCueMode.refresherWindowDays) * 24 * 3600)
        return !finishedSessions.contains { finished in
            (finished.endedAt ?? .distantPast) >= cutoff
                && finished.completedSetLogs.contains { $0.exerciseName == name }
        }
    }

    /// Pushes the current working state (exercise · set · progress) to the
    /// Live Activity — on rest end and after each logged set.
    private func syncActivityWorking() {
        let log = session.currentLog
        WorkoutActivityController.shared.working(
            exerciseName: log?.exerciseName ?? session.routineName,
            setNumber: log?.setNumber ?? 1,
            setsCompleted: completedSets,
            totalSets: totalSets
        )
    }

    // MARK: - Header

    private var header: some View {
        // Explicit 8 pt gaps: with HR + pace + Pause all present the
        // default spacing let the keys crowd (design-review spacing
        // audit, 2026-07-23).
        HStack(spacing: 8) {
            // No End once finished (#246): its dialog there offered
            // ONLY destructive Discard — a stray delete affordance on
            // an append-only record, one mistap from erasing a first
            // workout. Done is the exit.
            if !session.isFinished {
                Button {
                    showingExitDialog = true
                } label: {
                    // The live HUD predated the shape law (2026-07-20) as a
                    // capsule island; it joined the r11 raised-key family in
                    // the 2026-07-23 design review — controls press, data
                    // tags (HR/pace) stay soft. Cap 42 + travel 3 keeps the
                    // old 44 pt row height (#130 floor).
                    HStack(spacing: 6) {
                        Image(systemName: "xmark").font(.system(.caption, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("End").font(.system(.footnote, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
                }
                .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
                .accessibilityLabel("End workout")
                .accessibilityIdentifier("exitSessionButton")

                // Live heart rate, when Health has a fresh reading —
                // accent while it satisfies the current set's target.
                LiveHeartRateLabel(
                    monitor: heartRate,
                    target: (lingeringLog ?? session.currentLog)?.targetHeartRate,
                    chrome: true
                )

                // Live pace beside it on an outdoor run — accent while
                // it's meeting the set's pace target.
                if isOutdoorNow {
                    LivePaceLabel(
                        monitor: location,
                        unit: runUnit,
                        target: activeLog?.target(.pace),
                        chrome: true
                    )
                    // A denied Location grant says so (design review
                    // 2026-07-23, the Health-tray parity): amber advisory
                    // in the interactive control shape, opening iOS
                    // Settings. Absent this, denial rendered exactly like
                    // "no GPS fix yet" — a broken-looking feature instead
                    // of a fixable permission. Never a gate: the workout
                    // runs fine without it.
                    if location.authorizationDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "location.slash")
                                    .font(.system(.caption2, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text("GPS off")
                                    .font(.system(.caption2))
                            }
                            .foregroundStyle(Theme.notes)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(Theme.notes.opacity(0.14), in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
                            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                                .strokeBorder(Theme.notes.opacity(0.45), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Location is off. Pace and distance can't track.")
                        .accessibilityHint("Opens iOS Settings")
                        .accessibilityIdentifier("gpsDeniedChip")
                    }
                }

                // Pause the workout clock. Shown only while it's actually
                // running under the logging flow (never mid-rest, where
                // the rest screen owns the controls, and never before the
                // first exercise has started).
                if session.isRunning, restEndDate == nil, lingeringLog == nil {
                    Button {
                        session.pauseClock()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pause.fill").font(.system(.caption, weight: .semibold))
                                .accessibilityHidden(true)
                            Text("Pause").font(.system(.footnote, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 42)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
                    }
                    .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
                    .accessibilityLabel("Pause workout")
                    .accessibilityIdentifier("pauseWorkoutButton")
                }
            }

            Spacer()

            Button {
                showingOverview = true
            } label: {
                HStack(spacing: 7) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        // "set 1/0" is nonsense on an empty scratch
                        // session — the clock state alone carries it.
                        Text(totalSets == 0
                            ? clockText(at: context.date)
                            : "set \(min(completedSets + 1, max(totalSets, 1)))/\(totalSets) · \(clockText(at: context.date))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
            }
            .buttonStyle(RaisedKeyStyle(plate: Theme.border, cornerRadius: Theme.keyRadius, travel: 3))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the set overview")
            .accessibilityIdentifier("sessionOverviewButton")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// The clock face — mm:ss of active running time, from the session's
    /// pause-aware clock.
    private func elapsedText(at date: Date) -> String {
        let elapsed = max(0, Int(session.elapsed(at: date)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    /// The header pill's clock: "ready" before the first exercise starts
    /// (the timer hasn't engaged), the running time otherwise, tagged
    /// "· paused" while held.
    private func clockText(at date: Date) -> String {
        guard session.isWorkoutStarted else { return "ready" }
        let elapsed = elapsedText(at: date)
        return session.isPaused ? "\(elapsed) · paused" : elapsed
    }

    /// Engages the ad-hoc clock the first time a set screen appears —
    /// the moment the first exercise is started. Routine sessions have
    /// already started theirs, so the guard makes this a no-op for them.
    private func engageClockIfNeeded() {
        guard !session.isWorkoutStarted, !session.isFinished else { return }
        session.startClock()
        heartRate.start(from: session.effectiveStart)
        syncLocation()
    }

    // MARK: - Paused

    /// The workout on hold: the clock frozen at its banked total, a
    /// single Resume key. The screen replaces the logging/rest flow so
    /// no set can be logged while paused.
    private var pausedView: some View {
        // Scrollable so the Resume CTA can't be pushed off-screen at large
        // accessibility text sizes (it's the only exit from the paused state);
        // the minHeight keeps it centered when the content fits (a11y audit).
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Paused")
                        .font(.system(.title2, weight: .bold))
                    // Frozen while paused — elapsed doesn't advance, so no clock.
                    Text(elapsedText(at: Date()))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("your workout timer is on hold")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.center)
                    Spacer()
                    Button {
                        session.startClock()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(.footnote, weight: .bold))
                            Text("Resume workout").font(.system(.body, weight: .bold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                    .accessibilityIdentifier("resumeWorkoutButton")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
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

    /// How many sets (rounds) this exercise's block holds — a single-round
    /// run can auto-log the whole-session GPS distance as its actual.
    private func roundsInBlock(of log: SetLog) -> Int {
        session.sortedSetLogs.filter {
            $0.groupIndex == log.groupIndex && $0.exerciseName == log.exerciseName
        }.count
    }

    private func completeCurrentSet(_ log: SetLog) {
        // Taps during the beat are the double-log class — the button is
        // still on screen while the view lingers.
        guard lingeringLog == nil else { return }
        // An outdoor run's measured distance/pace become the logged
        // actuals, so the record reflects the GPS run instead of a hand
        // guess. Only for a single-round piece (the meter tracks the whole
        // exercise, not a per-round split), only with a FRESH reading (so
        // a still-acquiring re-base can't log stale values), and only when
        // not already edited — a manual actual always wins.
        if isOutdoorNow, location.isFresh, roundsInBlock(of: log) == 1 {
            if log.actual(.distance) == nil, let distance = location.totalDistanceInUnit {
                log.setActual(.distance, to: distance)
            }
            if log.actual(.pace) == nil, let pace = location.averagePaceSeconds {
                log.setActual(.pace, to: pace)
            }
        }
        session.complete(log)
        // Mirror the logged set to the watch (#322).
        LiveMirror.shared.logged(log, in: session)
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
            // The pause STARTS now (endDate anchored at log time) even
            // though its screen waits out the beat — the countdown stays
            // honest. The pause-over cue is watch haptics + the Live
            // Activity countdown, not a phone notification (#322). A new
            // round of the same block rests; a different exercise or
            // block gets the shorter transition (#369).
            let pause = session.pause(after: log)
            if pause.seconds > 0 {
                restTotalSeconds = pause.seconds
                restIsTransition = pause.isTransition
                let endDate = Date().addingTimeInterval(TimeInterval(pause.seconds))
                restEndDate = endDate
                if let upNext = session.currentLog {
                    reflectRest(endDate: endDate, upNext: upNext)
                }
            } else {
                // A 0-second transition: no countdown at all, straight
                // to the next station.
                syncActivityWorking()
            }
        } else {
            syncActivityWorking()
        }

        // Duration-driven sets have no +1 (their dock is the auto-timer;
        // the timer reaching zero IS the flourish) — no beat to wait for.
        // Ad-hoc sessions never auto-finish (routine == nil): the body's
        // stagedWorkDoneStage takes over when pending sets run out.
        guard Self.playsLogBeat, log.driver != .duration else {
            if !hasNext, session.routine != nil { finishSession(dismissAfter: false) }
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
            // stamped into a finished record. Ad-hoc sessions (routine
            // == nil) never auto-finish — see stagedWorkDoneStage.
            if session.nextPendingLog == nil && !session.isFinished && session.routine != nil {
                finishSession(dismissAfter: false)
            }
        }
    }

    private func finishSession(dismissAfter: Bool = true) {
        WorkoutActivityController.shared.end()
        // A cue still talking (or beeping) over the purple finish is noise.
        VoiceCueSpeaker.shared.stop()
        CountdownCue.shared.stop()
        if !session.isFinished {
            isFirstEverFinish = finishedSessions.isEmpty
            session.finish()
            // Tell the watch the session is done (#322) — after finish()
            // so the endedAt stamp rides along.
            LiveMirror.shared.finished(session, at: session.endedAt ?? Date())
            heartRate.stop()
            // Capture the GPS track before stop() (#348/#378): the flattened
            // route goes to Health (a non-empty one classifies the workout
            // as an outdoor run with its map), and the segmented track
            // becomes the session's durable record — the GPX bytes stored
            // here are the EXACT sidecar the repo sync will replay, plus
            // the denormalized summary for cheap display.
            let runTrack = location.sessionTrack
            let runRoute = location.sessionRoute
            location.stop()
            // Positive-measurement gate, not just non-empty: a degenerate
            // track (standing still → zero distance, or sub-floor creep →
            // zero moving time) must stamp NOTHING — the validator requires
            // positive run measurements, and an invalid session file would
            // make a whole repo restore throw. No summary, no sidecar; the
            // set actuals still tell the honest story.
            let hasRealRun = !runTrack.isEmpty && runTrack.totalMeters > 0 && runTrack.movingSeconds > 0
            if hasRealRun {
                session.routeData = GPX.encode(runTrack, name: session.routineName, startedAt: session.effectiveStart)
                session.runDistanceMeters = runTrack.totalMeters
                session.runMovingSeconds = runTrack.movingSeconds
                session.runElevationGainMeters = runTrack.elevationGainMeters
            }
            // The session's heart-rate summary, from Health's samples
            // over the window. Watch imports never pass through here —
            // their summary rides the result payload. The completion
            // lands on the main queue; the record backfill (session
            // detail) catches samples that sync in later.
            if let endedAt = session.endedAt {
                let finished = session
                HeartRateMonitor.summary(from: finished.effectiveStart, to: endedAt) { average, peak in
                    guard !finished.isDeleted else { return }
                    if let average { finished.averageHeartRate = average }
                    if let peak { finished.maxHeartRate = peak }
                }
            }
            // Phone-logged sessions reach Health here; watch imports are
            // recorded by the wrist's own live session (#90). Health gets
            // the route only when the durable record calls it a run — the
            // two must not disagree about a degenerate zero-distance track.
            HealthRecorder.record(session, route: hasRealRun ? runRoute : [])
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
            Text("Nothing logged yet")
                .font(.system(.title3, weight: .bold))
            Text("Add exercises as you go. When you finish, the whole thing can become a routine.")
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                // Creation is green (#202).
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 22)
                .frame(minHeight: 48)
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

    /// An ad-hoc session with every added set logged. Not a finish —
    /// the session has no plan to run out of, so the next move is the
    /// user's: add another exercise, or call it done (device report
    /// 2026-07-23: auto-finishing here ended the workout after the
    /// first added exercise).
    private var stagedWorkDoneStage: some View {
        VStack(spacing: 14) {
            Text("SCRATCH WORKOUT")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(Theme.textSecondary)
            Text("All added exercises done")
                .font(.system(.title3, weight: .bold))
            Text("Add another, or finish and log the workout.")
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                // Creation is green (#202).
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 22)
                .frame(minHeight: 48)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.borderStrong)
                )
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("addExerciseToSessionButton")
            .padding(.top, 8)
            Button {
                finishSession(dismissAfter: false)
            } label: {
                Text("Finish workout")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            }
            .buttonStyle(.raisedPrimaryKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("finishScratchWorkoutButton")
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

                    // The session's heart story, when Health had one.
                    // Facts in ink — avg/max are a record, not a delta.
                    if let heartLine = heartRateSummaryLine {
                        heartLine
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }

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
                        Text("widgets can show your schedule right on the home screen · long-press there to add one")
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            // Creation is green (#202).
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
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
                // Closing the recap goes home: the root switches to
                // Today and Today converts this workout's card to done
                // (pending green → committed purple). Posted before the
                // dismiss so Today is already staging the animation as
                // the cover pulls away. Only a finished session reaches
                // here — Discard deletes and dismisses on its own path.
                NotificationCenter.default.post(
                    name: .plusplusWorkoutFinished,
                    object: session.persistentModelID
                )
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
        let elapsed = max(0, Int(session.duration ?? 0))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    /// "♥ 132 avg · 158 max" — appears a beat after the finish (the
    /// summary query completes async and the @Bindable session
    /// re-renders), or not at all when Health had nothing.
    private var heartRateSummaryLine: Text? {
        guard let average = session.averageHeartRate else { return nil }
        var line = "\(average) avg"
        if let peak = session.maxHeartRate {
            line += " · \(peak) max"
        }
        return Text("\(Image(systemName: "heart.fill")) \(line)")
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
                durationSeconds: last.actualDuration,
                extras: last.extraActuals,
                distanceUnit: last.metricProfile.distanceUnit
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
                durationSeconds: last.actualDuration,
                extras: last.extraActuals
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
        return "★ \(best.name.lowercased()) \(WorkoutMetric.weight.displayText(best.weight, weightUnit: weightUnit)) · new best"
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
                addedOn: routine.createdAt,
                calendar: calendar
            )
            // Only `.notDue` next occurrences feed "next up". A `.missed`
            // routine is deliberately omitted (2026-07-14): the finish
            // screen is a moment of completion, and carried-over work
            // surfaces calmly in Today's CARRIED OVER lane, not as a nag
            // here (anti-shame grammar).
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
        var fact = "\(best.name) · \(day)"
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
    let heartRate: HeartRateMonitor
    /// Non-nil only on an outdoor run — its presence drives the live
    /// pace/distance rows.
    let location: RunLocationMonitor?
    let onComplete: () -> Void

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @State private var wheel: WorkoutMetric?
    /// The metric whose stepper-increment sheet is open (load metrics only).
    @State private var incrementMetric: WorkoutMetric?

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lb
    }

    /// The profile this set was snapshotted under and the metric driving
    /// its execution: reps → the classic log flow, duration → the
    /// auto-timer, distance/calories → a target card logged by hand.
    private var profile: MetricProfile { log.metricProfile }
    private var driver: WorkoutMetric { log.driver }

    /// The load metric sharing the stage with reps (weight, or the
    /// assistance stack on assisted machines). nil for pure bodyweight.
    private var loadMetric: WorkoutMetric? {
        if profile.contains(.weight) { return .weight }
        if profile.contains(.assistance) { return .assistance }
        return nil
    }

    /// What the stage's cards already show — everything else tracked
    /// renders as a compact secondary row. Classic metrics with a stored
    /// target the profile no longer tracks (pre-flip prescriptions) join
    /// the rows so nothing planned goes invisible mid-workout; weight
    /// defers to the assistance bridge when assistance is tracked.
    private var secondaryMetricsList: [WorkoutMetric] {
        let shown: [WorkoutMetric] = driver == .reps
            ? (loadMetric.map { [$0, .reps] } ?? [.reps])
            : [driver]
        var metrics = profile.metrics
        if log.targetWeight != nil, !profile.contains(.weight), !profile.contains(.assistance) {
            metrics.append(.weight)
        }
        if log.targetRepsLower != nil, !profile.tracksReps {
            metrics.append(.reps)
        }
        if log.targetDuration != nil, !profile.contains(.duration) {
            metrics.append(.duration)
        }
        return MetricProfile(metrics, distanceUnit: profile.distanceUnit).metrics
            .filter { !shown.contains($0) }
    }

    /// Sets in this exercise's block (same group + name).
    private var setsTotal: Int {
        session.sortedSetLogs.filter {
            $0.groupIndex == log.groupIndex && $0.exerciseName == log.exerciseName
        }.count
    }

    /// The pace target in ink, or a placeholder glyph when untargeted.
    private var paceTargetText: Text {
        guard let target = log.target(.pace) else { return Text("—").foregroundStyle(Theme.textFaint) }
        return Text(WorkoutMetric.pace.formatted(target) + " " + profile.distanceUnit.paceLabel)
            .foregroundStyle(Theme.textPrimary)
    }

    private var distanceTargetText: Text {
        guard let target = log.target(.distance) else { return Text("—").foregroundStyle(Theme.textFaint) }
        return Text(WorkoutMetric.distance.displayText(target, weightUnit: weightUnit, distanceUnit: profile.distanceUnit))
            .foregroundStyle(Theme.textPrimary)
    }

    var body: some View {
        VStack(spacing: 0) {
            if driver == .duration {
                // Duration is driven by the auto-timer dock; its secondary
                // metrics (a treadmill's incline) ride the header scroll as
                // cards, above the timer.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        exerciseHeader
                            .padding(.horizontal, 20)
                        if !secondaryMetricsList.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(secondaryMetricsList) { metricCard($0) }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        }
                    }
                }
                durationDock
            } else {
                // Rep/cardio work: the header scrolls up top, the metric
                // cards bottom-anchor just above Log set (the pausedView /
                // RestView pattern), so short content hugs the CTA and a tall
                // stack (big Dynamic Type, many metrics) scrolls instead of
                // shoving Log set off-screen (#391).
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            exerciseHeader
                                .padding(.horizontal, 20)
                            Spacer(minLength: 20)
                            stage
                        }
                        .frame(minHeight: proxy.size.height)
                    }
                }
                logDock
            }
        }
        .sheet(item: $wheel) { metric in
            MetricWheelSheet(
                metric: metric,
                weightUnit: weightUnit,
                distanceUnit: profile.distanceUnit,
                value: Binding(
                    get: { log.actual(metric) ?? log.target(metric) },
                    set: { log.setActual(metric, to: $0) }
                )
            )
        }
        // The increment sheet edits the load stride on the exercise's gear
        // (#391) — presented only for metrics that can hold one.
        .sheet(item: $incrementMetric) { metric in
            IncrementSheet(
                metric: metric,
                weightUnit: weightUnit,
                distanceUnit: profile.distanceUnit,
                current: stepValue(metric)
            ) { choice in
                log.exercise?.setStep(choice, for: metric)
            }
        }
    }

    /// The scrolling exercise header — set kicker, name, what's next, the
    /// cardio prescription lines, and notes. Extracted (#391) so both the
    /// duration and rep/cardio layouts mount it above their docks. Carries no
    /// horizontal padding of its own; call sites inset it by 20.
    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
                    // The kicker keeps the set count alone. Cardio work
                    // (a timed piece, a distance repeat) counts ROUNDS:
                    // "round 3 of 8" is the honest name for an interval.
                    Text("\(driver == .reps ? "SET" : "ROUND") \(log.setNumber) OF \(setsTotal)")
                        .foregroundStyle(Theme.accent)
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                        .kerning(0.7)
                        .padding(.top, 20)

                    Text(log.exerciseName)
                        .font(.system(.title, weight: .bold))
                        .padding(.top, 6)

                    // What comes after this set: a superset partner, or
                    // the exercise after this block, with its prescription.
                    // The clear replacement for the old A→B→C rotation
                    // chips (which truncated and confused more than they
                    // told), and it rides the shared header so auto-logging
                    // duration sets show it too (Dave, build-46).
                    if let upNext = upNextLine {
                        HStack(spacing: 8) {
                            Text("NEXT")
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                                .kerning(0.8)
                            upNext
                        }
                        .padding(.top, 10)
                    }

                    // Weight/reps sets carry target + last INSIDE the
                    // value cards now (mock 08); this line survives
                    // only for duration-driven sets, which have no cards.
                    if driver == .duration {
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

                    // The cardio prescription: target zone or range in
                    // plain ink (a prescription is a fact), the live
                    // reading beside it going accent while it's inside
                    // the band. Outside the duration branch — a
                    // distance-driven interval carries a band too.
                    if let target = log.targetHeartRate {
                        HStack(spacing: 10) {
                            (Text("target hr ").foregroundStyle(Theme.textSecondary)
                                + Text(target.label(maxHeartRate: heartRate.maxHeartRate))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary))
                            LiveHeartRateLabel(monitor: heartRate, target: target)
                        }
                        .font(.system(.subheadline))
                        .padding(.top, 6)
                    }

                    // Outdoor run: pace and distance as target · live
                    // actual, the actual accenting when it's meeting the
                    // target — the same grammar as the heart-rate line.
                    if let location {
                        VStack(alignment: .leading, spacing: 6) {
                            if profile.contains(.pace) {
                                HStack(spacing: 10) {
                                    (Text("pace ").foregroundStyle(Theme.textSecondary)
                                        + paceTargetText)
                                    LivePaceLabel(monitor: location, unit: profile.distanceUnit, target: log.target(.pace))
                                }
                            }
                            if profile.contains(.distance) {
                                HStack(spacing: 10) {
                                    (Text("distance ").foregroundStyle(Theme.textSecondary)
                                        + distanceTargetText)
                                    LiveDistanceLabel(monitor: location, unit: profile.distanceUnit, target: log.target(.distance))
                                }
                            }
                        }
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(.top, 6)
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
    }

    // MARK: - Stage (mock 08, #391)
    // EVERY configurable metric gets the same card — big value opening the
    // wheel, live "last · Δ", two full-width hold-to-repeat stepper keys, and
    // (on the load metrics) a `slider.horizontal.3` key opening the increment
    // sheet. Rep work stacks WEIGHT/ASSIST then REPS; cardio leads with its
    // driver; anything else the profile tracks follows as more cards. Reps and
    // secondaries used to be cramped rows — Dave asked for full cards (2026-07-16).

    /// The effective stepper increment for a metric, for the key labels
    /// ("−5" / "+5"): the exercise's per-gear override first (loads only,
    /// via `stepOverride`), then the metric's own unit step.
    private func stepValue(_ metric: WorkoutMetric) -> Double {
        log.exercise?.stepOverride(for: metric)
            ?? metric.step(weightUnit: weightUnit, distanceUnit: profile.distanceUnit)
    }

    /// "last 130 · +5" — the previous set's value and the live delta
    /// against it (mock 08, in the big card's corner). Green only while
    /// it's an IMPROVEMENT in the metric's own direction: +5 lb of
    /// weight, but −10 lb of assistance (anti-shame, the RoutineDiff
    /// rule — regressions render neutral). Nil without a prior.
    private func deltaAnnotation(_ metric: WorkoutMetric) -> (text: String, color: Color)? {
        guard let last = lastTime?.actual(metric), last > 0 else { return nil }
        let current = log.actual(metric) ?? log.target(metric) ?? last
        let delta = current - last
        let deltaText = delta == 0
            ? "="
            : (delta > 0 ? "+" : "−") + metric.formatted(abs(delta))
        let improved = switch metric.improvementDirection {
        case .up: delta > 0
        case .down: delta < 0
        case .neutral: false
        }
        return (
            "last \(metric.formatted(last)) · \(deltaText)",
            improved ? Theme.accent : Theme.textFaint
        )
    }

    /// The metrics shown as cards, in order: the load (or bare reps / the
    /// cardio driver) first, then everything else the profile tracks. The
    /// driver/load are already excluded from `secondaryMetricsList`, so no
    /// metric appears twice.
    private var stageMetrics: [WorkoutMetric] {
        var metrics: [WorkoutMetric] = []
        if driver == .reps {
            if let loadMetric { metrics.append(loadMetric) }
            metrics.append(.reps)
        } else {
            metrics.append(driver)
        }
        metrics += secondaryMetricsList
        return metrics
    }

    private var stage: some View {
        VStack(spacing: 12) {
            ForEach(stageMetrics) { metricCard($0) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// The unified metric card (#391): mono label with the increment key on
    /// its right (load metrics only — the rest have no gear stride to edit),
    /// the big value opening the wheel, the live "last · Δ" in data green, two
    /// full-width hold-to-repeat stepper keys, and the carry-forward note
    /// (faint — a mechanic note, not a delta).
    private func metricCard(_ metric: WorkoutMetric) -> some View {
        let current = log.actual(metric) ?? log.target(metric)
        let unitText = metric.unit(for: current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit)
        let canAdjust = log.exercise?.canAdjustStep(for: metric) ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(metric.label.uppercased())
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .kerning(0.7)
                Spacer(minLength: 8)
                if canAdjust {
                    ConfigIconButton(
                        accessibilityLabel: "Change \(metric.label.lowercased()) increment",
                        identifier: "configIncrement-\(metric.rawValue)"
                    ) {
                        incrementMetric = metric
                    }
                    // Pull the 44 pt hit frame back into the corner so it
                    // doesn't bloat the compact label row.
                    .padding(.trailing, -7)
                    .padding(.vertical, -7)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    wheel = metric
                } label: {
                    (Text(metric.formatted(current))
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        + Text(unitText.isEmpty ? "" : " \(unitText)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        // Digits roll like an odometer, directional
                        // with the raw value (#216).
                        .contentTransition(.numericText(value: current ?? 0))
                        .animation(Theme.Anim.standard, value: current)
                }
                .accessibilityIdentifier(metric == .weight ? "logWeightValue" : "log-\(metric.rawValue)-value")
                Spacer(minLength: 8)
                if let annotation = deltaAnnotation(metric) {
                    Text(annotation.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(annotation.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                        .animation(Theme.Anim.standard, value: annotation.text)
                }
            }
            HStack(spacing: 10) {
                HoldRepeatKey(
                    label: "−\(metric.formatted(stepValue(metric)))",
                    identifier: metric == .weight ? "logWeightDecrement" : "log-\(metric.rawValue)-decrement"
                ) {
                    stepActual(metric, -1)
                }
                HoldRepeatKey(
                    label: "+\(metric.formatted(stepValue(metric)))",
                    identifier: metric == .weight ? "logWeightIncrement" : "log-\(metric.rawValue)-increment"
                ) {
                    stepActual(metric, 1)
                }
            }
            if (metric == .weight || metric == .assistance), session.weightCarriesForward(from: log) {
                Text("new \(metric == .weight ? "weight" : "assist") carries to your remaining sets")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
    }

    private func stepActual(_ metric: WorkoutMetric, _ direction: Double) {
        // The stride: the exercise's per-gear override (loads only) or the
        // metric's own unit step — the same value the key label shows.
        let override = log.exercise?.stepOverride(for: metric)
        if metric == .reps {
            // Reps stay integer; step by the (possibly overridden) stride,
            // clamped to the reps range by the Kit.
            let current = (log.actualReps ?? log.targetRepsLower).map(Double.init)
            let stepped = direction > 0
                ? metric.incremented(current, stepOverride: override)
                : metric.decremented(current, stepOverride: override)
            log.actualReps = Int(stepped)
            return
        }
        let current = log.actual(metric) ?? log.target(metric)
        let stepped = direction > 0
            ? metric.incremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: override)
            : metric.decremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: override)
        log.setActual(metric, to: stepped)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                // Return logs the set for external-keyboard users (WCAG 2.1.1).
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("completeSetButton")

                PlusOneBurst(trigger: burstCount)
                    .offset(y: -40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            // The block tally and rest length that used to sit here are
            // gone (Dave, build-46): "SET n OF m" up top already carries
            // the count, and "what's next" now rides the header so every
            // driver — including auto-logging duration sets — shows it.
        }
        .padding(.bottom, 12)
    }

    /// The next DIFFERENT exercise coming up — a superset partner, or the
    /// exercise after this block — with its prescription. Nil when the
    /// next pending set is just another set of THIS exercise (the "SET n
    /// OF m" kicker already says that) or when nothing's left, so a plain
    /// block stays quiet until it hands off.
    private var upNextLine: Text? {
        guard let next = session.sortedSetLogs.first(where: {
            !$0.isCompleted && $0.order != log.order
        }), next.exerciseName != log.exerciseName else {
            return nil
        }
        let detail = MetricSummary.line(
            profile: next.metricProfile,
            weightUnit: weightUnit,
            repsText: next.targetReps.lower != nil ? next.targetReps.display : nil,
            value: { next.target($0) }
        ) ?? "\(next.driver == .reps ? "set" : "round") \(next.setNumber)"
        return Text(next.exerciseName)
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            + Text(" · ")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textFaint)
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
        guard let line = MetricSummary.line(
            profile: profile,
            weightUnit: weightUnit,
            repsText: log.targetReps.lower != nil ? log.targetReps.display : nil,
            value: { log.target($0) }
        ) else {
            return "\(driver == .reps ? "set" : "round") \(log.setNumber)"
        }
        return "target \(line)"
    }
}

/// "♥ 128" — the newest Health reading while it's fresh (a stale number
/// at the gym is worse than none, so anything older than the fresh
/// window renders NOTHING — including the chrome, when it wears any).
/// The reading goes accent while it satisfies `target`; targetless it
/// stays quiet ink, so green keeps meaning "where you're meant to be".
private struct LiveHeartRateLabel: View {
    let monitor: HeartRateMonitor
    let target: HeartRateTarget?
    var chrome = false

    var body: some View {
        // Ticks to EXPIRE a reading, not to display one — updates
        // arrive through the monitor's observation.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let bpm = monitor.latestBPM, let at = monitor.latestAt,
               context.date.timeIntervalSince(at) < HeartRateMonitor.freshWindow {
                let inTarget = target?.contains(bpm, maxHeartRate: monitor.maxHeartRate) ?? false
                let label = (Text("\(Image(systemName: "heart.fill")) ")
                    .foregroundStyle(inTarget ? Theme.accent : Theme.textSecondary)
                    + Text("\(bpm)")
                    .foregroundStyle(inTarget ? Theme.accent : Theme.textPrimary))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                let described = label
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: bpm)
                    .accessibilityLabel("Heart rate")
                    .accessibilityValue("\(bpm) beats per minute" + (inTarget ? ", in target" : ""))
                    .accessibilityIdentifier("liveHeartRate")
                if chrome {
                    // A readout is data, not a control — the soft r6 tag
                    // treatment (CardTagCapsule's), no stroke, beside the
                    // header's r11 raised keys (shape carries role).
                    described
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: CardTagCapsule.cornerRadius))
                } else {
                    described
                }
            }
        }
    }
}

/// "↗ 8:30 /mi" — the live GPS pace while it's fresh (same freshness rule
/// and chrome option as the heart-rate label). The reading goes accent
/// while it's meeting `target` (pace improves DOWN, so actual ≤ target);
/// untargeted it stays quiet ink.
private struct LivePaceLabel: View {
    let monitor: RunLocationMonitor
    let unit: DistanceUnit
    var target: Double?
    var chrome = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let pace = monitor.currentPaceSeconds, let at = monitor.latestAt,
               context.date.timeIntervalSince(at) < RunLocationMonitor.freshWindow {
                let meeting = target.map { pace <= $0 } ?? false
                let label = (Text("\(Image(systemName: "figure.run")) ")
                    .foregroundStyle(meeting ? Theme.accent : Theme.textSecondary)
                    + Text(WorkoutMetric.pace.formatted(pace))
                    .foregroundStyle(meeting ? Theme.accent : Theme.textPrimary)
                    + Text(" \(unit.paceLabel)")
                    .foregroundStyle(Theme.textSecondary))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                let described = label
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: pace)
                    .accessibilityLabel("Pace")
                    .accessibilityValue("\(WorkoutMetric.pace.formatted(pace)) \(unit.paceLabel)" + (meeting ? ", meeting target" : ""))
                    .accessibilityIdentifier("livePace")
                if chrome {
                    // A readout is data, not a control — the soft r6 tag
                    // treatment (CardTagCapsule's), no stroke, beside the
                    // header's r11 raised keys (shape carries role).
                    described
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: CardTagCapsule.cornerRadius))
                } else {
                    described
                }
            }
        }
    }
}

/// "1.24 mi" — the live GPS distance, accenting once it reaches `target`
/// (distance improves UP). Quiet ink before, and while untargeted.
private struct LiveDistanceLabel: View {
    let monitor: RunLocationMonitor
    let unit: DistanceUnit
    var target: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let value = monitor.totalDistanceInUnit, let at = monitor.latestAt,
               context.date.timeIntervalSince(at) < RunLocationMonitor.freshWindow {
                let reached = target.map { value >= $0 } ?? false
                Text(WorkoutMetric.distance.displayText(value, distanceUnit: unit))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(reached ? Theme.accent : Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: value)
                    .accessibilityLabel("Distance")
                    .accessibilityValue(WorkoutMetric.distance.displayText(value, distanceUnit: unit) + (reached ? ", target reached" : ""))
                    .accessibilityIdentifier("liveDistance")
            }
        }
    }
}

/// The "+1" popped on each logged set (Quiet Arcade, replacing the
/// mitosis "+"): a mono green +1 rises ~30 pt from the key's top edge,
/// scaling 0.7 → 1.25 while it fades, ~0.7 s, one-shot per trigger bump.
/// Real number, real increment — the whole brand in one flourish.
///
/// Driven by `keyframeAnimator`, which plays ONLY when `trigger` changes
/// and otherwise sits at `initialValue` (opacity 0). The old
/// value-derived opacity left it FROZEN at full opacity on any set whose
/// carried-in `trigger` was already > 0 — every set after the first
/// showed a stuck +1 above Log set before you'd logged anything (Dave,
/// build-46). A keyframe track can't get stranded like that: the resting
/// state is defined, not inferred.
private struct PlusOneBurst: View {
    let trigger: Int
    // Under Reduce Motion the +1 still appears (it's informative) but drops
    // the scale pop and upward travel, leaving a quiet opacity flash
    // (WCAG 2.3.3).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Beat {
        var opacity = 0.0
        var scale = 0.7
        var lift = 0.0
    }

    var body: some View {
        Text("+1")
            .font(.system(.body, design: .monospaced, weight: .bold))
            .foregroundStyle(Theme.accent)
            .allowsHitTesting(false)
            .keyframeAnimator(initialValue: Beat(scale: reduceMotion ? 1.0 : 0.7), trigger: trigger) { view, beat in
                view
                    .opacity(beat.opacity)
                    .scaleEffect(beat.scale)
                    .offset(y: beat.lift)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(0, duration: 0.65)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(reduceMotion ? 1.0 : 1.25, duration: 0.7)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(reduceMotion ? 0 : -30, duration: 0.7)
                }
            }
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
                        .animation(Theme.Anim.standard, value: pausedRemaining != nil)
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
    }

    private func togglePause() {
        if let remaining = pausedRemaining {
            let end = Date().addingTimeInterval(remaining)
            endDate = end
            pausedRemaining = nil
        } else if let endDate {
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
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
    /// A transition (different exercise or block up next, #369) says
    /// SWITCH; a new round of the same block says REST. Same screen,
    /// same controls — only the word changes.
    let isTransition: Bool
    let upNext: SetLog
    /// Live vitals through the rest: heart rate always, pace when the
    /// recovery interval is part of an outdoor run (a walk break still
    /// moves). `location` is non-nil only outdoors.
    let heartRate: HeartRateMonitor
    let location: RunLocationMonitor?
    let runUnit: DistanceUnit
    let onAddTime: () -> Void
    let onEnd: () -> Void

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))

            // Scrollable so the +30s / Skip controls stay reachable at large
            // accessibility text sizes; minHeight keeps it centered when it
            // fits (a11y audit).
            GeometryReader { screen in
              ScrollView {
                VStack(spacing: 20) {
                Text(isTransition ? "SWITCH" : "REST")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .kerning(1)

                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))

                rechargeBlocks(remaining: remaining)

                // Recovery at a glance — heart rate always, pace when a
                // walk break keeps moving. No target judgment during rest
                // (both stay quiet ink); pace simply drops out when you're
                // standing still.
                HStack(spacing: 14) {
                    LiveHeartRateLabel(monitor: heartRate, target: nil)
                    if let location {
                        LivePaceLabel(monitor: location, unit: runUnit, target: nil)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .kerning(0.8)
                    Text("\(upNext.exerciseName) · \(upNext.driver == .reps ? "set" : "round") \(upNext.setNumber)")
                        .font(.system(.body, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: (proxy.size.width - 10) * 5 / 12)
                                .frame(minHeight: 52)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
                        }
                        .buttonStyle(.raisedKey())
                        .accessibilityIdentifier("extendRestButton")
                        Button(action: onEnd) {
                            Text(isTransition ? "Skip" : "Skip rest")
                                .font(.system(.subheadline, weight: .bold))
                                .foregroundStyle(Theme.onPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                        }
                        .buttonStyle(.raisedPrimaryKey())
                        .accessibilityIdentifier("skipRestButton")
                    }
                }
                .frame(height: 56)
                .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: screen.size.height)
                .onChange(of: remaining) { oldValue, newValue in
                    // Beep the last three seconds; guard on a decrement so a
                    // +30s extension (which raises `remaining`) never beeps,
                    // and the higher "go" tone fires as the countdown lands on
                    // zero and the next exercise/set begins (#420).
                    if newValue < oldValue, (1...3).contains(newValue) {
                        CountdownCue.shared.tick()
                    }
                    if newValue <= 0 {
                        CountdownCue.shared.start()
                        onEnd()
                    }
                }
                .onAppear {
                    if remaining <= 0 { onEnd() }
                }
              }
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
        .animation(Theme.Anim.standard, value: filled)
    }

    /// "10 reps @ 135 lb" — weight value in ink, the rest faint. Classic
    /// rep work keeps its two-tone treatment; richer profiles (a rower's
    /// distance/pace line) render whole in ink via the shared summary.
    private var upNextTarget: Text? {
        let profile = upNext.metricProfile
        // Metrics-only comparison: profile equality includes the
        // distance unit, which is meaningless noise on a classic pair.
        if profile.metrics == MetricProfile.weightReps.metrics
            || profile.metrics == MetricProfile.repsOnly.metrics {
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
        guard let line = MetricSummary.line(
            profile: profile,
            weightUnit: weightUnit,
            repsText: upNext.targetReps.lower != nil ? upNext.targetReps.display : nil,
            value: { upNext.target($0) }
        ) else { return nil }
        return Text(line).foregroundStyle(Theme.textPrimary)
    }
}
