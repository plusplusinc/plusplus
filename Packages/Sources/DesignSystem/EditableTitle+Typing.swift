import Foundation

// How a suggestion types into the title, worked out from the time since it started: one clock,
// and plain values `EditableTitleContent` draws.

extension EditableTitle {
    /// Whether `character`, at `index` of `text`, shuffles before it lands: the first character,
    /// and anything that isn't a letter, land at once, and so does a letter with no other letter
    /// in the text to shuffle through.
    static func shuffles(_ character: Character, at index: Int, in text: String) -> Bool {
        index > 0 && character.isLetter
            && text.contains { $0.isLetter && $0.lowercased() != character.lowercased() }
    }

    /// The stand-in drawn for `character`, at `index`, on its `swap`th change: one of the
    /// other letters of `text`, in `character`'s case, so the letters seem to shuffle into place.
    /// Nil where it doesn't shuffle. Letters only, so a monospaced title never changes width.
    /// Picked from its arguments rather than at random, so the same moment always draws the
    /// same.
    public static func standIn(
        for character: Character,
        at index: Int,
        swap: Int,
        in text: String,
    ) -> Character? {
        guard shuffles(character, at: index, in: text) else { return nil }
        // In the character's case, where a letter has a one-character mapping to it: ß has none.
        let letters = Set(text.filter(\.isLetter).compactMap { letter -> Character? in
            let cased = character.isUppercase ? letter.uppercased() : letter.lowercased()
            return cased.count == 1 ? cased.first : nil
        })
        .subtracting([character])
        .sorted()
        guard !letters.isEmpty else { return nil }
        // SplitMix64's finalizer, so neighboring indexes and swaps pick unrelated letters.
        var mix = (UInt64(index) << 32 | UInt64(swap)) &+ 0x9E37_79B9_7F4A_7C15
        mix = (mix ^ (mix >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mix = (mix ^ (mix >> 27)) &* 0x94D0_49BB_1331_11EB
        mix ^= mix >> 31
        return letters[Int(mix % UInt64(letters.count))]
    }

    /// How far `text` has typed in, `elapsed` seconds after it started.
    public static func typingFrame(of text: String, at elapsed: TimeInterval) -> TypingFrame {
        let characters = Array(text)
        let lead = SuggestionTiming.leadInterval
        let decode = SuggestionTiming.decodeDuration
        let count = min(characters.count, max(0, Int(elapsed / lead) + 1))
        var frame = TypingFrame(shown: String(characters.prefix(count)))
        for index in 0 ..< count {
            let appeared = Double(index) * lead
            let since = elapsed - appeared
            let character = characters[index]
            let shuffles = shuffles(character, at: index, in: text)
            // Compared as typingDuration(of:) adds it up, so the end is the end.
            if shuffles, elapsed < appeared + decode {
                let swap = Int(since / SuggestionTiming.glyphSwapInterval)
                frame.standIns[index] = standIn(for: character, at: index, swap: swap, in: text)
                frame.tints[index] = 1
                continue
            }
            let landed = appeared + (shuffles ? decode : 0)
            guard elapsed < landed + SuggestionTiming.tintFade else { continue }
            // Eased out: quick to leave full blue, slow into gray.
            let fading = (elapsed - landed) / SuggestionTiming.tintFade
            frame.tints[index] = (1 - fading) * (1 - fading)
        }
        frame.cursorTint = count < characters.count ? 1 : frame.tints[characters.count - 1] ?? 0
        return frame
    }

    /// How long `text` takes to type in, until its last letter has landed and eased to gray.
    public static func typingDuration(of text: String) -> TimeInterval {
        Double(max(0, text.count - 1)) * SuggestionTiming.leadInterval
            + SuggestionTiming.decodeDuration + SuggestionTiming.tintFade
    }
}

/// A moment of a placeholder typing in, as plain values `EditableTitleContent` draws.
public struct TypingFrame: Equatable {
    /// The characters that have appeared.
    public var shown: String
    /// The letters still shuffling, by index, each with the letter drawn in its place.
    public var standIns: [Int: Character] = [:]
    /// How blue each character is, by index, from 1 while it shuffles to 0 once it has eased to
    /// gray. Missing is 0.
    public var tints: [Int: Double] = [:]
    /// How blue the `_` is: 1 until the last character appears, then fading with it.
    public var cursorTint: Double = 1
}
