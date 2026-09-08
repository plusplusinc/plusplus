import SwiftUI

/// Semantic color tokens.
///
/// Named for the job a color does, not the color it is: `positive` stays correct when the brand
/// green becomes a brand teal. Light and dark pairs live in `Tokens.xcassets` under the raw
/// value; a case without a colorset renders clear, which the palette snapshot makes obvious.
public enum ColorToken: String, CaseIterable, Sendable {
    case accent = "ppAccent"
    case background = "ppBackground"
    case danger = "ppDanger"
    /// A personal record, a completed set: progress.
    case positive = "ppPositive"
    case separator = "ppSeparator"
    case surface = "ppSurface"
    case surfaceElevated = "ppSurfaceElevated"
    case textPrimary = "ppTextPrimary"
    case textSecondary = "ppTextSecondary"
    case warning = "ppWarning"
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
