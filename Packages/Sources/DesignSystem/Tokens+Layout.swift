import SwiftUI

/// The spacing ramp. Anything not on this scale is a bug, not a refinement.
public enum Spacing {
    /// A hairline gap, such as between a row's name and its detail line.
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

public enum Radius {
    public static let sm: CGFloat = 8
    /// A small outlined mark, such as a row's L | R.
    public static let mark: CGFloat = 6
    /// A key-shaped button.
    public static let key: CGFloat = 11
    /// A row's rounded fill, such as a value's row in a sheet or the open row on a rail.
    public static let card: CGFloat = 14
}
