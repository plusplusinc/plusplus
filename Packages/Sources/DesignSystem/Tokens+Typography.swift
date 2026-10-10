import SwiftUI

/// The type ramp.
///
/// Every style scales with Dynamic Type: it is built on a `Font.TextStyle`, or, when the design
/// asks for a size between two styles, scaled relative to one. A fixed point size would
/// silently opt the whole app out of accessibility sizing.
extension Font {
    public static let ppCaption = Font.system(.caption)
    public static let ppButton = Font.system(.body, weight: .semibold)
    /// A row's name, such as an exercise's.
    public static let ppRowTitle = Font.system(.body, weight: .semibold)
    /// The line under a row's name.
    public static let ppRowDetail = Font.system(.subheadline)
    /// The ++ mark: monospaced so the two pluses read as one glyph.
    public static let ppMark = Font.system(.title2, design: .monospaced, weight: .bold)
}

extension View {
    /// The screen title: SF Mono, 24pt bold. Monospaced so its `_` cursor is exactly one character
    /// wide.
    public func ppScreenTitleFont() -> some View {
        modifier(TitleSizedFont(weight: .bold, design: .monospaced))
    }

    /// The primary key's label: 24pt heavy.
    public func ppPrimaryKeyFont() -> some View {
        modifier(TitleSizedFont(weight: .heavy, design: .default))
    }
}

/// 24pt, between `title2` and `title`, scaling as `title2` does.
private struct TitleSizedFont: ViewModifier {
    let weight: Font.Weight
    let design: Font.Design
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 24
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: design))
            .hotReloadable()
    }
}
