import Foundation

/// A tappable example prompt above the input bar. Hand-authored and
/// chosen DETERMINISTICALLY from app state — no model call, no
/// hallucination surface; the chips teach what Operator can do and
/// make the view-context feature visible.
///
/// The pill's text IS the prompt it sends, verbatim (Dave, build-85
/// design round: what you tap is what you say) — so every string here
/// must read well on a pill AND dispatch well on the 3B model.
struct OperatorChip: Identifiable, Equatable {
    let text: String
    var id: String { text }
}

enum OperatorChips {
    /// 2–3 chips for the current state. `detail` is the ViewContext
    /// detail line (nil at a tab root).
    static func chips(tab: String, detail: String?, hasHistory: Bool) -> [OperatorChip] {
        var chips: [OperatorChip] = []

        // The visible screen gets the first, most specific slot.
        if let detail, detail.hasPrefix("routines/") {
            let name = String(detail.dropFirst("routines/".count))
            chips.append(OperatorChip(text: "Which muscle groups does \(name) miss?"))
            chips.append(OperatorChip(text: "Add two stretches to \(name)"))
        } else {
            switch tab {
            case "routines":
                chips.append(OperatorChip(text: "Create a full body routine from my exercises"))
            case "exercises":
                chips.append(OperatorChip(text: "Make my rep-based stretches duration-based"))
            case "equipment":
                chips.append(OperatorChip(text: "Create an equipment library called Travel"))
            default:
                chips.append(OperatorChip(text: "What's scheduled this week?"))
            }
        }

        if hasHistory {
            chips.append(OperatorChip(text: "How many workouts in the last 30 days?"))
            if chips.count < 3 {
                chips.append(OperatorChip(text: "What's my current streak?"))
            }
        } else {
            chips.append(OperatorChip(text: "What can you help me with?"))
        }

        return Array(chips.prefix(3))
    }
}
