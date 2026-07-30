import Foundation
import SwiftData
import PlusPlusKit

/// The browsable routine catalog (#223): static template definitions,
/// NOT seeded `Routine` rows — seeding would pollute the user's routine
/// list and schedule queries. "Add" instantiates a real `Routine`
/// through the existing structure mutations and pulls its exercises
/// into the library (the "anything you use joins your library" rule).
/// Only three attributes are authored (focus/effort/style); time,
/// equipment, and muscle coverage derive from the exercise content —
/// an authored "30 min" lies the moment the user edits the copy.
/// `RoutineCatalogTests` validates every exercise reference against
/// the built-in catalog so content can't drift from SeedData.
struct RoutineTemplate: Identifiable, Hashable {
    /// The universal split vocabulary — the routine's identity and the
    /// highest-signal filter facet.
    enum Focus: String, CaseIterable, Hashable {
        case fullBody = "Full body"
        case upper = "Upper"
        case lower = "Lower"
        case push = "Push"
        case pull = "Pull"
        case core = "Core"
        case conditioning = "Conditioning"

        /// A best-effort focus for a routine that carries no authored one (a
        /// custom or heavily edited routine). Push/pull can't be told from
        /// muscles alone, so this only reaches Upper/Lower/Core/Conditioning/
        /// Full body — the coarse read is fine, since a routine added from a
        /// template shows the template's AUTHORED focus instead.
        static func derived(fromMuscles muscles: [MuscleGroup], isCardio: Bool) -> Focus {
            if isCardio { return .conditioning }
            let present = Set(muscles)
            guard !present.isEmpty else { return .fullBody }
            let upper: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps]
            let lower: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]
            let hasUpper = !present.isDisjoint(with: upper)
            let hasLower = !present.isDisjoint(with: lower)
            if present == [.core] { return .core }
            if hasUpper && hasLower { return .fullBody }
            if hasLower { return .lower }
            if hasUpper { return .upper }
            return .fullBody
        }
    }

    /// Names the SESSION, never the user — "Beginner" labels a person
    /// and violates the same anti-shame rule that killed "due".
    enum Effort: String, CaseIterable, Hashable {
        case light = "Light"
        case moderate = "Moderate"
        case intense = "Intense"
    }

    /// What one session is (not what a person wants — goals are
    /// program-level). Recovery gives the PT scenario a home.
    enum Style: String, CaseIterable, Hashable {
        case strength = "Strength"
        case build = "Build"
        case conditioning = "Conditioning"
        case recovery = "Recovery"
    }

    struct Entry: Hashable {
        let exercise: String
        var reps: Int?
        var repsUpper: Int?
        var durationSeconds: Int?
        /// Targets beyond the three columns — distance and pace, so a
        /// template can say "500 m at a 2:00 split" rather than only how
        /// long it lasts. Empty on every strength entry, which is why the
        /// catalog above reads exactly as it did.
        var extraTargets: [WorkoutMetric: Double] = [:]

        /// Seconds of WORK one round takes. The authored duration is the
        /// honest answer; failing that, a distance and a pace multiply
        /// out. nil when the entry states neither, and the caller charges
        /// the flat per-set estimate.
        ///
        /// ⚠️ Goes through the same `CardioTargets` rule as
        /// `Routine.workSeconds(for:)` — the template's number must not
        /// change the moment it becomes a routine.
        var workSeconds: Int? {
            guard let profile = SeedData.builtInProfile(named: exercise) else {
                return durationSeconds
            }
            return CardioTargets.estimatedSeconds(profile: profile) { metric in
                metric == .duration ? durationSeconds.map(Double.init) : extraTargets[metric]
            }
        }
    }

    /// One rail block; >1 entry = superset (strict rotation, as ever).
    struct Block: Hashable {
        let sets: Int
        let entries: [Entry]
        /// This block's own rest, when it differs from the routine's.
        /// Intervals are the reason it exists: three minutes between
        /// quarter-mile repeats, inside a session that otherwise turns
        /// around in one. The `= nil` is explicit so the memberwise init
        /// keeps its default and `b(_:_:)` stays a two-argument call.
        var restSeconds: Int? = nil
    }

    let name: String
    let summary: String
    let focus: Focus
    let effort: Effort
    let style: Style
    let restSeconds: Int
    let blocks: [Block]

    var id: String { name }

    // MARK: - Derived

    /// Mirrors `Routine.estimatedSeconds` (~45 s of work per weight
    /// set, actual target for timed sets, rest before each new round,
    /// the default transition at exercise/block boundaries #369) — the
    /// card's number must not change the moment a template becomes a
    /// routine, and created routines ride the default transition.
    var estimatedSeconds: Int {
        let transition = Int(WorkoutMetric.transition.defaultValue)
        var work = 0
        var pauses = 0
        let populated = blocks.filter { !$0.entries.isEmpty }
        for block in populated {
            let rounds = max(block.sets, 1)
            for entry in block.entries {
                // Shares Routine's per-set charge so a template's number
                // cannot drift from the routine it becomes.
                work += (entry.workSeconds ?? Routine.assumedSetSeconds) * rounds
            }
            pauses += (block.entries.count - 1) * transition * rounds
            pauses += (rounds - 1) * (block.restSeconds ?? restSeconds)
        }
        pauses += max(0, populated.count - 1) * transition
        return work + pauses
    }

    var totalSets: Int {
        blocks.reduce(0) { $0 + $1.sets * $1.entries.count }
    }

    /// Same 5-minute bucketing as RoutineCard, so the number doesn't
    /// visibly change the moment a template becomes a routine.
    var estimatedMinutesText: String {
        let minutes = max(5, Int((Double(estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    var exerciseCount: Int {
        blocks.reduce(0) { $0 + $1.entries.count }
    }

    /// Union of the exercises' gear, via the canonical definitions.
    var equipmentNames: [String] {
        var names: Set<String> = []
        for block in blocks {
            for entry in block.entries {
                names.formUnion(SeedData.builtInDefinition(named: entry.exercise)?.equipmentNames ?? [])
            }
        }
        return names.sorted()
    }

    /// What the template trains, for its detail line. PRIMARY groups only,
    /// for the same reason `Routine.focusLabel` uses them: a list that
    /// folds in every secondary names most of the body and distinguishes
    /// nothing.
    var muscleGroups: [MuscleGroup] {
        let present = Set(blocks.flatMap(\.entries).compactMap {
            SeedData.builtInDefinition(named: $0.exercise)?.muscleGroup
        })
        return MuscleGroup.allCases.filter { present.contains($0) }
    }

    // MARK: - Instantiation

    /// Builds a real Routine from the template: unique name (#189's
    /// invariant at creation), template targets over exercise
    /// defaults, and every referenced built-in joins the library. The
    /// new routine lands at order 0 like every create path. Exercises
    /// missing from the store are skipped defensively — the top-up
    /// seeder (#95) makes that unreachable in practice, and the unit
    /// test makes it unreachable in content.
    @discardableResult
    func instantiate(in context: ModelContext, among existingRoutines: [Routine]) -> Routine {
        let routine = Routine(
            name: Routine.uniqueName(name, among: existingRoutines),
            order: 0,
            restSeconds: restSeconds
        )
        context.insert(routine)
        // Carry the curated one-liner onto the routine so its description
        // survives into the library (the catalog voice, editable after).
        routine.summary = summary
        for other in existingRoutines {
            other.order += 1
        }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byName = Dictionary(
            allExercises.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        for block in blocks {
            var group: ExerciseGroup?
            for entry in block.entries {
                guard let exercise = byName[entry.exercise.lowercased()] else { continue }
                // No library to join (2026-07-17, whole catalog): the
                // exercise is already browsable; using it in a routine
                // doesn't favorite it.
                let routineExercise: RoutineExercise?
                if let existing = group {
                    routineExercise = routine.addExercise(exercise, to: existing, context: context)
                } else {
                    let newGroup = routine.addExerciseInNewGroup(exercise, context: context)
                    group = newGroup
                    routineExercise = newGroup.sortedExercises.first
                }
                if let routineExercise {
                    // ⚠️ An authored cardio target REPLACES the prefill,
                    // so the whole triad clears first. The add path seeds
                    // from the exercise's bumped defaults (#187), so a
                    // "500 m at 2:00" template landing on an erg you last
                    // rowed for twenty minutes would otherwise arrive
                    // carrying that duration as a THIRD value, and the
                    // two-of-three law would have a contradiction to
                    // resolve on the user's behalf.
                    if !entry.extraTargets.isEmpty {
                        for metric in CardioTargets.triad {
                            routineExercise.setTarget(metric, to: nil)
                        }
                        for (metric, value) in entry.extraTargets {
                            routineExercise.setTarget(metric, to: value)
                        }
                    }
                    if let seconds = entry.durationSeconds {
                        routineExercise.durationSeconds = seconds
                    }
                    if let reps = entry.reps {
                        routineExercise.reps = reps
                        routineExercise.repsUpper = entry.repsUpper
                    }
                }
            }
            group?.sets = block.sets
            // Same rule the planning sheet enforces: an override exists
            // only while it DIFFERS from the workout default, so a later
            // routine-level rest edit isn't silently ignored by a block
            // that never meant to diverge.
            if let blockRest = block.restSeconds, blockRest != restSeconds {
                group?.restSecondsOverride = blockRest
            }
        }
        routine.reindexGroups()
        return routine
    }
}

/// The authored catalog. Featured order is the curated order below,
/// grouped by rough intent: strength foundations → splits → home/gear-
/// light → machines → conditioning → core → recovery.
enum RoutineCatalog {
    private static func r(_ exercise: String, _ reps: Int, _ upper: Int? = nil) -> RoutineTemplate.Entry {
        .init(exercise: exercise, reps: reps, repsUpper: upper, durationSeconds: nil)
    }

    private static func d(_ exercise: String, _ seconds: Int) -> RoutineTemplate.Entry {
        .init(exercise: exercise, reps: nil, repsUpper: nil, durationSeconds: seconds)
    }

    private static func b(_ sets: Int, _ entries: RoutineTemplate.Entry...) -> RoutineTemplate.Block {
        .init(sets: sets, entries: entries)
    }

    /// A cardio effort: any TWO of distance, duration and pace, and the
    /// third falls out (`CardioTargets`). `distance` is in the exercise's
    /// own unit — miles on the road, meters on an erg — and `pace` is
    /// seconds over that unit's reference split.
    private static func c(
        _ exercise: String,
        distance: Double? = nil,
        seconds: Int? = nil,
        pace: Int? = nil
    ) -> RoutineTemplate.Entry {
        var extras: [WorkoutMetric: Double] = [:]
        if let distance { extras[.distance] = distance }
        if let pace { extras[.pace] = Double(pace) }
        return .init(
            exercise: exercise,
            reps: nil,
            repsUpper: nil,
            durationSeconds: seconds,
            extraTargets: extras
        )
    }

    /// A block that sets its own rest — the interval shape, where the
    /// turnaround between rounds is the prescription and the rest of the
    /// session wants nothing like it.
    private static func bi(_ sets: Int, rest: Int, _ entries: RoutineTemplate.Entry...) -> RoutineTemplate.Block {
        .init(sets: sets, entries: entries, restSeconds: rest)
    }

    static let all: [RoutineTemplate] = [
        // MARK: Strength foundations
        .init(
            name: "Full Body Strength A",
            summary: "The classic squat-bench-row session. Half of a simple alternating pair.",
            focus: .fullBody, effort: .moderate, style: .strength, restSeconds: 150,
            blocks: [
                b(3, r("Squat", 5)),
                b(3, r("Bench Press", 5)),
                b(3, r("Barbell Row", 8)),
                b(3, d("Plank", 45)),
            ]
        ),
        .init(
            name: "Full Body Strength B",
            summary: "Deadlift, press, and pull-ups. The other half of the pair.",
            focus: .fullBody, effort: .moderate, style: .strength, restSeconds: 150,
            blocks: [
                b(3, r("Deadlift", 5)),
                b(3, r("Overhead Press", 5)),
                b(3, r("Pull-Up", 6)),
                b(3, r("Hanging Knee Raise", 10)),
            ]
        ),
        .init(
            name: "Upper Body A",
            summary: "Heavy horizontal push and pull, then volume. Half of an upper/lower.",
            focus: .upper, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Bench Press", 6, 8)),
                b(4, r("Barbell Row", 6, 8)),
                b(3, r("Overhead Press", 8, 10)),
                b(3, r("Lat Pulldown", 10, 12)),
                b(3, r("Dumbbell Curl", 12), r("Tricep Pushdown", 12)),
            ]
        ),
        .init(
            name: "Lower Body A",
            summary: "Squat-led leg day with hinge and single-leg balance.",
            focus: .lower, effort: .moderate, style: .build, restSeconds: 120,
            blocks: [
                b(4, r("Squat", 6, 8)),
                b(3, r("Hip Thrust", 8, 10)),
                b(3, r("Bulgarian Split Squat", 10)),
                b(3, r("Leg Curl", 12)),
                b(4, r("Calf Raise", 15)),
            ]
        ),
        .init(
            name: "Upper Body B",
            summary: "Vertical push and pull lead; incline and arms close it out.",
            focus: .upper, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Overhead Press", 6, 8)),
                b(4, r("Pull-Up", 6, 8)),
                b(3, r("Incline Bench Press", 8, 10)),
                b(3, r("Chest-Supported Row", 10)),
                b(3, r("Hammer Curl", 10, 12), r("Skull Crusher", 10, 12)),
            ]
        ),
        .init(
            name: "Lower Body B",
            summary: "Deadlift-led lower day balancing the squat session.",
            focus: .lower, effort: .moderate, style: .build, restSeconds: 120,
            blocks: [
                b(3, r("Deadlift", 5)),
                b(3, r("Front Squat", 8)),
                b(3, r("Walking Lunge", 12)),
                b(3, r("Back Extension", 12)),
                b(4, r("Seated Calf Raise", 15)),
            ]
        ),

        // MARK: Push / Pull / Legs
        .init(
            name: "Push Day A",
            summary: "Chest, shoulders, triceps. Heavy first, isolation after.",
            focus: .push, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Bench Press", 6, 8)),
                b(3, r("Overhead Press", 8)),
                b(3, r("Incline Dumbbell Press", 10)),
                b(3, r("Lateral Raise", 12, 15)),
                b(3, r("Tricep Pushdown", 10, 12)),
            ]
        ),
        .init(
            name: "Pull Day A",
            summary: "Hinge, vertical pull, rows, and rear delts.",
            focus: .pull, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(3, r("Deadlift", 5)),
                b(4, r("Pull-Up", 6, 8)),
                b(3, r("Seated Cable Row", 10)),
                b(3, r("Face Pull", 12, 15)),
                b(3, r("EZ Bar Curl", 10, 12)),
            ]
        ),
        .init(
            name: "Leg Day A",
            summary: "The full quad-hinge-press stack. Pack a snack.",
            focus: .lower, effort: .intense, style: .build, restSeconds: 120,
            blocks: [
                b(4, r("Squat", 6, 8)),
                b(3, r("Romanian Deadlift", 8, 10)),
                b(3, r("Leg Press", 10, 12)),
                b(3, r("Leg Curl", 10, 12)),
                b(4, r("Standing Calf Raise", 12, 15)),
            ]
        ),
        .init(
            name: "Push Day B",
            summary: "Shoulder-led pressing with cable finish.",
            focus: .push, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Overhead Press", 6)),
                b(3, r("Incline Bench Press", 8)),
                b(3, r("Dumbbell Bench Press", 10)),
                b(3, r("Cable Fly", 12, 15)),
                b(3, r("Lateral Raise", 15), r("Rope Pushdown", 12)),
            ]
        ),
        .init(
            name: "Pull Day B",
            summary: "Row-led back volume with curls and shrugs.",
            focus: .pull, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Barbell Row", 6, 8)),
                b(3, r("Lat Pulldown", 10)),
                b(3, r("Dumbbell Row", 10)),
                b(3, r("Rear Delt Fly", 12, 15)),
                b(3, r("Barbell Curl", 10), r("Barbell Shrug", 12)),
            ]
        ),

        // MARK: Body-part sessions
        .init(
            name: "Chest Day",
            summary: "Pressing angles top to bottom, dips to finish.",
            focus: .push, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Bench Press", 6, 8)),
                b(3, r("Incline Dumbbell Press", 8, 10)),
                b(3, r("Dumbbell Fly", 12)),
                b(3, r("Cable Fly", 12, 15)),
                b(3, r("Chest Dip", 10)),
            ]
        ),
        .init(
            name: "Back Day",
            summary: "Deadlift first, then rows and pulldowns from every angle.",
            focus: .pull, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(3, r("Deadlift", 5)),
                b(4, r("Barbell Row", 8)),
                b(3, r("Lat Pulldown", 10, 12)),
                b(3, r("Seated Cable Row", 12)),
                b(3, r("Straight-Arm Pulldown", 12, 15)),
            ]
        ),
        .init(
            name: "Shoulder Day",
            summary: "Heavy press then every head of the delt.",
            focus: .upper, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Overhead Press", 6, 8)),
                b(3, r("Seated Dumbbell Press", 10)),
                b(4, r("Lateral Raise", 12, 15)),
                b(3, r("Rear Delt Fly", 15)),
                b(3, r("Face Pull", 15), r("Barbell Shrug", 12)),
            ]
        ),
        .init(
            name: "Arm Day",
            summary: "Superset pairs, biceps against triceps, all the way down.",
            focus: .upper, effort: .light, style: .build, restSeconds: 60,
            blocks: [
                b(4, r("EZ Bar Curl", 10), r("Skull Crusher", 10)),
                b(3, r("Hammer Curl", 12), r("Rope Pushdown", 12)),
                b(3, r("Cable Curl", 12, 15), r("Cable Overhead Extension", 12, 15)),
            ]
        ),
        .init(
            name: "Glute Builder",
            summary: "Thrust-led session with hinge, split squat, and band work.",
            focus: .lower, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Hip Thrust", 8, 10)),
                b(3, r("Sumo Deadlift", 8)),
                b(3, r("Bulgarian Split Squat", 10)),
                b(3, r("Cable Kickback", 12, 15)),
                b(3, r("Banded Lateral Walk", 15)),
            ]
        ),

        // MARK: Dumbbells only
        .init(
            name: "Dumbbell Full Body",
            summary: "One pair of dumbbells, every movement pattern.",
            focus: .fullBody, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(3, r("Goblet Squat", 10)),
                b(3, r("Dumbbell Bench Press", 10)),
                b(3, r("Dumbbell Row", 10)),
                b(3, r("Dumbbell Shoulder Press", 10)),
                b(3, r("Dumbbell Romanian Deadlift", 10)),
            ]
        ),
        .init(
            name: "Dumbbell Upper",
            summary: "Upper-body volume without a barbell in sight.",
            focus: .upper, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Dumbbell Bench Press", 8, 10)),
                b(4, r("Dumbbell Row", 8, 10)),
                b(3, r("Arnold Press", 10)),
                b(3, r("Dumbbell Curl", 12), r("Overhead Tricep Extension", 12)),
                b(3, r("Lateral Raise", 15)),
            ]
        ),
        .init(
            name: "Dumbbell Lower",
            summary: "Legs and hinge with dumbbells, carried out the door.",
            focus: .lower, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Goblet Squat", 10)),
                b(3, r("Dumbbell Romanian Deadlift", 10)),
                b(3, r("Reverse Lunge", 12)),
                b(3, r("Single-Leg Calf Raise", 15)),
                b(3, d("Farmer's Carry", 40)),
            ]
        ),
        .init(
            name: "Dumbbell Push",
            summary: "Pressing session for the home rack.",
            focus: .push, effort: .light, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Dumbbell Bench Press", 10)),
                b(3, r("Dumbbell Shoulder Press", 10)),
                b(3, r("Incline Dumbbell Press", 10)),
                b(3, r("Lateral Raise", 15)),
                b(3, r("Tricep Kickback", 12)),
            ]
        ),
        .init(
            name: "Dumbbell Pull",
            summary: "Rows, rear delts, and arms from the same pair.",
            focus: .pull, effort: .light, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Dumbbell Row", 10)),
                b(3, r("Chest-Supported Row", 10)),
                b(3, r("Rear Delt Fly", 15)),
                b(3, r("Hammer Curl", 12)),
                b(3, r("Dumbbell Shrug", 15)),
            ]
        ),

        // MARK: Bodyweight + minimal gear
        .init(
            name: "Bodyweight Basics",
            summary: "No equipment, all fundamentals: squat, push, hinge, brace.",
            focus: .fullBody, effort: .light, style: .build, restSeconds: 60,
            blocks: [
                b(3, r("Bodyweight Squat", 15)),
                b(3, r("Push-Up", 10, 15)),
                b(3, r("Glute Bridge", 15)),
                b(3, d("Plank", 30)),
                b(3, d("Bird Dog", 30)),
            ]
        ),
        .init(
            name: "Bodyweight Push",
            summary: "Push-up progressions from floor to pike.",
            focus: .push, effort: .moderate, style: .build, restSeconds: 60,
            blocks: [
                b(4, r("Push-Up", 12, 15)),
                b(3, r("Pike Push-Up", 8, 10)),
                b(3, r("Deficit Push-Up", 10)),
                b(3, r("Diamond Push-Up", 10)),
            ]
        ),
        .init(
            name: "Pull-Up Bar Day",
            summary: "One bar, every grip, plus hanging core.",
            focus: .pull, effort: .intense, style: .strength, restSeconds: 120,
            blocks: [
                b(5, r("Pull-Up", 5)),
                b(3, r("Chin-Up", 6, 8)),
                b(3, r("Neutral-Grip Pull-Up", 6)),
                b(3, r("Hanging Leg Raise", 10)),
            ]
        ),
        .init(
            name: "Hotel Room Circuit",
            summary: "Zero equipment, twenty minutes, anywhere with a floor.",
            focus: .fullBody, effort: .moderate, style: .conditioning, restSeconds: 45,
            blocks: [
                b(3, r("Burpee", 12)),
                b(3, r("Bodyweight Squat", 20)),
                b(3, r("Push-Up", 15)),
                b(3, d("Mountain Climber", 40)),
                b(3, r("Bicycle Crunch", 20)),
            ]
        ),

        // MARK: Kettlebell
        .init(
            name: "Kettlebell Full Body",
            summary: "Squat, swing, press, carry. One bell does it all.",
            focus: .fullBody, effort: .moderate, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Kettlebell Goblet Squat", 10)),
                b(4, r("Kettlebell Swing", 15)),
                b(3, r("Kettlebell Clean and Press", 8)),
                b(3, d("Suitcase Carry", 40)),
            ]
        ),
        .init(
            name: "Kettlebell Conditioning",
            summary: "Swings and snatches until the floor feels close.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 60,
            blocks: [
                b(5, r("Kettlebell Swing", 20)),
                b(4, r("Kettlebell Snatch", 10)),
                b(3, r("Turkish Get-Up", 3)),
                b(3, r("Burpee", 10)),
            ]
        ),

        // MARK: Machines
        .init(
            name: "Machine Full Body",
            summary: "A guided circuit around the machine floor.",
            focus: .fullBody, effort: .light, style: .build, restSeconds: 90,
            blocks: [
                b(3, r("Leg Press", 12)),
                b(3, r("Machine Chest Press", 12)),
                b(3, r("Machine Row", 12)),
                b(3, r("Machine Shoulder Press", 12)),
                b(3, r("Leg Curl", 12)),
            ]
        ),
        .init(
            name: "Machine Upper",
            summary: "Upper-body volume, pin-loaded end to end.",
            focus: .upper, effort: .light, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Machine Chest Press", 10, 12)),
                b(4, r("Lat Pulldown", 10, 12)),
                b(3, r("Machine Shoulder Press", 12)),
                b(3, r("Pec Deck", 12, 15)),
                b(3, r("Reverse Pec Deck", 15)),
            ]
        ),
        .init(
            name: "Machine Lower",
            summary: "Legs on rails: press, extend, curl, raise.",
            focus: .lower, effort: .light, style: .build, restSeconds: 90,
            blocks: [
                b(4, r("Leg Press", 12)),
                b(3, r("Hack Squat", 10)),
                b(3, r("Leg Extension", 12, 15)),
                b(3, r("Leg Curl", 12, 15)),
                b(4, r("Standing Calf Raise", 15)),
            ]
        ),

        // MARK: Conditioning
        .init(
            name: "Row Intervals",
            summary: "Six hard two-minute pieces on the erg.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 90,
            blocks: [
                b(6, d("Rowing", 120)),
            ]
        ),
        .init(
            name: "Bike Intervals",
            summary: "Eight one-minute efforts. The fan is not your friend.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 90,
            blocks: [
                b(8, d("Assault Bike", 60)),
            ]
        ),
        .init(
            name: "Jump Rope Circuit",
            summary: "Rope rounds broken up with ground work.",
            focus: .conditioning, effort: .moderate, style: .conditioning, restSeconds: 45,
            blocks: [
                b(5, d("Jump Rope", 90)),
                b(3, r("Burpee", 10)),
                b(3, d("Mountain Climber", 40)),
            ]
        ),
        .init(
            name: "Sled and Carries",
            summary: "Push heavy things, carry heavy things, repeat.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 90,
            blocks: [
                b(5, d("Sled Push", 30)),
                b(4, d("Farmer's Carry", 40)),
                b(3, d("Sandbag Carry", 40)),
                b(3, d("Battle Rope Waves", 30)),
            ]
        ),
        .init(
            name: "Full Body Conditioning",
            summary: "Thrusters, swings, jumps, and slams in rotation.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 60,
            blocks: [
                b(4, r("Dumbbell Thruster", 10)),
                b(4, r("Kettlebell Swing", 15)),
                b(4, r("Box Jump", 8)),
                b(3, d("Battle Rope Waves", 30)),
                b(3, r("Medicine Ball Slam", 12)),
            ]
        ),

        // MARK: Road and console cardio
        //
        // The first templates that state a DISTANCE and a PACE rather than
        // only a stopwatch. Two of the three fix the third, so an authored
        // "three miles at 9:00" carries its own honest estimate and the
        // rail rows read like a coach wrote them.
        .init(
            name: "Steady Run",
            summary: "Three miles at one pace. No surges, no finishing kick.",
            focus: .conditioning, effort: .moderate, style: .conditioning, restSeconds: 60,
            blocks: [
                b(1, c("Running", distance: 3, pace: 9 * 60)),
            ]
        ),
        .init(
            name: "Quarter Mile Repeats",
            summary: "Six quarters, hard, with a jog either side. Three full minutes between them.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 60,
            blocks: [
                b(1, c("Running", seconds: 600)),
                bi(6, rest: 180, c("Running", distance: 0.25, pace: 7 * 60)),
                b(1, c("Running", seconds: 600)),
            ]
        ),
        .init(
            name: "Erg 500s",
            summary: "Six five-hundreds at a 2:00 split. Two minutes back between each.",
            focus: .conditioning, effort: .intense, style: .conditioning, restSeconds: 120,
            blocks: [
                b(6, c("Rowing", distance: 500, pace: 120)),
            ]
        ),
        .init(
            name: "Studio Ride",
            summary: "Forty-five minutes on the bike. Resistance and cadence are yours to pick.",
            focus: .conditioning, effort: .moderate, style: .conditioning, restSeconds: 60,
            blocks: [
                b(1, c("Indoor Cycling", seconds: 2700)),
            ]
        ),
        .init(
            name: "Trail Hike",
            summary: "Ninety minutes on the trail. Distance is not the point.",
            focus: .conditioning, effort: .light, style: .conditioning, restSeconds: 60,
            blocks: [
                b(1, c("Hiking", seconds: 5400)),
            ]
        ),
        .init(
            name: "Long Walk",
            summary: "Three miles, unhurried. It counts the same.",
            focus: .conditioning, effort: .light, style: .recovery, restSeconds: 60,
            blocks: [
                b(1, c("Walking", distance: 3, pace: 17 * 60)),
            ]
        ),

        // MARK: Core
        .init(
            name: "Core Foundations",
            summary: "Anti-extension, anti-rotation, and holds. The quiet work.",
            focus: .core, effort: .light, style: .build, restSeconds: 60,
            blocks: [
                b(3, d("Plank", 40)),
                b(3, d("Dead Bug", 30)),
                b(3, d("Side Plank", 30)),
                b(3, d("Hollow Hold", 25)),
                b(3, d("Bird Dog", 30)),
            ]
        ),
        .init(
            name: "Core Circuit",
            summary: "Higher-tempo trunk work, nothing but a floor.",
            focus: .core, effort: .moderate, style: .conditioning, restSeconds: 45,
            blocks: [
                b(3, r("Sit-Up", 15), r("Bicycle Crunch", 20)),
                b(3, r("V-Up", 12)),
                b(3, d("Mountain Climber", 40)),
                b(3, r("Leg Raise", 12)),
            ]
        ),
        .init(
            name: "Weighted Core",
            summary: "Load the trunk like anything else you train.",
            focus: .core, effort: .moderate, style: .build, restSeconds: 60,
            blocks: [
                b(4, r("Cable Crunch", 12)),
                b(3, r("Pallof Press", 12)),
                b(3, r("Ab Wheel Rollout", 10)),
                b(3, r("Woodchopper", 12)),
                b(3, r("Hanging Leg Raise", 10)),
            ]
        ),

        // MARK: Recovery
        .init(
            name: "Shoulder Care",
            summary: "Band and light rear-delt work for cranky shoulders.",
            focus: .upper, effort: .light, style: .recovery, restSeconds: 45,
            blocks: [
                b(4, r("Band Pull-Apart", 15, 20)),
                b(3, r("Face Pull", 15, 20)),
                b(3, r("Rear Delt Fly", 12, 15)),
                b(2, d("Side Plank", 30)),
            ]
        ),
        .init(
            name: "Posterior Chain Care",
            summary: "Bridges, extensions, and slow bracing for the back line.",
            focus: .lower, effort: .light, style: .recovery, restSeconds: 60,
            blocks: [
                b(3, r("Glute Bridge", 15)),
                b(3, d("Bird Dog", 30)),
                b(3, r("Back Extension", 12)),
                b(3, d("Dead Bug", 30)),
                b(2, r("Single-Leg Glute Bridge", 12)),
            ]
        ),

        // MARK: Warm-up + stretch
        // Bookends for a session (Dave, 2026-07-11): dynamic drills to
        // open up before you lift, static holds to finish. One round
        // through each (sets: 1) — mobility work is a sequence, not
        // volume. Run standalone, or drop the blocks into any routine.
        .init(
            name: "Dynamic Warm-Up",
            summary: "Joint circles and dynamic moves to open up before you lift.",
            focus: .fullBody, effort: .light, style: .recovery, restSeconds: 30,
            blocks: [
                b(1, r("Arm Circles", 10)),
                b(1, r("Leg Swings", 10)),
                b(1, r("Hip Circles", 10)),
                b(1, r("Walking Knee Hug", 10)),
                b(1, r("Standing Torso Twist", 10)),
                b(1, r("Cat-Cow", 10)),
                b(1, r("World's Greatest Stretch", 5)),
                b(1, r("Inchworm", 8)),
            ]
        ),
        .init(
            name: "Full Body Stretch",
            summary: "Hold-and-breathe stretches head to toe. The way to finish a session.",
            focus: .fullBody, effort: .light, style: .recovery, restSeconds: 20,
            blocks: [
                b(1, d("Standing Hamstring Stretch", 30)),
                b(1, d("Standing Quad Stretch", 30)),
                b(1, d("Kneeling Hip Flexor Stretch", 30)),
                b(1, d("Figure-Four Stretch", 30)),
                b(1, d("Standing Calf Stretch", 30)),
                b(1, d("Doorway Chest Stretch", 30)),
                b(1, d("Cross-Body Shoulder Stretch", 30)),
                b(1, d("Child's Pose", 30)),
                b(1, d("Seated Spinal Twist", 30)),
            ]
        ),
    ]
}
