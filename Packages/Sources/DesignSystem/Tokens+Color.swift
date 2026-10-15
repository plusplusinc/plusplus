import SwiftUI

/// Semantic color tokens.
///
/// Named for the job a color does, not the color it is, so a palette change touches only the
/// asset catalog. Light and dark pairs live in `Tokens.xcassets` under the raw value; a case
/// without a colorset renders clear, which the palette snapshot makes obvious.
public enum ColorToken: String, CaseIterable, Sendable {
    /// Brand and data green: the ++ mark, and later timers and progress. Never a control's fill.
    case accent = "ppAccent"
    case background = "ppBackground"
    /// The outline of a key-shaped button, the title's resting cursor, a rail's nodes, and the
    /// fill of a selected row, such as the part a sheet's wheel sets.
    case borderStrong = "ppBorderStrong"
    /// The label on a primary key.
    case onPrimaryKey = "ppOnPrimaryKey"
    /// The fill of the one primary key on a screen, such as Start.
    case primaryKey = "ppPrimaryKey"
    /// The line that runs down a rail, joining its nodes.
    case rail = "ppRail"
    /// Something joining a rail, for the moment it joins: an added row's node draws in it, then
    /// settles to `borderStrong`. Never at rest, and never the line.
    case railJoin = "ppRailJoin"
    /// A raised fill: a key's, a row's at rest in a sheet, and the open exercise's row on a rail.
    case surface = "ppSurface"
    case textPrimary = "ppTextPrimary"
    /// Placeholder text: the default title while it is being edited.
    case textSecondary = "ppTextSecondary"
}

extension Color {
    /// `Color.pp(.textPrimary)`. Call sites never reference a literal color.
    public static func pp(_ token: ColorToken) -> Color {
        Color(token.rawValue, bundle: .module)
    }
}

extension ShapeStyle where Self == Color {
    /// `.foregroundStyle(.pp(.textPrimary))`.
    public static func pp(_ token: ColorToken) -> Color {
        Color.pp(token)
    }
}
