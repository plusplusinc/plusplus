import Foundation

extension String {
    /// Sentence-case a short search query for a `Create "…"` / `Add "…"`
    /// label: capitalize ONLY the first letter, leaving the rest verbatim
    /// so "iPhone", "EZ-bar", and "e1RM" survive intact (2026-07-18).
    var sentenceCasedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
