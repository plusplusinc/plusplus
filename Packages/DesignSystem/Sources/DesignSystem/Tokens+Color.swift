import SwiftUI

/// Semantic colour tokens.
///
/// Named for the job a colour does, not the colour it is. `ppAccent` stays correct when the brand
/// green becomes a brand teal; `ppGreen` would not. Call sites never reference a literal.
///
/// Values carry over from the previous app's palette, including its high-contrast variants —
/// several pairs were tuned to clear WCAG AA on specific grounds, so treat a hex here as a
/// measured value rather than a preference.
extension Color {
    // Grounds, lightest to heaviest.
    public static let ppBackground = token("ppBackground")
    public static let ppSurface = token("ppSurface")
    public static let ppSurfaceRaised = token("ppSurfaceRaised")

    // Ink.
    public static let ppTextPrimary = token("ppTextPrimary")
    public static let ppTextSecondary = token("ppTextSecondary")

    /// Data green: deltas, live progress, creation, the `++` mark. Never chrome.
    public static let ppAccent = token("ppAccent")
    /// Advisory amber — form cues, "needs X". Never alarm.
    public static let ppWarning = token("ppWarning")
    /// Destructive only.
    public static let ppDanger = token("ppDanger")

    // Edges. `ppBorder` separates; `ppBorderStrong` sits under a raised key as its base plate.
    public static let ppBorder = token("ppBorder")
    public static let ppBorderStrong = token("ppBorderStrong")

    /// The cap of a primary key, and the ink that sits on it.
    public static let ppPrimaryFill = token("ppPrimaryFill")
    public static let ppOnPrimary = token("ppOnPrimary")

    /// Resolved from the package's own bundle; appearance pairs live in `Tokens.xcassets`.
    private static func token(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}
