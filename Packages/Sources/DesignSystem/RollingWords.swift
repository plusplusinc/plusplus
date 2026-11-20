/// `text`'s words, each with the whitespace after it, so the words set side by side read as
/// one string, and a word rolls only when it changes; grouped where no-break spaces join them,
/// so a line wraps only at a breaking space. None empty.
func rollingWords(_ text: String) -> [[String]] {
    var groups: [[String]] = []
    var group: [String] = []
    var word = ""
    for character in text {
        word.append(character)
        guard character.isWhitespace else { continue }
        group.append(word)
        word = ""
        if String(character) != noBreakSpace {
            groups.append(group)
            group = []
        }
    }
    if !word.isEmpty {
        group.append(word)
    }
    if !group.isEmpty {
        groups.append(group)
    }
    return groups
}
