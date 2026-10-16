import SwiftUI

extension AttributedString {
    /// `text` with every number in it set in `font`, SF Mono, and the words around them left in
    /// the text's own font: "3 × 10 reps", "2:30 min", "142.5 lb".
    public static func monoNumbers(_ text: String, font: Font) -> AttributedString {
        var attributed = AttributedString(text)
        for match in text.matches(of: /\d+(?:[.,:]\d+)*/) {
            guard let range = Range(match.range, in: attributed) else { continue }
            attributed[range].font = font
        }
        return attributed
    }
}
