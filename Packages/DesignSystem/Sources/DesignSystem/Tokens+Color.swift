import SwiftUI

/// Semantic colour tokens.
///
/// Named for the job a colour does, not the colour it is. `ppPositive` stays correct when the
/// brand green becomes a brand teal; `ppGreen` would not. Call sites never reference a literal.
extension Color {
    public static let ppBackground = token("ppBackground")
    public static let ppSurface = token("ppSurface")
    public static let ppSurfaceElevated = token("ppSurfaceElevated")
    public static let ppTextPrimary = token("ppTextPrimary")
    public static let ppTextSecondary = token("ppTextSecondary")
    public static let ppAccent = token("ppAccent")
    /// A personal record, a completed set — progress.
    public static let ppPositive = token("ppPositive")
    public static let ppWarning = token("ppWarning")
    public static let ppDanger = token("ppDanger")
    public static let ppSeparator = token("ppSeparator")

    /// Resolved from the package's own bundle; light and dark pairs live in `Tokens.xcassets`.
    private static func token(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}
