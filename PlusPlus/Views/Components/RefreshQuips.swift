import Foundation

/// Little delight for a pull-to-refresh when there's nothing to sync (GitHub not
/// connected, so the gesture has no real work to do). The Slack move: instead of
/// a dead pull, a random friendly line. All obey the copy laws — no em dashes,
/// anti-shame, no obligation words — and lean into the `++` / increment identity.
enum RefreshQuip {
    static let all: [String] = [
        // Increment / code (most on-brand)
        "you++",
        "+1 to you.",
        "Nice increment.",
        "Commit to yourself.",
        "Incrementally yours.",
        "One more than before.",
        "Consistency compiles.",
        // Body / gym
        "Hydrate, then conquer. 🚰",
        "Rest is part of the program.",
        "Every rep counts.",
        "Keep stacking.",
        "Fuel up. 🍎",
        // Warm / progress / whimsy
        "Stronger than yesterday.",
        "Look who showed up. 👀",
        "Future you says thanks.",
        "Small reps, big you.",
        "Steady wins.",
        "Proud of you.",
        "Showing up is the whole thing.",
        "Momentum suits you.",
    ]

    static func random() -> String { all.randomElement() ?? "you++" }
}
