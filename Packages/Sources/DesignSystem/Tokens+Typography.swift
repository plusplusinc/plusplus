import SwiftUI

/// The type ramp.
///
/// Every style scales with Dynamic Type: it is built on a `Font.TextStyle`, or, when the design
/// asks for a size between two styles, scaled relative to one. A fixed point size would
/// silently opt the whole app out of accessibility sizing.
extension Font {
    public static let ppCaption = Font.system(.caption)
    public static let ppButton = Font.system(.body, weight: .semibold)
    /// The ++ mark: monospaced so the two pluses read as one glyph.
    public static let ppMark = Font.system(.title2, design: .monospaced, weight: .bold)
}

extension View {
    /// The screen title: 24pt bold, between `title2` and `title`, scaling as `title2` does.
    public func ppScreenTitleFont() -> some View {
        modifier(ScreenTitleFont())
    }
}

private struct ScreenTitleFont: ViewModifier {
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 24

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .bold))
    }
}
