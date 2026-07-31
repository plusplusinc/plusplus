import Foundation

// Authored exercise attributes (catalog expansion, 2026-07-31): three
// facets the filter row and search reach, carried as columns on
// `SeedData.BuiltInExerciseDefinition` and resolved through
// `Exercise.catalogDefinition` — app-side static data, the
// `equipmentCategories` pattern. No model column, no migration, no
// interchange ripple; customs resolve nil on all three (we can't
// classify intent, the isLoadable rule).

/// The bucket a move files under on a program — what "hinge day" or
/// "add a vertical pull" means. Authored on compound strength rows;
/// isolation work may carry one where it genuinely reads as a pattern
/// (a cable woodchopper is rotation), and cardio rows carry none
/// (their identity is modality). The display name doubles as a hidden
/// search term, so typing "hinge" surfaces the deadlifts.
enum MovementPattern: String, CaseIterable, Identifiable {
    case squat, hinge, lunge
    case horizontalPush, verticalPush, horizontalPull, verticalPull
    case carry, rotation, hold, jump

    var id: Self { self }

    var displayName: String {
        switch self {
        case .squat: "Squat"
        case .hinge: "Hinge"
        case .lunge: "Lunge"
        case .horizontalPush: "Horizontal push"
        case .verticalPush: "Vertical push"
        case .horizontalPull: "Horizontal pull"
        case .verticalPull: "Vertical pull"
        case .carry: "Carry"
        case .rotation: "Rotation"
        case .hold: "Hold"
        case .jump: "Jump"
        }
    }
}

/// Programming semantics, not strict joint-count: a compound is a
/// multi-muscle movement you'd build a session around; an isolation is
/// a single-focus accessory. Core flexion work (crunches, leg raises)
/// files as isolation on that reading. nil = unclassified — the
/// stretch/mobility/foam-roll rows, where the question doesn't apply.
enum ExerciseMechanic: String, CaseIterable, Identifiable {
    case compound, isolation

    var id: Self { self }

    var displayName: String { rawValue.capitalized }
}

/// Whether the work loads one side at a time. The authoring rule:
/// unilateral means a SET belongs to a side (single-arm rows, split
/// squats, suitcase carries, per-side stretches); a drill that merely
/// alternates limbs within one set (dead bug, walking knee hug) stays
/// bilateral.
enum ExerciseLaterality: String, CaseIterable, Identifiable {
    case bilateral, unilateral

    var id: Self { self }

    var displayName: String { rawValue.capitalized }
}
