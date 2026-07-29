import Foundation
import PlusPlusKit

/// One exercise's prescription beside what it actually did last time.
///
/// `moved` is the ledger's own question — did anything about this block
/// change since the last run — and it is what lets Today print MOVERS ONLY
/// while routine detail prints every row. Same producer, two readings.
struct RoutineLedgerRow: Identifiable {
    let id: String
    let name: String
    /// What is being asked for, formatted per the profile's metrics.
    let target: [PrescriptionRun]
    /// What happened last time. Empty when this exercise has never run.
    let prev: [PrescriptionRun]
    /// The fields that differ, for the target column's lit/dim treatment.
    let changed: Set<RoutineDiff.Field>
    /// Added since the last run, so there is nothing to compare against.
    /// Distinct from an empty `prev` for any other reason.
    let isNew: Bool

    var moved: Bool { !changed.isEmpty }
}

/// The target-vs-prev producer, shared by Today's pending card and routine
/// detail's rail (2026-07-29).
///
/// ⚠️ It lives here rather than in `TodayView` because TWO surfaces read it
/// now, and a second copy of this logic is the failure mode worth avoiding:
/// the rules below (planned rounds, not finished ones; same-routine set
/// counts; the top set by weight) are each load-bearing and each learned from
/// a bug. One of them drifting between two producers would show up as the two
/// screens disagreeing about the same exercise.
enum RoutineLedger {

    /// Every exercise in the routine, in rail order.
    ///
    /// `sessions` must be newest-first — the first session containing an
    /// exercise wins, which is how "last time" is resolved.
    static func rows(
        for routine: Routine,
        sessions: [WorkoutSession],
        weightUnit: WeightUnit
    ) -> [RoutineLedgerRow] {
        var out: [RoutineLedgerRow] = []
        var index = 0
        for group in routine.sortedGroups {
            for entry in group.sortedExercises {
                guard let exercise = entry.exercise else { continue }
                let profile = exercise.metricProfile
                let target = RoutineDiff.Target(
                    name: exercise.name,
                    isDuration: profile.legacyType == .duration,
                    // The block's rounds. Superset members each run once per
                    // round, so every entry in the group carries the group's
                    // count — which is what `prior` counts back.
                    sets: group.sets,
                    weight: entry.weight,
                    reps: entry.reps,
                    repsUpper: entry.repsUpper,
                    durationSeconds: entry.durationSeconds,
                    extras: entry.extraTargets.filter { profile.contains($0.key) },
                    distanceUnit: profile.distanceUnit
                )
                // The uuid is effectively always present, but a store migrated
                // before the backfill runs can hold nil — and two blocks of the
                // same exercise is an anticipated shape, so the fallback carries
                // the position to keep ForEach identity unique.
                let id = entry.uuid?.uuidString ?? "\(index)·\(exercise.name)"
                index += 1

                guard let prior = prior(for: entry, in: sessions) else {
                    out.append(RoutineLedgerRow(
                        id: id,
                        name: exercise.name,
                        target: Prescription.blockRuns(target: target, profile: profile, weightUnit: weightUnit),
                        prev: [],
                        changed: [],
                        isNew: true
                    ))
                    continue
                }
                out.append(RoutineLedgerRow(
                    id: id,
                    name: exercise.name,
                    target: Prescription.blockRuns(target: target, profile: profile, weightUnit: weightUnit),
                    prev: Prescription.blockRuns(prior: prior, profile: profile, weightUnit: weightUnit),
                    changed: RoutineDiff.movedFields(target: target, prior: prior, profile: profile),
                    isNew: false
                ))
            }
        }
        return out
    }

    /// How this exercise last actually went, from the newest session that
    /// contains it.
    ///
    /// Every rule here is load-bearing; see the inline notes before changing
    /// any of them.
    static func prior(for routineExercise: RoutineExercise, in sessions: [WorkoutSession]) -> RoutineDiff.Prior? {
        let exercise = routineExercise.exercise
        let name = exercise?.name ?? ""
        let routine = routineExercise.group?.routine
        func isThisExercise(_ log: SetLog) -> Bool {
            if let a = log.exercise, let b = exercise { return a === b }
            return log.exerciseName == name
        }
        for session in sessions {
            let matches = session.completedSetLogs.filter(isThisExercise)
            guard let last = matches.last else { continue }
            let top = matches.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) } ?? last
            let isSameRoutine = routine.map { session.routine === $0 || session.routineName == $0.name } ?? false
            // The rounds the block was PLANNED for, not the rounds finished.
            // The two sides of a set comparison have to be the same kind of
            // number: today's is a prescription, so last time's must be too.
            // Comparing a plan against a shortfall manufactures a change out
            // of an unfinished session, and on a ledger — which draws a row
            // for any field that moved — one short week would repaint every
            // exercise on the next card as a mover.
            //
            // The HIGHEST set number reached, not the count of logs: the
            // filter spans the whole session, and an exercise may appear in
            // more than one block (a 2-set warm-up plus a 4-set working
            // block). Counting logs would compare one block's target against
            // every block's total; `setNumber` is 1-based within its group,
            // so its maximum is the deepest single block.
            //
            // And only against the SAME routine: a set count belongs to a
            // prescription, so an A/B split running bench for 4 rounds one
            // day and 2 the next must not read as movement. Weight converges
            // across routines; structure does not.
            let plannedSets = session.sortedSetLogs.filter(isThisExercise).map(\.setNumber).max()
            return RoutineDiff.Prior(
                sets: isSameRoutine ? plannedSets : nil,
                weight: top.actualWeight,
                reps: top.actualReps ?? last.actualReps,
                durationSeconds: last.actualDuration,
                extras: last.extraActuals
            )
        }
        return nil
    }
}
