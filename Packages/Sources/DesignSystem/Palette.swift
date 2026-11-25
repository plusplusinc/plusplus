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

    /// Which of the scheme's own grays do the neutral jobs, by base16's meanings: `base01` a
    /// lighter background (a card), `base02` the selection background (a chip, a selected
    /// row), the band between `base02` and `base03` the lines, `base04` the dark foreground (the
    /// quieter text). Schemes do not order these steadily (Catppuccin Mocha's `base01` is darker
    /// than its background; Solarized's `base02` is nearly its comment gray), so a theme names
    /// a mix, in PlusPlus's proportions of background and text, wherever its own gray would not
    /// keep the steps the screens rely on: a card apart from the screen, a chip apart from a
    /// card, a line apart from both and quieter than the rail.
    struct Grays: Sendable {
        var surface = Gray.slot(0x01)
        /// `surfaceRaised` and `selectionFill`.
        var raised = Gray.slot(0x02)
        /// `separator` and `borderStrong`.
        var line = Gray.between(0x02, 0x03)
        var textSecondary = Gray.slot(0x04)
        /// A set still to do: mixed in every theme, as it is placed by its distance from `done`.
        var toDo = Gray.mixed
        /// Sunk below the background: `base01` where a dark scheme has it on that side.
        var well = Gray.mixed
    }

    enum Gray: Sendable {
        /// Between the background and the text, in PlusPlus's proportion for the job.
        case mixed
        case slot(Int)
        /// Halfway between two slots, in OKLab.
        case between(Int, Int)
    }
}

/// One look's value for every `ColorToken`. A finished set must not look like the one being
/// done: `done` keeps 0.12 from `accent` in OKLab lightness when their hues are within 80° (a
/// purple beside a blue), and 0.05 otherwise (`doneGap(_:_:)`).
nonisolated struct Palette: Sendable {
    private let colors: [ColorToken: Color.Resolved]

    subscript(_ token: ColorToken) -> Color.Resolved {
        colors[token] ?? Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0)
    }

    /// The mapping from a base16 scheme onto every token. The fills and lines are the scheme's
    /// own grays where `grays` names them, else mixed between its background and text in
    /// PlusPlus's own proportions; the hues are the scheme's, moved in lightness only as far as
    /// the contrast each job needs.
    init(
        _ scheme: Base16,
        roles: Base16.Roles = Base16.Roles(),
        grays: Base16.Grays = Base16.Grays(),
        isDark: Bool,
    ) {
        let background = scheme[0x00]
        let text = scheme[roles.text]
        func mixed(dark: Double, light: Double) -> RGB {
            mix(background, text, isDark ? dark : light)
        }
        func gray(_ gray: Base16.Gray, dark: Double, light: Double) -> RGB {
            switch gray {
            case .mixed: mixed(dark: dark, light: light)
            case let .slot(slot): scheme[slot]
            case let .between(first, second): mix(scheme[first], scheme[second], 0.5)
            }
        }
        func nudged(_ color: RGB, _ ratio: Double, on grounds: [RGB]) -> RGB {
            nudge(color, to: ratio, on: grounds, awayFrom: background)
        }
        let surface = gray(grays.surface, dark: 0.06, light: 0.05)
        let raised = gray(grays.raised, dark: 0.11, light: 0.09)
        let well = gray(grays.well, dark: -0.05, light: 0.05)
        let accent = nudged(nudged(scheme[roles.accent], 4.5, on: [background]), 3, on: [well])
        let rail = nudged(scheme[0x03], 3, on: [background, well])
        let done = Self.apart(
            nudged(scheme[roles.done], 3, on: [background, well]),
            from: accent,
            background: background,
            grounds: [background, well],
        )
        var toDo = gray(grays.toDo, dark: 0.41, light: 0.25)
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
            .surfaceRaised: raised.resolved(),
            .selectionFill: raised.resolved(),
            .borderStrong: gray(grays.line, dark: 0.245, light: 0.257).resolved(),
            .separator: gray(grays.line, dark: 0.30, light: 0.19).resolved(),
            .toDo: toDo.resolved(),
            .well: well.resolved(),
            .textSecondary: nudged(
                gray(grays.textSecondary, dark: 0.64, light: 0.64),
                4.5,
                on: [background, surface],
            ).resolved(),
            .rail: rail.resolved(),
            .textTertiary: rail.resolved(),
            .accent: accent.resolved(),
            .done: done.resolved(),
            .railJoin: nudged(scheme[roles.railJoin], 3, on: [background, well]).resolved(),
            .dim: black.resolved(opacity: isDark ? 0.5 : 0.25),
            .shadow: black.resolved(opacity: isDark ? 0.4 : 0.12),
        ]
    }

    /// How far `done` and `accent` must be apart in OKLab lightness, by how far apart their hues
    /// are. Hues within `closeHues` degrees (a purple beside a blue: Solarized's are 34° apart,
    /// Tomorrow dark's 74°) differ too little to tell two 4 pt bars apart by hue alone, so they
    /// need `closeHueGap`; hues further apart (a purple beside a green or an orange, 90° and
    /// more) need only `lightnessGap`, PlusPlus dark's own margin. Chosen by looking at the
    /// bars side by side at their size: at 0.08 Kanagawa's and Tomorrow dark's still blurred
    /// together; at 0.12 every pair read apart.
    static let closeHues = 80.0
    static let closeHueGap = 0.12
    static let lightnessGap = 0.05

    static func doneGap(_ done: RGB, _ accent: RGB) -> Double {
        OKLab(done).hueDistance(to: OKLab(accent)) < closeHues ? closeHueGap : lightnessGap
    }

    /// `done` kept apart from `accent` in lightness as well as hue, by `doneGap`: short of it,
    /// `done` moves to `accent`'s lightness that gap plus 0.005 nearer the background, or as far
    /// away from it if nearer loses 3:1 on `grounds`. Its hue stays the theme's purple; on a
    /// light look a close pair usually ends with `done` the darker, as nearer has no room.
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
