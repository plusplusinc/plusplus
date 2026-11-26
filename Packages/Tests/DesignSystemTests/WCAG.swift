import SwiftUI

/// WCAG 2's contrast ratio of two resolved colors, worked out from their own linear components
/// rather than through `DesignSystem.contrast`, so a check does not share the palette's math.
nonisolated func wcagContrast(_ first: Color.Resolved, _ second: Color.Resolved) -> Double {
    /// `Color.Resolved`'s linear components are already linear sRGB.
    func luminance(_ color: Color.Resolved) -> Double {
        0.2126 * Double(color.linearRed) + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
    }
    let (one, two) = (luminance(first), luminance(second))
    return (max(one, two) + 0.05) / (min(one, two) + 0.05)
}
