import Foundation
import SwiftData
import PlusPlusKit

/// The built-in EQUIPMENT catalog: what gear exists, what kind each
/// piece is, which pieces hold load, and what a piece implies an
/// exercise tracks. Split out of SeedData 2026-08-02 (#499) — seeding
/// and the one-shot migrations stayed there, the exercise definitions
/// went to ExerciseCatalog.swift, and this is the gear half.
extension SeedData {

    // MARK: - Equipment

    // Generic types only, no brand names (#222 — compiled from a sweep
    // of Rogue/Rep/Titan home-gym catalogs and Hammer Strength /
    // Life Fitness / Precor-class commercial lines). Inclusion rule: an
    // item qualifies only if some exercise can genuinely REQUIRE it;
    // pure accessories (straps, chalk, collars, bracing belts) stay
    // out. Near-synonyms map to one type (functional trainer → Cable
    // Machine, prowler → Sled, power tower → its stations, buffalo bar
    // → Cambered Squat Bar). The top-up seeder delivers newcomers to
    // existing stores catalog-only and un-owned (#95).
    static var builtInEquipment: [Equipment] {
        [
            // Free weights + bars
            "Barbell", "EZ Bar", "Trap Bar", "Dumbbells", "Kettlebell",
            "Weight Plate", "Sandbag",
            // Specialty bars
            "Safety Squat Bar", "Swiss Bar", "Cambered Squat Bar",
            "Axle Bar",
            // Racks, benches, stations
            "Squat Rack", "Bench", "Incline Bench", "Decline Bench",
            "Preacher Bench", "Dip Station", "Pull-Up Bar",
            "Back Extension Bench", "Glute-Ham Developer",
            "Reverse Hyper Machine", "Nordic Bench", "Sissy Squat Bench",
            "Captain's Chair", "Plyo Box", "Landmine",
            // Machines — plate-loaded
            "Smith Machine", "T-Bar Row Machine", "Belt Squat Machine",
            "Pendulum Squat Machine", "Pullover Machine",
            // Machines — cable + selectorized
            "Cable Machine", "Leg Press Machine",
            "Lat Pulldown Machine", "Leg Extension Machine",
            "Leg Curl Machine", "Calf Raise Machine", "Hack Squat Machine",
            "Hip Thrust Machine", "Pec Deck Machine", "Chest Press Machine",
            "Shoulder Press Machine", "Seated Row Machine",
            "Hip Abduction Machine", "Hip Adduction Machine",
            "Assisted Pull-Up Machine", "Ab Crunch Machine",
            "Torso Rotation Machine", "Lateral Raise Machine",
            "Bicep Curl Machine", "Tricep Extension Machine",
            "Low Back Extension Machine", "Multi-Hip Machine",
            "Glute Kickback Machine",
            // Cardio (Bicycle = the road bike, like the Weight Vest for
            // Ruck: outdoor gear an exercise genuinely requires)
            "Rowing Machine", "Stationary Bike", "Treadmill", "Air Bike",
            "Ski Erg", "Elliptical", "Stair Climber", "Vertical Climber",
            "Upper Body Ergometer", "Bicycle",
            // Strongman
            "Sled", "Yoke", "Farmers Walk Handles", "Log Bar",
            "Atlas Stone", "Circus Dumbbell", "Husafell Stone", "Tire",
            "Sledgehammer",
            // Gymnastics + calisthenics
            "Suspension Trainer", "Gymnastic Rings", "Parallettes",
            "Climbing Rope", "Peg Board", "Stall Bars",
            // Small equipment
            "Battle Ropes", "Jump Rope", "Medicine Ball", "Slam Ball",
            "Stability Ball", "Balance Trainer", "Ab Wheel",
            "Resistance Band", "Weightlifting Chains", "Dip Belt",
            "Weight Vest", "Sliders", "Macebell", "Steel Club",
            "Bulgarian Bag", "Wrist Roller", "Neck Harness",
            "Hand Gripper", "Heavy Bag", "Agility Ladder",
            "Tibialis Bar", "Slant Board", "Foam Roller",
        ].map { Equipment(name: $0, isBuiltIn: true) }
    }

    // MARK: - Equipment categories (the catalog's type facet, 2026-07-17)

    /// The equipment catalog's type buckets — user-facing chip labels.
    /// App-side static data like `equipmentProfiles`: no model column,
    /// no migration, no interchange ripple. Customs carry no category
    /// and drop out under a type chip.
    enum EquipmentCategory: String, CaseIterable {
        case freeWeights = "Free weights"
        case machines = "Machines"
        case bandsStraps = "Bands & straps"
        case cardio = "Cardio"
        case bodyweightGear = "Bodyweight equipment"
    }

    /// Every built-in name maps to exactly one category (accounting
    /// enforced by `SeedDataTests` so catalog growth can't silently
    /// skip the facet). Findability rules: a name containing "Machine"
    /// buckets under Machines EXCEPT the Rowing Machine (purpose wins —
    /// it's cardio); strongman implements, thrown/carried loads, and
    /// loading accessories are Free weights; benches, racks, stations,
    /// and bodyweight floor tools are Bodyweight equipment.
    static let equipmentCategories: [String: EquipmentCategory] = {
        var table: [String: EquipmentCategory] = [:]
        let buckets: [(EquipmentCategory, [String])] = [
            (.freeWeights, [
                "Barbell", "EZ Bar", "Trap Bar", "Dumbbells", "Kettlebell",
                "Weight Plate", "Sandbag", "Safety Squat Bar", "Swiss Bar",
                "Cambered Squat Bar", "Axle Bar", "Landmine",
                "Sled", "Yoke", "Farmers Walk Handles", "Log Bar",
                "Atlas Stone", "Circus Dumbbell", "Husafell Stone", "Tire",
                "Sledgehammer", "Weightlifting Chains", "Macebell",
                "Steel Club", "Bulgarian Bag", "Medicine Ball", "Slam Ball",
                "Dip Belt", "Weight Vest", "Wrist Roller",
            ]),
            (.machines, [
                "Smith Machine", "T-Bar Row Machine", "Belt Squat Machine",
                "Pendulum Squat Machine", "Pullover Machine", "Cable Machine",
                "Leg Press Machine", "Lat Pulldown Machine",
                "Leg Extension Machine", "Leg Curl Machine",
                "Calf Raise Machine", "Hack Squat Machine",
                "Hip Thrust Machine", "Pec Deck Machine",
                "Chest Press Machine", "Shoulder Press Machine",
                "Seated Row Machine", "Hip Abduction Machine",
                "Hip Adduction Machine", "Assisted Pull-Up Machine",
                "Ab Crunch Machine", "Torso Rotation Machine",
                "Lateral Raise Machine", "Bicep Curl Machine",
                "Tricep Extension Machine", "Low Back Extension Machine",
                "Multi-Hip Machine", "Glute Kickback Machine",
                "Reverse Hyper Machine",
            ]),
            (.cardio, [
                "Rowing Machine", "Stationary Bike", "Treadmill", "Air Bike",
                "Ski Erg", "Elliptical", "Stair Climber", "Vertical Climber",
                "Upper Body Ergometer", "Bicycle", "Jump Rope",
                "Battle Ropes", "Agility Ladder", "Heavy Bag",
            ]),
            (.bandsStraps, [
                "Suspension Trainer", "Gymnastic Rings", "Resistance Band",
                "Climbing Rope",
            ]),
            (.bodyweightGear, [
                "Squat Rack", "Bench", "Incline Bench", "Decline Bench",
                "Preacher Bench", "Dip Station", "Pull-Up Bar",
                "Back Extension Bench", "Glute-Ham Developer", "Nordic Bench",
                "Sissy Squat Bench", "Captain's Chair", "Plyo Box",
                "Parallettes", "Peg Board", "Stall Bars", "Stability Ball",
                "Balance Trainer", "Ab Wheel", "Sliders", "Neck Harness",
                "Hand Gripper", "Tibialis Bar", "Slant Board", "Foam Roller",
            ]),
        ]
        for (category, names) in buckets {
            for name in names { table[name] = category }
        }
        return table
    }()

    static func equipmentCategory(named name: String) -> EquipmentCategory? {
        equipmentCategories[name]
    }

    // MARK: - Equipment configuration (#236)

    /// Which built-ins are incrementally LOADABLE — plates, pins,
    /// bells, stacks, or a stepped rating that IS the load (bands and
    /// grippers are sold in lb ratings) — and therefore get a
    /// weight-step option. A bench holds you; a barbell holds plates.
    /// Custom equipment always shows the option (the user created it;
    /// we can't classify intent).
    static let loadableEquipmentNames: Set<String> = [
        "Barbell", "EZ Bar", "Trap Bar", "Safety Squat Bar", "Swiss Bar",
        "Cambered Squat Bar", "Axle Bar", "Log Bar", "Dumbbells",
        "Kettlebell", "Weight Plate", "Sandbag", "Circus Dumbbell",
        "Atlas Stone", "Husafell Stone", "Macebell", "Steel Club",
        "Bulgarian Bag", "Slam Ball", "Medicine Ball", "Weight Vest",
        "Dip Belt", "Weightlifting Chains", "Wrist Roller", "Neck Harness",
        "Landmine", "Sled", "Yoke", "Farmers Walk Handles", "Tibialis Bar",
        "Reverse Hyper Machine", "Resistance Band", "Hand Gripper",
        "Smith Machine", "Cable Machine", "Leg Press Machine",
        "Lat Pulldown Machine", "Leg Extension Machine", "Leg Curl Machine",
        "Calf Raise Machine", "Hack Squat Machine", "Hip Thrust Machine",
        "Pec Deck Machine", "Chest Press Machine", "Shoulder Press Machine",
        "Seated Row Machine", "T-Bar Row Machine", "Belt Squat Machine",
        "Pendulum Squat Machine", "Pullover Machine", "Hip Abduction Machine",
        "Hip Adduction Machine", "Assisted Pull-Up Machine",
        "Ab Crunch Machine", "Torso Rotation Machine", "Lateral Raise Machine",
        "Bicep Curl Machine", "Tricep Extension Machine",
        "Low Back Extension Machine", "Multi-Hip Machine",
        "Glute Kickback Machine",
    ]

    /// Whether the given equipment's detail screen offers weight-step
    /// configuration (#236: config adapts to the equipment). Custom gear
    /// with a declared exercise-config profile is loadable only when
    /// that profile tracks load — a custom spin bike whose exercises
    /// track duration/resistance has no plates to step. Undeclared
    /// customs keep the old always-loadable default (we can't classify
    /// the user's intent).
    static func isLoadable(_ equipment: Equipment) -> Bool {
        if equipment.isBuiltIn { return loadableEquipmentNames.contains(equipment.name) }
        guard let profile = equipment.suggestedProfile else { return true }
        return profile.tracksLoad
    }

    // MARK: - Metric profiles (flexible metrics)

    /// Suggested profiles for gear whose exercises track more than the
    /// classic weight×reps pair — cardio machines (the console's real
    /// dials), assisted machines (a stack that helps instead of loads),
    /// carry implements (load over ground), the plyo box (height). The
    /// evaluation that produced these lives in the feature's design
    /// notes; every entry answers "what does a lifter actually set and
    /// read on this thing".
    static let equipmentProfiles: [String: MetricProfile] = [
        // Ergs: pieces are distance-first (2000 m), splits per 500 m,
        // damper as the setting.
        "Rowing Machine": MetricProfile([.distance, .duration, .pace, .resistance]),
        "Ski Erg": MetricProfile([.distance, .duration, .pace, .resistance]),
        // The air bike prescribes in calories and punishes in watts.
        "Air Bike": MetricProfile([.duration, .calories, .power]),
        "Stationary Bike": MetricProfile([.duration, .distance, .resistance, .power], distanceUnit: .miles),
        "Bicycle": MetricProfile([.distance, .duration, .speed], distanceUnit: .miles),
        "Treadmill": MetricProfile([.distance, .duration, .speed, .incline], distanceUnit: .miles),
        "Elliptical": MetricProfile([.duration, .resistance, .incline]),
        "Stair Climber": MetricProfile([.duration, .resistance]),
        "Vertical Climber": MetricProfile([.duration]),
        "Upper Body Ergometer": MetricProfile([.duration, .resistance]),
        // The stack subtracts: less assistance IS the progression.
        "Assisted Pull-Up Machine": MetricProfile([.assistance, .reps]),
        "Plyo Box": MetricProfile([.height, .reps]),
        // Carries: load over ground — meters, like the strongman events.
        "Sled": MetricProfile([.weight, .distance, .duration]),
        "Yoke": MetricProfile([.weight, .distance, .duration]),
        "Farmers Walk Handles": MetricProfile([.weight, .distance, .duration]),
        "Husafell Stone": MetricProfile([.weight, .distance, .duration]),
        "Jump Rope": MetricProfile([.duration]),
        "Battle Ropes": MetricProfile([.duration]),
        "Heavy Bag": MetricProfile([.duration]),
        "Agility Ladder": MetricProfile([.duration]),
    ]

    static func equipmentProfile(named name: String) -> MetricProfile? {
        equipmentProfiles[name]
    }

    /// What a new exercise on this gear should track — the shared
    /// derivation for the built-in catalog AND the editor's prefill:
    /// union the gear's declared profiles, add weight when anything is
    /// loadable (unless assistance already speaks for the load), and
    /// guarantee a work metric from the legacy type when the union
    /// doesn't provide one.
    static func mergeSuggestedProfiles(_ matched: [MetricProfile], hasLoadable: Bool, type: ExerciseType) -> MetricProfile {
        guard !matched.isEmpty else {
            if type == .duration {
                return hasLoadable ? MetricProfile([.weight, .duration]) : .durationOnly
            }
            return hasLoadable ? .weightReps : .repsOnly
        }
        var metrics = matched.flatMap(\.metrics)
        let distanceUnit = matched.first {
            $0.metrics.contains(where: [.distance, .pace, .speed].contains)
        }?.distanceUnit ?? .meters
        if hasLoadable, !metrics.contains(.assistance) {
            metrics.append(.weight)
        }
        var profile = MetricProfile(metrics, distanceUnit: distanceUnit)
        if !profile.isValid {
            profile = MetricProfile(
                profile.metrics + [type == .duration ? .duration : .reps],
                distanceUnit: distanceUnit
            )
        }
        return profile
    }

    /// Table-backed derivation for built-in definitions (names only).
    static func suggestedProfile(type: ExerciseType, equipmentNames: [String]) -> MetricProfile {
        mergeSuggestedProfiles(
            equipmentNames.compactMap { equipmentProfiles[$0] },
            hasLoadable: equipmentNames.contains(where: loadableEquipmentNames.contains),
            type: type
        )
    }

    /// Live-model derivation for the editor's prefill — custom gear's
    /// declared profiles participate alongside the built-in table.
    static func suggestedProfile(type: ExerciseType, equipment: [Equipment]) -> MetricProfile {
        mergeSuggestedProfiles(
            equipment.compactMap(\.suggestedProfile),
            hasLoadable: equipment.contains(where: isLoadable),
            type: type
        )
    }
}
