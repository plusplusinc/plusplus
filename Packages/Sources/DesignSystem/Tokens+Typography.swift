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
    public static let ppPrimaryKey = Font.system(.title3, weight: .semibold)
    /// A row's name, such as an exercise's.
    public static let ppRowTitle = Font.system(.body, weight: .semibold)
    /// The line under a row's name.
    public static let ppRowDetail = Font.system(.subheadline)
    /// A screen's title collapsed into its bar: SF Mono, as the screen title is, at the size and
    /// weight of the system's inline title.
    public static let ppInlineTitle = Font.system(.headline, design: .monospaced, weight: .semibold)
    /// The system's own inline bar title, SF Pro, for one drawn by hand where the bar's would
    /// drop out (`BarSearchField`'s title).
    public static let ppBarTitle = Font.system(.headline)
    /// The numbers in a row's detail line: SF Mono at the detail's size.
    public static let ppRowDetailNumber = Font.system(.subheadline, design: .monospaced)
    /// The numbers in a value at the row title's size and weight: SF Mono.
    public static let ppRowTitleNumber = Font.system(.body, design: .monospaced, weight: .semibold)
    /// The current exercise's name, grown from `ppRowTitle`.
    public static let ppCurrentTitle = Font.system(.title, weight: .semibold)
    /// Which set the current exercise is on, "Set 1 of 3": SF Mono, as numbers are.
    public static let ppCurrentProgress = Font.system(.body, design: .monospaced, weight: .medium)
    /// A workout's time on its key in the bar: SF Mono, so the digits hold still as they tick.
    public static let ppWorkoutTime = ppRowTitleNumber
    /// A place in the drawer, Routines or a routine under it: one font for all, so none reads as
    /// a heading over the others.
    public static let ppDrawerItem = Font.system(.body, weight: .medium)
    /// A routine's name in a list of routines: SF Pro, as the name can't be edited there, the
    /// drawer's font, so a row reads the same in both.
    public static let ppRoutineName = ppDrawerItem
    /// The +1 that pops off Start as it is pressed: SF Mono, as numbers are.
    public static let ppPlusOne = Font.system(.title3, design: .monospaced, weight: .bold)
    /// A floating button's icon, such as Add exercise's +.
    public static let ppFloatingIcon = Font.system(.title2, weight: .semibold)
    /// The ++ mark: monospaced so the two pluses read as one glyph.
    public static let ppMark = Font.system(.title2, design: .monospaced, weight: .bold)
}

extension View {
    /// The screen title: SF Mono, 24pt bold, so a title that can be edited reads as typed text.
    public func ppScreenTitleFont() -> some View {
        modifier(ScreenTitleFont(design: .monospaced))
    }

    /// A title that can't be edited, such as the drawer's or the Routines screen's: the screen
    /// title's size and weight in SF Pro, as it is a name, not typed text.
    public func ppFixedTitleFont() -> some View {
        modifier(ScreenTitleFont(design: .default))
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

/// The current exercise's large figure: its digits 104pt bold at the default size, and the
/// letters with them, a time's "m" and "s" and what a number counts, "reps", "lb", bold and a bit
/// over half the digits' size, in the same color, on their baseline (Dave's pick, 2026-11-14).
/// Both scale as `largeTitle` does. Read with
/// `@ScaledMetric(relativeTo: CurrentFigure.textStyle) var size = CurrentFigure.size`.
enum CurrentFigure {
    static let size: CGFloat = 104
    /// The letters' size: 0.57 of the digits', as in the drawing picked.
    static let unitSize: CGFloat = 59
    /// The gap between a number's last digit and the letters after it.
    static let unitGap: CGFloat = 6
    /// A word space in the letters' font, as a fraction of their size: between a time's last
    /// letter and the words after it, "45s per side".
    static let wordSpace: CGFloat = 0.26
    static let textStyle = Font.TextStyle.largeTitle
}

private struct ScreenTitleFont: ViewModifier {
    let design: Font.Design
    @ScaledMetric(relativeTo: ScreenTitle.textStyle) private var size = ScreenTitle.size

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold, design: design))
    }
}
