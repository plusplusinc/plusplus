import Foundation
import PlusPlusKit

/// Hidden search terms for built-in catalog names (2026-07-31): what
/// people actually type when they mean an item whose canonical name
/// says it differently — "erg" for the Rowing Machine, "rdl" for the
/// Romanian Deadlift, "trx" for the Suspension Trainer. Never shown;
/// only folded into the search haystacks (`ExerciseFilterState.
/// searchHaystack`, the equipment scorer) so typing reaches the row.
/// Name-keyed like `FormCues`/`equipmentCategories`; the accounting
/// test keeps every key resolving to a real catalog name.
///
/// Authoring rules:
/// - Every entry earns its place: a term goes in only if someone
///   genuinely types it AND the name/muscle/category haystack doesn't
///   already reach it (prefix and typo tiers cover a lot).
/// - Genericized brand terms (trx, stairmaster, bosu) are fine HERE —
///   the #222 no-brands rule governs catalog NAMES, and a hidden term
///   is exactly where "the word everyone uses" belongs.
/// - Families ride the derived pass, not forty hand rows: any name
///   containing "Kettlebell" answers "kb", "Dumbbell" answers "db",
///   "Suspension" answers "trx".
enum CatalogSearchSynonyms {

    /// Exercise name → space-separated hidden terms.
    static let exercise: [String: String] = [
        // Abbreviations lifters type
        "Romanian Deadlift": "rdl",
        "Dumbbell Romanian Deadlift": "rdl",
        "Single-Leg Romanian Deadlift": "rdl",
        "Landmine Romanian Deadlift": "rdl",
        "Overhead Press": "ohp strict press military press",
        "Overhead Squat": "ohs",
        "Handstand Push-Up": "hspu pushup",
        "Turkish Get-Up": "tgu getup",
        "Glute-Ham Raise": "ghr",
        "Nordic Curl": "nordic ham curl",
        "Bulgarian Split Squat": "rfess rear foot elevated",
        // Hyphen-collapsed forms people type as one word
        "Push-Up": "pushup",
        "Pull-Up": "pullup",
        "Chin-Up": "chinup",
        "Sit-Up": "situp",
        // Alternate common names
        "Skull Crusher": "lying triceps extension",
        "Chest-Supported Row": "seal row",
        "Pec Deck": "chest fly machine butterfly",
        "Pallof Press": "anti rotation press",
        "Farmer's Carry": "farmers walk",
        "Inverted Row": "australian pull up bodyweight row",
        "Lunge": "forward lunge",
        "Split Squat": "static lunge",
        "Lateral Lunge": "side lunge",
        "Pistol Squat": "single leg squat",
        "Wrist Curl": "forearm curl",
        "Reverse Wrist Curl": "forearm extension",
        "Copenhagen Plank": "adductor side plank",
        "Band External Rotation": "rotator cuff",
        "Cable External Rotation": "rotator cuff",
        "Shoulder Dislocates": "pass through",
        "Jumping Jacks": "star jumps",
        "Broad Jump": "standing long jump",
        // Dave's compound family, reachable by any of its names
        "Dumbbell Thruster": "squat thrust squat to press",
        "Thruster": "squat to press",
        "Devil Press": "dumbbell squat thrust burpee press",
        "Squat Thrust": "burpee",
        "Renegade Row": "plank row commando row push up row",
        "Man Maker": "manmaker",
        // Cardio the console names differently
        "Rowing": "erg ergometer rower",
        "Assault Bike": "air fan bike",
        "Indoor Cycling": "spin stationary bike",
        "Cycling": "bike biking",
        "Running": "run jog jogging",
        "Pool Swim": "laps",
        "Jump Rope": "skipping",
        "Elliptical": "cross trainer",
        "Stair Climber": "stairmaster stairs",
        "Upper Body Ergometer": "arm bike ube",
        "Sled Push": "prowler push",
        "Sled Drag": "prowler drag",
        "Backward Sled Drag": "reverse prowler drag",
    ]

    /// Equipment name → space-separated hidden terms.
    static let equipment: [String: String] = [
        "Rowing Machine": "erg rower ergometer",
        "Ski Erg": "skierg",
        "Bicycle": "bike road outdoor",
        "Stationary Bike": "bike spin exercise",
        "Air Bike": "bike fan assault",
        "Treadmill": "running machine",
        "Elliptical": "cross trainer",
        "Stair Climber": "stairmaster stepmill",
        "Upper Body Ergometer": "arm bike ube",
        "Suspension Trainer": "trx straps",
        "Kettlebell": "kb bell",
        "Dumbbells": "db free weights",
        "Barbell": "bb bar",
        "EZ Bar": "curl bar",
        "Trap Bar": "hex bar",
        "Resistance Band": "bands mini loop",
        "Foam Roller": "roller rolling",
        "Ab Wheel": "ab roller",
        "Pull-Up Bar": "pullup chinup chin up",
        "Squat Rack": "power rack rig cage",
        "Cable Machine": "functional trainer pulley cables",
        "Sled": "prowler",
        "Jump Rope": "skipping speed rope",
        "Weight Plate": "plates bumper",
        "Weight Vest": "ruck vest",
        "Glute-Ham Developer": "ghd",
        "Medicine Ball": "med ball",
        "Slam Ball": "dead ball",
        "Stability Ball": "swiss ball exercise ball",
        "Balance Trainer": "bosu half ball",
        "Battle Ropes": "battling ropes",
        "Hand Gripper": "grip trainer",
    ]

    /// Authored terms + the derived family terms; "" when none.
    static func exerciseTerms(named name: String) -> String {
        var terms: [String] = []
        if let authored = exercise[name] { terms.append(authored) }
        if name.contains("Kettlebell") { terms.append("kb") }
        if name.contains("Dumbbell") { terms.append("db") }
        if name.contains("Suspension") { terms.append("trx") }
        return terms.joined(separator: " ")
    }

    static func equipmentTerms(named name: String) -> String {
        equipment[name] ?? ""
    }

    // MARK: - Fuzzy ranking beyond the catalog surfaces (#497)

    /// A name plus its hidden terms, for any fuzzy ranking that should
    /// answer what people TYPE rather than only what the catalog calls
    /// things. Returns the bare name when nothing is known about it, so
    /// it is safe to key on for mixed lists (routine and kit names pass
    /// straight through). Both tables are consulted because a few names
    /// are in each — "Jump Rope" is an exercise AND a piece of equipment.
    /// ⚠️ For RANKING a visible list only (a digest, a suggestion run),
    /// never for resolving one canonical name — see `bestMatch`, which
    /// scores the name and the terms separately for that reason.
    static func searchKey(for name: String) -> String {
        let terms = hiddenTerms(for: name)
        return terms.isEmpty ? name : "\(name) \(terms)"
    }

    /// `FuzzySearch.bestMatch` with the hidden terms in play — the same
    /// one-canonical-name contract, now reachable by "rdl". Used by
    /// Operator's READ paths; write-target resolution stays strict.
    ///
    /// ⚠️ This is a RESOLVER, not a ranker, and two things follow.
    /// A BLANK query resolves to nothing (`FuzzySearch.bestMatch`'s own
    /// guard): `ranked` passes items through unchanged when the query is
    /// blank, so `.first` would attribute a stat to an arbitrary
    /// exercise — a confidently wrong number.
    /// And the name is scored SEPARATELY from the hidden terms, never
    /// concatenated into one candidate: `FuzzySearch`'s coverage term
    /// divides by the candidate's token count, so a glued haystack
    /// PENALIZES a row for having synonyms. Concatenating made "bike"
    /// resolve to Cycling over Assault Bike, and the number would have
    /// been reported under the wrong name. A hidden-term hit is demoted
    /// to 0.75 like every other tolerant match in the app, so a literal
    /// hit always wins.
    static func bestMatch(query: String, in candidates: [String]) -> String? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var best: (name: String, score: Double)?
        for candidate in candidates {
            let literal = FuzzySearch.score(query: query, candidate: candidate)
            let terms = hiddenTerms(for: candidate)
            let hidden = terms.isEmpty
                ? nil
                : FuzzySearch.score(query: query, candidate: "\(candidate) \(terms)").map { $0 * 0.75 }
            guard let score = [literal, hidden].compactMap({ $0 }).max() else { continue }
            // Strictly greater keeps the incoming order on ties, matching
            // `FuzzySearch.ranked`'s stability.
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        return best?.name
    }

    /// The hidden terms alone, "" when the tables know nothing.
    private static func hiddenTerms(for name: String) -> String {
        [exerciseTerms(named: name), equipmentTerms(named: name)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
