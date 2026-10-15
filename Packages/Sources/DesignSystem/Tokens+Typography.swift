import SwiftUI

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
    /// A sheet's heading, such as an exercise's name over its plan.
    public static let ppSheetTitle = Font.system(.title2, weight: .bold)
    /// A stepper's name, such as "Reps", leading its row.
    public static let ppStepperLabel = Font.system(.footnote)
    /// What a stepper's number means, under its name: "Per side", "Bar, total".
    public static let ppStepperNote = Font.system(.caption)
    /// A stepper's number: SF Mono, so digits keep their width as it steps.
    public static let ppStepperValue = Font.system(.subheadline, design: .monospaced, weight: .semibold)
    /// The unit drawn small after a stepper's number.
    public static let ppValueUnit = Font.system(.footnote, weight: .medium)
    /// A stepper's "Not set", in place of a number.
    public static let ppValuePlaceholder = Font.system(.subheadline)
    /// A stepper's − and + glyphs.
    public static let ppStepGlyph = Font.system(.caption, weight: .medium)
    /// The L | R mark on a row done one side at a time: SF Mono, so the two letters sit evenly
    /// either side of the divider.
    public static let ppSidesMark = Font.system(.caption2, design: .monospaced, weight: .bold)
    /// The ++ mark: monospaced so the two pluses read as one glyph.
    public static let ppMark = Font.system(.title2, design: .monospaced, weight: .bold)
}

extension View {
    /// The screen title: SF Mono, 24pt bold. Monospaced so its `_` cursor is exactly one character
    /// wide.
    public func ppScreenTitleFont() -> some View {
        modifier(ScreenTitleFont())
    }
}

/// 24pt, between `title2` and `title`, scaling as `title2` does.
private struct ScreenTitleFont: ViewModifier {
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 24
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .hotReloadable()
    }
}
