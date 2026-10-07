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
    /// The outline of a key-shaped button, and the title's resting cursor.
    case borderStrong = "ppBorderStrong"
    case surface = "ppSurface"
    case textPrimary = "ppTextPrimary"
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
