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
    /// interchange. OPTIONAL and set in `init` (NOT a property-level
    /// `= UUID()` default): SwiftData's lightweight migration applies a
    /// property default as a SINGLE CONSTANT to every existing row, so a
    /// `= UUID()` default made all migrated routines share ONE uuid and
    /// nav resolved every routine to the same one. Without the default,
    /// migrated rows get `nil` and `SeedData.backfillModelUUIDsIfNeeded`
    /// assigns each a UNIQUE value at launch (it also de-dupes any store
    /// already stamped with the shared default). New instances mint one in
    /// `init`. Effectively always non-nil and unique once populated.
    var uuid: UUID?
    var createdAt: Date
    var order: Int
    /// Rest between sets during execution, in seconds. New routines
    /// default to 45 (#369): with transitions carved out, rest no longer
    /// has to cover station switches.
    var restSeconds: Int = 45
    /// Pause when the session moves to a DIFFERENT exercise or block —
    /// just enough to switch stations (#369); rest covers a new round of
    /// the same block. 0 means no countdown at all. Constant property
    /// default on purpose: lightweight migration stamps every existing
    /// routine 15 s, which IS the feature — station switches (and
    /// superset partners) shorten from a full rest to a transition.
    var transitionSeconds: Int = 15
    /// Freeform intent for the whole routine ("keep it under an hour",
    /// "finisher optional") — shown at session start.
    var notes: String?
    /// A one-line description (the routine's voice), seeded from a catalog
    /// template's summary on add and editable after. Optional additive
    /// column: existing rows migrate in as nil (no description), blank and
    /// custom routines start nil until the user writes one.
    var summary: String?
    /// Encoded RoutineSchedule (#83); nil means unscheduled. Stored as
    /// JSON Data (with a default) so the SwiftData migration is additive.
    var scheduleData: Data?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseGroup.routine)
    var groups: [ExerciseGroup] = []

    init(name: String, order: Int = 0, restSeconds: Int = 45, transitionSeconds: Int = 15, notes: String? = nil, summary: String? = nil) {
        self.uuid = UUID()
        self.name = name
        self.createdAt = Date()
        self.order = order
        self.restSeconds = restSeconds
        self.transitionSeconds = transitionSeconds
        self.notes = notes
        self.summary = summary
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
    /// weight set, the actual target for timed sets, plus the pause after
    /// every set but the last (#369) — rest before a new round of the same
    /// block (interval blocks count their override), transition when the
    /// session moves to a superset partner or another block.
    var estimatedSeconds: Int {
        var work = 0
        var pauses = 0
        let populated = sortedGroups.filter { !$0.sortedExercises.isEmpty }
        for group in populated {
            let rounds = max(group.sets, 1)
            let groupRest = group.restSecondsOverride ?? restSeconds
            for entry in group.sortedExercises {
                let perSet = entry.exercise?.exerciseType == .duration
                    ? (entry.durationSeconds ?? 45)
                    : 45
                work += perSet * rounds
            }
            // Superset partners hand off within the round; each new round
            // of the block is the rest.
            pauses += (group.sortedExercises.count - 1) * transitionSeconds * rounds
            pauses += (rounds - 1) * groupRest
        }
        // Every block boundary is a station switch.
        pauses += max(0, populated.count - 1) * transitionSeconds
        return work + pauses
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
    /// The set count is the exercise's own default (config audit: a
    /// stretch lands as one hold, a steady erg piece as one round, a
    /// press as the classic 3).
    @discardableResult
    func addExerciseInNewGroup(_ exercise: Exercise, context: ModelContext) -> ExerciseGroup {
        let group = ExerciseGroup(order: groups.count, sets: exercise.defaultSetCount)
        group.routine = self
        context.insert(group)

        let routineExercise = RoutineExercise(exercise: exercise, order: 0)
        applyDefaultTargets(to: routineExercise, for: exercise)
        routineExercise.group = group
        context.insert(routineExercise)

        reindexGroups()
        return group
    }

    /// Fresh entries start from `Exercise.addTimeTargets` — the ONE
    /// resolution (own bumped default #187 → catalog assignment → global
    /// floor) shared with the session add sheet, so the two paths can
    /// never prefill differently.
    private func applyDefaultTargets(to entry: RoutineExercise, for exercise: Exercise) {
        let targets = exercise.addTimeTargets
        entry.weight = targets.weight
        entry.reps = targets.reps
        entry.repsUpper = targets.repsUpper
        entry.durationSeconds = targets.durationSeconds
        entry.heartRateTargetData = targets.heartRateTargetData
        entry.extraTargets = targets.extraTargets
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
