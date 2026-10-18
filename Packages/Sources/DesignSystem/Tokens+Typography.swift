import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The type ramp.
///
/// Every style scales with Dynamic Type: it is built on a `Font.TextStyle`, or, when the design
/// asks for a size between two styles, scaled relative to one. A fixed point size would
/// silently opt the whole app out of accessibility sizing.
extension Font {
    public static let ppCaption = Font.system(.caption)
    public static let ppButton = Font.system(.body, weight: .semibold)
    /// The primary key's label, such as Start's.
    public static let ppPrimaryKey = Font.system(.title3, weight: .heavy)
    /// A row's name, such as an exercise's.
    public static let ppRowTitle = Font.system(.body, weight: .semibold)
    /// The line under a row's name.
    public static let ppRowDetail = Font.system(.subheadline)
    /// A screen's title collapsed into its bar: SF Mono, as the screen title is, at the size and
    /// weight of the system's inline title.
    public static let ppInlineTitle = Font.system(.headline, design: .monospaced, weight: .semibold)
    /// The numbers in a row's detail line: SF Mono at the detail's size.
    public static let ppRowDetailNumber = Font.system(.subheadline, design: .monospaced)
    /// The numbers in a value at the row title's size and weight: SF Mono.
    public static let ppRowTitleNumber = Font.system(.body, design: .monospaced, weight: .semibold)
    /// The ++ mark: monospaced so the two pluses read as one glyph.
    public static let ppMark = Font.system(.title2, design: .monospaced, weight: .bold)
}

extension View {
    /// The screen title: SF Mono, 24pt bold, so a title that can be edited reads as typed text.
    public func ppScreenTitleFont() -> some View {
        modifier(ScreenTitleFont())
    }
}

/// The screen title's size: 24pt, between `title2` and `title`, scaling as `title2` does. Read
/// with `@ScaledMetric(relativeTo: ScreenTitle.textStyle) var size = ScreenTitle.size`.
enum ScreenTitle {
    static let size: CGFloat = 24
    static let textStyle = Font.TextStyle.title2
    /// How far the title's `_` sits below the font's own underscore, so it reads as a cursor
    /// under the letter rather than a typed character: just past the tails of g, p, and y.
    /// Scaled with the title.
    static let cursorDrop: CGFloat = 4.5
    /// How tall the title takes taps, reaching down past a short title.
    static let touchTarget: CGFloat = 44

    #if canImport(UIKit)
    /// The title's font at `size`, for the UIKit views that draw it.
    static func uiFont(ofSize size: CGFloat) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: .bold)
    }
    #endif
}

private struct ScreenTitleFont: ViewModifier {
    @ScaledMetric(relativeTo: ScreenTitle.textStyle) private var size = ScreenTitle.size
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .hotReloadable()
    }
}
