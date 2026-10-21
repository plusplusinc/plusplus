import Foundation

// How a workout's time reads: on its key, and to VoiceOver. The formats follow the locale's
// separator and digits.

extension Workout {
    /// "04:12" under an hour, "1:04:12" from an hour.
    public static func elapsedText(_ elapsed: Duration, locale: Locale = .current) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern =
            elapsed < .seconds(3600) ? .minuteSecond(padMinuteToLength: 2) : .hourMinuteSecond
        return elapsed.formatted(.time(pattern: pattern).locale(locale))
    }

    /// "4 minutes, 12 seconds", for VoiceOver.
    public static func spokenElapsed(_ elapsed: Duration, locale: Locale = .current) -> String {
        elapsed.formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale),
        )
    }
}
