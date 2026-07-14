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
        "You're the main branch.",
        "Ship it. 🚢",
        "No conflicts to merge.",
        // Body / gym
        "Hydrate, then conquer. 🚰",
        "Drink some water. 🚰",
        "Rest is part of the program.",
        "The bar misses you. 🏋️",
        "Stronger than yesterday.",
        // Warm / whimsy / lore
        "Look who showed up. 👀",
        "Future you says thanks.",
        "The machines are impressed. 🤖",
        "Small reps, big you.",
    ]

    static func random() -> String { all.randomElement() ?? "you++" }
}
