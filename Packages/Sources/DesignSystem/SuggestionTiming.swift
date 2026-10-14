import Foundation

/// How a suggested title arrives, in one place so the timings are tuned together.
public enum SuggestionTiming {
    /// How long what a suggestion is made from must stay unchanged before one is asked for, so
    /// a burst of changes asks once.
    public static let pause = Duration.milliseconds(750)
    /// How quickly the old suggestion fades out before the new one types in.
    public static let fadeOut: TimeInterval = 0.15
    /// How many stand-in letters a new character flickers through before it lands.
    public static let decodeGlyphs = 2
    /// How long each stand-in letter shows.
    public static let decodeGlyph = Duration.milliseconds(30)
    /// How long a landed character leads, blue, before the next one takes over.
    public static let keystroke = Duration.milliseconds(25)
    /// One slow fade of the `_`, blue, out and back in, while a suggestion is on its way and
    /// typing in. Slower than
    /// the editing cursor's blink, and soft where that is on and off, so it never reads as focus.
    public static let pulsePeriod: TimeInterval = 1.6
    /// How far the `_` fades at the bottom of a pulse.
    public static let pulseLowestOpacity = 0.15
    /// With Reduce Motion on, the new suggestion crossfades in instead of typing.
    public static let crossfade: TimeInterval = 0.3
}
