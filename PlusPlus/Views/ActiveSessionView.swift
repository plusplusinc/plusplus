import SwiftUI
import Combine
import SwiftData
import CoreLocation
import UIKit
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
    /// The set bar's up-next breathe falls back to a static green under
    /// Reduce Motion (WCAG 2.3.3), like the overview's pulse.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// The rest interval held across a pause, re-based onto the resume
    /// instant. Non-nil only while paused mid-rest, which is also how
    /// the paused screen knows a rest is what's being held.
    @State private var restPausedRemaining: TimeInterval?
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
    /// When the current effort's count-up clock started, and what it
    /// banked before the last pause.
    ///
    /// ⚠️ These live on the SESSION view, not inside the timer card, and
    /// that is a data-integrity fix rather than tidiness. Pausing swaps
    /// the whole body to `pausedView`, which UNMOUNTS the card, so an
    /// `@State` anchor seeded in `onAppear` restarted at zero on resume —
    /// and in count-up mode the displayed elapsed IS the logged duration.
    /// A 29-minute ride with one water stop recorded as four minutes,
    /// unrecoverably. Same law `bankRestForPause` exists for, same shape.
    @State private var effortStartedAt = Date()
    @State private var effortBanked: TimeInterval = 0
    /// When the live set became live — the window a per-set heart-rate
    /// summary is drawn over. Distinct from `effortStartedAt`, which
    /// re-anchors on RESUME so the clock doesn't double-count a pause;
    /// the heart-rate window wants the whole set, pause included, because
    /// the recovery in the middle is part of what the set cost.
    @State private var currentSetStartedAt = Date()
    /// Drives the island's measured-value refresh. A publisher rather than
    /// a `TimelineView` because nothing on screen depends on it — the
    /// on-screen readings have their own timelines.
    ///
    /// ⚠️ `@State`, not a computed property and not a plain `let`. A
    /// publisher rebuilt on each body pass is a NEW publisher, so
    /// `onReceive` resubscribes and `autoconnect()` restarts the timer
    /// from zero — on a screen that re-renders every second, a 30 s timer
    /// built that way never fires at all.
    @State private var islandRefresh = Timer.publish(every: 30, tolerance: 5, on: .main, in: .common).autoconnect()
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

    /// The noun this WHOLE session counts in, or nil for a sport that
    /// counts nothing. A MIXED session is never nil — `SessionModality`
    /// files strength-plus-cardio as strength — which is the right generic:
    /// a run plus a lifting block is not four pieces.
    private var sessionWorkUnit: WorkUnit? { session.modality.primary.workUnit }

    /// The same noun where a count ABOVE ONE has to be named out loud: the
    /// island's progress, the block bar's VoiceOver subject, the Live
    /// Activity's word. All three render only above one, and a count above
    /// one on a walk is exactly what the divider authored.
    private var sessionUnit: WorkUnit { WorkUnit.divider(sessionWorkUnit) }

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
                // The 16 pt content column (Dave, 2026-07-28): the same
                // width as Today's week bar, and the same as the metric
                // cards and the Log-set dock directly below it. At 20 it
                // sat inset from everything it shares a screen with.
                .padding(.horizontal, 16)
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
                        onAdjust: { adjustRest(by: $0) },
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
                        effortStartedAt: effortStartedAt,
                        effortBanked: effortBanked,
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
                // Discarded means discarded everywhere: a live recording
                // that merely ended would still save the workout to Health.
                LiveWorkoutController.shared.discard()
                modelContext.delete(session)
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            if completedSets > 0 {
                // One effort has no count worth naming, so the sentence
                // names the act instead of saying "the 1 set you logged".
                if let logged = WorkUnit.summaryCount(sessionWorkUnit, completedSets) {
                    Text("Finish keeps the \(logged) you logged; Discard deletes the session.")
                } else {
                    Text("Finish keeps what you logged; Discard deletes the session.")
                }
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
            .presentationDetents([.appTall])
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView(onConfigured: { config in
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
            Text("Today's exercises and everything you logged become the template.")
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
                    startedAt: session.effectiveStart,
                    workUnit: sessionUnit.singular
                )
            }
            // HR monitoring rides the workout clock: a routine session
            // has already started, so it begins now; an ad-hoc session
            // waits for its first exercise (engageClockIfNeeded).
            if !session.isFinished, session.isWorkoutStarted {
                heartRate.start(from: session.effectiveStart)
                syncLocation()
                startLiveRecordingIfEnabled()
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
        //
        // ⚠️ The REST countdown pauses too, but NOT from here — see
        // `bankRestForPause`. It has to happen before the state flips,
        // and `.onChange` fires after the render that observed it.
        .onChange(of: session.isPaused) { _, paused in
            paused ? location.pause() : location.resume()
            // The live recording holds with the clock, so paused minutes
            // are not filed as effort. No-op when nothing is recording.
            paused ? LiveWorkoutController.shared.pause() : LiveWorkoutController.shared.resume()
            // Belt for the Pause key's braces, and cover for any future
            // pause affordance (#157's island controls would post a
            // notification, exactly like `.plusplusAdjustRest` does).
            // Safe on THIS edge only: by the time it fires, `isPaused` is
            // already true, so the body has rendered `pausedView` and
            // RestView is gone — no frame can observe the un-banked state.
            // The RESUME side must stay in the button; there the ordering
            // is the whole point. `bankRestForPause` is guarded, so the
            // two callers can't double-apply.
            if paused { bankRestForPause() }
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
        // A new set is a new effort: re-anchor the count-up clock, drop
        // what the last one banked, and stamp the heart-rate window.
        // ⚠️ Keys on the LOG's order, since the cursor moves for a new
        // round of the same block as well as a new exercise. It fires on
        // the way into the rest screen too, which is correct for both: the
        // next set starts when the last one ended, and the rest is the
        // recovery, not the effort.
        .onChange(of: session.currentLog?.order) { _, _ in
            effortStartedAt = Date()
            effortBanked = 0
            currentSetStartedAt = Date()
        }
        // Bank the count-up across a pause, for the same reason and on the
        // same edge as `bankRestForPause`: by the time this fires the body
        // has already rendered `pausedView`, so no frame observes the
        // un-banked state, and the resume side re-anchors.
        .onChange(of: session.isPaused) { _, paused in
            if paused {
                effortBanked += Date().timeIntervalSince(effortStartedAt)
            } else {
                effortStartedAt = Date()
            }
        }
        // ⚠️ The island's distance and pace are pushed values, not
        // date-derived ones like the elapsed clock, so without this they
        // would freeze at whatever they read when the set began and sit
        // there for forty minutes — a stalled number the island cannot
        // tell you is stale, which is the exact class of lie this push is
        // removing. Every 30 s, and only while an outdoor effort is
        // actually running: ActivityKit budgets app-driven updates, and a
        // strength session must not spend any of them.
        .onReceive(islandRefresh) { _ in
            guard isOutdoorNow, !session.isPaused, !session.isFinished, restEndDate == nil else { return }
            syncActivityWorking()
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
            case .add: adjustRest(by: RestAdjustment.stepSeconds)
            case .subtract: adjustRest(by: -RestAdjustment.stepSeconds)
            case .skip: endRest()
            }
        }
        // A WATCH-initiated rest (live mirror, #322) reflected onto the
        // open phone view — the countdown appears/clears here too.
        // The mirror op is kind-agnostic, so a watch-initiated pause
        // always reads REST here (#369 deferred the kind op-field).
        .onReceive(NotificationCenter.default.publisher(for: LiveMirror.restChanged)) { note in
            guard let endsAt = note.object as? Date else {
                restEndDate = nil
                restPausedRemaining = nil
                return
            }
            let interval = max(0, endsAt.timeIntervalSinceNow)
            restTotalSeconds = max(1, Int(interval.rounded()))
            restIsTransition = false
            // ⚠️ The one other path that can set a rest, so it has to bank
            // like the Pause key does: a set logged on the WRIST while the
            // phone sits paused would otherwise park a wall-clock date
            // behind the paused screen, and Resume would remount RestView
            // against an expired date and eat the rest — the exact bug
            // bankRestForPause exists to prevent, through a door it
            // doesn't own (swift-reviewer).
            if session.isPaused {
                restPausedRemaining = interval
                restEndDate = nil
            } else {
                restEndDate = endsAt
            }
        }
    }

    // MARK: - Rest controls (shared by RestView buttons and the island)

    /// Steps the running countdown by ±15 s (the on-screen pair and the
    /// island's controls post the same amounts).
    ///
    /// ⚠️ `restTotalSeconds` moves BY THE SAME DELTA, because it is the
    /// recharge blocks' denominator and the stepper now sits directly
    /// under those blocks: left alone, `+15s` would push `remaining`
    /// past the total and the bar would simply pin full, so the control
    /// would appear to do nothing. Shifting both keeps the bar meaning
    /// "this rest, as it now stands" and makes it grow and shrink with
    /// the taps above it.
    private func adjustRest(by seconds: Int) {
        guard let current = restEndDate, let currentLog = session.currentLog else { return }
        // ⚠️ Subtracting CLAMPS to one full step left; it does not refuse.
        // "Never reaches zero" has to be enforced on the RESULT, not on
        // the starting value: a guard of "more than one step left" still
        // allows 16 s − 15 s, which lands inside a second of zero and
        // ends the rest — a Skip performed by the minus key, from a
        // window that occurs in every single rest (swift-reviewer).
        // Clamping also keeps the ISLAND honest, since a Live Activity
        // button has no disabled state: near the floor its minus still
        // moves the clock to the floor instead of silently doing nothing.
        // The outer `min` stops a clamp from ever running the rest UP
        // when the countdown is already inside the floor.
        let floor = Date().addingTimeInterval(TimeInterval(RestAdjustment.stepSeconds))
        let proposed = current.addingTimeInterval(TimeInterval(seconds))
        let adjusted = seconds < 0 ? min(current, max(proposed, floor)) : proposed
        let applied = adjusted.timeIntervalSince(current)
        // A clamp that lands on the floor already applies nothing.
        guard abs(applied) >= 1 else { return }
        restEndDate = adjusted
        // Moves by what was APPLIED, not by what was asked for, or a
        // clamped subtract would desync the blocks from the clock.
        restTotalSeconds = max(1, restTotalSeconds + Int(applied.rounded()))
        reflectRest(endDate: adjusted, upNext: currentLog)
    }

    /// Holds the rest across a pause: the interval is banked and the end
    /// date cleared, so nothing can expire behind the paused screen.
    ///
    /// ⚠️ `restEndDate` is a WALL-CLOCK instant, which is why Pause used
    /// to be hidden mid-rest: the paused screen replaces `RestView`, so
    /// nothing ticks, but the date keeps arriving — and on resume the
    /// remounting view computes zero remaining and `onAppear` fires
    /// `onEnd()`. The rest, silently eaten by the pause. Banking the
    /// interval and re-basing it is the same trick the interval timer
    /// uses (`pausedRemaining`).
    ///
    /// ⚠️ Called from the Pause KEY, not from `.onChange(of: isPaused)`:
    /// an `onChange` runs after the render that observed the flip, so
    /// the first paused frame would read the un-banked state (and on the
    /// way back, `RestView` would remount against the expired date
    /// before the re-base landed — a race for the bug this exists to
    /// prevent). Both are guarded, so neither can double-apply.
    ///
    /// The island drops back to the working phase, since a countdown
    /// that keeps running to zero while the workout is held is worse
    /// than no countdown. (The activity's ELAPSED timer still advances
    /// through a pause — pre-existing, unchanged here.)
    private func bankRestForPause() {
        guard let end = restEndDate else { return }
        restPausedRemaining = max(0, end.timeIntervalSinceNow)
        restEndDate = nil
        // Deliberately NOT LiveMirror.restEnded: the op vocabulary has no
        // "held" kind, and telling the wrist the rest is OVER is further
        // from the truth than leaving it showing a rest it can't tick.
        // A real pause op is the honest fix and a Kit change (#322's
        // deferred pile).
        syncActivityWorking()
    }

    /// Re-bases the banked rest onto the resume instant.
    private func resumeRestAfterPause() {
        guard let banked = restPausedRemaining else { return }
        restPausedRemaining = nil
        let end = Date().addingTimeInterval(banked)
        restEndDate = end
        if let upNext = session.currentLog {
            reflectRest(endDate: end, upNext: upNext)
        }
    }

    private func endRest() {
        // ⚠️ Cancels BOTH representations of a live rest. While paused the
        // end date is nil and the interval is banked, and the overview's
        // jump affordances reach this from the PAUSED screen — a guard on
        // the date alone returned early there, so "skip to this exercise"
        // left the bank intact and Resume restored a countdown in front of
        // the exercise you had just said to go to now (swift-reviewer).
        guard restEndDate != nil || restPausedRemaining != nil else { return }
        restEndDate = nil
        restPausedRemaining = nil
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
            totalSets: totalSets,
            distanceText: islandDistanceText,
            paceText: islandPaceText
        )
    }

    /// The live distance for the island, formatted here because the app is
    /// the only side that knows the exercise's denomination. Only while
    /// the fix is FRESH — a stale reading frozen on the Lock Screen reads
    /// as a stalled run, and the island cannot tell you it is stale.
    private var islandDistanceText: String? {
        guard isOutdoorNow, location.isFresh, let value = location.totalDistanceInUnit else { return nil }
        let profile = session.currentLog?.metricProfile
        return WorkoutMetric.distance.displayText(
            value,
            distanceUnit: profile?.distanceUnit ?? location.unit,
            paceReference: profile?.paceReference
        )
    }

    private var islandPaceText: String? {
        guard isOutdoorNow, location.isFresh, let pace = location.currentPaceSeconds else { return nil }
        let profile = session.currentLog?.metricProfile
        let reference = profile?.resolvedPaceReference ?? location.unit.defaultPaceReference
        return WorkoutMetric.pace.formatted(pace) + " " + reference.label
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
                            // Ink, not `notes`: this sits on its own wash.
                            .foregroundStyle(Theme.notesInk)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(Theme.notesWash, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
                            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                                .strokeBorder(Theme.notesRing, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Pace and distance can't track. Location is off.")
                        .accessibilityHint("Opens iOS Settings")
                        .accessibilityIdentifier("gpsDeniedChip")
                    }
                }

                // Pause the workout clock. Shown whenever it's actually
                // running, INCLUDING mid-rest (2026-07-27) — a rest is
                // exactly when something interrupts you, and the countdown
                // now banks and re-bases across a pause instead of
                // expiring behind it. Still hidden before the first
                // exercise, and through the +1 beat.
                if session.isRunning, lingeringLog == nil {
                    Button {
                        // Bank BEFORE the flip; see bankRestForPause.
                        bankRestForPause()
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
                        Text(totalSets <= 1
                            ? clockText(at: context.date)
                            : "\(sessionUnit.singular) \(min(completedSets + 1, totalSets))/\(totalSets) · \(clockText(at: context.date))")
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
        // The 16 pt content column, like everything under it (Dave,
        // 2026-07-28). `RaisedKeyStyle` insets only the BOTTOM (its
        // travel), so a key's cap edge lands exactly on this number —
        // at 14 the End key overhung the bar and the cards by 2 pt.
        .padding(.horizontal, 16)
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
        startLiveRecordingIfEnabled()
    }

    /// Hand the recording to the phone's own `HKWorkoutSession` when the
    /// user has opted in (off by default). Idempotent, and inert when the
    /// switch is off — with it off nothing below changes and the finish
    /// still writes retrospectively.
    ///
    /// ⚠️ It rides the WORKOUT CLOCK, not the screen: an ad-hoc session
    /// exists while its exercises are being assembled, and a session that
    /// began recording then would file the assembly time as training.
    /// Both callers are the two places the clock engages.
    private func startLiveRecordingIfEnabled() {
        LiveWorkoutController.shared.start(modality: session.modality, at: session.effectiveStart)
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
                    // The frozen clock says the timer is held and the card
                    // says what it's holding, so the old "your workout timer
                    // is on hold" caption between them was a second referent
                    // for the same fact 30 pt from the ON HOLD label.
                    pausedPlace
                    Spacer()
                    Button {
                        // Re-base BEFORE the flip, or the remounting
                        // RestView reads an expired date and ends the rest.
                        resumeRestAfterPause()
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
    }

    /// Where the pause caught you, and what it's holding you back from
    /// (Dave, 2026-07-27). Paused used to show a frozen clock and
    /// nothing else, so coming back to the phone told you it was held
    /// but not what from — and mid-rest that matters most, since the
    /// screen you'd otherwise be looking at is the one naming the set
    /// you're about to do.
    ///
    /// Two labelled facts in the rest screen's card anatomy: what's on
    /// hold, then what follows it. UP NEXT is omitted rather than
    /// emptied when the pause caught the last set of the workout.
    @ViewBuilder
    private var pausedPlace: some View {
        let held = heldDescription
        if held != nil || pausedUpNext != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let held {
                    pausedFact(label: "ON HOLD", value: held)
                }
                if let next = pausedUpNext {
                    pausedFact(label: "UP NEXT", value: next)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private func pausedFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .kerning(0.8)
            Text(value)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The held rest interval. Prefers the banked value and falls back to
    /// a live read, so this reads correctly even on a frame where the
    /// pause flipped before the banking did (no such path today; the
    /// keys bank first).
    private var heldRestRemaining: TimeInterval? {
        if let banked = restPausedRemaining { return banked }
        return restEndDate.map { max(0, $0.timeIntervalSinceNow) }
    }

    /// "Rest · 0:42 left" when the pause caught a countdown, else the set
    /// that was in play. The banked interval is the honest number: the
    /// countdown is stopped, so a live clock here would be a lie.
    private var heldDescription: String? {
        if let banked = heldRestRemaining {
            let seconds = max(0, Int(banked.rounded(.up)))
            let clock = String(format: "%d:%02d", seconds / 60, seconds % 60)
            return "\(restIsTransition ? "Switch" : "Rest") · \(clock) left"
        }
        guard let log = session.currentLog else { return nil }
        return log.caption
    }

    /// Mid-rest, the set the countdown leads into. Mid-exercise, the next
    /// DIFFERENT exercise — the next set of what you're already on is the
    /// same answer as ON HOLD, and repeating it says nothing.
    private var pausedUpNext: String? {
        guard let current = session.currentLog else { return nil }
        if heldRestRemaining != nil {
            return current.caption
        }
        // Keyed on (group, name), not name alone: a routine that comes
        // back to an exercise in a later block would otherwise skip past
        // that occurrence and name something farther down.
        return session.sortedSetLogs.first {
            $0.order > current.order && !$0.isCompleted
                && ($0.groupIndex != current.groupIndex || $0.exerciseName != current.exerciseName)
        }?.exerciseName
    }

    /// Block-style set progress (Quiet Arcade, mock 08): one block per
    /// set of the CURRENT exercise's block, synced with the "SET N OF
    /// M" kicker — session-wide position lives in the header pill.
    /// Hidden when finished (the purple screen has its own bars) and
    /// before a scratch session's first exercise.
    ///
    /// The blocks carry the app's state grammar, not plain progress
    /// (Dave, 2026-07-28): landed sets purple, the one you're on green,
    /// the rest inert. ⚠️ Status is read PER LOG, never "index < count" —
    /// a jump/redo can complete sets out of order, and a left-to-right
    /// fill would then colour the wrong blocks. While a rest runs the
    /// live block BREATHES: the cursor has already moved on by then, so
    /// the green block is the set you're about to do, and the bar shows
    /// it waiting for you.
    @ViewBuilder
    private var progressBar: some View {
        if !session.isFinished, let log = lingeringLog ?? session.currentLog {
            let block = session.sortedSetLogs.filter {
                $0.groupIndex == log.groupIndex && $0.exerciseName == log.exerciseName
            }
            let states: [BlockState] = block.map { setLog -> BlockState in
                if setLog.isCompleted { return .done }
                return setLog.order == log.order ? .live : .upcoming
            }
            // ⚠️ A one-block bar states nothing, and on a continuous
            // effort it states nothing for forty minutes. Same law the
            // kicker already follows (`WorkUnit.kicker` returns nil at a
            // total of one): a count of one is not a count. The hero owns
            // progress for a single effort — a countdown fills its own
            // bar, and an open-ended one has nothing to fill toward.
            if block.count > 1 {
                BlockBar(
                    total: block.count,
                    // Colour comes from `states`; this is the VoiceOver count.
                    filled: block.filter(\.isCompleted).count,
                    states: states,
                    // Paused banks the rest and clears the date, so holding a
                    // workout stops the breathing too.
                    breathing: restEndDate != nil && !reduceMotion
                )
                // No caption sibling here, so the bar needs its own
                // subject or VoiceOver hears a bare "2 of 4" (a11y,
                // 2026-07-23).
                .accessibilityLabel(sessionUnit.plural.capitalized)
            }
        }
    }

    // MARK: - Actions

    /// Whether a log's dock is the timer rather than the stage — the
    /// same question `SetLoggingView.showsClock` asks, so the +1 beat and
    /// the dock can't disagree about which screen you are on. It used to
    /// key on `driver != .duration`, which after the hero chain meant a
    /// count-up rower got a 0.75 s beat on a dock that has no `+1` to
    /// show, while a count-up plank was excluded from one it could use.
    private func heroIsClock(for log: SetLog) -> Bool {
        var measurable: Set<WorkoutMetric> = [.duration]
        if isOutdoorNow, location.isFresh { measurable.formUnion([.distance, .pace]) }
        return CardioHero.resolve(
            profile: log.metricProfile,
            target: { log.target($0) },
            measurable: measurable
        )?.hero.isClock == true
    }

    /// What this set's heart rate was, over THIS set's own window.
    ///
    /// The window is the interesting part. Drawing it from the session
    /// start would average an hour of lifting and resting into one
    /// number that says almost nothing; drawing it from the previous
    /// set's completion would fold the rest in and drag every set down.
    /// `currentSetStartedAt` is stamped when the cursor moves, so the
    /// window is the effort itself.
    ///
    /// Applies to EVERY workout, not just cardio — a heavy triple spikes
    /// a heart rate too, and the set that spiked it is the unit worth
    /// recording. Health answers asynchronously and on the main queue;
    /// nil stays nil (no sensor, no access, no samples), because a
    /// fabricated zero is the anti-shame rule's inverse.
    private func recordHeartRate(for log: SetLog) {
        let from = currentSetStartedAt
        let to = Date()
        guard to > from else { return }
        HeartRateMonitor.summary(from: from, to: to) { average, peak in
            guard !log.isDeleted else { return }
            if let average { log.actualAverageHeartRate = average }
            if let peak { log.actualMaxHeartRate = peak }
        }
    }

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
        recordHeartRate(for: log)
        // An outdoor run's measured distance/pace become the logged
        // actuals, so the record reflects the GPS run instead of a hand
        // guess. Only for a single-round piece (the meter tracks the whole
        // exercise, not a per-round split), only with a FRESH reading (so
        // a still-acquiring re-base can't log stale values), and only when
        // not already edited — a manual actual always wins.
        if isOutdoorNow, location.isFresh, roundsInBlock(of: log) == 1 {
            // ⚠️ `storedActual`, not `actual`: pace derives from distance and
            // duration (#302), so an `actual(.pace) == nil` guard would read
            // a derivation as an edit and drop the GPS reading. The meter's
            // average is over MOVING time; a derivation divides by elapsed,
            // so the measurement is the better number and must win.
            if log.storedActual(.distance) == nil, let distance = location.totalDistanceInUnit {
                log.setActual(.distance, to: distance)
            }
            if log.storedActual(.pace) == nil, let pace = location.averagePaceSeconds {
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
        // stagedWorkDoneStage takes over when pending sets run out — except
        // when there was only ever ONE effort, where it asks about
        // repetition at the moment there is none ("All added exercises
        // done. Add another, or finish"). A run ends when you stop.
        let endsTheWorkout = !hasNext && (session.routine != nil || session.isSingleEffort)
        guard Self.playsLogBeat, !heroIsClock(for: log) else {
            if endsTheWorkout { finishSession(dismissAfter: false) }
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
            if session.nextPendingLog == nil, !session.isFinished,
               session.routine != nil || session.isSingleEffort {
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
            //
            // ⚠️ EXACTLY ONE writer. When the phone ran its own live
            // session it has been recording all along and saves the
            // workout itself, so the retrospective write would be a
            // duplicate in Health — the one failure mode worse than
            // either path alone. `finish` answers synchronously, before
            // its own asynchronous end sequence, precisely so this
            // decision never waits on a callback that might not arrive.
            let route = hasRealRun ? runRoute : []
            let liveOwnsTheSave = LiveWorkoutController.shared.finish(
                at: session.endedAt ?? Date(), route: route
            )
            if !liveOwnsTheSave {
                HealthRecorder.record(session, route: route)
            }
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
    /// The finish screen's fact line: name · count · elapsed. ⚠️ The count
    /// drops out at one — "the finish screen counts a run as 1 set" was on
    /// the cardio audit's list of things the app stated untruthfully, and
    /// it outlived the four beside it because the finish screen is the one
    /// record surface you reach before the session is a record.
    private var finishedFactLine: String {
        let parts: [String?] = [
            session.routineName.lowercased(),
            WorkUnit.summaryCount(sessionWorkUnit, completedSets),
            finalElapsedText
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

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
                    Text(finishedFactLine)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)

                    // The session's heart story, when Health had one.
                    // Facts in ink — avg/max are a record, not a delta.
                    if let heartLine = heartRateSummaryLine {
                        heartLine
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if !movedTally.isEmpty {
                        tallyCard(movedTally)
                            .padding(.horizontal, 20)
                    }

                    // The week bar with THIS session already counted;
                    // the ★ line rides the caption when a lift beat its
                    // own history (a real number or nothing at all).
                    if weekPlanNow.planned > 0 {
                        VStack(spacing: 8) {
                            // The caption below states the fact for
                            // VoiceOver; unhidden, the bar announces a
                            // bare "3 of 4" with no subject (a11y,
                            // 2026-07-23).
                            BlockBar(total: weekPlanNow.planned, filled: weekPlanNow.completed)
                                .accessibilityHidden(true)
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
                // Both sides are actuals here, so this compares rounds
                // finished against rounds finished. The highest set
                // number reached rather than the log count, since an
                // exercise can appear in more than one block and
                // `setNumber` is 1-based within its group.
                sets: mine.map(\.setNumber).max(),
                weight: top.actualWeight,
                reps: top.actualReps ?? last.actualReps,
                durationSeconds: last.actualDuration,
                extras: last.extraActuals,
                distanceUnit: last.metricProfile.distanceUnit
            )
            return TallyLine(name: name, delta: RoutineDiff.delta(target: target, prior: prior(for: name)))
        }
    }

    /// The tally rows worth showing: exercises that MOVED (or are new).
    /// Unchanged lines render nothing — not an "=" (Dave, 2026-07-23) —
    /// so an all-steady session shows no tally card at all. `netText`
    /// still aggregates over the full tally; the Kit summary drops
    /// unchanged deltas itself, so the two agree.
    private var movedTally: [TallyLine] {
        diffTally.filter { $0.delta != .unchanged }
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
                // Only against the same routine: a set count belongs to a
                // prescription, so alternating an A/B split that runs this
                // exercise for different rounds must not read as movement.
                sets: other.routineName == session.routineName ? matches.map(\.setNumber).max() : nil,
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

    /// Only changed/new deltas reach here — unchanged lines are filtered
    /// out of the tally entirely (Dave, 2026-07-23: "=" renders nowhere;
    /// an exercise that held steady is not news).
    private func deltaText(_ delta: RoutineDiff.Delta) -> Text {
        switch delta {
        case .new:
            return Text("new").foregroundStyle(Theme.accent)
        default:
            // Color by the segment's KIND, matching netText: deloads
            // render neutral (anti-shame) — a "−5 lb" row used to paint
            // green here while the net line correctly greyed it
            // (swift-reviewer, round 2b).
            let segment = RoutineDiff.summary(deltas: [delta], weightUnit: weightUnit).first
            let color: Color = segment?.kind == .down ? Theme.textSecondary : Theme.accent
            return Text(segment?.text ?? "").foregroundStyle(color)
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
            }
            result = result + Text(segment.text).foregroundStyle(color)
        }
        return result
    }

    /// "3 of 4 workouts this week · ★ bench 135 lb · new best".
    /// "Workouts", never "sessions" (#144: performed things are
    /// workouts; "session" is the type name, not the vocabulary).
    private var weekCaptionText: Text {
        let plan = weekPlanNow
        var text = Text("\(plan.completed) of \(plan.planned) workout\(plan.planned == 1 ? "" : "s") this week")
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
                addedOn: routine.scheduleAnchor,
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
    /// The count-up clock's anchor and its banked time, owned by the
    /// session view so a pause cannot discard them — see the properties
    /// there for why that matters.
    let effortStartedAt: Date
    let effortBanked: TimeInterval
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
        return trackedWithStranded.filter { !shown.contains($0) }
    }

    /// Everything the profile tracks, plus any classic metric carrying a
    /// stored target the profile no longer tracks — a pre-flip
    /// prescription stays visible mid-workout rather than vanishing.
    private var trackedWithStranded: [WorkoutMetric] {
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
    }

    // MARK: - The hero

    /// What the device can read RIGHT NOW — not what the exercise tracks.
    /// The clock always; distance and pace only while a location fix is
    /// actually live. `location` is non-nil only on an outdoor run, and a
    /// denied or lost fix is exactly the case the chain degrades for.
    private var measurableNow: Set<WorkoutMetric> {
        var metrics: Set<WorkoutMetric> = [.duration]
        if let location, let at = location.latestAt,
           Date().timeIntervalSince(at) < RunLocationMonitor.freshWindow {
            metrics.formUnion([.distance, .pace])
        }
        return metrics
    }

    /// What the big number counts. nil on rep work, which keeps the stage
    /// it has always had — that gate is what makes every strength surface
    /// identical.
    private var hero: CardioHero.Resolution? {
        CardioHero.resolve(
            profile: profile,
            // ⚠️ The PRESCRIPTION, never `actual ?? target`. A hero keyed
            // on the running actual feeds its own output back into its own
            // configuration: one tap on the distance stepper conjures a
            // "target" out of nothing, and committing a count-up effort
            // writes a duration that instantly re-resolves the card into a
            // countdown while the +1 beat is still on screen.
            target: { log.target($0) },
            measurable: measurableNow
        )
    }

    /// Whether the timer dock owns this effort. ⚠️ This replaces the old
    /// `driver == .duration` test, and the difference is the point: an
    /// UNTARGETED cardio effort used to fall through to a metric card
    /// reading "—" with a Log key under it and nothing moving on screen.
    private var showsClock: Bool { hero?.hero.isClock == true }

    /// The cards riding above the timer dock: everything tracked except
    /// the metric the clock already shows. ⚠️ Not `secondaryMetricsList`,
    /// which excludes the DRIVER — on a calorie-driven effort the clock is
    /// the hero and calories still needs its card, and using the driver
    /// list there made it disappear.
    private var clockStageMetrics: [WorkoutMetric] {
        trackedWithStranded.filter { $0 != .duration }
    }

    /// How long the countdown runs, or nil to count up. ⚠️ The old card
    /// derived this itself and fell back to a hard-coded thirty seconds
    /// when nothing was prescribed, so an open-ended effort counted down
    /// from a number nobody chose and logged itself at zero.
    private var countdownSeconds: Int? {
        guard case .progress(.duration, let target)? = hero?.hero else { return nil }
        return max(1, Int(target.rounded()))
    }

    /// Why the hero is not the number you asked for. Only rendered when a
    /// target exists that nothing can watch: silently showing a stopwatch
    /// where a five-mile countdown was prescribed is the kind of quiet
    /// substitution this whole push is removing.
    private var degradeLine: String? {
        // ⚠️ `unmeasurableTarget` is only ever set on an OUTDOOR profile
        // now (`CardioHero` hands an indoor target to `.selfReported`
        // instead), so this can only mean one thing and never appears
        // beside a pool or an erg. It said "no gps fix" in a chlorinated
        // pool before that split existed, and "calories isn't measured
        // here" on an air bike.
        guard hero?.unmeasurableTarget != nil else { return nil }
        return "no gps fix · timing it instead"
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
        return Text(WorkoutMetric.distance.displayText(target, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, paceReference: profile.paceReference))
            .foregroundStyle(Theme.textPrimary)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsClock {
                // The clock is the hero: a countdown to a duration target,
                // or elapsed counting up when nothing else can be watched.
                // Everything else tracked (a treadmill's incline, a spin
                // bike's resistance) rides the header scroll as cards.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        exerciseHeader
                            .padding(.horizontal, 16)
                        if !clockStageMetrics.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(clockStageMetrics) { metricCard($0) }
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
                                .padding(.horizontal, 16)
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
                paceReference: profile.paceReference,
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
                paceReference: profile.paceReference,
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
                    // The kicker keeps the count alone, in the sport's own
                    // noun — a rower does PIECES, a runner REPS, a lifter
                    // SETS. It is absent entirely on a single continuous
                    // effort, so a steady ride never claims a second one
                    // is coming.
                    let kicker = WorkUnit.kicker(log.workUnit, index: log.setNumber, total: setsTotal)
                    if let kicker {
                        Text(kicker)
                            .foregroundStyle(Theme.accent)
                            .font(.system(.footnote, design: .monospaced, weight: .semibold))
                            .kerning(0.7)
                            .padding(.top, 20)
                    }

                    Text(log.exerciseName)
                        .font(.system(.title, weight: .bold))
                        // The name carries the top margin itself when no
                        // kicker sits above it.
                        .padding(.top, kicker == nil ? 20 : 6)

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

                    // Weight/reps sets carry target + prev INSIDE the
                    // value cards now (mock 08); this line survives
                    // only for duration-driven sets, which have no cards.
                    if showsClock, targetDescription != nil || lastTime != nil {
                        HStack(spacing: 12) {
                            if let targetDescription { Text(targetDescription) }
                            if let lastTime {
                                (Text("prev: ").foregroundStyle(Theme.textSecondary)
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
    // wheel, the "prev:" reference, two full-width hold-to-repeat stepper keys, and
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

    /// "prev: 130" — the previous set's value, in the big card's corner.
    /// A reference point, not a scoreboard: no live delta and no colour
    /// change (Dave, 2026-07-28 — the "· +10" and its green went with
    /// the carry-forward note). Nil without a prior.
    private func previousAnnotation(_ metric: WorkoutMetric) -> String? {
        guard let last = lastTime?.actual(metric), last > 0 else { return nil }
        return "prev: \(metric.formatted(last))"
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
    /// the big value opening the wheel, the faint "prev:" reference, and two
    /// full-width hold-to-repeat stepper keys.
    private func metricCard(_ metric: WorkoutMetric) -> some View {
        let current = log.actual(metric) ?? log.target(metric)
        let unitText = metric.unit(for: current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, paceReference: profile.paceReference)
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
                if let annotation = previousAnnotation(metric) {
                    Text(annotation)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                        .animation(Theme.Anim.standard, value: annotation)
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
            ? metric.incremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: override, paceReference: profile.paceReference)
            : metric.decremented(current, weightUnit: weightUnit, distanceUnit: profile.distanceUnit, stepOverride: override, paceReference: profile.paceReference)
        log.setActual(metric, to: stepped)
    }

    /// What the commit key says.
    ///
    /// Normally the exercise's own noun — "Log set" in the rack, "Log piece"
    /// on an erg, plain "Log" for a walk, since walkers do not do eight of
    /// anything. On a session that is ONE continuous effort it names the
    /// ENDING instead: a run has nothing to count, so logging it and
    /// finishing are the same decision and one key should say so.
    ///
    /// "Finish workout" rather than a new phrase, because the exit dialog
    /// already uses those words for the same act, and two strings for one
    /// state is how "Log it" and "Log" ended up on the same screen.
    private var commitKeyLabel: String {
        if session.isSingleEffort { return "Finish workout" }
        return log.workUnit.map { "Log \($0.singular)" } ?? "Log"
    }

    // MARK: - Log dock
    // Log set stands alone: a full 28 pt of clear air above it, nothing
    // adjacent to mis-hit.

    private var logDock: some View {
        VStack(spacing: 0) {
            ZStack {
                Button(action: onComplete) {
                    // The commit key names what it commits, in the
                    // exercise's own noun: "Log set" in the rack, "Log
                    // piece" on an erg, plain "Log" for a walk. The
                    // identifier stays completeSetButton so the smoke
                    // suite keeps finding it.
                    //
                    // ⚠️ On a session that is ONE effort it names the
                    // ending instead. Logging it and finishing are the
                    // same decision there, so one key says so, in the
                    // exit dialog's own words.
                    Text(commitKeyLabel)
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
        ) ?? WorkUnit.inline(next.workUnit, index: next.setNumber, total: session.blockCount(of: next))
        let name = Text(next.exerciseName)
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
        // An open-ended effort states no prescription and counts nothing,
        // so there is no detail to separate — the name stands alone rather
        // than trailing a naked "·".
        guard let detail, !detail.isEmpty else { return name }
        return name
            + Text(" · ")
            .font(.system(.footnote))
            .foregroundStyle(Theme.textFaint)
            + Text(detail)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
    }

    private var durationDock: some View {
        VStack(spacing: 10) {
            DurationTimerCard(
                log: log,
                // nil counts UP. A countdown ends itself; an open-ended
                // effort ends when you say so.
                countdownSeconds: countdownSeconds,
                unit: setsTotal > 1 ? log.workUnit : nil,
                finishesWorkout: session.isSingleEffort,
                degradeLine: degradeLine,
                startedAt: effortStartedAt,
                banked: effortBanked
            ) {
                onComplete()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var targetDescription: String? {
        guard let line = MetricSummary.line(
            profile: profile,
            weightUnit: weightUnit,
            repsText: log.targetReps.lower != nil ? log.targetReps.display : nil,
            value: { log.target($0) }
        ) else {
            // Nothing prescribed. The position is worth stating; the
            // exercise name is not — it is four lines up in .title bold.
            return WorkUnit.inline(log.workUnit, index: log.setNumber, total: setsTotal)
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

    /// The number to show, live stream first (#418).
    ///
    /// ⚠️ The phone's own workout session, when one is running, is the
    /// better source and the whole reason it exists: the anchored query
    /// reads whatever Health has, and watch→phone delivery is batched, so
    /// the newest visible sample was routinely older than the 180 s gate
    /// and the capsule stayed blank for a whole workout. A live builder
    /// delivers what it collects, which is why its window is far shorter —
    /// a stream that has gone quiet for 30 s has genuinely stopped.
    /// Read from the singleton rather than threaded through three call
    /// sites: there is one recorder per process, as with
    /// `WorkoutActivityController.shared`, and observation tracks it here
    /// just the same.
    @MainActor
    private func reading(at date: Date) -> Int? {
        let live = LiveWorkoutController.shared
        if let bpm = live.latestBPM, let at = live.latestBPMAt,
           date.timeIntervalSince(at) < LiveWorkoutController.bpmFreshWindow {
            return bpm
        }
        if let bpm = monitor.latestBPM, let at = monitor.latestAt,
           date.timeIntervalSince(at) < HeartRateMonitor.freshWindow {
            return bpm
        }
        return nil
    }

    var body: some View {
        // Ticks to EXPIRE a reading, not to display one — updates
        // arrive through the monitor's observation.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let bpm = reading(at: context.date) {
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

/// The timer dock, in its two shapes.
///
/// **Counting down** (#66) is the original: it starts at the target,
/// pauses and resets, and logs the set by itself at zero. A screen that
/// completes on its own has no primary key, so its commit is a quiet
/// "log now" beside the explanation.
///
/// **Counting up** is what an open-ended effort gets, and it is the
/// reason this card was rebuilt. Before, an untargeted timed effort
/// counted down from a hard-coded thirty seconds and logged itself; an
/// untargeted DISTANCE effort — which is what quick start and a studio
/// ride produce — never reached this card at all and showed a metric row
/// reading "—" with nothing moving. A count-up effort ends when you say
/// so, so it earns the filled commit key, labelled in the sport's own
/// noun (#302's primitive: a start `Date`, never an end one).
private struct DurationTimerCard: View {
    @Bindable var log: SetLog
    /// The countdown target in seconds, or nil to count up.
    let countdownSeconds: Int?
    /// The sport's noun for the commit key. nil where a sport counts
    /// nothing (a walk is a walk), and the key says "Log it".
    let unit: WorkUnit?
    /// Whether this effort IS the workout, so the key ends it. Passed in
    /// rather than re-derived: the kicker, the block bar, the island and
    /// this key all answer one question, and deriving it four times is how
    /// they drift.
    let finishesWorkout: Bool
    /// Printed under the clock when a target exists that nothing here can
    /// watch.
    let degradeLine: String?
    /// ⚠️ The count-up anchor is passed IN, not seeded in `onAppear`.
    /// Pausing unmounts this card, and in count-up mode the displayed
    /// elapsed is the value that gets logged — a locally-seeded anchor
    /// silently discarded everything before the last resume. The session
    /// view owns these and banks them across a pause.
    let startedAt: Date
    let banked: TimeInterval
    let onComplete: () -> Void

    /// The COUNTDOWN's own state stays local: it is derived from the
    /// target rather than accumulated, so a remount rebuilds it exactly.
    /// Date-based like the rest timer — an interval, never a tick count,
    /// so backgrounding and a locked screen cannot drift it.
    @State private var endDate: Date?
    /// Remaining, banked while the countdown is paused.
    @State private var pausedRemaining: TimeInterval?

    private var countsUp: Bool { countdownSeconds == nil }
    /// The card's own pause key only ever pauses the COUNTDOWN. A
    /// count-up effort is paused by pausing the workout, which is the
    /// thing that actually stops the clock everywhere (the rest engine,
    /// GPS, the island) — two pause affordances meaning different things
    /// on one screen is how the banked-time bug got in.
    private var isPaused: Bool { pausedRemaining != nil }
    private var totalSeconds: Int { max(1, countdownSeconds ?? 1) }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let seconds = displaySeconds(at: context.date)
                    VStack(spacing: 2) {
                        Text(countsUp ? "ELAPSED" : "AUTO TIMER")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .kerning(0.8)
                        Text(clock(seconds))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .contentTransition(.numericText())
                        // Nothing to fill toward when the effort is
                        // open-ended, and an empty bar reads as a stalled
                        // one.
                        if !countsUp {
                            ProgressView(value: Double(totalSeconds - seconds), total: Double(totalSeconds))
                                .tint(Theme.accent)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.vertical, 11)
                    .onChange(of: seconds) { _, newValue in
                        if !countsUp && newValue <= 0 && endDate != nil {
                            expire()
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(countsUp ? "Elapsed" : "Time remaining")

                if !countsUp {
                Divider().overlay(Theme.border)

                HStack(spacing: 0) {
                    Button(action: togglePause) {
                        HStack(spacing: 6) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(.caption, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                            Text(isPaused ? "Resume" : "Pause")
                                .font(.system(.footnote, weight: .bold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .animation(Theme.Anim.standard, value: isPaused)
                    }
                    Divider().frame(height: 46).overlay(Theme.border)
                    Button(action: start) {
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
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))

            if let degradeLine {
                Text(degradeLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if countsUp {
                // ⚠️ The one filled key on this dock, and only in this
                // mode: a countdown finishes by itself, so a primaryFill
                // cap there would make ending it early read as the thing
                // to do (the rest-screen law, 2026-07-27). An open-ended
                // effort has no other ending.
                Button(action: logNow) {
                    // ⚠️ The same expression `logDock` uses, plain "Log"
                    // included: two strings for one state is how "Log it"
                    // and "Log" ended up on the same screen. And the noun
                    // is dropped at a block total of one by the caller —
                    // "Log rep" on a single continuous forty-minute run is
                    // the count-of-one lie `WorkUnit.kicker` already
                    // refuses to tell.
                    //
                    // ⚠️ When the effort IS the workout the key names the
                    // ending instead. This is the case the whole card
                    // exists for — you go for a run, then you stop — and
                    // "Log" followed by a separate Finish asks twice for
                    // one decision.
                    Text(finishesWorkout
                         ? "Finish workout"
                         : (unit.map { "Log \($0.singular)" } ?? "Log"))
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                // Return commits the effort for external-keyboard users
                // (WCAG 2.1.1), exactly as it does in `logDock`.
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("completeSetButton")
            } else {
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
        }
        .onAppear(perform: start)
        // A prescription can change under the card (the overview sheet
        // edits a live set), and a countdown that keeps running to the old
        // number is the same class of lie as the rest of this push.
        .onChange(of: countdownSeconds) { _, _ in start() }
    }

    /// Seconds to render: remaining on a countdown, elapsed counting up.
    private func displaySeconds(at date: Date) -> Int {
        if countsUp {
            return max(0, Int(banked + date.timeIntervalSince(startedAt)))
        }
        if let pausedRemaining {
            return max(0, Int(pausedRemaining.rounded(.up)))
        }
        guard let endDate else { return totalSeconds }
        return max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
    }

    /// h:mm:ss once an effort passes the hour — a ninety-minute hike read
    /// "90:00" before, which is a minutes value on a clock face.
    private func clock(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func start() {
        pausedRemaining = nil
        endDate = countsUp ? nil : Date().addingTimeInterval(TimeInterval(totalSeconds))
    }

    private func togglePause() {
        if let pausedRemaining {
            endDate = Date().addingTimeInterval(pausedRemaining)
            self.pausedRemaining = nil
        } else if let endDate {
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
        }
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
        let elapsed = countsUp
            ? displaySeconds(at: Date())
            : totalSeconds - displaySeconds(at: Date())
        endDate = nil
        pausedRemaining = nil
        log.actualDuration = max(1, elapsed)
        onComplete()
    }
}

// MARK: - Rest

/// Renders the countdown and ends itself (via `onEnd`) when the clock
/// runs out — the only ticking view on the rest screen. Quiet Arcade:
/// 52 pt mono countdown over 12 recharge blocks draining with the
/// clock (live progress, so accent green), then the controls, then UP
/// NEXT as a card with its target in plain ink.
///
/// The stack is STATE · CONTROL · WHAT YOU'RE WAITING FOR (Dave,
/// 2026-07-27): kicker, live vitals, countdown, recharge blocks, the
/// three keys, and the up-next card LAST. Two things fall out of that
/// order. The stepper sits directly under the bars it moves, so
/// `+15s` and the blocks growing read as one gesture; and the controls
/// come before the card, so they stay above the fold at large text
/// sizes instead of being pushed under it.
///
/// ⚠️ NOTHING here is filled except the stepper pair. Skip used to be
/// the screen's `primaryFill` key, which made ending recovery early
/// read as the thing to do on a screen whose whole job is to finish by
/// itself (Dave: "it feels like the thing to do, over just waiting").
/// A screen that completes on its own has no primary act, so the two
/// keys that ADJUST are the loud ones and Skip is a quiet key set
/// apart by an extra gap — present, one tap, clearly not the point.
/// That gap is load-bearing: `−15s` beside Skip means a fat thumb
/// stepping down twice would otherwise end the rest.
private struct RestView: View {
    let endDate: Date
    /// The rest length AS IT NOW STANDS — the recharge blocks'
    /// denominator. `adjustRest` moves it with the end date, so
    /// `remaining <= totalSeconds` holds and the bar grows and shrinks
    /// with the stepper sitting directly above it.
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
    /// Steps the countdown by ±`RestAdjustment.stepSeconds`.
    let onAdjust: (Int) -> Void
    let onEnd: () -> Void

    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))

            // Scrollable so the controls stay reachable at large
            // accessibility text sizes; minHeight keeps it centered when it
            // fits (a11y audit).
            GeometryReader { screen in
              ScrollView {
                VStack(spacing: 20) {
                Text(isTransition ? "SWITCH" : "REST")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .kerning(1)

                // Recovery at a glance, riding directly under the kicker
                // (Dave, 2026-07-27) — heart rate, plus pace when a walk
                // break keeps moving. No target judgment during rest (both
                // stay quiet ink); pace drops out when you're standing
                // still.
                //
                // ⚠️ Gated on this session having EVER had a reading (or
                // being outdoors), not on one being fresh, and the row
                // holds a minimum height once it's in. Two hazards, one
                // shape: a phone-only workout has no HR sensor at all
                // (#418), and an ungated empty `HStack` still consumes the
                // stack's 20 pt on both sides — a 40 pt hole above the
                // clock. But a gate on FRESHNESS would let the row come
                // and go every time a reading aged out, and since this
                // stack is vertically centred that would shift the
                // countdown AND the keys under a travelling thumb.
                // Appearing once, at the first sample, is the only
                // movement worth having.
                if heartRate.latestAt != nil || location != nil {
                    HStack(spacing: 14) {
                        LiveHeartRateLabel(monitor: heartRate, target: nil)
                        if let location {
                            LivePaceLabel(monitor: location, unit: runUnit, target: nil)
                        }
                    }
                    .frame(minHeight: 17)
                }

                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))

                rechargeBlocks(remaining: remaining)

                controls()

                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .kerning(0.8)
                    Text(upNext.caption)
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
                .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: screen.size.height)
                .onChange(of: remaining) { oldValue, newValue in
                    // Beep the last three seconds; guard on a decrement so a
                    // +15s extension (which raises `remaining`) never beeps,
                    // and the higher "go" tone fires as the countdown lands on
                    // zero and the next exercise/set begins (#420). A −15s
                    // can't land inside the window either: it clamps one
                    // full step above zero.
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

    /// Skip rest · −15s · +15s. The pair is filled and flexible; Skip is
    /// a quiet cap at its content width, carrying the extra gap.
    ///
    /// All three keys use the SAME 4 pt travel (`.raisedKey` /
    /// `.raisedPrimaryKey`) rather than the 3 pt `.quietKey`, so their
    /// caps sit on one baseline — the quiet reading comes from the cap's
    /// ink and type and the absence of a fill, not from a shorter key
    /// that would leave the row misaligned by a point.
    ///
    /// ⚠️ At accessibility sizes the row REFLOWS to the pair over Skip
    /// (#164's reflow-don't-cap, as `DiffLedger` does): three keys with
    /// a content-width label among them cannot hold one line at AX5, and
    /// the two-key row this replaced could — `Skip rest` alone wants
    /// more than the whole content width there. Stacking also states the
    /// separation more plainly than a 6 pt inset can at that scale.
    private func controls() -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    HStack(spacing: 10) { reduceKey; extendKey }
                    skipKey.frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 10) {
                    // The gap that separates the escape from the pair.
                    skipKey.padding(.trailing, 6)
                    reduceKey
                    extendKey
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var skipKey: some View {
        Button(action: onEnd) {
            Text(isTransition ? "Skip" : "Skip rest")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                // borderStrong is the raised-key stroke everywhere in the
                // app; `Theme.border` is QuietKey's, and on a background
                // cap over a background page it reads as barely there.
                // The quiet comes from having no fill beside two that do.
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityIdentifier("skipRestButton")
    }

    private var reduceKey: some View {
        // Live only while a full step would still be left after the tap.
        // Read from `endDate` and not the tick's `remaining`: a
        // `.periodic` TimelineView hands back the LAST SCHEDULED tick, so
        // a re-render driven by anything else (a heart-rate sample, the
        // other key) would judge this against a stale second and could
        // show a live key over a model that no longer moves — the
        // silent-dead-tap class (swift-reviewer).
        stepKey(label: "−\(RestAdjustment.stepSeconds)s",
                accessibility: "Subtract \(RestAdjustment.stepSeconds) seconds",
                identifier: "reduceRestButton",
                // Dim in place (never removed) so the row can't reflow
                // mid-rest. On a 15 s SWITCH it simply starts dim, which
                // is honest: there's nothing to take off.
                enabled: endDate.timeIntervalSinceNow > TimeInterval(RestAdjustment.stepSeconds)) {
            onAdjust(-RestAdjustment.stepSeconds)
        }
    }

    private var extendKey: some View {
        stepKey(label: "+\(RestAdjustment.stepSeconds)s",
                accessibility: "Add \(RestAdjustment.stepSeconds) seconds",
                identifier: "extendRestButton",
                enabled: true) {
            onAdjust(RestAdjustment.stepSeconds)
        }
    }

    /// One half of the stepper: a filled primary cap, mono numerals.
    private func stepKey(
        label: String,
        accessibility: String,
        identifier: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .opacity(enabled ? 1 : 0.35)
                .animation(Theme.Anim.standard, value: enabled)
        }
        .buttonStyle(.raisedPrimaryKey())
        .disabled(!enabled)
        .accessibilityLabel(accessibility)
        .accessibilityIdentifier(identifier)
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
