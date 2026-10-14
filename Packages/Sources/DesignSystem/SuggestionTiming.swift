import Foundation

/// How a suggested title arrives, in one place so the timings are tuned together.
public enum SuggestionTiming {
    /// How long what a suggestion is made from must stay unchanged before one is asked for, so
    /// a burst of changes asks once.
    public static let pause = Duration.milliseconds(750)
    /// One character erased or typed, as the old suggestion makes way for the new one.
    public static let keystroke = Duration.milliseconds(25)
    /// One slow fade of the `_` out and back in, while a suggestion is on its way. Slower than
    /// the editing cursor's blink, and soft where that is on and off, so it never reads as focus.
    public static let pulsePeriod: TimeInterval = 1.6
    /// How far the `_` fades at the bottom of a pulse.
    public static let pulseLowestOpacity = 0.15
    /// With Reduce Motion on, the new suggestion crossfades in instead of typing.
    public static let crossfade: TimeInterval = 0.3
}
