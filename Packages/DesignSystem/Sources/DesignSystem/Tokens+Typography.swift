import SwiftUI

/// The type ramp.
///
/// Every style is built on a `Font.TextStyle`, so Dynamic Type scaling comes for free — a fixed
/// point size silently opts the whole app out of accessibility sizing. The one exception is
/// ``ppMark``, and it is documented where it lives.
///
/// The voice is plain SF, not rounded: the app's character comes from its palette and its press
/// grammar, and a rounded face fights the monospaced `++` mark rather than complementing it.
extension Font {
    public static let ppScreenTitle = Font.system(.largeTitle, weight: .bold)
    /// A screen's own name, where it is the subject rather than a heading above content.
    public static let ppTitle = Font.system(.title2, weight: .bold)
    public static let ppSectionTitle = Font.system(.title3, weight: .semibold)
    public static let ppBody = Font.system(.body)
    /// Supporting copy under a title — a tagline, an explanatory line.
    public static let ppSubheadline = Font.system(.subheadline)
    public static let ppCaption = Font.system(.caption)
    public static let ppButtonLabel = Font.system(.body, weight: .bold)

    /// For weights, reps, timers and any other number that changes in place.
    ///
    /// Monospaced digits are not a stylistic preference: proportional digits change width as they
    /// increment, so a rep counter visibly jitters every time you tap it.
    public static let ppMetric = Font.system(.title, weight: .bold).monospacedDigit()
    public static let ppMetricSmall = Font.system(.subheadline, weight: .semibold).monospacedDigit()

    /// The `++` mark.
    ///
    /// Deliberately a fixed size rather than a text style: the mark animates between two sizes via
    /// `scaleEffect`, because `font` itself cannot be interpolated. Callers scale it; Dynamic Type
    /// does not apply to a logotype.
    public static let ppMark = Font.system(size: 72, weight: .bold, design: .monospaced)
}
