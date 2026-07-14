import Foundation
import SwiftData
import PlusPlusKit

@Model
final class Routine {
    var name: String
    /// Stable identity for presentation/navigation (#155 + the tray-flicker
    /// decoupling): `persistentModelID` re-keys at a fresh model's first
    /// save and flickers open sheets/pushes, so the UI keys on this instead
    /// (mirrors `EquipmentLibrary.uuid`). Device-local, NOT in the
    /// interchange. OPTIONAL so the additive migration is lightweight-safe
    /// (a non-optional UUID has no static default, so existing rows would
    /// fail validation) — a new instance mints one via the default, and rows
    /// migrated in from a pre-uuid store are backfilled at launch
    /// (`SeedData.backfillModelUUIDsIfNeeded`). Effectively always non-nil.
    var uuid: UUID? = UUID()
    var createdAt: Date
    var order: Int
    /// Rest between sets during execution, in seconds.
    var restSeconds: Int = 90
    /// Freeform intent for the whole routine ("keep it under an hour",
    /// "finisher optional") — shown at session start.
    var notes: String?
    /// Encoded RoutineSchedule (#83); nil means unscheduled. Stored as
    /// JSON Data (with a default) so the SwiftData migration is additive.
    var scheduleData: Data?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.routine)
    var groups: [ExerciseGroup] = []

    init(name: String, order: Int = 0, restSeconds: Int = 90, notes: String? = nil) {
        self.name = name
        self.createdAt = Date()
        self.order = order
        self.restSeconds = restSeconds
        self.notes = notes
    }

    /// #189's invariant applied at creation: routine names are unique
    /// case-insensitively (Siri entities, the broken-reference session
    /// fallback, and the settings rename guard all key on the name — a
    /// duplicate pair jams renaming for both). Collisions get a numeric
    /// suffix instead of a block: creation happens inside an alert,
    /// which has nowhere to surface validation.
    static func uniqueName(_ proposed: String, among existing: [Routine]) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        guard taken.contains(proposed.lowercased()) else { return proposed }
        var counter = 2
        while taken.contains("\(proposed) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(proposed) \(counter)"
    }

    /// Typed view over `scheduleData`. Unscheduled round-trips as nil so
    /// a routine that has never been scheduled stays byte-identical.
    var schedule: RoutineSchedule {
        get {
            guard let scheduleData,
                  let decoded = try? JSONDecoder().decode(RoutineSchedule.self, from: scheduleData)
            else { return .unscheduled }
            return decoded
        }
        set {
            let normalized = newValue.normalized
            scheduleData = normalized == .unscheduled ? nil : try? JSONEncoder().encode(normalized)
        }
    }

    var sortedGroups: [ExerciseGroup] {
        groups.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var equipmentNames: [String] {
        let names = sortedGroups
            .flatMap { $0.sortedExercises }
            .compactMap { $0.exercise }
            .flatMap { $0.equipment }
            .map { $0.name }
        return Array(Set(names)).sorted()
    }

    /// Rough all-in seconds for the detail meta line: ~45 s of work per
    /// weight set, the actual target for timed sets, plus rest between
    /// sets (matches the v2 prototype's estimate). Blocks with a rest
    /// override (interval blocks) count their own rest.
    var estimatedSeconds: Int {
        var work = 0
        var rest = 0
        var lastRest = restSeconds
        for group in sortedGroups {
            let groupRest = group.restSecondsOverride ?? restSeconds
            for entry in group.sortedExercises {
                let perSet = entry.exercise?.exerciseType == .duration
                    ? (entry.durationSeconds ?? 45)
                    : 45
                work += perSet * group.sets
                rest += groupRest * group.sets
            }
            if !group.sortedExercises.isEmpty {
                lastRest = groupRest
            }
        }
        // Rest follows every set except the very last — whose length is
        // the FINAL block's, not the routine default's.
        return work + max(0, rest - lastRest)
    }

    /// "~40 min" — the shared rendering of `estimatedSeconds` (Today
    /// cards, detail meta, the start tray), rounded to 5-minute steps
    /// so it never pretends to precision the estimate doesn't have.
    var estimateText: String {
        let minutes = max(5, Int((Double(estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    func reindexGroups() {
        for (index, group) in sortedGroups.filter({ !$0.isDeleted }).enumerated() {
            group.order = index
        }
    }

    // MARK: - Structure mutations
    // All group/exercise structure changes go through these so the order
    // invariants hold; views should not assemble groups by hand.

    /// Adds an exercise in its own new group at the end of the routine.
    @discardableResult
    func addExerciseInNewGroup(_ exercise: Exercise, context: ModelContext) -> ExerciseGroup {
        let group = ExerciseGroup(order: groups.count, sets: 3)
        group.routine = self
        context.insert(group)

        let routineExercise = RoutineExercise(exercise: exercise, order: 0)
        applyDefaultTargets(to: routineExercise, for: exercise)
        routineExercise.group = group
        context.insert(routineExercise)

        reindexGroups()
        return group
    }

    /// Fresh entries start from the exercise's own defaults (#187) and
    /// fall back to the design's global ones (10 reps / 45 s) instead of
    /// blank targets. Richer cardio profiles take defaults only — a
    /// fabricated duration target would hijack the set's driver (the
    /// appendExercise rule).
    private func applyDefaultTargets(to entry: RoutineExercise, for exercise: Exercise) {
        let profile = exercise.metricProfile
        if profile.contains(.weight) {
            entry.weight = exercise.defaultWeight
        }
        if profile.tracksReps {
            entry.reps = exercise.defaultReps ?? 10
            entry.repsUpper = exercise.defaultRepsUpper
        }
        if profile.contains(.duration) {
            entry.durationSeconds = exercise.defaultDurationSeconds
                ?? (profile.metrics == [.duration] ? 45 : nil)
        }
        // The heart-rate prescription prefills on cardio entries, same
        // as the other defaults (#187).
        if profile.legacyType == .duration {
            entry.heartRateTargetData = exercise.defaultHeartRateTargetData
        }
        entry.extraTargets = exercise.extraDefaults.filter { profile.contains($0.key) }
    }

    /// Adds an exercise to an existing group, making (or extending) a
    /// superset. Returns the new entry so callers can apply their own
    /// targets without a fragile sortedExercises readback.
    @discardableResult
    func addExercise(_ exercise: Exercise, to group: ExerciseGroup, context: ModelContext) -> RoutineExercise {
        let routineExercise = RoutineExercise(exercise: exercise, order: group.exercises.count)
        applyDefaultTargets(to: routineExercise, for: exercise)
        routineExercise.group = group
        context.insert(routineExercise)
        group.reindexExercises()
        return routineExercise
    }

    /// Merges a solo group's exercise into the adjacent group (direction
    /// -1 = above, +1 = below), forming or extending a superset there.
    /// No-op when the group isn't solo or there is no neighbor (the v2
    /// design only offers the action for solo rows).
    func mergeSoloGroup(_ group: ExerciseGroup, direction: Int, context: ModelContext) {
        let sorted = sortedGroups
        guard group.sortedExercises.count == 1,
              let index = sorted.firstIndex(where: { $0 === group }),
              sorted.indices.contains(index + direction),
              let moving = group.sortedExercises.first
        else { return }

        let target = sorted[index + direction]
        if direction < 0 {
            moving.order = target.exercises.count
            moving.group = target
        } else {
            for member in target.sortedExercises {
                member.order += 1
            }
            moving.order = 0
            moving.group = target
        }
        target.reindexExercises()
        context.delete(group)
        reindexGroups()
    }

    /// Moves a superset member out into its own group, placed immediately
    /// after (or, with `placeAbove`, immediately before) the group it
    /// came from. No-op for a solo exercise. `placeAbove` is the ring
    /// gesture's top-edge contraction (#78): the ejected member lands
    /// just outside the edge it crossed.
    func splitExercise(_ routineExercise: RoutineExercise, placeAbove: Bool = false, context: ModelContext) {
        guard let sourceGroup = routineExercise.group, sourceGroup.isSuperset else { return }

        let insertionOrder = placeAbove ? sourceGroup.order : sourceGroup.order + 1
        for group in sortedGroups where group.order >= insertionOrder {
            group.order += 1
        }

        let newGroup = ExerciseGroup(order: insertionOrder, sets: sourceGroup.sets)
        newGroup.routine = self
        context.insert(newGroup)

        routineExercise.group = newGroup
        routineExercise.order = 0

        sourceGroup.reindexExercises()
        reindexGroups()
    }

    /// Drops an exercise into the gap between groups (#78 drag-drop):
    /// `gap` is 0...sortedGroups.count in pre-move indices. A solo
    /// exercise moves its whole group; a superset member leaves its group
    /// and lands solo, keeping the source group's set count. Membership
    /// never grows this way — joining a superset is the ring gesture.
    func placeSolo(_ routineExercise: RoutineExercise, atGap gap: Int, context: ModelContext) {
        guard let source = routineExercise.group else { return }
        var arranged = sortedGroups
        guard let sourceIndex = arranged.firstIndex(where: { $0 === source }) else { return }
        let gap = max(0, min(gap, arranged.count))

        if source.isSuperset {
            let newGroup = ExerciseGroup(order: 0, sets: source.sets)
            newGroup.routine = self
            context.insert(newGroup)
            routineExercise.group = newGroup
            routineExercise.order = 0
            source.reindexExercises()
            arranged.insert(newGroup, at: gap)
        } else {
            arranged.remove(at: sourceIndex)
            let insertion = gap > sourceIndex ? gap - 1 : gap
            arranged.insert(source, at: min(insertion, arranged.count))
        }
        for (index, group) in arranged.enumerated() {
            group.order = index
        }
    }

    /// Reorders a member within its own group (#78 in-ring drag).
    func reorderExercise(_ routineExercise: RoutineExercise, toIndex target: Int) {
        guard let group = routineExercise.group else { return }
        var members = group.sortedExercises
        guard let from = members.firstIndex(where: { $0 === routineExercise }) else { return }
        let to = max(0, min(target, members.count - 1))
        guard from != to else { return }
        members.remove(at: from)
        members.insert(routineExercise, at: to)
        for (index, member) in members.enumerated() {
            member.order = index
        }
    }
}
