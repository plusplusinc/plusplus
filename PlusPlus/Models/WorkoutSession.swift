import Foundation
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
    /// Snapshot of the routine's rest setting at start time.
    var restSeconds: Int = 90
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

    init(routine: Routine? = nil, routineName: String, startedAt: Date = Date(), restSeconds: Int = 90) {
        self.routine = routine
        self.routineName = routineName
        self.startedAt = startedAt
        self.restSeconds = restSeconds
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

    /// The rest that follows a just-completed set: its block's override
    /// when one exists (interval blocks), else the session default.
    func restSeconds(after log: SetLog) -> Int {
        log.restSecondsOverride ?? restSeconds
    }

    var isFinished: Bool { endedAt != nil }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    func finish(at date: Date = Date()) {
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
            restSeconds: routine.restSeconds
        )
        context.insert(session)

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
    /// defaults (#187). Logged sets are never touched — mid-session
    /// additions only ever add pending work.
    @discardableResult
    func appendExercise(_ exercise: Exercise, sets: Int = 3, context: ModelContext) -> [SetLog] {
        // A finished session is a record, not a plan. The duration
        // auto-timer can finish the session while the picker is still
        // presented over the overview sheet — a pick landing here after
        // that must not plant invisible pending sets in history
        // (swift-reviewer catch).
        guard !isFinished else { return [] }
        let existing = sortedSetLogs
        let groupIndex = (existing.map(\.groupIndex).max() ?? -1) + 1
        var order = (existing.map(\.order).max() ?? -1) + 1
        let profile = exercise.metricProfile
        var appended: [SetLog] = []
        for setNumber in 1...max(sets, 1) {
            let log = SetLog(
                order: order,
                groupIndex: groupIndex,
                setNumber: setNumber,
                exerciseName: exercise.name,
                exerciseType: exercise.exerciseType,
                targetWeight: profile.contains(.weight) ? exercise.defaultWeight : nil,
                // The classic profiles keep their floor prescriptions (a
                // 10-rep / 45 s block is startable as-is); richer cardio
                // profiles start from the exercise's own defaults only —
                // a fabricated 45 s target on a 2000 m rower would
                // hijack the driver into a timer.
                targetRepsLower: profile.tracksReps ? (exercise.defaultReps ?? 10) : nil,
                targetRepsUpper: profile.tracksReps ? exercise.defaultRepsUpper : nil,
                targetDuration: profile.contains(.duration)
                    ? (exercise.defaultDurationSeconds ?? (profile.metrics == [.duration] ? 45 : nil))
                    : nil,
                targetHeartRateData: profile.legacyType == .duration ? exercise.defaultHeartRateTargetData : nil
            )
            log.metricProfile = profile
            log.extraTargets = exercise.extraDefaults.filter { profile.contains($0.key) }
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
