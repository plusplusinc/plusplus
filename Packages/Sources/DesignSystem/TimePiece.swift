/// One unit of a time as a value row writes it, "1m" or "35s", identified by its unit so the
/// same unit keeps its view as the time changes shape ("55s" to "0m 55s").
struct TimePiece: Identifiable, Equatable {
    let id: String
    let text: String

    /// A word with no number ("None"), never beside another piece.
    var isWord: Bool {
        !text.contains(where: \.isNumber)
    }

    /// A time's pieces, its words in order, every one but the last carrying the space after it;
    /// a word with no number ("None") is a piece of its own. Nil when the value isn't a time in
    /// this shape: a weight ("25.0 lb"), whose number stands apart from its unit.
    static func pieces(of value: String) -> [Self]? {
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let isTime = words.allSatisfy { word in
            word.first?.isNumber == true && word.last?.isLetter == true
        }
        let isWord = words.count == 1 && !value.contains(where: \.isNumber)
        guard isTime || isWord else { return nil }
        return words.enumerated().map { index, word in
            let unit = String(word.drop { $0.isNumber || $0 == "." || $0 == "," })
            let space = index < words.count - 1 ? noBreakSpace : ""
            return Self(id: unit, text: word + space)
        }
    }
}
