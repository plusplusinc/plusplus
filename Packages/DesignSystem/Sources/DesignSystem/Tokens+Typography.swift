import SwiftUI

/// The type ramp.
///
/// Every style is built on a `Font.TextStyle`, so Dynamic Type scaling comes for free — a fixed
/// point size would silently opt the whole app out of accessibility sizing.
extension Font {
    public static let ppScreenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let ppSectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    public static let ppBody = Font.system(.body)
    public static let ppCaption = Font.system(.caption)
    public static let ppButtonLabel = Font.system(.headline, design: .rounded, weight: .semibold)

    /// For weights, reps, timers and any other number that changes in place.
    ///
    /// Monospaced digits are not a stylistic preference here: proportional digits change width as
    /// they increment, so a rep counter visibly jitters every time you tap it.
    public static let ppMetric = Font.system(.title, design: .rounded, weight: .bold)
        .monospacedDigit()

    public static let ppMetricSmall = Font.system(.subheadline, design: .rounded, weight: .semibold)
        .monospacedDigit()
}
