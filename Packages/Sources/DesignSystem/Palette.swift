import SwiftUI

/// A base16 color scheme's sixteen slots, as `tinted-theming/schemes` gives them.
nonisolated struct Base16: Sendable {
    private(set) var slots: [RGB]

    /// `base00` to `base0F`, in order.
    init(_ hexes: [UInt32]) {
        precondition(hexes.count == 16, "A base16 scheme has sixteen colors")
        slots = hexes.map(RGB.init)
    }

    subscript(_ slot: Int) -> RGB {
        slots[slot]
    }

    /// This scheme with one slot holding another of the theme's own colors, for a job its
    /// base16 file has no color for (Horizon's light scheme has no purple).
    func replacing(_ slot: Int, with hex: UInt32) -> Self {
        var copy = self
        copy.slots[slot] = RGB(hex)
        return copy
    }

    /// Which slot does which job: `text` the names and figures, `accent` what is active and
    /// makes something, `done` what is finished, `railJoin` what is arriving. The background is
    /// always `base00` and the comment gray `base03`; the rest differ by scheme: Dracula's
    /// purple is `base0D`, Rosé Pine has no green, and Nord is known by its frost blue,
    /// `base0C`. A theme names its own where the defaults miss what it is.
    struct Roles: Sendable {
        var text = 0x05
        var accent = 0x0B
        var done = 0x0E
        var railJoin = 0x0D
    }
}

/// One look's value for every `ColorToken`.
nonisolated struct Palette: Sendable {
    private let colors: [ColorToken: Color.Resolved]

    subscript(_ token: ColorToken) -> Color.Resolved {
        colors[token] ?? Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0)
    }

    /// The mapping from a base16 scheme onto every token. The fills and lines are mixed between
    /// the scheme's background and text in PlusPlus's own proportions, since `base01`, `base02`,
    /// and `base04` hold no steady order across schemes; the hues are the scheme's, moved in
    /// lightness only as far as the contrast each job needs.
    init(_ scheme: Base16, roles: Base16.Roles = Base16.Roles(), isDark: Bool) {
        let background = scheme[0x00]
        let text = scheme[roles.text]
        func mixed(dark: Double, light: Double) -> RGB {
            mix(background, text, isDark ? dark : light)
        }
        func nudged(_ color: RGB, _ ratio: Double, on grounds: [RGB]) -> RGB {
            nudge(color, to: ratio, on: grounds, awayFrom: background)
        }
        let surface = mixed(dark: 0.06, light: 0.05)
        let well = mixed(dark: -0.05, light: 0.05)
        let accent = nudged(nudged(scheme[roles.accent], 4.5, on: [background]), 3, on: [well])
        let rail = nudged(scheme[0x03], 3, on: [background, well])
        let done = Self.apart(
            nudged(scheme[roles.done], 3, on: [background, well]),
            from: accent,
            background: background,
            grounds: [background, well],
        )
        var toDo = mixed(dark: 0.41, light: 0.25)
        let backgroundLightness = OKLab(background).lightness
        while abs(OKLab(toDo).lightness - OKLab(done).lightness) < 0.10,
              abs(OKLab(toDo).lightness - backgroundLightness) > 0.01
        {
            let step = OKLab(toDo).lightness > backgroundLightness ? -0.01 : 0.01
            toDo = withLightness(toDo, OKLab(toDo).lightness + step)
        }
        let black = RGB(0x000000)
        colors = [
            .background: background.resolved(),
            .textPrimary: text.resolved(),
            .primaryKey: text.resolved(),
            .onPrimaryKey: background.resolved(),
            .surface: surface.resolved(),
            .surfaceRaised: mixed(dark: 0.11, light: 0.09).resolved(),
            .selectionFill: mixed(dark: 0.11, light: 0.09).resolved(),
            .borderStrong: mixed(dark: 0.245, light: 0.257).resolved(),
            .separator: mixed(dark: 0.30, light: 0.19).resolved(),
            .toDo: toDo.resolved(),
            .well: well.resolved(),
            .textSecondary: nudged(mixed(dark: 0.64, light: 0.64), 4.5, on: [background, surface])
                .resolved(),
            .rail: rail.resolved(),
            .textTertiary: rail.resolved(),
            .accent: accent.resolved(),
            .done: done.resolved(),
            .railJoin: nudged(scheme[roles.railJoin], 3, on: [background, well]).resolved(),
            .dim: black.resolved(opacity: isDark ? 0.5 : 0.25),
            .shadow: black.resolved(opacity: isDark ? 0.4 : 0.12),
        ]
    }

    /// `done` kept apart from `accent` in lightness as well as hue, as PlusPlus's are: within
    /// 0.05, it moves to `accent`'s lightness 0.055 nearer the background, or away from it if
    /// that loses 3:1 on `grounds`.
    private static func apart(
        _ done: RGB,
        from accent: RGB,
        background: RGB,
        grounds: [RGB],
    ) -> RGB {
        let (doneLightness, accentLightness) = (OKLab(done).lightness, OKLab(accent).lightness)
        guard abs(doneLightness - accentLightness) < 0.05 else { return done }
        let toward = OKLab(background).lightness < accentLightness ? -0.055 : 0.055
        let nearer = withLightness(done, accentLightness + toward)
        if grounds.allSatisfy({ contrast(nearer, $0) >= 3 }) {
            return nearer
        }
        return withLightness(done, accentLightness - toward)
    }
}
