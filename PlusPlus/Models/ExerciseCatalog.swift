import Foundation
import SwiftData
import PlusPlusKit

/// The built-in EXERCISE catalog: the canonical definition table every
/// built-in resolves through, and the lookups over it. Split out of
/// SeedData 2026-08-02 (#499) — it had grown past a thousand lines and
/// every catalog round rewrote the same file, so seeding, gear and
/// exercises now sit apart. Pure data and pure lookups: no ModelContext
/// reaches in here.
extension SeedData {

    // MARK: - Exercises

    // Exposed as internal for testing; use loadIfNeeded for production
    static func makeBuiltInExercisesForTesting(equipment: [Equipment]) -> [Exercise] {
        makeBuiltInExercises(equipment: equipment)
    }

    /// Canonical catalog definition — the "default" a customized
    /// built-in reverts to (#136).
    struct BuiltInExerciseDefinition {
        let name: String
        /// Every group the move works, PRIMARY FIRST. The primary is what
        /// the move is FOR (the group it would be filed under on a
        /// program); the rest are the muscles that do real work in it, not
        /// every muscle that fires. See the authoring note on the table.
        let muscleGroups: [MuscleGroup]
        let equipmentNames: [String]
        let exerciseType: ExerciseType
        /// Explicit metric-profile override. nil derives from the
        /// equipment table + type (`suggestedProfile`) — only exercises
        /// whose tracking the rules can't express carry one (Ruck's
        /// mileage on plain strength gear, the no-equipment cardio).
        let metrics: MetricProfile?
        /// Add-time set count (config audit, 2026-07-15). 3 — the classic
        /// strength block — unless the exercise's shape says otherwise:
        /// a stretch is one hold, a mobility drill one pass, a steady
        /// cardio piece one round.
        let defaultSets: Int
        /// Catalog rep prescription where the global 10-rep floor is
        /// never what anyone does (a Turkish get-up is 3, a power clean
        /// 3, a rope climb 3). nil rides the global floor. A user's own
        /// bumped default (#187) always wins over this.
        let defaultReps: Int?
        /// Catalog effort length where the global 45 s floor misses (a
        /// static stretch holds 30 s, a heavy-bag round runs 3 min, an
        /// L-sit survives 20 s). Same precedence as defaultReps.
        let defaultDurationSeconds: Int?
        /// Whether a heart-rate prescription makes sense here. False for
        /// stretches and static holds — a "zone 2 hamstring stretch" is
        /// noise — so their planning/config sheets drop the Target HR
        /// row. A column, not a side table, so a new stretch can't
        /// forget it. Customs always keep the row (the isLoadable
        /// can't-classify-intent rule, applied in Exercise).
        let supportsHeartRate: Bool
        /// Authored modality override. nil derives from gear + metrics
        /// (`ExerciseModality.derive`); only the shapes derivation can't
        /// see carry one — the stretch/mobility rows are `.flexibility`
        /// (a stretch and a plank look identical to the metrics).
        let modality: ExerciseModality?
        /// The program bucket (hinge, vertical pull, carry…). Authored on
        /// compound strength rows — `ExerciseAttributeTests` fails a
        /// strength compound that names no pattern and no exemption.
        /// nil on cardio (identity is modality) and most isolation.
        let movementPattern: MovementPattern?
        /// Compound vs isolation, programming semantics (see the enum).
        /// nil = unclassified — the stretch/mobility/roll shapes.
        let mechanic: ExerciseMechanic?
        /// Per-side work? Unilateral when a SET belongs to a side.
        let laterality: ExerciseLaterality

        /// The group this exercise is FOR — every single-group reader's
        /// view of it (the interchange's required field, the substitution
        /// pools, the seeded `Exercise.muscleGroup` column).
        var muscleGroup: MuscleGroup { muscleGroups[0] }
    }

    /// Keyed lookup (the builtInProfilesByName pattern) — the resolution
    /// helpers on Exercise hit this per add/sheet-open, so no linear scan.
    private static let definitionsByName: [String: BuiltInExerciseDefinition] = {
        Dictionary(uniqueKeysWithValues: builtInExerciseDefinitions.map { ($0.name, $0) })
    }()

    static func builtInDefinition(named name: String) -> BuiltInExerciseDefinition? {
        definitionsByName[name]
    }

    /// Definition-table size, so tests assert against the table instead
    /// of a hardcoded count that rots every time the catalog grows.
    static var builtInExerciseCount: Int { builtInExerciseDefinitions.count }

    private static func makeBuiltInExercises(equipment: [Equipment]) -> [Exercise] {
        let eq = Dictionary(uniqueKeysWithValues: equipment.map { ($0.name, $0) })
        return builtInExerciseDefinitions.map { def in
            Exercise(
                name: def.name,
                muscleGroup: def.muscleGroup,
                equipment: def.equipmentNames.compactMap { eq[$0] },
                exerciseType: def.exerciseType,
                isBuiltIn: true
            )
        }
    }

    // Internal, not private: `loadIfNeeded` (SeedData.swift) tops up an
    // existing store from it, and that is the one read that crosses a
    // file after the #499 split.
    static let builtInExerciseDefinitions: [BuiltInExerciseDefinition] = {
        // `also:` lists the SECONDARY muscle groups a move works — the ones
        // that do real work under load, not every muscle that fires. The
        // authoring rule, applied row by row across this table:
        //   • The primary is the first argument and never moves. It is what
        //     the exercise is FOR, so an existing row's reading, its
        //     substitution pool, and its exported `muscleGroup` are all
        //     unchanged by this column.
        //   • A secondary earns its place only if someone would program the
        //     move to train it. Bench Press lists triceps and shoulders;
        //     it does not list core, which braces in nearly everything and
        //     would therefore say nothing.
        //   • Isolation stays isolated. A Biceps Curl is biceps, full stop.
        //   • `.fullBody` absorbs its own secondaries by definition, so a
        //     full-body primary takes `also:` only where a specific group
        //     genuinely dominates (a Clean's quads and back).
        //   • Stretches and mobility drills name what they lengthen, so
        //     they keep their single group.
        func e(_ name: String, _ muscle: MuscleGroup, _ eqNames: [String], _ type: ExerciseType = .weightReps, also: [MuscleGroup] = [], metrics: MetricProfile? = nil, sets: Int = 3, reps: Int? = nil, seconds: Int? = nil, heartRate: Bool = true, modality: ExerciseModality? = nil, pattern: MovementPattern? = nil, mechanic: ExerciseMechanic? = .compound, laterality: ExerciseLaterality = .bilateral) -> BuiltInExerciseDefinition {
            BuiltInExerciseDefinition(name: name, muscleGroups: MuscleGroups.normalized(primary: muscle, others: also), equipmentNames: eqNames, exerciseType: type, metrics: metrics, defaultSets: sets, defaultReps: reps, defaultDurationSeconds: seconds, supportsHeartRate: heartRate, modality: modality, movementPattern: pattern, mechanic: mechanic, laterality: laterality)
        }
        // The three mobility-work shapes, defined ONCE: a static stretch
        // is a single 30 s hold (the standard prescription — and what the
        // Full Body Stretch routine already prescribes per entry); a
        // dynamic drill is one pass of reps; a foam roll is a 30 s pass
        // on the roller. None takes a heart-rate prescription or a
        // mechanic (compound/isolation doesn't apply to mobility work).
        // Static HOLDS that build strength (Plank, Wall Sit) are NOT
        // stretches — they keep their 3-set blocks, declare
        // `heartRate: false` on their own rows, and file under the
        // `.hold` pattern.
        func stretch(_ name: String, _ muscle: MuscleGroup, sides: ExerciseLaterality = .bilateral) -> BuiltInExerciseDefinition {
            e(name, muscle, [], .duration, sets: 1, seconds: 30, heartRate: false, modality: .flexibility, mechanic: nil, laterality: sides)
        }
        func mobility(_ name: String, _ muscle: MuscleGroup, sides: ExerciseLaterality = .bilateral) -> BuiltInExerciseDefinition {
            e(name, muscle, [], sets: 1, heartRate: false, modality: .flexibility, mechanic: nil, laterality: sides)
        }
        func roll(_ name: String, _ muscle: MuscleGroup) -> BuiltInExerciseDefinition {
            e(name, muscle, ["Foam Roller"], .duration, sets: 1, seconds: 30, heartRate: false, modality: .flexibility, mechanic: nil)
        }

        return [
            // Chest
            e("Bench Press", .chest, ["Barbell", "Bench"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Incline Bench Press", .chest, ["Barbell", "Incline Bench"], also: [.shoulders, .triceps], pattern: .horizontalPush),
            e("Dumbbell Bench Press", .chest, ["Dumbbells", "Bench"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Incline Dumbbell Press", .chest, ["Dumbbells", "Incline Bench"], also: [.shoulders, .triceps], pattern: .horizontalPush),
            e("Machine Chest Press", .chest, ["Chest Press Machine"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Smith Machine Bench Press", .chest, ["Smith Machine", "Bench"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Dumbbell Fly", .chest, ["Dumbbells", "Bench"], also: [.shoulders], mechanic: .isolation),
            e("Cable Fly", .chest, ["Cable Machine"], also: [.shoulders], mechanic: .isolation),
            e("Low-to-High Cable Fly", .chest, ["Cable Machine"], also: [.shoulders], mechanic: .isolation),
            e("Pec Deck", .chest, ["Pec Deck Machine"], mechanic: .isolation),
            e("Chest Dip", .chest, ["Dip Station"], also: [.triceps, .shoulders], pattern: .verticalPush),
            e("Push-Up", .chest, [], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Deficit Push-Up", .chest, [], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Ring Push-Up", .chest, ["Gymnastic Rings"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Band Chest Press", .chest, ["Resistance Band"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Svend Press", .chest, ["Weight Plate"], also: [.shoulders], mechanic: .isolation),

            // Back
            e("Deadlift", .back, ["Barbell"], also: [.hamstrings, .glutes], pattern: .hinge),
            e("Trap Bar Deadlift", .back, ["Trap Bar"], also: [.quads, .glutes, .hamstrings], pattern: .hinge),
            e("Barbell Row", .back, ["Barbell"], also: [.biceps], pattern: .horizontalPull),
            e("Pendlay Row", .back, ["Barbell"], also: [.biceps], pattern: .horizontalPull),
            e("Dumbbell Row", .back, ["Dumbbells", "Bench"], also: [.biceps], pattern: .horizontalPull, laterality: .unilateral),
            e("Chest-Supported Row", .back, ["Dumbbells", "Incline Bench"], also: [.biceps], pattern: .horizontalPull),
            e("Seated Cable Row", .back, ["Seated Row Machine"], also: [.biceps], pattern: .horizontalPull),
            e("Cable Row", .back, ["Cable Machine"], also: [.biceps], pattern: .horizontalPull),
            e("Machine Row", .back, ["Seated Row Machine"], also: [.biceps], pattern: .horizontalPull),
            // A landmine is a sleeve for a BARBELL — the bar is required
            // (equipment audit; the Chain Bench Press convention).
            e("Landmine Row", .back, ["Barbell", "Landmine"], also: [.biceps], pattern: .horizontalPull, laterality: .unilateral),
            e("Pull-Up", .back, ["Pull-Up Bar"], also: [.biceps], pattern: .verticalPull),
            e("Chin-Up", .back, ["Pull-Up Bar"], also: [.biceps], pattern: .verticalPull),
            e("Neutral-Grip Pull-Up", .back, ["Pull-Up Bar"], also: [.biceps], pattern: .verticalPull),
            e("Lat Pulldown", .back, ["Lat Pulldown Machine"], also: [.biceps], pattern: .verticalPull),
            e("Straight-Arm Pulldown", .back, ["Cable Machine"], mechanic: .isolation),
            e("Ring Row", .back, ["Gymnastic Rings"], also: [.biceps], pattern: .horizontalPull),
            e("Suspension Row", .back, ["Suspension Trainer"], also: [.biceps], pattern: .horizontalPull),
            e("Band Pull-Apart", .back, ["Resistance Band"], also: [.shoulders], mechanic: .isolation),
            e("Back Extension", .back, ["Back Extension Bench"], also: [.glutes, .hamstrings], pattern: .hinge),
            e("Good Morning", .back, ["Barbell"], also: [.hamstrings, .glutes], pattern: .hinge),

            // Shoulders
            e("Overhead Press", .shoulders, ["Barbell"], also: [.triceps], pattern: .verticalPush),
            e("Seated Dumbbell Press", .shoulders, ["Dumbbells", "Bench"], also: [.triceps], pattern: .verticalPush),
            e("Dumbbell Shoulder Press", .shoulders, ["Dumbbells"], also: [.triceps], pattern: .verticalPush),
            e("Machine Shoulder Press", .shoulders, ["Shoulder Press Machine"], also: [.triceps], pattern: .verticalPush),
            e("Arnold Press", .shoulders, ["Dumbbells"], also: [.triceps], pattern: .verticalPush),
            e("Push Press", .shoulders, ["Barbell"], also: [.triceps, .quads], pattern: .verticalPush),
            e("Landmine Press", .shoulders, ["Barbell", "Landmine"], also: [.triceps], pattern: .verticalPush, laterality: .unilateral),
            e("Lateral Raise", .shoulders, ["Dumbbells"], mechanic: .isolation),
            e("Cable Lateral Raise", .shoulders, ["Cable Machine"], mechanic: .isolation, laterality: .unilateral),
            e("Front Raise", .shoulders, ["Dumbbells"], mechanic: .isolation),
            e("Plate Front Raise", .shoulders, ["Weight Plate"], mechanic: .isolation),
            e("Rear Delt Fly", .shoulders, ["Dumbbells"], also: [.back], mechanic: .isolation),
            e("Reverse Pec Deck", .shoulders, ["Pec Deck Machine"], also: [.back], mechanic: .isolation),
            e("Face Pull", .shoulders, ["Cable Machine"], also: [.back], pattern: .horizontalPull),
            e("Upright Row", .shoulders, ["Barbell"], also: [.back], pattern: .verticalPull),
            e("Barbell Shrug", .shoulders, ["Barbell"], also: [.back], mechanic: .isolation),
            e("Dumbbell Shrug", .shoulders, ["Dumbbells"], also: [.back], mechanic: .isolation),
            e("Pike Push-Up", .shoulders, [], also: [.triceps], pattern: .verticalPush),

            // Biceps
            e("Barbell Curl", .biceps, ["Barbell"], mechanic: .isolation),
            e("EZ Bar Curl", .biceps, ["EZ Bar"], mechanic: .isolation),
            e("Dumbbell Curl", .biceps, ["Dumbbells"], mechanic: .isolation),
            e("Hammer Curl", .biceps, ["Dumbbells"], mechanic: .isolation),
            e("Incline Dumbbell Curl", .biceps, ["Dumbbells", "Incline Bench"], mechanic: .isolation),
            e("Preacher Curl", .biceps, ["EZ Bar", "Preacher Bench"], mechanic: .isolation),
            e("Concentration Curl", .biceps, ["Dumbbells", "Bench"], mechanic: .isolation, laterality: .unilateral),
            e("Cable Curl", .biceps, ["Cable Machine"], mechanic: .isolation),
            e("Band Curl", .biceps, ["Resistance Band"], mechanic: .isolation),
            e("Zottman Curl", .biceps, ["Dumbbells"], mechanic: .isolation),
            e("Spider Curl", .biceps, ["Dumbbells", "Incline Bench"], mechanic: .isolation),

            // Triceps
            e("Close-Grip Bench Press", .triceps, ["Barbell", "Bench"], also: [.chest, .shoulders], pattern: .horizontalPush),
            e("Tricep Pushdown", .triceps, ["Cable Machine"], mechanic: .isolation),
            e("Rope Pushdown", .triceps, ["Cable Machine"], mechanic: .isolation),
            e("Overhead Tricep Extension", .triceps, ["Dumbbells"], mechanic: .isolation),
            e("Cable Overhead Extension", .triceps, ["Cable Machine"], mechanic: .isolation),
            e("Skull Crusher", .triceps, ["EZ Bar", "Bench"], mechanic: .isolation),
            e("Tricep Dip", .triceps, ["Dip Station"], also: [.chest, .shoulders], pattern: .verticalPush),
            e("Bench Dip", .triceps, ["Bench"], also: [.chest, .shoulders], pattern: .verticalPush),
            e("Diamond Push-Up", .triceps, [], also: [.chest, .shoulders], pattern: .horizontalPush),
            e("Band Pushdown", .triceps, ["Resistance Band"], mechanic: .isolation),
            e("Tricep Kickback", .triceps, ["Dumbbells"], mechanic: .isolation, laterality: .unilateral),

            // Quads
            e("Squat", .quads, ["Barbell", "Squat Rack"], also: [.glutes, .hamstrings], pattern: .squat),
            e("Front Squat", .quads, ["Barbell", "Squat Rack"], also: [.glutes, .core], pattern: .squat),
            e("Smith Machine Squat", .quads, ["Smith Machine"], also: [.glutes], pattern: .squat),
            e("Goblet Squat", .quads, ["Dumbbells"], also: [.glutes, .core], pattern: .squat),
            e("Kettlebell Goblet Squat", .quads, ["Kettlebell"], also: [.glutes, .core], pattern: .squat),
            e("Hack Squat", .quads, ["Hack Squat Machine"], also: [.glutes], pattern: .squat),
            e("Leg Press", .quads, ["Leg Press Machine"], also: [.glutes, .hamstrings], pattern: .squat),
            e("Leg Extension", .quads, ["Leg Extension Machine"], mechanic: .isolation),
            e("Bulgarian Split Squat", .quads, ["Dumbbells", "Bench"], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Walking Lunge", .quads, ["Dumbbells"], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Reverse Lunge", .quads, ["Dumbbells"], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Step-Up", .quads, ["Dumbbells", "Plyo Box"], also: [.glutes], pattern: .lunge, laterality: .unilateral),
            e("Box Squat", .quads, ["Barbell", "Squat Rack", "Plyo Box"], also: [.glutes, .hamstrings], pattern: .squat),
            e("Bodyweight Squat", .quads, [], also: [.glutes], pattern: .squat),
            e("Jump Squat", .quads, [], also: [.glutes, .calves], pattern: .jump),
            e("Wall Sit", .quads, [], .duration, heartRate: false, pattern: .hold),
            e("Sissy Squat", .quads, [], mechanic: .isolation),

            // Hamstrings
            e("Romanian Deadlift", .hamstrings, ["Barbell"], also: [.glutes, .back], pattern: .hinge),
            e("Dumbbell Romanian Deadlift", .hamstrings, ["Dumbbells"], also: [.glutes, .back], pattern: .hinge),
            e("Stiff-Leg Deadlift", .hamstrings, ["Barbell"], also: [.glutes, .back], pattern: .hinge),
            e("Single-Leg Romanian Deadlift", .hamstrings, ["Dumbbells"], also: [.glutes, .core], pattern: .hinge, laterality: .unilateral),
            e("Leg Curl", .hamstrings, ["Leg Curl Machine"], mechanic: .isolation),
            // Nordics are near-maximal eccentrics — 5 is a real set.
            e("Nordic Curl", .hamstrings, [], also: [.glutes], reps: 5, mechanic: .isolation),
            e("Glute-Ham Raise", .hamstrings, ["Back Extension Bench"], also: [.glutes, .calves], mechanic: .isolation),
            e("Cable Pull-Through", .hamstrings, ["Cable Machine"], also: [.glutes, .back], pattern: .hinge),
            // Sliders required, like Slider Lunge/Body Saw (equipment
            // audit — this one shipped as bodyweight).
            e("Slider Leg Curl", .hamstrings, ["Sliders"], also: [.glutes], mechanic: .isolation),

            // Glutes
            e("Hip Thrust", .glutes, ["Barbell", "Bench"], also: [.hamstrings], pattern: .hinge),
            e("Machine Hip Thrust", .glutes, ["Hip Thrust Machine"], also: [.hamstrings], pattern: .hinge),
            e("Glute Bridge", .glutes, [], also: [.hamstrings], pattern: .hinge),
            e("Single-Leg Glute Bridge", .glutes, [], also: [.hamstrings], pattern: .hinge, laterality: .unilateral),
            e("Kettlebell Swing", .glutes, ["Kettlebell"], also: [.hamstrings, .back, .core], pattern: .hinge),
            e("Sumo Deadlift", .glutes, ["Barbell"], also: [.back, .quads, .hamstrings], pattern: .hinge),
            e("Cable Kickback", .glutes, ["Cable Machine"], also: [.hamstrings], mechanic: .isolation, laterality: .unilateral),
            e("Curtsy Lunge", .glutes, ["Dumbbells"], also: [.quads], pattern: .lunge, laterality: .unilateral),
            e("Frog Pump", .glutes, [], mechanic: .isolation),
            e("Banded Lateral Walk", .glutes, ["Resistance Band"], mechanic: .isolation),
            e("Fire Hydrant", .glutes, [], mechanic: .isolation, laterality: .unilateral),

            // Calves
            e("Standing Calf Raise", .calves, ["Calf Raise Machine"], mechanic: .isolation),
            e("Seated Calf Raise", .calves, ["Calf Raise Machine"], mechanic: .isolation),
            e("Smith Machine Calf Raise", .calves, ["Smith Machine"], mechanic: .isolation),
            e("Single-Leg Calf Raise", .calves, [], mechanic: .isolation, laterality: .unilateral),
            e("Donkey Calf Raise", .calves, [], mechanic: .isolation),
            e("Calf Raise", .calves, ["Calf Raise Machine"], mechanic: .isolation),

            // Core. The isometric holds are strength work (3-set blocks
            // stay), but take no heart-rate prescription; per-side and
            // positional holds start at an honest 30 s where the plank
            // keeps 45.
            e("Plank", .core, [], .duration, heartRate: false, pattern: .hold),
            e("Side Plank", .core, [], .duration, seconds: 30, heartRate: false, pattern: .hold, laterality: .unilateral),
            e("Dead Bug", .core, [], .duration, seconds: 30, heartRate: false, pattern: .hold),
            e("Bird Dog", .core, [], .duration, seconds: 30, heartRate: false, pattern: .hold),
            e("Hollow Hold", .core, [], .duration, seconds: 30, heartRate: false, pattern: .hold),
            e("Crunch", .core, [], mechanic: .isolation),
            e("Cable Crunch", .core, ["Cable Machine"], mechanic: .isolation),
            e("Sit-Up", .core, [], mechanic: .isolation),
            e("Russian Twist", .core, ["Medicine Ball"], pattern: .rotation, mechanic: .isolation),
            e("Hanging Knee Raise", .core, ["Pull-Up Bar"], also: [.back], mechanic: .isolation),
            e("Hanging Leg Raise", .core, ["Pull-Up Bar"], also: [.back], mechanic: .isolation),
            e("Toes to Bar", .core, ["Pull-Up Bar"], also: [.back], mechanic: .isolation),
            e("Ab Wheel Rollout", .core, ["Ab Wheel"], also: [.back]),
            e("Mountain Climber", .core, [], .duration, also: [.shoulders], seconds: 30),
            e("Bicycle Crunch", .core, [], mechanic: .isolation),
            e("V-Up", .core, [], mechanic: .isolation),
            e("Leg Raise", .core, [], mechanic: .isolation),
            e("Pallof Press", .core, ["Cable Machine"], pattern: .rotation, mechanic: .isolation, laterality: .unilateral),
            e("Suitcase Carry", .core, ["Kettlebell"], .duration, also: [.back], pattern: .carry, laterality: .unilateral),
            e("Farmer's Carry", .core, ["Dumbbells"], .duration, also: [.back], pattern: .carry),
            e("Woodchopper", .core, ["Cable Machine"], also: [.shoulders], pattern: .rotation, mechanic: .isolation, laterality: .unilateral),
            e("Medicine Ball Slam", .core, ["Medicine Ball"], also: [.back, .shoulders]),

            // Full Body
            e("Burpee", .fullBody, [], also: [.chest, .quads]),
            // Technical/max-effort movements: nobody's prescription is
            // the global 10-rep floor — cleans live at 3-5, a get-up
            // at 3 a side.
            e("Clean and Press", .fullBody, ["Barbell"], also: [.quads, .back, .shoulders], reps: 5, pattern: .hinge),
            e("Power Clean", .fullBody, ["Barbell"], also: [.quads, .back], reps: 3, pattern: .hinge),
            e("Kettlebell Clean and Press", .fullBody, ["Kettlebell"], also: [.shoulders, .glutes], reps: 5, pattern: .hinge, laterality: .unilateral),
            e("Kettlebell Snatch", .fullBody, ["Kettlebell"], also: [.shoulders, .glutes], pattern: .hinge, laterality: .unilateral),
            e("Thruster", .fullBody, ["Barbell", "Squat Rack"], also: [.quads, .shoulders], pattern: .squat),
            e("Dumbbell Thruster", .fullBody, ["Dumbbells"], also: [.quads, .shoulders], pattern: .squat),
            e("Turkish Get-Up", .fullBody, ["Kettlebell"], also: [.shoulders, .core], reps: 3, laterality: .unilateral),
            e("Sled Push", .fullBody, ["Sled"], .duration, also: [.quads, .glutes], pattern: .carry),
            // Interval-shaped conditioning keeps 3 "rounds" but gets an
            // honest round length: battle ropes burn out in 30 s, a bag
            // round is boxing's 3 minutes, a jump-rope round a minute.
            e("Battle Rope Waves", .fullBody, ["Battle Ropes"], .duration, also: [.shoulders], seconds: 30),
            e("Box Jump", .fullBody, ["Plyo Box"], also: [.quads, .calves], pattern: .jump),
            e("Jump Rope", .fullBody, ["Jump Rope"], .duration, also: [.calves], seconds: 60),
            // Machine cardio defaults to ONE steady piece — 3 "sets" of
            // rowing is an interval prescription, which stays a
            // deliberate configuration (bump Sets, add a block rest).
            e("Rowing", .fullBody, ["Rowing Machine"], .duration, also: [.back, .quads], sets: 1),
            e("Assault Bike", .fullBody, ["Air Bike"], .duration, also: [.quads], sets: 1),
            // ⚠️ ONE row for riding a bike indoors (Dave, build 158). This
            // shipped as two — a "Stationary Bike" exercise named after its
            // own equipment, and an "Indoor Cycling" added beside it on the
            // theory that a studio class is dialled differently. It is not a
            // different activity, it is the same activity with cadence on the
            // console, so the catalog offered a choice with no answer. The
            // activity noun wins, as it does for Rowing (not "Rowing
            // Machine") and Treadmill Run; the equipment keeps its own name.
            // `mergeIndoorBikeExercises` folds the old row into this one on
            // stores that already have both.
            // ⚠️ No duration default, deliberately, and the coherence test
            // enforces it: a duration prescription on a profile that also
            // tracks distance decides the driver behind your back. A ride
            // that runs long would count DOWN to a number nobody chose and
            // stop; open-ended is both the honest default and the one
            // Rowing and Assault Bike already carry.
            e("Indoor Cycling", .fullBody, ["Stationary Bike"], .duration,
              also: [.quads, .glutes],
              metrics: MetricProfile([.duration, .distance, .resistance, .power, .cadence], distanceUnit: .miles),
              sets: 1),
            e("Treadmill Run", .fullBody, ["Treadmill"], .duration, also: [.quads, .calves], sets: 1),
            e("Sandbag Carry", .fullBody, ["Sandbag"], .duration, also: [.back, .core], pattern: .carry),
            // Road cardio (flexible metrics): the road is not gear, but
            // running is training — these make distance intervals
            // (6×400 m) and steady pieces first-class. One steady piece
            // by default, like the machines. Cycling DOES require gear
            // (equipment audit, 2026-07-15: it read as "Bodyweight"):
            // the Bicycle, whose declared profile derives the same
            // [distance, duration, speed] the old explicit override
            // spelled out. Running/Walking stay genuinely equipment-free.
            // ⚠️ Modality is AUTHORED on these two. Running and Walking
            // are equipment-free and metrically identical, so derivation
            // cannot tell them apart and lands both on generic `.cardio`
            // — which would file every GPS run in Health as Mixed Cardio
            // instead of Running. The catalog knows; derivation can't.
            e("Running", .fullBody, [], .duration,
              also: [.quads, .calves], metrics: MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true), sets: 1, modality: .running),
            e("Walking", .fullBody, [], .duration,
              metrics: MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true), sets: 1, modality: .walking),
            e("Cycling", .fullBody, ["Bicycle"], .duration, also: [.quads], sets: 1),
            // Hiking is equipment-free like Running and Walking (the
            // trail is not gear), and authored for the same reason they
            // are: derivation cannot tell three metrically identical
            // road efforts apart.
            e("Hiking", .fullBody, [], .duration,
              also: [.quads, .glutes, .calves],
              metrics: MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true),
              sets: 1, modality: .hiking),
            // Swimming, in YARDS and split per 100 — the short-course
            // convention, and the reason `PaceReference` exists: a metric
            // pool is denominated in meters like an erg but splits per 100,
            // not per 500. Both rows state the reference explicitly, so the
            // meaning survives a unit change in the editor.
            // ⚠️ Equipment-free like Running and Walking (a pool is not
            // gear), so the modality is AUTHORED — derivation cannot tell
            // metrically identical water and road efforts apart.
            e("Pool Swim", .fullBody, [], .duration,
              also: [.back, .shoulders, .core],
              metrics: MetricProfile([.distance, .duration, .pace],
                                     distanceUnit: .yards,
                                     paceReference: .per100Yards),
              sets: 1, modality: .swimming),
            // Open water is the outdoor one: GPS engages, and Health files
            // it against the open-water location.
            e("Open Water Swim", .fullBody, [], .duration,
              also: [.back, .shoulders, .core],
              metrics: MetricProfile([.distance, .duration, .pace],
                                     distanceUnit: .yards,
                                     isOutdoor: true,
                                     paceReference: .per100Yards),
              sets: 1, modality: .swimming),

            // #235: every equipment type gates at least one exercise —
            // the 60 types the #222 sweep added get their movements.
            // Specialty bars
            e("Safety Bar Squat", .quads, ["Safety Squat Bar", "Squat Rack"], also: [.glutes, .hamstrings, .back], pattern: .squat),
            e("Safety Bar Good Morning", .hamstrings, ["Safety Squat Bar", "Squat Rack"], also: [.glutes, .back], pattern: .hinge),
            e("Swiss Bar Bench Press", .chest, ["Swiss Bar", "Bench"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Swiss Bar Overhead Press", .shoulders, ["Swiss Bar"], also: [.triceps], pattern: .verticalPush),
            e("Cambered Bar Squat", .quads, ["Cambered Squat Bar", "Squat Rack"], also: [.glutes, .hamstrings], pattern: .squat),
            e("Axle Deadlift", .back, ["Axle Bar"], also: [.hamstrings, .glutes], pattern: .hinge),
            e("Axle Clean and Press", .fullBody, ["Axle Bar"], also: [.quads, .back, .shoulders], reps: 5, pattern: .hinge),
            // Benches + stations
            e("Decline Bench Press", .chest, ["Barbell", "Decline Bench"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Decline Sit-Up", .core, ["Decline Bench"], mechanic: .isolation),
            e("GHD Raise", .hamstrings, ["Glute-Ham Developer"], also: [.glutes, .back], mechanic: .isolation),
            e("GHD Sit-Up", .core, ["Glute-Ham Developer"], mechanic: .isolation),
            e("Reverse Hyperextension", .glutes, ["Reverse Hyper Machine"], also: [.hamstrings, .back], pattern: .hinge),
            e("Nordic Bench Curl", .hamstrings, ["Nordic Bench"], also: [.glutes], reps: 5, mechanic: .isolation),
            e("Weighted Sissy Squat", .quads, ["Sissy Squat Bench", "Weight Plate"], mechanic: .isolation),
            e("Captain's Chair Leg Raise", .core, ["Captain's Chair"], mechanic: .isolation),
            // Plate-loaded machines
            e("T-Bar Row", .back, ["T-Bar Row Machine"], also: [.biceps], pattern: .horizontalPull),
            e("Belt Squat", .quads, ["Belt Squat Machine"], also: [.glutes], pattern: .squat),
            e("Pendulum Squat", .quads, ["Pendulum Squat Machine"], also: [.glutes], pattern: .squat),
            e("Machine Pullover", .back, ["Pullover Machine"], also: [.chest, .triceps], mechanic: .isolation),
            // Selectorized machines
            e("Hip Abduction", .glutes, ["Hip Abduction Machine"], mechanic: .isolation),
            e("Hip Adduction", .quads, ["Hip Adduction Machine"], mechanic: .isolation),
            e("Assisted Pull-Up", .back, ["Assisted Pull-Up Machine"], also: [.biceps], pattern: .verticalPull),
            e("Assisted Dip", .triceps, ["Assisted Pull-Up Machine"], also: [.chest, .shoulders], pattern: .verticalPush),
            e("Machine Crunch", .core, ["Ab Crunch Machine"], mechanic: .isolation),
            e("Torso Rotation", .core, ["Torso Rotation Machine"], pattern: .rotation, mechanic: .isolation),
            e("Machine Lateral Raise", .shoulders, ["Lateral Raise Machine"], mechanic: .isolation),
            e("Machine Bicep Curl", .biceps, ["Bicep Curl Machine"], mechanic: .isolation),
            e("Machine Tricep Extension", .triceps, ["Tricep Extension Machine"], mechanic: .isolation),
            e("Machine Back Extension", .back, ["Low Back Extension Machine"], also: [.glutes, .hamstrings], pattern: .hinge),
            e("Multi-Hip Kickback", .glutes, ["Multi-Hip Machine"], also: [.hamstrings], mechanic: .isolation, laterality: .unilateral),
            e("Machine Glute Kickback", .glutes, ["Glute Kickback Machine"], also: [.hamstrings], mechanic: .isolation, laterality: .unilateral),
            // Cardio — one steady piece, like the other machines. The
            // ones whose ONLY work metric is duration (no distance or
            // calories on the console profile) get an honest 10-minute
            // piece: without it the work-metric floor would stamp them
            // with an absurd 45 s "steady" piece. Distance/calorie
            // machines (Ski Erg, Rowing, the bikes) stay target-less —
            // the driver-hijack rule.
            e("Ski Erg", .fullBody, ["Ski Erg"], .duration, also: [.back, .core], sets: 1),
            e("Elliptical", .fullBody, ["Elliptical"], .duration, also: [.quads], sets: 1, seconds: 600),
            e("Stair Climber", .fullBody, ["Stair Climber"], .duration, also: [.quads, .glutes], sets: 1, seconds: 600),
            e("Vertical Climber", .fullBody, ["Vertical Climber"], .duration, also: [.quads, .back], sets: 1, seconds: 600),
            e("Upper Body Ergometer", .fullBody, ["Upper Body Ergometer"], .duration, also: [.shoulders, .back], sets: 1, seconds: 600),
            // Strongman
            e("Yoke Carry", .fullBody, ["Yoke"], .duration, also: [.back, .quads], pattern: .carry),
            e("Farmers Handle Carry", .fullBody, ["Farmers Walk Handles"], .duration, also: [.back, .core], pattern: .carry),
            e("Log Clean and Press", .fullBody, ["Log Bar"], also: [.quads, .back, .shoulders], reps: 5, pattern: .hinge),
            e("Atlas Stone Load", .fullBody, ["Atlas Stone"], also: [.back, .quads], reps: 5, pattern: .hinge),
            e("Circus Dumbbell Press", .shoulders, ["Circus Dumbbell"], also: [.triceps, .core], pattern: .verticalPush, laterality: .unilateral),
            e("Husafell Carry", .fullBody, ["Husafell Stone"], .duration, also: [.back, .core], pattern: .carry),
            e("Tire Flip", .fullBody, ["Tire"], also: [.back, .quads], pattern: .hinge),
            e("Sledgehammer Slam", .fullBody, ["Sledgehammer", "Tire"], also: [.core, .back], pattern: .rotation),
            // Gymnastics + calisthenics: an L-sit is measured in tens of
            // seconds, and a climb "rep" is a whole ascent.
            e("Parallette L-Sit", .core, ["Parallettes"], .duration, also: [.shoulders, .triceps], seconds: 20, heartRate: false, pattern: .hold),
            e("Parallette Push-Up", .chest, ["Parallettes"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Rope Climb", .back, ["Climbing Rope"], also: [.biceps, .core], reps: 3, pattern: .verticalPull),
            e("Peg Board Ascent", .back, ["Peg Board"], also: [.biceps, .core], reps: 3, pattern: .verticalPull),
            e("Stall Bar Leg Raise", .core, ["Stall Bars"], mechanic: .isolation),
            // Small equipment
            e("Slam Ball Slam", .fullBody, ["Slam Ball"], also: [.core, .back]),
            e("Stability Ball Leg Curl", .hamstrings, ["Stability Ball"], also: [.glutes], mechanic: .isolation),
            e("Stability Ball Rollout", .core, ["Stability Ball"], also: [.back]),
            e("Balance Trainer Squat", .quads, ["Balance Trainer"], also: [.glutes, .core], pattern: .squat),
            e("Slider Lunge", .quads, ["Sliders"], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Body Saw", .core, ["Sliders"], .duration, also: [.shoulders], seconds: 30, heartRate: false, pattern: .hold),
            e("Chain Bench Press", .chest, ["Barbell", "Bench", "Weightlifting Chains"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Weighted Dip", .chest, ["Dip Station", "Dip Belt"], also: [.triceps, .shoulders], pattern: .verticalPush),
            e("Weighted Pull-Up", .back, ["Pull-Up Bar", "Dip Belt"], also: [.biceps], pattern: .verticalPull),
            e("Weighted Push-Up", .chest, ["Weight Vest"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Ruck", .fullBody, ["Weight Vest"], .duration,
              also: [.quads, .back], metrics: MetricProfile([.weight, .distance, .duration], distanceUnit: .miles), sets: 1, pattern: .carry),
            e("Mace 360", .shoulders, ["Macebell"], also: [.core, .back], pattern: .rotation),
            e("Steel Club Mill", .shoulders, ["Steel Club"], also: [.core], pattern: .rotation, laterality: .unilateral),
            e("Bulgarian Bag Spin", .fullBody, ["Bulgarian Bag"], also: [.shoulders, .core], pattern: .rotation),
            // A roll-up is a full up-and-down trip — 3 torches forearms.
            e("Wrist Roller Roll-Up", .biceps, ["Wrist Roller"], reps: 3, mechanic: .isolation),
            e("Neck Harness Extension", .shoulders, ["Neck Harness"], mechanic: .isolation),
            e("Gripper Close", .biceps, ["Hand Gripper"], mechanic: .isolation, laterality: .unilateral),
            // A bag round is boxing's three minutes, not a 45 s hold.
            e("Heavy Bag Rounds", .fullBody, ["Heavy Bag"], .duration, also: [.shoulders, .core], seconds: 180),
            e("Agility Ladder Drills", .fullBody, ["Agility Ladder"], .duration, also: [.calves, .quads]),
            e("Tibialis Raise", .calves, ["Tibialis Bar"], mechanic: .isolation),
            e("Slant Board Squat", .quads, ["Slant Board"], pattern: .squat),

            // MARK: Catalog expansion (gap audit, 2026-07-31)
            // Six gap clusters + depth behind the types that gated one
            // lone exercise. Same authoring rules as the whole table.

            // Calisthenics progressions + skills. Rings and the
            // suspension trainer stop being one-exercise gear.
            e("Pistol Squat", .quads, [], also: [.glutes, .core], reps: 5, pattern: .squat, laterality: .unilateral),
            e("Cossack Squat", .quads, [], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Incline Push-Up", .chest, [], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Knee Push-Up", .chest, [], also: [.triceps, .shoulders], pattern: .horizontalPush),
            // An inverted row hangs under a racked bar (the squat-family
            // convention names the rack).
            e("Inverted Row", .back, ["Barbell", "Squat Rack"], also: [.biceps], pattern: .horizontalPull),
            e("Dead Hang", .back, ["Pull-Up Bar"], .duration, also: [.biceps], seconds: 30, heartRate: false, pattern: .hold),
            e("Scapular Pull-Up", .back, ["Pull-Up Bar"], mechanic: .isolation),
            e("Wall Handstand Hold", .shoulders, [], .duration, also: [.core], seconds: 30, heartRate: false, pattern: .hold),
            e("Handstand Push-Up", .shoulders, [], also: [.triceps], reps: 5, pattern: .verticalPush),
            e("Ring Dip", .chest, ["Gymnastic Rings"], also: [.triceps, .shoulders], pattern: .verticalPush),
            e("Ring Muscle-Up", .back, ["Gymnastic Rings"], also: [.biceps, .chest, .triceps], reps: 3, pattern: .verticalPull),
            e("Bar Muscle-Up", .back, ["Pull-Up Bar"], also: [.biceps, .chest, .triceps], reps: 3, pattern: .verticalPull),
            e("Ring Support Hold", .shoulders, ["Gymnastic Rings"], .duration, also: [.triceps, .core], seconds: 20, heartRate: false, pattern: .hold),
            e("L-Sit", .core, [], .duration, also: [.shoulders], seconds: 20, heartRate: false, pattern: .hold),
            e("Superman", .back, [], also: [.glutes], pattern: .hinge),
            e("Bear Crawl", .fullBody, [], .duration, also: [.shoulders, .core], seconds: 30),
            e("Broad Jump", .fullBody, [], also: [.quads, .glutes], reps: 3, pattern: .jump),

            // Olympic lifting: the bar's technical lifts, prescribed the
            // way they're trained — doubles and triples, never a 10-floor.
            e("Snatch", .fullBody, ["Barbell"], also: [.quads, .back, .shoulders], reps: 2, pattern: .hinge),
            e("Clean and Jerk", .fullBody, ["Barbell"], also: [.quads, .back, .shoulders], reps: 2, pattern: .hinge),
            e("Hang Power Clean", .fullBody, ["Barbell"], also: [.quads, .back], reps: 3, pattern: .hinge),
            e("Overhead Squat", .quads, ["Barbell", "Squat Rack"], also: [.shoulders, .core], reps: 5, pattern: .squat),
            e("Front Rack Lunge", .quads, ["Barbell", "Squat Rack"], also: [.glutes, .core], pattern: .lunge, laterality: .unilateral),
            e("Wall Ball", .fullBody, ["Medicine Ball"], also: [.quads, .shoulders], pattern: .squat),

            // Everyday staples the catalog was oddly missing.
            e("Lunge", .quads, [], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Barbell Lunge", .quads, ["Barbell", "Squat Rack"], also: [.glutes, .hamstrings], pattern: .lunge, laterality: .unilateral),
            e("Split Squat", .quads, ["Dumbbells"], also: [.glutes], pattern: .lunge, laterality: .unilateral),
            e("Lateral Lunge", .quads, [], also: [.glutes], pattern: .lunge, laterality: .unilateral),
            e("Floor Press", .chest, ["Barbell"], also: [.triceps], pattern: .horizontalPush),
            e("Dumbbell Floor Press", .chest, ["Dumbbells"], also: [.triceps], pattern: .horizontalPush),
            e("Rack Pull", .back, ["Barbell", "Squat Rack"], also: [.glutes, .hamstrings], reps: 5, pattern: .hinge),
            e("Zercher Squat", .quads, ["Barbell", "Squat Rack"], also: [.glutes, .core], pattern: .squat),
            e("Decline Dumbbell Press", .chest, ["Dumbbells", "Decline Bench"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Reverse Curl", .biceps, ["EZ Bar"], mechanic: .isolation),
            e("Wrist Curl", .biceps, ["Dumbbells", "Bench"], mechanic: .isolation),
            e("Reverse Wrist Curl", .biceps, ["Dumbbells", "Bench"], mechanic: .isolation),
            e("Reverse Crunch", .core, [], mechanic: .isolation),
            e("Dumbbell Side Bend", .core, ["Dumbbells"], mechanic: .isolation, laterality: .unilateral),
            e("Close-Grip Lat Pulldown", .back, ["Lat Pulldown Machine"], also: [.biceps], pattern: .verticalPull),
            e("Leg Press Calf Raise", .calves, ["Leg Press Machine"], mechanic: .isolation),

            // Kettlebell depth: one bell covers a whole session.
            e("Kettlebell Press", .shoulders, ["Kettlebell"], also: [.triceps, .core], pattern: .verticalPush, laterality: .unilateral),
            e("Kettlebell Row", .back, ["Kettlebell"], also: [.biceps], pattern: .horizontalPull, laterality: .unilateral),
            e("Kettlebell Deadlift", .back, ["Kettlebell"], also: [.glutes, .hamstrings], pattern: .hinge),
            e("Kettlebell Front Rack Squat", .quads, ["Kettlebell"], also: [.glutes, .core], pattern: .squat),
            e("Kettlebell Halo", .shoulders, ["Kettlebell"], also: [.core], pattern: .rotation),

            // Prehab: the Shoulder Care pool gets real depth, and the
            // hips and adductors join it.
            e("Band External Rotation", .shoulders, ["Resistance Band"], mechanic: .isolation, laterality: .unilateral),
            e("Cable External Rotation", .shoulders, ["Cable Machine"], mechanic: .isolation, laterality: .unilateral),
            e("Clamshell", .glutes, [], mechanic: .isolation, laterality: .unilateral),
            e("Copenhagen Plank", .core, ["Bench"], .duration, also: [.quads], seconds: 20, heartRate: false, pattern: .hold, laterality: .unilateral),
            e("YTW Raise", .shoulders, ["Incline Bench", "Dumbbells"], also: [.back], mechanic: .isolation),
            e("Scapular Push-Up", .chest, [], also: [.shoulders], mechanic: .isolation),

            // Conditioning drills + the dumbbell complexes (the
            // compound sweep — a thruster's whole extended family).
            e("Jumping Jacks", .fullBody, [], .duration, also: [.calves], seconds: 30),
            e("High Knees", .fullBody, [], .duration, also: [.quads, .calves], seconds: 30),
            e("Butt Kicks", .fullBody, [], .duration, also: [.hamstrings, .calves], seconds: 30),
            e("Squat Thrust", .fullBody, [], also: [.quads, .chest]),
            e("Renegade Row", .back, ["Dumbbells"], also: [.core, .chest, .biceps], pattern: .horizontalPull, laterality: .unilateral),
            e("Man Maker", .fullBody, ["Dumbbells"], also: [.chest, .back, .shoulders], reps: 5),
            e("Devil Press", .fullBody, ["Dumbbells"], also: [.shoulders, .chest], reps: 5),
            e("Dumbbell Snatch", .fullBody, ["Dumbbells"], also: [.shoulders, .glutes], reps: 5, pattern: .hinge, laterality: .unilateral),
            e("Dumbbell Clean and Press", .fullBody, ["Dumbbells"], also: [.quads, .shoulders], reps: 5, pattern: .hinge),

            // Depth behind the one-exercise types.
            e("Trap Bar Carry", .fullBody, ["Trap Bar"], .duration, also: [.back, .core], pattern: .carry),
            e("Trap Bar Shrug", .shoulders, ["Trap Bar"], also: [.back], mechanic: .isolation),
            e("Sandbag Clean", .fullBody, ["Sandbag"], also: [.quads, .back], reps: 5, pattern: .hinge),
            e("Sandbag Squat", .quads, ["Sandbag"], also: [.glutes, .core], pattern: .squat),
            e("Sandbag Over Shoulder", .fullBody, ["Sandbag"], also: [.back, .quads], reps: 5, pattern: .hinge),
            e("Sled Drag", .fullBody, ["Sled"], .duration, also: [.quads, .glutes], pattern: .carry),
            e("Backward Sled Drag", .quads, ["Sled"], .duration, also: [.calves], pattern: .carry),
            e("Landmine Squat", .quads, ["Barbell", "Landmine"], also: [.glutes], pattern: .squat),
            e("Landmine Rotation", .core, ["Barbell", "Landmine"], also: [.shoulders], pattern: .rotation),
            e("Landmine Romanian Deadlift", .hamstrings, ["Barbell", "Landmine"], also: [.glutes, .back], pattern: .hinge),
            e("Suspension Chest Press", .chest, ["Suspension Trainer"], also: [.triceps, .shoulders], pattern: .horizontalPush),
            e("Suspension Pike", .core, ["Suspension Trainer"], also: [.shoulders], mechanic: .isolation),
            e("Suspension Face Pull", .shoulders, ["Suspension Trainer"], also: [.back], pattern: .horizontalPull),
            e("Suspension Hamstring Curl", .hamstrings, ["Suspension Trainer"], also: [.glutes], mechanic: .isolation),
            e("Battle Rope Slams", .fullBody, ["Battle Ropes"], .duration, also: [.core, .shoulders], seconds: 30),

            // ⚠️ No bare "Swimming" row. The expansion round (#494) and the
            // cardio push (#478) added swimming independently; this merge
            // keeps the cardio pair — Pool Swim / Open Water Swim, above —
            // because they carry what #478 built swimming ON: yard lengths,
            // the per-100 `PaceReference`, and the authored `.swimming`
            // modality that files it to Health as swimming. Neither row had
            // shipped in a build, so nothing in any store loses a name.

            // MARK: Stretches + mobility
            // Warmup and cooldown work, first-class (Dave, 2026-07-11:
            // "finish with stretching, sometimes at the start after a
            // warmup"). No new primitives: a static stretch is a timed
            // HOLD (.duration → .durationOnly, run as an auto-timer on the
            // set screen); a dynamic drill is rep-based (default type →
            // .repsOnly). Each carries its TARGET muscle so it lives in
            // the same equipment⇢exercise⇢routine graph and surfaces in
            // the library search — hip openers cluster under glutes, neck
            // rides shoulders and forearm/biceps under biceps, matching
            // how the catalog already files adduction/neck/grip work.
            // All bodyweight, so they reach everyone and add no gear.
            // Static holds (timed): the `stretch` shape — ONE 30 s hold,
            // no HR prescription (config audit, 2026-07-15). Repeats
            // stay one Sets-tap away.
            stretch("Standing Hamstring Stretch", .hamstrings, sides: .unilateral),
            stretch("Standing Quad Stretch", .quads, sides: .unilateral),
            stretch("Kneeling Hip Flexor Stretch", .quads, sides: .unilateral),
            stretch("Figure-Four Stretch", .glutes, sides: .unilateral),
            stretch("Pigeon Pose", .glutes, sides: .unilateral),
            stretch("Butterfly Stretch", .glutes),
            stretch("Standing Calf Stretch", .calves, sides: .unilateral),
            stretch("Downward Dog", .fullBody),
            stretch("Doorway Chest Stretch", .chest),
            stretch("Cross-Body Shoulder Stretch", .shoulders, sides: .unilateral),
            stretch("Neck Stretch", .shoulders, sides: .unilateral),
            stretch("Overhead Triceps Stretch", .triceps, sides: .unilateral),
            stretch("Standing Biceps Stretch", .biceps, sides: .unilateral),
            stretch("Child's Pose", .back),
            stretch("Seated Spinal Twist", .back, sides: .unilateral),
            stretch("Lat Stretch", .back, sides: .unilateral),
            stretch("Cobra Stretch", .core),
            stretch("Standing Side Bend Stretch", .core, sides: .unilateral),
            stretch("Deep Squat Hold", .glutes),
            // Dynamic warmup drills: the `mobility` shape — one pass of
            // reps through a warmup, not a 3-set block.
            mobility("Arm Circles", .shoulders),
            mobility("Leg Swings", .hamstrings, sides: .unilateral),
            mobility("Hip Circles", .glutes),
            mobility("Walking Knee Hug", .glutes),
            mobility("Standing Torso Twist", .core),
            mobility("Cat-Cow", .back),
            mobility("World's Greatest Stretch", .fullBody, sides: .unilateral),
            mobility("Inchworm", .fullBody),
            mobility("Ankle Circles", .calves),
            mobility("Wrist Circles", .biceps),
            mobility("Glute Bridge March", .glutes),
            mobility("90/90 Hip Switch", .glutes),
            mobility("Thread the Needle", .back, sides: .unilateral),
            // Dislocates ride a band, and the band is loadable — the
            // explicit reps profile keeps derivation from stamping
            // weight×reps onto a mobility drill.
            e("Shoulder Dislocates", .shoulders, ["Resistance Band"], also: [.chest], metrics: .repsOnly, sets: 1, heartRate: false, modality: .flexibility, mechanic: nil),
            // Foam rolls: recovery passes on the roller, the stretch
            // shape (one 30 s pass, no heart-rate prescription).
            roll("Foam Roll Quads", .quads),
            roll("Foam Roll Hamstrings", .hamstrings),
            roll("Foam Roll Calves", .calves),
            roll("Foam Roll Upper Back", .back),
            roll("Foam Roll Lats", .back),
            roll("Foam Roll IT Band", .quads),
        ]
    }()

    /// The catalog's profile for a built-in exercise — the fallback
    /// `Exercise.metricProfile` resolves through when no per-store
    /// customization exists, so existing stores pick up rich profiles
    /// with zero migration writes.
    private static let builtInProfilesByName: [String: MetricProfile] = {
        Dictionary(uniqueKeysWithValues: builtInExerciseDefinitions.map { def in
            (def.name, def.metrics ?? suggestedProfile(type: def.exerciseType, equipmentNames: def.equipmentNames))
        })
    }()

    static func builtInProfile(named name: String) -> MetricProfile? {
        builtInProfilesByName[name]
    }
}
