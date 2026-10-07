import SwiftUI

/// The type ramp.
///
/// Every style is built on a `Font.TextStyle`, so Dynamic Type scaling comes for free; a fixed
/// point size would silently opt the whole app out of accessibility sizing.
extension Font {
    public static let ppScreenTitle = Font.system(.title2, weight: .bold)
    public static let ppBody = Font.system(.body)
    public static let ppCaption = Font.system(.caption)
    public static let ppButton = Font.system(.body, weight: .semibold)
    /// The ++ mark: monospaced so the two pluses read as one glyph.
    public static let ppMark = Font.system(.title2, design: .monospaced, weight: .bold)
}
