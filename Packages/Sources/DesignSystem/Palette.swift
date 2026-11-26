import SwiftUI

/// Black belt's value for every `ColorToken` (`Appearance.blackBelt`), on the screen and on a
/// sheet, worked out from a ground and PlusPlus dark's text, active, done, and arriving colors.
/// PlusPlus's own are the asset catalog's colorsets.
nonisolated struct Palette: Sendable {
    private let colors: [ColorToken: Color.Resolved]

    subscript(_ token: ColorToken) -> Color.Resolved {
        colors[token] ?? Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0)
    }

    /// True black, for an OLED screen, drawn as iOS draws its own dark: neutral grays, nothing
    /// warm, and pure white text.
    static let blackBelt = Self(ground: 0x000000)

    /// A sheet over Black belt stands on iOS's own sheet gray, a clear step up from the black
    /// screen, with every neutral on it stepped from that: in the screen's black a sheet had no
    /// edge, and a card on it none either.
    static let blackBeltSheet = Self(ground: 0x1C1C1E)

    /// Every neutral is mixed in OKLab from the ground toward the white text, so it carries the
    /// ground's tint, as far from the ground as PlusPlus dark's own gray for that job stands from
    /// its ground in WCAG 2 contrast: the card 1.13, the chip 1.29, the lines 1.89 to 2.24, a set
    /// to do 3.14, the rail 3.95, the quieter text 5.93. Contrast, not a share of the way to the
    /// text, as near black a share is too small to see: a share made the card `010101`. The well
    /// sinks below the ground, as PlusPlus dark's does, where the ground has room below it, and
    /// rises a step on black. The meaningful colors are PlusPlus dark's, moved in lightness only
    /// where a job's contrast needs it, which on these grounds it doesn't.
    private init(ground: UInt32) {
        let background = RGB(ground)
        let white = RGB(0xFFFFFF)
        func stepped(_ ratio: Double, below: Bool = false) -> RGB {
            Self.gray(from: background, toward: white, ratio, below: below)
        }
        func nudged(_ hex: UInt32, _ ratio: Double, on grounds: [RGB]) -> RGB {
            nudge(RGB(hex), to: ratio, on: grounds, awayFrom: background)
        }
        let surface = stepped(1.13)
        let raised = stepped(1.29)
        let sunk = stepped(1.09, below: true)
        let well = contrast(sunk, background) < 1.08 ? stepped(1.11) : sunk
        let marks = [background, well]
        let rail = nudge(stepped(3.95), to: 3, on: marks, awayFrom: background)
        let textSecondary = nudge(
            stepped(5.93),
            to: 4.5,
            on: [background, surface, raised],
            awayFrom: background,
        )
        let black = RGB(0x000000)
        colors = [
            .background: background.resolved(),
            .textPrimary: white.resolved(),
            .primaryKey: white.resolved(),
            .onPrimaryKey: background.resolved(),
            .surface: surface.resolved(),
            .surfaceRaised: raised.resolved(),
            .selectionFill: raised.resolved(),
            .borderStrong: stepped(1.89).resolved(),
            .separator: stepped(2.24).resolved(),
            .toDo: stepped(3.14).resolved(),
            .well: well.resolved(),
            .textSecondary: textSecondary.resolved(),
            .rail: rail.resolved(),
            .textTertiary: rail.resolved(),
            .accent: nudged(0x46D17C, 4.5, on: marks).resolved(),
            .done: nudged(0xB08CF0, 3, on: marks).resolved(),
            .railJoin: nudged(0x5CA8F5, 3, on: marks).resolved(),
            .dim: black.resolved(opacity: 0.5),
            .shadow: black.resolved(opacity: 0.4),
        ]
    }

    /// The OKLab mix from `ground` toward `text` that stands `ratio` from `ground` in WCAG 2
    /// contrast, found by halving; `below` goes past `ground` away from `text` instead, and
    /// stops at black where there is no room for the ratio.
    private static func gray(
        from ground: RGB,
        toward text: RGB,
        _ ratio: Double,
        below: Bool,
    ) -> RGB {
        var (short, past) = (0.0, 1.0)
        for _ in 0 ..< 30 {
            let fraction = (short + past) / 2
            if contrast(mix(ground, text, below ? -fraction : fraction), ground) < ratio {
                short = fraction
            } else {
                past = fraction
            }
        }
        return mix(ground, text, below ? -past : past)
    }
}
