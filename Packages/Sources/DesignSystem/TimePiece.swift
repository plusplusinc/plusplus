/// One unit of a time as a value row writes it, "1m" or "35s", identified by its unit so the
/// same unit keeps its view as the time changes shape ("55s" to "0m 55s").
struct TimePiece: Identifiable, Equatable {
    let id: String
    let text: String

    /// A word with no number ("None"), never beside another piece.
    var isWord: Bool {
        !text.contains(where: \.isNumber)
    }

    /// A time's pieces, its units in order, then the words after them ("per side") as one piece,
    /// every piece but the last carrying the space after it; a word with no number ("None") is
    /// a piece of its own. Nil when the value isn't a time in this shape: a weight ("25.0 lb"),
    /// whose number stands apart from its unit.
    static func pieces(of value: String) -> [Self]? {
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        if words.count == 1, !value.contains(where: \.isNumber) {
            return [Self(id: value, text: value)]
        }
        let units = Array(words.prefix { $0.first?.isNumber == true && $0.last?.isLetter == true })
        let after = words.dropFirst(units.count)
        guard !units.isEmpty, !after.contains(where: { $0.contains(where: \.isNumber) }) else {
            return nil
        }
        var pieces = units.map { word in
            let unit = String(word.drop { $0.isNumber || $0 == "." || $0 == "," })
            return Self(id: unit, text: word)
        }
        if !after.isEmpty {
            let words = after.joined(separator: " ")
            pieces.append(Self(id: words, text: words))
        }
        return pieces.enumerated().map { index, piece in
            index < pieces.count - 1 ? Self(id: piece.id, text: piece.text + noBreakSpace) : piece
        }
    }
}
