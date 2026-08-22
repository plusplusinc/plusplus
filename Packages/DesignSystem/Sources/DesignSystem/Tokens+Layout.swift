import SwiftUI

/// The spacing ramp. Anything not on this scale is a bug, not a refinement.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    /// Inset for a full-width key sitting at the bottom of a screen. Deliberately off the
    /// main scale: it pairs with ``Radius/xl`` so the key's corners echo the display's own
    /// curve, which is a concentricity relationship rather than a rhythm one.
    public static let screenEdge: CGFloat = 22
}

public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 22
    /// A full-width key sitting near the bottom edge of the screen, where the corner radius
    /// wants to echo the display's own curve rather than a control's.
    public static let xl: CGFloat = 24
    /// A raised key's cap. Its base plate must use the same value or the plate stops
    /// reading as the underside of that key.
    public static let key: CGFloat = 11
}

/// Minimum hit sizes.
///
/// `standard` is Apple's 44pt floor. `primary` is deliberately larger: the actions this app cares
/// about most get tapped mid-set, one-handed, with chalk on your hands and a bar waiting.
public enum TouchTarget {
    public static let standard: CGFloat = 44
    public static let primary: CGFloat = 60
}
