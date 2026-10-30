/// The slide that logs the current exercise's set: what it says, how firm its haptic is, and
/// what it does.
public struct LogStep {
    public var label: String
    public var weight: SlideToLog.Weight
    /// Logs the set, as the slide commits.
    public var action: () -> Void
    /// Once the key is back at the start after a log (`SlideToLog`'s `onReturn`).
    public var onReturn: () -> Void

    public init(
        label: String,
        weight: SlideToLog.Weight = .set,
        action: @escaping () -> Void,
        onReturn: @escaping () -> Void = { },
    ) {
        self.label = label
        self.weight = weight
        self.action = action
        self.onReturn = onReturn
    }

    /// Logs the set with no slide, as VoiceOver's action does: the key never leaves the start.
    public func logAtOnce() {
        action()
        onReturn()
    }
}

/// `text`'s words, each with the whitespace after it, a no-break space included, so the words
/// set side by side read as one string, and a word rolls only when it changes: none empty.
func rollingWords(_ text: String) -> [String] {
    var words: [String] = []
    var word = ""
    for character in text {
        word.append(character)
        if character.isWhitespace {
            words.append(word)
            word = ""
        }
    }
    if !word.isEmpty {
        words.append(word)
    }
    return words
}
