import SwiftUI

/// PlusPlus dark on the Watch. watchOS has no light and dark: its asset catalogs keep a
/// colorset's one appearance for any, so `Color(_:bundle:)` there draws the light values. The
/// Watch draws PlusPlus dark's instead, copied from `Tokens.xcassets`, which
/// `WatchPaletteTests` holds them to.
nonisolated enum WatchPalette {
    static let hex: [ColorToken: (rgb: UInt32, opacity: Double)] = [
        .accent: (0x46D17C, 1),
        .background: (0x201F1D, 1),
        .borderStrong: (0x4E4B43, 1),
        .dim: (0x000000, 0.5),
        .done: (0xB08CF0, 1),
        .onPrimaryKey: (0x161616, 1),
        .pillOnSurface: (0x45443F, 1),
        .primaryKey: (0xF0EDE6, 1),
        .rail: (0x7E7C76, 1),
        .railJoin: (0x5CA8F5, 1),
        .selectionFill: (0x34322D, 1),
        .separator: (0x585650, 1),
        .shadow: (0x000000, 0.4),
        .surface: (0x2A2925, 1),
        .surfaceRaised: (0x34322D, 1),
        .textPrimary: (0xF0EDE6, 1),
        .textSecondary: (0x9D9B96, 1),
        .textTertiary: (0x7C7B75, 1),
        .toDo: (0x6E6C66, 1),
        .well: (0x181715, 1),
    ]

    static subscript(_ token: ColorToken) -> Color.Resolved {
        guard let color = hex[token] else {
            return Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0)
        }
        return RGB(color.rgb).resolved(opacity: color.opacity)
    }
}
