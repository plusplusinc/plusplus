import Foundation

/// A tappable example prompt above the input bar. Hand-authored and
/// chosen DETERMINISTICALLY from app state — no model call, no
/// hallucination surface; the chips teach what Operator can do and
/// make the view-context feature visible.
struct OperatorChip: Identifiable, Equatable {
    let label: String
    let prompt: String
    var id: String { label }
}

enum OperatorChips {
    /// 2–3 chips for the current state. `detail` is the ViewContext
    /// detail line (nil at a tab root).
    static func chips(tab: String, detail: String?, hasHistory: Bool) -> [OperatorChip] {
        var chips: [OperatorChip] = []

        // The visible screen gets the first, most specific slot.
        if let detail, detail.hasPrefix("routines/") {
            let name = String(detail.dropFirst("routines/".count))
            chips.append(OperatorChip(
                label: "Balance this routine",
                prompt: "Which muscle groups does \(name) miss?"
            ))
            chips.append(OperatorChip(
                label: "Add a stretch block",
                prompt: "Add two stretches to \(name)"
            ))
        } else {
            switch tab {
            case "routines":
                chips.append(OperatorChip(
                    label: "Build a routine",
                    prompt: "Create a 30 minute full body routine from my exercises"
                ))
            case "exercises":
                chips.append(OperatorChip(
                    label: "Stretches to duration",
                    prompt: "Make all my rep-based stretches duration-based instead"
                ))
            case "equipment":
                chips.append(OperatorChip(
                    label: "New gear list",
                    prompt: "Create an equipment library called Travel"
                ))
            default:
                chips.append(OperatorChip(
                    label: "What's my week look like?",
                    prompt: "Which routines are scheduled this week?"
                ))
            }
        }

        if hasHistory {
            chips.append(OperatorChip(
                label: "Last 30 days",
                prompt: "How many workouts did I do in the last 30 days?"
            ))
            if chips.count < 3 {
                chips.append(OperatorChip(
                    label: "Streak check",
                    prompt: "What's my current streak?"
                ))
            }
        } else {
            chips.append(OperatorChip(
                label: "What can you do?",
                prompt: "What can you help me with?"
            ))
        }

        return Array(chips.prefix(3))
    }
}
