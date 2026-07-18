import Foundation

/// Per-turn micro-recipes: one deterministic line injected into the
/// PROMPT channel when the user's message matches a topic — skills
/// scaled to a 4,096-token window. The build-91 field round showed the
/// 3B still fumbles its FIRST tool pick from standing instructions
/// alone ("What equipment do I have?" opened with a routines lookup
/// and narrated the noise); a recipe naming the right tool at the
/// point of need is the cheapest reliable steer. Hand-authored and
/// keyword-triggered: unmatched turns pay zero tokens, and a recipe is
/// a FIXED string — never interpolated user input (the injection rule).
enum OperatorRecipes {
    /// First match wins, so order is priority. Keywords are
    /// case-insensitive substrings of the user's message.
    private static let table: [(keywords: [String], recipe: String)] = [
        // Gear before everything: "equipment" questions were the
        // field-proven wrong-first-tool case.
        (
            ["equipment", "gear", "kit"],
            "gear lives in libraries; find_items kind library lists each kit's gear, the active one is the user's; add_gear and remove_gear edit it"
        ),
        // Tracking conversions before schedule/stats: "duration" must
        // not fall through to a lesser match.
        (
            ["duration", "track", "rep-based", "rep based"],
            "tracking conversions use convert_tracking; nameContains selects many exercises at once"
        ),
        (
            ["superset"],
            "form_superset groups exercises within one routine; delete_item kind superset dissolves one"
        ),
        // History numbers before schedule: "how many workouts last
        // week" is a stats question, not a schedule one.
        (
            ["streak", "how many", "last time", "last done", "volume"],
            "history numbers come from get_stats only; never estimate"
        ),
        (
            ["schedule", "week"],
            "find_items kind routine shows each routine's days; set_schedule changes them"
        ),
    ]

    /// The recipe line for a user message, nil when no topic matches
    /// (most turns; the injection costs nothing then).
    static func recipe(for message: String) -> String? {
        let lowered = message.lowercased()
        return table.first { entry in
            entry.keywords.contains { lowered.contains($0) }
        }?.recipe
    }
}
