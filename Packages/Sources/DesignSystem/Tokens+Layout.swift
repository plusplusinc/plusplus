import SwiftUI

/// The spacing ramp. Anything not on this scale is a bug, not a refinement.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}

public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 22
}

/// Minimum hit sizes.
///
/// `standard` is Apple's 44pt floor. `primary` is deliberately larger: the actions this app cares
/// about most get tapped mid-set, one-handed, with chalk on your hands and a bar waiting.
public enum TouchTarget {
    public static let standard: CGFloat = 44
    public static let primary: CGFloat = 60
}
