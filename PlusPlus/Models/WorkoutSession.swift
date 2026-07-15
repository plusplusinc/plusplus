import Foundation
import Observation
import SwiftData
import PlusPlusKit

/// A performed (or in-progress) run of a routine. Snapshots what it needs
/// from the template at start time — later edits or deletion of the source
/// routine must never corrupt logged history.
@Model
final class WorkoutSession {
    var routine: Routine?
    var routineName: String
    var startedAt: Date
    var endedAt: Date?
    /// Stable cross-device identity for live mirror (#322): the shared key
    /// both the phone and the watch tag their ops with, so a session
    /// STARTED on either device is the same session everywhere. Minted per
    /// instance; a routine/scratch start gets a fresh one, a watch-born
    /// session adopts the id its `.started` op carried. Old rows migrate
    /// to a default (inert — finished history never mirrors).
    var sessionId: UUID = UUID()
    /// Snapshot of the routine's rest setting at start time.
    var restSeconds: Int = 90
    /// Snapshot of the routine's transition setting at start time (#369):
    /// the pause when the session moves to a different exercise or block,
    /// where rest covers a new round of the same block. Constant default
    /// stamps old rows 15 — inert on finished history, and NOT in the
    /// interchange (see the census: a finished record's real gaps live in
    /// `completedAt`).
    var transitionSeconds: Int = 15
    /// When the workout TIMER first engaged — the first exercise being
    /// started. nil while an ad-hoc session is still being assembled: no
    /// clock runs during setup (Dave, 2026-07-11). Routine sessions
    /// engage it at start; ad-hoc sessions engage it when the first
    /// exercise's set screen appears. Also anchors the Health workout
    /// window and the heart-rate summary.
    var runStartedAt: Date?
    /// Start of the current RUNNING segment; nil while paused, finished,
    /// or not yet started. Elapsed running time is `accumulatedSeconds`
    /// plus this segment's live length.
    var segmentStartedAt: Date?
    /// Running seconds banked from segments that have already ended —
    /// every pause and the finish bank the live segment here, so the
    /// clock counts active time only, never staging or paused stretches.
    var accumulatedSeconds: Double = 0
    /// Where the session is pointed (v2 jump/redo, #66): the order of the
    /// log the user is doing now. `currentLog` falls back to the first
    /// pending log when the cursor's log is already done.
    var cursorOrder: Int = 0
    /// Session heart-rate summary in bpm. Watch-run sessions carry it in
    /// the result payload (the wrist's live builder); phone-run sessions
    /// read it from Health at the finish, and the record backfills later
    /// if the watch's samples hadn't synced yet. nil = no data (no
    /// sensor, no Health access) — never zero.
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var setLogs: [SetLog] = []

    init(routine: Routine? = nil, routineName: String, startedAt: Date = Date(), restSeconds: Int = 45, transitionSeconds: Int = 15) {
        self.routine = routine
        self.routineName = routineName
        self.startedAt = startedAt
        self.restSeconds = restSeconds
        self.transitionSeconds = transitionSeconds
    }

    var sortedSetLogs: [SetLog] {
        setLogs.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var completedSetLogs: [SetLog] {
        sortedSetLogs.filter(\.isCompleted)
    }

    /// The set the user should do next; nil when everything is logged.
    var nextPendingLog: SetLog? {
        sortedSetLogs.first { !$0.isCompleted }
    }

    /// The cursor's log when it's still pending, else the first pending
    /// log (v2 jump/redo can move the cursor anywhere).
    var currentLog: SetLog? {
        sortedSetLogs.first { $0.order == cursorOrder && !$0.isCompleted } ?? nextPendingLog
    }

    /// Jump the session to a specific log ("Do now" / "Skip to"). With
    /// `redo`, a completed log is reopened first — its previous actuals
    /// stay as the prefill.
    func jump(to log: SetLog, redo: Bool = false) {
        if redo, log.isCompleted {
            log.completedAt = nil
        }
        guard !log.isCompleted else { return }
        cursorOrder = log.order
    }

    /// Load and machine-setting metrics whose mid-session edits carry to
    /// the remaining pending sets of the same exercise: you re-racked the
    /// bar or re-dialed the machine — round N+1 starts where you left it.
    /// Work metrics (reps, distance, duration…) never carry: an extra rep
    /// on set 2 is not a new prescription for set 3.
    private static let carryForwardMetrics: [WorkoutMetric] = [
        .weight, .assistance, .resistance, .incline, .speed, .height,
    ]

    /// Marks the current log complete, prefilling every tracked metric's
    /// actual from its target, and carries changed load/setting values
    /// forward to the remaining pending sets of the same exercise (v2,
    /// #65). Advances the cursor to the next pending log after this one
    /// (wrapping to the first pending).
    func complete(_ log: SetLog, at date: Date = Date()) {
        let profile = log.metricProfile
        for metric in profile.metrics where log.actual(metric) == nil {
            log.setActual(metric, to: log.target(metric))
        }
        for metric in Self.carryForwardMetrics where profile.contains(metric) {
            guard let newValue = log.actual(metric), newValue != log.target(metric) else { continue }
            for other in sortedSetLogs
            where !other.isCompleted && other !== log && other.exerciseName == log.exerciseName {
                other.setTarget(metric, to: newValue)
            }
        }
        log.completedAt = date
        let pending = sortedSetLogs.filter { !$0.isCompleted }
        cursorOrder = (pending.first { $0.order > log.order } ?? pending.first)?.order ?? cursorOrder
    }

    /// True when a different pending set of the same exercise will pick up
    /// this log's edited load on completion — drives the carry-forward
    /// hint line (loads only; machine settings carry silently).
    func weightCarriesForward(from log: SetLog) -> Bool {
        let profile = log.metricProfile
        let loadChanged = [WorkoutMetric.weight, .assistance].contains { metric in
            profile.contains(metric)
                && log.actual(metric) != nil
                && log.actual(metric) != log.target(metric)
        }
        guard loadChanged else { return false }
        return sortedSetLogs.contains { !$0.isCompleted && $0 !== log && $0.exerciseName == log.exerciseName }
    }

    /// The pause that follows a just-completed set (#369): a NEW ROUND of
    /// the same block earns the block's rest (override when one exists —
    /// interval blocks — else the session default); anything else — the
    /// superset partner within a round, or the first set of another block
    /// — is a transition, just enough to switch stations. Classified
    /// against wherever the cursor points next, so jump/redo reclassifies
    /// naturally. A 0-second transition means no countdown at all.
    func pause(after log: SetLog) -> (seconds: Int, isTransition: Bool) {
        let rest = (seconds: log.restSecondsOverride ?? restSeconds, isTransition: false)
        guard let next = currentLog else { return rest }
        let newRoundOfSameBlock = next.groupIndex == log.groupIndex && next.setNumber != log.setNumber
        return newRoundOfSameBlock ? rest : (seconds: transitionSeconds, isTransition: true)
    }

    var isFinished: Bool { endedAt != nil }

    // MARK: - Workout clock (pause + staged start)

    /// True once the timer has engaged (the first exercise was started).
    /// An ad-hoc session reads false while it's being assembled.
    var isWorkoutStarted: Bool { runStartedAt != nil }

    /// True while the timer is actively counting.
    var isRunning: Bool { segmentStartedAt != nil }

    /// True while the workout is paused mid-run (started, held, not yet
    /// finished) — the state the Paused screen renders.
    var isPaused: Bool { isWorkoutStarted && segmentStartedAt == nil && !isFinished }

    /// The wall-clock anchor for the Health window and the heart-rate
    /// summary: the timer's start, or the session's creation for a
    /// legacy record that predates the clock.
    var effectiveStart: Date { runStartedAt ?? startedAt }

    /// Elapsed RUNNING time at `now` — banked segments plus the live
    /// one, excluding staging and paused stretches. A legacy record
    /// (finished before the clock existed) falls back to its span.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        if let segmentStartedAt {
            return accumulatedSeconds + max(0, now.timeIntervalSince(segmentStartedAt))
        }
        // Started then paused/finished: the live segment is already banked.
        if isWorkoutStarted || accumulatedSeconds > 0 {
            return accumulatedSeconds
        }
        // Clock never engaged: a legacy finished record rides its span;
        // a fresh ad-hoc still being assembled reads zero.
        if let endedAt { return max(0, endedAt.timeIntervalSince(startedAt)) }
        return 0
    }

    /// Engages the timer, or resumes it after a pause. Idempotent while
    /// running; a no-op once finished.
    func startClock(at date: Date = Date()) {
        guard !isFinished else { return }
        if runStartedAt == nil { runStartedAt = date }
        if segmentStartedAt == nil { segmentStartedAt = date }
    }

    /// Banks the running segment and holds the timer. A no-op when it
    /// isn't running (never started, or already paused).
    func pauseClock(at date: Date = Date()) {
        guard let segmentStartedAt else { return }
        accumulatedSeconds += max(0, date.timeIntervalSince(segmentStartedAt))
        self.segmentStartedAt = nil
    }

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return elapsed(at: endedAt)
    }

    func finish(at date: Date = Date()) {
        // Bank the final running segment so duration counts active time.
        pauseClock(at: date)
        endedAt = date
    }

    /// The most recent completed log for the same exercise as `log` from an
    /// earlier finished session — what "last time" looked like. Prefers the
    /// same set number within the newest session that included the exercise;
    /// falls back to that session's last set of the exercise. Matches by
    /// exercise identity when both references survive, else by name snapshot.
    static func lastPerformance(matching log: SetLog, in sessions: [WorkoutSession]) -> SetLog? {
        let priorSessions = sessions
            .filter { $0 !== log.session && $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        for session in priorSessions {
            let matches = session.completedSetLogs.filter { candidate in
                if let a = candidate.exercise, let b = log.exercise {
                    return a === b
                }
                return candidate.exerciseName == log.exerciseName
            }
            guard !matches.isEmpty else { continue }
            return matches.first { $0.setNumber == log.setNumber } ?? matches.last
        }
        return nil
    }

    /// Builds a session from a routine template with one SetLog per
    /// exercise per set, in execution order. Supersets rotate: a group with
    /// exercises [A, B] and 3 sets produces A1 B1 A2 B2 A3 B3.
    static func start(from routine: Routine, context: ModelContext, at date: Date = Date()) -> WorkoutSession {
        let session = WorkoutSession(
            routine: routine,
            routineName: routine.name,
            startedAt: date,
            restSeconds: routine.restSeconds,
            transitionSeconds: routine.transitionSeconds
        )
        context.insert(session)
        // A routine session is started the moment it's presented — the
        // user tapped Start — so its clock engages now. (Ad-hoc sessions
        // stay unstarted until the first exercise begins.)
        session.startClock(at: date)

        var order = 0
        for (groupIndex, group) in routine.sortedGroups.enumerated() {
            for setNumber in 1...max(group.sets, 1) {
                for routineExercise in group.sortedExercises {
                    guard let exercise = routineExercise.exercise else { continue }
                    let profile = exercise.metricProfile
                    let log = SetLog(
                        order: order,
                        groupIndex: groupIndex,
                        setNumber: setNumber,
                        exercise: exercise,
                        exerciseName: exercise.name,
                        exerciseType: exercise.exerciseType,
                        targetWeight: routineExercise.weight,
                        targetRepsLower: routineExercise.reps,
                        targetRepsUpper: routineExercise.repsUpper,
                        targetDuration: routineExercise.durationSeconds,
                        targetHeartRateData: routineExercise.heartRateTargetData
                    )
                    // Snapshots like name and type: the profile the set
                    // runs under must survive later library edits.
                    log.metricProfile = profile
                    log.extraTargets = routineExercise.extraTargets.filter { profile.contains($0.key) }
                    log.restSecondsOverride = group.restSecondsOverride
                    log.session = session
                    context.insert(log)
                    order += 1
                }
            }
        }
        // Save NOW, not on the next autosave: the session is presented
        // via fullScreenCover(item:), which keys on persistentModelID —
        // the temporary→permanent ID swap at first save reads as a new
        // item and briefly dismisses/re-presents a live routine (Dave,
        // build 12).
        try? context.save()
        return session
    }
}

// MARK: - Ad-hoc sessions (#239)

extension WorkoutSession {
    /// The snapshot name for sessions started without a routine — the
    /// scratch buffer of workouts. Renamed if the user saves the session
    /// as a routine at the finish.
    static let scratchName = "Scratch workout"

    /// An empty session with no routine: built on the gym floor one
    /// exercise at a time via `appendExercise`. Ordinary in every other
    /// way — history, diffs, and salvage all key on snapshots, and a
    /// nil routine satisfies no schedule.
    static func startEmpty(context: ModelContext, at date: Date = Date()) -> WorkoutSession {
        let session = WorkoutSession(routineName: scratchName, startedAt: date)
        context.insert(session)
        // Same identity rule as start(from:): fullScreenCover(item:)
        // keys on persistentModelID, which changes at first save.
        try? context.save()
        return session
    }

    /// Appends `sets` pending logs of `exercise` as a new solo block at
    /// the end of the session, targets prefilled from the exercise's own
    /// defaults (#187). The convenience overload; the configured path
    /// (a set count and targets chosen in the add sheet) is
    /// `appendExercise(config:context:)`.
    @discardableResult
    func appendExercise(_ exercise: Exercise, sets: Int = 3, context: ModelContext) -> [SetLog] {
        appendExercise(config: SessionExerciseConfig(exercise: exercise, sets: sets), context: context)
    }

    /// Appends a configured block: `config.sets` pending logs of
    /// `config.exercise`, each carrying the targets the user set in the
    /// add sheet ("configure before you do it", Dave 2026-07-11). Logged
    /// sets are never touched — mid-session additions only ever add
    /// pending work.
    @discardableResult
    func appendExercise(config: SessionExerciseConfig, context: ModelContext) -> [SetLog] {
        // A finished session is a record, not a plan. The duration
        // auto-timer can finish the session while the picker is still
        // presented over the overview sheet — a pick landing here after
        // that must not plant invisible pending sets in history
        // (swift-reviewer catch).
        guard !isFinished else { return [] }
        let exercise = config.exercise
        let profile = config.profile
        let existing = sortedSetLogs
        let groupIndex = (existing.map(\.groupIndex).max() ?? -1) + 1
        var order = (existing.map(\.order).max() ?? -1) + 1
        var appended: [SetLog] = []
        for setNumber in 1...max(config.sets, 1) {
            let log = SetLog(
                order: order,
                groupIndex: groupIndex,
                setNumber: setNumber,
                exerciseName: exercise.name,
                exerciseType: exercise.exerciseType,
                targetWeight: profile.contains(.weight) ? config.weight : nil,
                targetRepsLower: profile.tracksReps ? config.reps : nil,
                targetRepsUpper: profile.tracksReps ? config.repsUpper : nil,
                targetDuration: profile.contains(.duration) ? config.durationSeconds : nil,
                targetHeartRateData: profile.legacyType == .duration ? config.heartRateTargetData : nil
            )
            log.metricProfile = profile
            log.extraTargets = config.extraTargets.filter { profile.contains($0.key) }
            // Insert first, relationships after (the seeder's hard-won
            // rule) — start(from:) predates it and is #195's audit.
            context.insert(log)
            log.session = self
            log.exercise = exercise
            appended.append(log)
            order += 1
        }
        return appended
    }

    /// Resizes a still-pending block to `count` sets — appends prefilled
    /// pending sets (copied from the block's template) or trims pending
    /// ones. Completed sets and the LIVE set are never removed (the live
    /// set may be any pending set once the cursor has been jumped, not
    /// just the first): the floor is the number already done plus the
    /// live set when the block is current, never below one. Ends by
    /// reindexing — block `setNumber`s densified 1..n and session `order`
    /// re-densified with the cursor re-pinned by reference — so the
    /// reindex-after-every-mutation law holds and no gaps survive a trim.
    /// Drives the in-session exercise sheet's Sets stepper.
    @discardableResult
    func resizePendingBlock(groupIndex: Int, exerciseName: String, to count: Int, context: ModelContext) -> [SetLog] {
        guard !isFinished else { return [] }
        let blockLogs = sortedSetLogs.filter { $0.groupIndex == groupIndex && $0.exerciseName == exerciseName }
        guard let template = blockLogs.first else { return [] }
        let completed = blockLogs.count { $0.isCompleted }
        let liveOrder = currentLog?.order
        let blockIsLive = liveOrder.map { order in blockLogs.contains { $0.order == order } } ?? false
        let floor = max(1, completed + (blockIsLive ? 1 : 0))
        let target = max(count, floor)
        let current = blockLogs.count
        guard target != current else { return blockLogs }
        // Re-pinned by reference after the reindex — the integer
        // cursorOrder would otherwise go stale.
        let cursor = currentLog

        if target < current {
            // Trim the highest-order pending sets, but never the LIVE one
            // (a jumped cursor can make the live set a high-order pending
            // set — trimming the tail would delete it and silently move
            // the cursor).
            let removable = blockLogs
                .filter { !$0.isCompleted && $0.order != liveOrder }
                .suffix(current - target)
            for log in removable { context.delete(log) }
        } else {
            // Append after the block's last set, shifting later blocks
            // down so the new sets sort into place; the reindex below
            // then densifies the whole session's order.
            let insertionOrder = blockLogs.map(\.order).max() ?? -1
            let shift = target - current
            for log in sortedSetLogs where log.order > insertionOrder {
                log.order += shift
            }
            var order = insertionOrder + 1
            for _ in (current + 1)...target {
                let log = SetLog(
                    order: order,
                    groupIndex: groupIndex,
                    setNumber: 0,   // reindexed below
                    exerciseName: template.exerciseName,
                    exerciseType: template.exerciseType,
                    targetWeight: template.targetWeight,
                    targetRepsLower: template.targetRepsLower,
                    targetRepsUpper: template.targetRepsUpper,
                    targetDuration: template.targetDuration,
                    targetHeartRateData: template.targetHeartRateData
                )
                log.metricProfile = template.metricProfile
                log.extraTargets = template.extraTargets
                log.restSecondsOverride = template.restSecondsOverride
                context.insert(log)
                log.session = self
                log.exercise = template.exercise
                order += 1
            }
        }

        // Reindex-after-every-mutation: the block's surviving sets renumber
        // 1..n by order (closing any gap a trim left), the session's order
        // re-densifies, and the cursor re-pins to the same log object.
        let survivors = sortedSetLogs.filter { $0.groupIndex == groupIndex && $0.exerciseName == exerciseName }
        for (index, log) in survivors.enumerated() { log.setNumber = index + 1 }
        for (index, log) in sortedSetLogs.enumerated() { log.order = index }
        if let cursor, !cursor.isDeleted { cursorOrder = cursor.order }
        return sortedSetLogs.filter { $0.groupIndex == groupIndex && $0.exerciseName == exerciseName }
    }

    /// Materializes a routine from what was actually performed: blocks
    /// in session order, set counts as done, targets from each block's
    /// last completed log (weight carry-forward makes that the latest
    /// prescription). Referenced exercises join the library; the session
    /// relinks and renames so this run becomes the routine's first
    /// performance for future diffs. Returns nil when nothing completed
    /// survives (no completed sets, or their exercises were deleted).
    @discardableResult
    func saveAsRoutine(named proposed: String, among existing: [Routine], context: ModelContext) -> Routine? {
        var blockOrder: [String] = []
        var blocks: [String: [SetLog]] = [:]
        for log in completedSetLogs {
            let key = "\(log.groupIndex)|\(log.exerciseName)"
            if blocks[key] == nil { blockOrder.append(key) }
            blocks[key, default: []].append(log)
        }
        guard !blockOrder.isEmpty else { return nil }

        let trimmed = proposed.trimmingCharacters(in: .whitespaces)
        let name = Routine.uniqueName(trimmed.isEmpty ? Self.scratchName : trimmed, among: existing)
        let routine = Routine(name: name, order: 0, restSeconds: restSeconds)
        context.insert(routine)

        for key in blockOrder {
            // A deleted exercise can't join a template; its logged sets
            // stay in this session's history either way.
            guard let logs = blocks[key], let exercise = logs.first?.exercise else { continue }
            exercise.inLibrary = true
            let group = routine.addExerciseInNewGroup(exercise, context: context)
            group.sets = logs.count
            guard let last = logs.last, let entry = group.sortedExercises.first else { continue }
            group.restSecondsOverride = last.restSecondsOverride
            var extras: [WorkoutMetric: Double] = [:]
            for metric in last.metricProfile.metrics {
                switch metric {
                case .weight:
                    entry.weight = last.actualWeight ?? last.targetWeight
                case .reps:
                    // A performed rep count is a scalar; the target range
                    // survives only when no actual was recorded.
                    entry.reps = last.actualReps ?? last.targetRepsLower
                    entry.repsUpper = last.actualReps == nil ? last.targetRepsUpper : nil
                case .duration:
                    entry.durationSeconds = last.actualDuration ?? last.targetDuration
                    // The heart-rate band the block ran under carries
                    // into the template with its duration.
                    entry.heartRateTargetData = last.targetHeartRateData
                default:
                    extras[metric] = last.actual(metric) ?? last.target(metric)
                }
            }
            entry.extraTargets = extras
        }
        guard !routine.sortedGroups.isEmpty else {
            context.delete(routine)
            return nil
        }

        // The new routine deliberately lands at the top; siblings shift
        // down like every other creation path — duplicate orders would
        // make the watch's plan push (no tiebreak) nondeterministic.
        for other in existing {
            other.order += 1
        }

        self.routine = routine
        self.routineName = routine.name
        return routine
    }
}

// MARK: - Configuring an exercise before adding it

/// Editable configuration for one exercise being added to a live
/// session — a set count plus per-metric targets, prefilled from the
/// exercise's own defaults (#187). SwiftUI-free so it stays unit
/// testable, the same pattern as `ExerciseDraft` / `ExerciseFilterState`.
/// "Configure before you do it" (Dave, 2026-07-11): the add sheet binds
/// to this, then `appendExercise(config:context:)` builds the block. The
/// target API mirrors `RoutineExercise` so both editing surfaces speak
/// the same grammar.
@Observable
final class SessionExerciseConfig: Identifiable {
    let exercise: Exercise
    let profile: MetricProfile
    var sets: Int
    var weight: Double?
    var reps: Int?
    var repsUpper: Int?
    var durationSeconds: Int?
    var heartRateTargetData: Data?
    var extraTargets: [WorkoutMetric: Double]

    init(exercise: Exercise, sets: Int = 3) {
        self.exercise = exercise
        let profile = exercise.metricProfile
        self.profile = profile
        self.sets = sets
        // The same prefill the old appendExercise and
        // Routine.applyDefaultTargets use: the classic profiles keep
        // their floor prescriptions (a 10-rep / 45 s block is startable
        // as-is); richer cardio profiles take the exercise's own
        // defaults only — a fabricated 45 s target on a 2000 m rower
        // would hijack the driver into a timer.
        self.weight = profile.contains(.weight) ? exercise.defaultWeight : nil
        self.reps = profile.tracksReps ? (exercise.defaultReps ?? 10) : nil
        self.repsUpper = profile.tracksReps ? exercise.defaultRepsUpper : nil
        self.durationSeconds = profile.contains(.duration)
            ? (exercise.defaultDurationSeconds ?? (profile.metrics == [.duration] ? 45 : nil))
            : nil
        self.heartRateTargetData = profile.legacyType == .duration ? exercise.defaultHeartRateTargetData : nil
        self.extraTargets = exercise.extraDefaults.filter { profile.contains($0.key) }
    }

    /// Typed view over `heartRateTargetData`.
    var heartRateTarget: HeartRateTarget? {
        get { heartRateTargetData.flatMap { try? JSONDecoder().decode(HeartRateTarget.self, from: $0) } }
        set { heartRateTargetData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// One lookup/store for any metric's target, columns and bag alike
    /// (mirrors `RoutineExercise.target`/`setTarget`).
    func target(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: weight
        case .reps: reps.map(Double.init)
        case .duration: durationSeconds.map(Double.init)
        case .assistance: extraTargets[.assistance] ?? weight
        default: extraTargets[metric]
        }
    }

    func setTarget(_ metric: WorkoutMetric, to value: Double?) {
        switch metric {
        case .weight: weight = value
        case .reps: reps = value.map { Int($0.rounded()) }
        case .duration: durationSeconds = value.map { Int($0.rounded()) }
        default:
            var extras = extraTargets
            extras[metric] = value
            extraTargets = extras
        }
    }
}

/// One planned/performed set of one exercise within a session. Targets are
/// copied from the plan; actuals are what happened. Exercise name and type
/// are snapshotted so history survives library edits.
@Model
final class SetLog {
    var session: WorkoutSession?
    var order: Int
    var groupIndex: Int
    /// 1-based set number within the group.
    var setNumber: Int
    var exercise: Exercise?
    var exerciseName: String
    var exerciseType: ExerciseType
    /// Tracked-metric profile snapshot (flexible metrics), Kit-encoded —
    /// history must survive library edits, so the profile the set was
    /// performed under travels with it. nil (pre-profile rows) derives
    /// from the snapshotted exerciseType.
    var metricsData: Data?
    /// The block's rest override at start time; nil rides the session's
    /// restSeconds.
    var restSecondsOverride: Int?

    var targetWeight: Double?
    var targetRepsLower: Int?
    var targetRepsUpper: Int?
    var targetDuration: Int?
    /// Snapshot of the plan entry's HeartRateTarget (encoded JSON) —
    /// guidance shown during execution, never an actual. Snapshotted
    /// like every other target so history survives template edits.
    var targetHeartRateData: Data?
    /// Targets/actuals beyond the columns — Kit-encoded [metric: value]
    /// bags (see MetricValues).
    var extraTargetsData: Data?

    var actualWeight: Double?
    var actualReps: Int?
    var actualDuration: Int?
    var extraActualsData: Data?
    var completedAt: Date?

    init(
        order: Int,
        groupIndex: Int,
        setNumber: Int,
        exercise: Exercise? = nil,
        exerciseName: String,
        exerciseType: ExerciseType = .weightReps,
        targetWeight: Double? = nil,
        targetRepsLower: Int? = nil,
        targetRepsUpper: Int? = nil,
        targetDuration: Int? = nil,
        targetHeartRateData: Data? = nil
    ) {
        self.order = order
        self.groupIndex = groupIndex
        self.setNumber = setNumber
        self.exercise = exercise
        self.exerciseName = exerciseName
        self.exerciseType = exerciseType
        self.targetWeight = targetWeight
        self.targetRepsLower = targetRepsLower
        self.targetRepsUpper = targetRepsUpper
        self.targetDuration = targetDuration
        self.targetHeartRateData = targetHeartRateData
    }

    var isCompleted: Bool { completedAt != nil }

    /// Typed view over `targetHeartRateData`.
    var targetHeartRate: HeartRateTarget? {
        targetHeartRateData.flatMap { try? JSONDecoder().decode(HeartRateTarget.self, from: $0) }
    }

    var targetReps: RepTarget {
        RepTarget(lower: targetRepsLower, upper: targetRepsUpper)
    }

    /// The profile this set was performed under.
    var metricProfile: MetricProfile {
        get { MetricProfile.decode(from: metricsData) ?? .derived(from: exerciseType) }
        set {
            metricsData = newValue.encoded()
            exerciseType = newValue.legacyType
        }
    }

    var extraTargets: [WorkoutMetric: Double] {
        get { MetricValues.decode(extraTargetsData) }
        set { extraTargetsData = MetricValues.encode(newValue) }
    }

    var extraActuals: [WorkoutMetric: Double] {
        get { MetricValues.decode(extraActualsData) }
        set { extraActualsData = MetricValues.encode(newValue) }
    }

    /// The metric driving this set's execution — decides the set-screen
    /// mode (reps → log flow, duration → auto-timer, distance/calories →
    /// target card + manual log).
    var driver: WorkoutMetric {
        metricProfile.driver { target($0) }
    }

    /// One lookup for any metric's target/actual, columns and bags alike.
    func target(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: targetWeight
        case .reps: targetRepsLower.map(Double.init)
        case .duration: targetDuration.map(Double.init)
        // Same bridge as actual(_:): pre-profile assisted prescriptions
        // lived in the weight column — a stranded 60 lb stack must stay
        // visible and steppable, not reset to the unit default.
        case .assistance: extraTargets[.assistance] ?? targetWeight
        default: extraTargets[metric]
        }
    }

    func actual(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: actualWeight
        case .reps: actualReps.map(Double.init)
        case .duration: actualDuration.map(Double.init)
        // Assistance predates its own metric on assisted machines —
        // pre-profile logs stored the stack value in the weight column,
        // so "last time" still resolves there.
        case .assistance: extraActuals[.assistance] ?? actualWeight
        default: extraActuals[metric]
        }
    }

    func setActual(_ metric: WorkoutMetric, to value: Double?) {
        switch metric {
        case .weight: actualWeight = value
        case .reps: actualReps = value.map { Int($0.rounded()) }
        case .duration: actualDuration = value.map { Int($0.rounded()) }
        default:
            var extras = extraActuals
            extras[metric] = value
            extraActuals = extras
        }
    }

    func setTarget(_ metric: WorkoutMetric, to value: Double?) {
        switch metric {
        case .weight: targetWeight = value
        case .reps: targetRepsLower = value.map { Int($0.rounded()) }
        case .duration: targetDuration = value.map { Int($0.rounded()) }
        default:
            var extras = extraTargets
            extras[metric] = value
            extraTargets = extras
        }
    }

    /// "10 reps @ 135 lb", "45 sec", "25:00", "2000 m · 7:52 · lvl 5",
    /// or "—" — how this set went. Weight numbers are unit-agnostic; the
    /// caller supplies the current unit setting (issue #33).
    func resultSummary(weightUnit: WeightUnit) -> String {
        MetricSummary.line(
            profile: metricProfile,
            weightUnit: weightUnit,
            value: { actual($0) }
        ) ?? "—"
    }
}
