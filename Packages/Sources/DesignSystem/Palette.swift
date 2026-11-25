import SwiftUI

/// One look's value for every `ColorToken`, worked out from five colors: the ground, the text,
/// and the three that carry meaning, active, done, and arriving. A finished set must not look
/// like the one being done: `done` keeps 0.12 from `accent` in OKLab lightness when their hues
/// are within 80° (a purple beside a blue), and 0.05 otherwise (`doneGap(_:_:)`).
nonisolated struct Palette: Sendable {
    private let colors: [ColorToken: Color.Resolved]

    subscript(_ token: ColorToken) -> Color.Resolved {
        colors[token] ?? Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0)
    }

    /// Every neutral is mixed in OKLab between the ground and the text, so a theme's grays carry
    /// its ground's tint, as far from the ground as PlusPlus's own gray for that job stands from
    /// its ground in WCAG 2 contrast (dark, then light): the card 1.13 and 1.11, the chip 1.29
    /// and 1.21, the lines 1.89 to 2.24 and 1.54 to 1.82, a set to do 3.14 and 1.78, the rail
    /// 3.95 and 3.54, the quieter text 5.93 and 5.48. Contrast, not a share of the way to the
    /// text, as near black a share is too small to see: Black's card was `010101`. A dark well
    /// sinks below the ground, as PlusPlus dark's does, where the ground has room below it;
    /// Black's and Phosphor's rise a step instead, as a light look's does. The three meaningful
    /// colors and the text are moved in lightness only, as far as the contrast each job needs.
    /// A ground darker than mid gray makes a dark look.
    init(ground: UInt32, text: UInt32, active: UInt32, done: UInt32, arriving: UInt32) {
        let background = RGB(ground)
        let isDark = OKLab(background).lightness < 0.5
        func stepped(_ dark: Double, _ light: Double, below: Bool = false) -> RGB {
            Self.gray(from: background, toward: RGB(text), isDark ? dark : light, below: below)
        }
        func nudged(_ color: RGB, _ ratio: Double, on grounds: [RGB]) -> RGB {
            nudge(color, to: ratio, on: grounds, awayFrom: background)
        }
        let surface = stepped(1.13, 1.11)
        let raised = stepped(1.29, 1.21)
        let sunk = stepped(1.09, 1.11, below: isDark)
        let well = contrast(sunk, background) < 1.08 ? stepped(1.11, 1.11) : sunk
        let accent = nudged(nudged(RGB(active), 4.5, on: [background]), 3, on: [well])
        let marks = [background, well]
        let finished = Self.apart(
            nudged(RGB(done), 3, on: marks),
            from: accent,
            background: background,
            grounds: marks,
        )
        let joining = nudged(RGB(arriving), 3, on: marks)
        let rail = Self.node(
            nudged(stepped(3.95, 3.54), 3, on: marks),
            apartFrom: [finished, joining],
            grounds: marks,
        )
        let textSecondary = nudged(stepped(5.93, 5.48), 4.5, on: [background, surface, raised])
        let textPrimary = Self.text(RGB(text), past: textSecondary, background: background)
        let toDo = Self.toDo(stepped(3.14, 1.78), apartFrom: finished, background: background)
        let black = RGB(0x000000)
        colors = [
            .background: background.resolved(),
            .textPrimary: textPrimary.resolved(),
            .primaryKey: textPrimary.resolved(),
            .onPrimaryKey: background.resolved(),
            .surface: surface.resolved(),
            .surfaceRaised: raised.resolved(),
            .selectionFill: raised.resolved(),
            .borderStrong: stepped(1.89, 1.82).resolved(),
            .separator: stepped(2.24, 1.54).resolved(),
            .toDo: toDo.resolved(),
            .well: well.resolved(),
            .textSecondary: textSecondary.resolved(),
            .rail: rail.resolved(),
            .textTertiary: rail.resolved(),
            .accent: accent.resolved(),
            .done: finished.resolved(),
            .doneText: nudged(finished, 4.5, on: [background, surface]).resolved(),
            .railJoin: joining.resolved(),
            .dim: black.resolved(opacity: isDark ? 0.5 : 0.25),
            .shadow: black.resolved(opacity: isDark ? 0.4 : 0.12),
        ]
    }

    /// The OKLab mix from `ground` toward `text` that stands `ratio` from `ground` in WCAG 2
    /// contrast, found by halving; `below` goes past `ground` away from `text` instead, and
    /// stops at black or white where there is no room for the ratio.
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

    /// How far the text stands past the quieter text in OKLab lightness, so a detail line reads
    /// a step down from its name.
    static let textStep = 0.09

    /// The theme's text, moved in lightness away from the background only as far as `textStep`
    /// past `secondary` needs: where a text is soft, the quieter text at 4.5:1 on a chip
    /// otherwise sat almost on it.
    private static func text(_ text: RGB, past secondary: RGB, background: RGB) -> RGB {
        let (lightness, secondaryLightness) = (OKLab(text).lightness, OKLab(secondary).lightness)
        let away = OKLab(background).lightness < secondaryLightness ? 1.0 : -1.0
        let needed = secondaryLightness + away * textStep
        guard (needed - lightness) * away > 0 else { return text }
        return withLightness(text, needed + away * 0.005)
    }

    /// How far apart a finished exercise's node (`done`) and an upcoming one (`rail`) stand, as
    /// a distance in OKLab. Not a contrast ratio: PlusPlus light's are 1.2:1 apart in contrast
    /// and read apart by hue, a purple beside a gray, 0.20 apart; a muted violet 0.08 from its
    /// gray read as one.
    static let nodeDistance = 0.10

    /// The rail's gray moved in lightness, from where it keeps 3:1 on `grounds`, by the least
    /// step that keeps 3:1 and stands it `nodeDistance` from each of `nodes`: `done`, a
    /// finished exercise's, and `railJoin`, an arriving one's, which settles to the rail, so the
    /// arrival shows. Moved, not them, so they stay the theme's own colors.
    private static func node(_ rail: RGB, apartFrom nodes: [RGB], grounds: [RGB]) -> RGB {
        func distance(_ gray: RGB, _ node: RGB) -> Double {
            let (one, two) = (OKLab(gray), OKLab(node))
            let lightness = one.lightness - two.lightness
            let greenRed = one.greenRed - two.greenRed
            let blueYellow = one.blueYellow - two.blueYellow
            return (lightness * lightness + greenRed * greenRed + blueYellow * blueYellow)
                .squareRoot()
        }
        let start = OKLab(rail).lightness
        for step in 0 ... 50 {
            for direction in [0.01, -0.01] {
                let moved = withLightness(rail, start + Double(step) * direction)
                if nodes.allSatisfy({ distance(moved, $0) >= nodeDistance }),
                   grounds.allSatisfy({ contrast(moved, $0) >= 3 })
                {
                    return moved
                }
            }
        }
        return rail
    }

    /// A set still to do, moved toward the background until it is 0.10 from `done` in OKLab
    /// lightness, or reaches the background.
    private static func toDo(_ gray: RGB, apartFrom done: RGB, background: RGB) -> RGB {
        var toDo = gray
        let backgroundLightness = OKLab(background).lightness
        while abs(OKLab(toDo).lightness - OKLab(done).lightness) < 0.10,
              abs(OKLab(toDo).lightness - backgroundLightness) > 0.01
        {
            let step = OKLab(toDo).lightness > backgroundLightness ? -0.01 : 0.01
            toDo = withLightness(toDo, OKLab(toDo).lightness + step)
        }
        return toDo
    }

    /// How far `done` and `accent` must be apart in OKLab lightness, by how far apart their hues
    /// are. Hues within `closeHues` degrees (a purple beside a blue, 34° to 74° apart) differ too
    /// little to tell two 4 pt bars apart by hue alone, so they need `closeHueGap`; hues further
    /// apart (a purple beside a green or an orange, 90° and more) need only `lightnessGap`,
    /// PlusPlus dark's own margin. Chosen by looking at the bars side by side at their size: at
    /// 0.08 a violet beside a blue still blurred together; at 0.12 every pair read apart.
    static let closeHues = 80.0
    static let closeHueGap = 0.12
    static let lightnessGap = 0.05

    static func doneGap(_ done: RGB, _ accent: RGB) -> Double {
        OKLab(done).hueDistance(to: OKLab(accent)) < closeHues ? closeHueGap : lightnessGap
    }

    /// `done` kept apart from `accent` in lightness as well as hue, by `doneGap`: short of it,
    /// `done` moves to `accent`'s lightness that gap plus 0.005 nearer the background, or as far
    /// away from it if nearer loses 3:1 on `grounds`. Its hue stays the theme's; on a light look
    /// a close pair usually ends with `done` the darker, as nearer has no room.
    private static func apart(
        _ done: RGB,
        from accent: RGB,
        background: RGB,
        grounds: [RGB],
    ) -> RGB {
        let (doneLightness, accentLightness) = (OKLab(done).lightness, OKLab(accent).lightness)
        let gap = doneGap(done, accent)
        guard abs(doneLightness - accentLightness) < gap else { return done }
        let margin = gap + 0.005
        let toward = OKLab(background).lightness < accentLightness ? -margin : margin
        let nearer = withLightness(done, accentLightness + toward)
        if grounds.allSatisfy({ contrast(nearer, $0) >= 3 }) {
            return nearer
        }
        return withLightness(done, accentLightness - toward)
    }
}
