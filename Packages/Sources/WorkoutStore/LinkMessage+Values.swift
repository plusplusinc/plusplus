import Foundation

// The link's own Codable shapes for the domain's values, mapped both ways, so the stored types
// stay free of a wire format and the wire can change apart from them.

/// A workout's plan as the Watch needs it: each row's exercise by what it counts (name, per
/// side, load), not by the phone's list, so a created or customized exercise reads the same;
/// rests in seconds, as the phone works them out now.
public struct WirePlan: Codable, Equatable, Sendable {
    public struct Row: Codable, Equatable, Sendable {
        var id: UUID
        var exerciseID: String
        var name: String
        var isPerSide: Bool
        var load: String?
        var sets: Int
        var target: WireTarget
        var weight: WireWeight?
        var rest: Int
        var supersetID: UUID?
        var roundRest: Int?
    }

    var id: UUID
    var name: String
    var rows: [Row]

    init(_ workout: Workout) {
        id = workout.id
        name = workout.name
        rows = workout.exercises.map { row in
            Row(
                id: row.id,
                exerciseID: row.exercise.id,
                name: row.exercise.name,
                isPerSide: row.exercise.isPerSide,
                load: row.exercise.load.map { "\($0)" },
                sets: row.plan.sets,
                target: WireTarget(row.plan.target),
                weight: row.plan.weight.map(WireWeight.init),
                rest: row.rest,
                supersetID: row.supersetID,
                roundRest: workout.restAfterRound(of: row.id),
            )
        }
    }

    /// The workout, its rests set by hand to the seconds they came as.
    public var workout: Workout {
        Workout(id: id, name: name, exercises: rows.map { row in
            WorkoutExercise(
                id: row.id,
                exercise: Exercise(
                    id: row.exerciseID,
                    name: row.name,
                    muscleGroups: [],
                    plan: ExercisePlan(sets: row.sets, target: row.target.target),
                    load: row.load.flatMap(Load.init(wire:)),
                    perSide: row.isPerSide,
                    tags: .groupOnly,
                ),
                plan: ExercisePlan(
                    sets: row.sets,
                    target: row.target.target,
                    weight: row.weight?.weight,
                    rest: .byHand(row.rest),
                ),
                supersetID: row.supersetID,
                roundRest: row.roundRest.map(Rest.byHand) ?? .neverSet,
            )
        })
    }
}

extension Load {
    init?(wire: String) {
        switch wire {
        case "single": self = .single
        case "pair": self = .pair
        case "bar": self = .bar
        default: return nil
        }
    }
}

public struct WireTarget: Codable, Equatable, Sendable {
    var reps: Int?
    var seconds: Int?

    init(_ target: SetTarget) {
        switch target {
        case let .reps(reps): self.reps = reps
        case let .time(seconds): self.seconds = seconds
        }
    }

    var target: SetTarget {
        seconds.map { .time(seconds: $0) } ?? .reps(reps ?? 0)
    }
}

public struct WireWeight: Codable, Equatable, Sendable {
    var amount: Double
    var unit: String

    init(_ weight: Weight) {
        amount = weight.amount
        unit = weight.unit.rawValue
    }

    var weight: Weight {
        Weight(amount, WeightUnit(rawValue: unit) ?? .pounds)
    }
}

public struct WireSet: Codable, Equatable, Sendable {
    var row: UUID
    var round: Int
    var side: String?

    init(_ set: PlannedSet) {
        row = set.row
        round = set.round
        side = set.side?.rawValue
    }

    var planned: PlannedSet {
        PlannedSet(row: row, round: round, side: side.flatMap(Side.init(rawValue:)))
    }
}

public struct WireCount: Codable, Equatable, Sendable {
    var set: WireSet
    var startClock: Double
    var added: Int

    init(_ count: SetCount) {
        set = WireSet(count.set)
        startClock = count.startClock
        added = count.added
    }

    var count: SetCount {
        SetCount(set: set.planned, startClock: startClock, added: added)
    }
}

/// A logged set, every field but none the Watch has no use for.
public struct WireLogged: Codable, Equatable, Sendable {
    var id: UUID
    var set: WireSet
    var exerciseID: String
    var exerciseName: String?
    var target: WireTarget
    var weight: WireWeight?
    var plannedTarget: WireTarget
    var plannedWeight: WireWeight?
    var loggedAt: Date
    var clockWhenLogged: Double?
    var restAdjustment: Int
    var restSkippedAt: Double?
    var timeAdded: Int

    init(_ logged: LoggedSet) {
        id = logged.id
        set = WireSet(logged.planned)
        exerciseID = logged.exerciseID
        exerciseName = logged.exerciseName
        target = WireTarget(logged.target)
        weight = logged.weight.map(WireWeight.init)
        plannedTarget = WireTarget(logged.plannedTarget)
        plannedWeight = logged.plannedWeight.map(WireWeight.init)
        loggedAt = logged.loggedAt
        clockWhenLogged = logged.clockWhenLogged
        restAdjustment = logged.restAdjustment
        restSkippedAt = logged.restSkippedAt
        timeAdded = logged.timeAdded
    }

    var logged: LoggedSet {
        let planned = set.planned
        var logged = LoggedSet(
            id: id,
            row: planned.row,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            round: planned.round,
            side: planned.side,
            target: target.target,
            weight: weight?.weight,
            plannedTarget: plannedTarget.target,
            plannedWeight: plannedWeight?.weight,
            loggedAt: loggedAt,
        )
        logged.clockWhenLogged = clockWhenLogged
        logged.restAdjustment = restAdjustment
        logged.restSkippedAt = restSkippedAt
        logged.timeAdded = timeAdded
        return logged
    }
}

/// A workout session, every field but its Apple Health ones, which stay on the phone.
public struct WireSession: Codable, Equatable, Sendable {
    var id: UUID
    var workoutID: UUID
    var workoutName: String
    var startedAt: Date
    var pausedAt: Date?
    var pausedSeconds: Double
    var pauses: [DateInterval]
    var endedAt: Date?
    var sets: [WireLogged]
    var count: WireCount?

    init(_ session: WorkoutSession) {
        id = session.id
        workoutID = session.workoutID
        workoutName = session.workoutName
        startedAt = session.startedAt
        pausedAt = session.pausedAt
        pausedSeconds = session.pausedSeconds
        pauses = session.pauses
        endedAt = session.endedAt
        sets = session.sets.map(WireLogged.init)
        count = session.count.map(WireCount.init)
    }

    public var session: WorkoutSession {
        WorkoutSession(
            id: id,
            workoutID: workoutID,
            workoutName: workoutName,
            startedAt: startedAt,
            pausedAt: pausedAt,
            pausedSeconds: pausedSeconds,
            pauses: pauses,
            endedAt: endedAt,
            sets: sets.map(\.logged),
            count: count?.count,
        )
    }
}

/// A `WorkoutAction` on the wire.
public struct WireAction: Codable, Equatable, Sendable {
    var kind: String
    var set: WireSet?
    var seconds: Int?
    var count: WireCount?

    init(_ action: WorkoutAction) {
        switch action {
        case let .log(set): kind = "log"
            self.set = WireSet(set)
        case .skipRest: kind = "skipRest"
        case let .extendRest(seconds): kind = "extendRest"
            self.seconds = seconds
        case let .extendCount(seconds): kind = "extendCount"
            self.seconds = seconds
        case let .beginCount(count): kind = "beginCount"
            self.count = WireCount(count)
        case .pause: kind = "pause"
        case .resume: kind = "resume"
        case .finish: kind = "finish"
        case .discard: kind = "discard"
        }
    }

    /// The action, or nil for a kind this build does not know.
    public var action: WorkoutAction? {
        switch kind {
        case "log": set.map { .log($0.planned) }
        case "skipRest": .skipRest
        case "extendRest": seconds.map { .extendRest(by: $0) }
        case "extendCount": seconds.map { .extendCount(by: $0) }
        case "beginCount": count.map { .beginCount($0.count) }
        case "pause": .pause
        case "resume": .resume
        case "finish": .finish
        case "discard": .discard
        default: nil
        }
    }
}
