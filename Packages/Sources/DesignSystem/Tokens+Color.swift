import SwiftUI

/// Semantic color tokens.
///
/// Named for the job a color does, not the color it is, so a palette change touches only the
/// asset catalog. Light and dark pairs live in `Tokens.xcassets` under the raw value; a case
/// without a colorset renders clear, which the palette snapshot makes obvious.
public enum ColorToken: String, CaseIterable, Sendable {
    /// Green: what's active, and a value that went up; also the ++ mark. Never a control's fill.
    case accent = "ppAccent"
    case background = "ppBackground"
    /// The outline of a key-shaped button, and the title's resting cursor.
    case borderStrong = "ppBorderStrong"
    /// The label on a primary key.
    case onPrimaryKey = "ppOnPrimaryKey"
    /// The fill of the one primary key on a screen, such as Start.
    case primaryKey = "ppPrimaryKey"
    /// The line that runs down a rail and its nodes at rest, one gray, and the loop beside it
    /// that marks a group of rows, a superset.
    case rail = "ppRail"
    /// Something joining a rail, for the moment it joins: an added row's node draws in it, then
    /// settles to `rail`; a group's loop as a drop makes the group, then settling to
    /// `rail`. Never at rest, and never the line.
    case railJoin = "ppRailJoin"
    /// The soft shadow all around something lifted off the screen, such as a held row's card.
    case shadow = "ppShadow"
    case surface = "ppSurface"
    /// The fill of something lifted off the screen, such as a row held to be moved: lighter
    /// than `surface`, as if nearer the light, with no border.
    case surfaceRaised = "ppSurfaceRaised"
    case textPrimary = "ppTextPrimary"
    /// Placeholder text: the default title while it is being edited.
    case textSecondary = "ppTextSecondary"
    /// A region sunk into the screen, flat, with no shadow: the rows of a superset. Darker than
    /// `background` in both appearances, as if further from the light.
    case well = "ppWell"
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
