import Foundation

/// How a suggested title arrives, in one place so the timings are tuned together.
public enum SuggestionTiming {
    /// How long what a suggestion is made from must stay unchanged before one is asked for, so
    /// a burst of changes asks once.
    public static let pause = Duration.milliseconds(750)
    /// How quickly the old suggestion fades out before the new one types in.
    public static let fadeOut: TimeInterval = 0.15
    /// How often the lead moves on to the next character of the new suggestion.
    public static let leadInterval: TimeInterval = 0.02
    /// How long each new letter shuffles through the name's other letters, in blue, before it
    /// lands. About two lead intervals, so a short trail shuffles behind the lead.
    public static let decodeDuration: TimeInterval = 0.05
    /// How long each stand-in letter of a shuffling one shows.
    public static let glyphSwapInterval: TimeInterval = 0.03
    /// How long a landed letter, and the `_` once the last one lands, takes to ease from blue to
    /// its own color.
    public static let tintFade: TimeInterval = 0.16
    /// One slow breath of the `_`, blue, while a suggestion is on its way and typing in. Slower
    /// than the editing cursor's blink, and soft where that is on and off, so it never reads as
    /// focus.
    public static let pulsePeriod: TimeInterval = 1.8
    /// How far the `_` fades at the bottom of a breath.
    public static let pulseLowestOpacity = 0.4
    /// With Reduce Motion on, the new suggestion crossfades in instead of typing.
    public static let crossfade: TimeInterval = 0.3
}
