import SwiftUI

/// The type ramp.
///
/// Every style is built on a `Font.TextStyle`, so Dynamic Type scaling comes for free; a fixed
/// point size would silently opt the whole app out of accessibility sizing.
extension Font {
    public static let ppScreenTitle = Font.system(.largeTitle, weight: .bold)
    public static let ppBody = Font.system(.body)
    public static let ppCaption = Font.system(.caption)
}
