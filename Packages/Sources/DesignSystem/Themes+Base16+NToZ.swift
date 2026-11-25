import SwiftUI

/// The base16 themes from Nord to Zenburn, by the rules in `Themes+Base16.swift`.
nonisolated extension Theme {
    /// Active in its green, `nord14`, done in its purple, `nord15` (`B48EAD`), arriving in its
    /// blue, in both looks: base16's light scheme has a raspberry that reads as a red in its
    /// purple slot, so it takes `nord15` back, darkened for the light background. Its own grays,
    /// the Polar Night steps, but the dark scheme's lines and quieter text are mixed: nord1 to
    /// nord3 sit within 0.13 of its background, so a line between them barely shows on a card,
    /// and its `base04`, nord4, is within 0.04 of its text. The light scheme's fills are mixed:
    /// base16's `base01` and `base02` there are a pale blue (`C2D0E7`), so cards and chips read
    /// as selected.
    public static let nord = Theme(
        id: "nord",
        name: "Nord",
        looks: .both(
            light: Palette(
                .nordLight.replacing(0x0E, with: 0xB48EAD),
                roles: .init(),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .nord,
                roles: .init(),
                grays: .init(line: .mixed, textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its green, done in its purple, arriving in its blue. Its own grays, but the
    /// dark scheme's quieter text is mixed: its `base04` is a step from its comment gray, far
    /// under 4.5:1. The dark scheme's text, `ABB2BF`, is soft, so `Palette` lightens it a step
    /// past the quieter text.
    public static let one = Theme(
        id: "one",
        name: "One",
        looks: .both(
            light: Palette(.oneLight, roles: .init(), isDark: false),
            dark: Palette(
                .onedark,
                roles: .init(),
                grays: .init(textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its green, done in its purple, arriving in its IBM blue, Carbon's link color
    /// (carbondesignsystem.com). Its own grays (Carbon's gray steps), the chip halfway between
    /// `base01` and `base02`, as `base02` is 0.14 out; the dark scheme's quieter text is mixed,
    /// as its `base04` is within 0.06 of its text.
    public static let oxocarbon = Theme(
        id: "oxocarbon",
        name: "Oxocarbon",
        looks: .both(
            light: Palette(
                .oxocarbonLight,
                roles: .init(text: 0x06),
                grays: .init(raised: .between(0x01, 0x02)),
                isDark: false,
            ),
            dark: Palette(
                .oxocarbonDark,
                roles: .init(),
                grays: .init(raised: .between(0x01, 0x02), textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its green, done in its purple, arriving in its blue. Text is `base07`: the dark
    /// scheme's `base05` is a mid gray that read washed out on the workout screen. Its fills are
    /// mixed: its `base01` is 0.11 to 0.13 from its background, a mid gray past a card's step.
    /// The light scheme's lines are mixed too, as its `base02` and `base03` are past a line's;
    /// the dark scheme's are its own.
    public static let paperColor = Theme(
        id: "papercolor",
        name: "PaperColor",
        looks: .both(
            light: Palette(
                .papercolorLight,
                roles: .init(text: 0x07),
                grays: .init(surface: .mixed, raised: .mixed, line: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .papercolorDark,
                roles: .init(text: 0x07),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Rosé Pine has no green. Active in its pine, a teal blue, which stands in for one: its
    /// terminal green and its color for "added content" and "constructive or affirmative
    /// signals" (rosepinetheme.com/en/palette/pine). Done in its iris, arriving in its foam, its
    /// terminal blue. Its own grays throughout: Dawn's card is its `surface`, lighter than its
    /// base, as a grouped list's cards are on iOS.
    public static let rosePine = Theme(
        id: "rose-pine",
        name: "Rosé Pine",
        looks: .both(
            light: Palette(.rosePineDawn, roles: .init(done: 0x0D, railJoin: 0x0C), isDark: false),
            dark: Palette(.rosePine, roles: .init(done: 0x0D, railJoin: 0x0C), isDark: true),
        ),
    )

    /// Active in its green, done in its violet, arriving in its blue. Its own grays throughout.
    public static let selenized = Theme(
        id: "selenized",
        name: "Selenized",
        looks: .both(
            light: Palette(.selenizedLight, roles: .init(text: 0x06), isDark: false),
            dark: Palette(.selenizedDark, roles: .init(text: 0x06), isDark: true),
        ),
    )

    /// Active in its green, `base0B`, a yellow-green that goes olive on the light background,
    /// but its only green: its cyan, `2AA198`, reads cyan. Done in its violet, arriving in its
    /// blue. Text is `base06`: `base05` is 5:1, leaving no room for a quieter text. Its card is
    /// its background highlight (`base01`); its chip and lines are mixed, as base16 puts its
    /// content grays in `base02` and `base03`, 0.26 to 0.32 out.
    public static let solarized = Theme(
        id: "solarized",
        name: "Solarized",
        looks: .both(
            light: Palette(
                .solarizedLight,
                roles: .init(text: 0x06),
                grays: .init(raised: .mixed, line: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .solarizedDark,
                roles: .init(text: 0x06),
                grays: .init(raised: .mixed, line: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its green, tokyonight's `green` (`9ECE6A`, folke/tokyonight.nvim) in both
    /// looks: the light scheme's own `485E30` is a dull olive. Done in its magenta, arriving in
    /// its blue. Text is `base08`, which holds Tokyo Night's own foreground in both schemes
    /// (`C0CAF5`, `343B58`); their `base05` is a dim lavender gray. The dark scheme's `base0D`
    /// holds `blue1` (`2AC3DE`), a cyan, so it takes tokyonight's `blue` (`7AA2F7`) back. Its
    /// own grays. In the light scheme its chip is mixed, as its `base02` is lighter than its
    /// background while its card is darker, and its lines and quieter text are mixed: `base02`
    /// to `base03` spans only 0.08, and its `base04` is within 0.08 of its text. The dark
    /// scheme's `base01` is darker than its background, so it is the well, and the card is mixed.
    public static let tokyoNight = Theme(
        id: "tokyo-night",
        name: "Tokyo Night",
        looks: .both(
            light: Palette(
                .tokyoNightLight.replacing(0x0B, with: 0x9ECE6A),
                roles: .init(text: 0x08),
                grays: .init(raised: .mixed, line: .mixed, textSecondary: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .tokyoNightDark.replacing(0x0D, with: 0x7AA2F7),
                roles: .init(text: 0x08),
                grays: sunkenBase01,
                isDark: true,
            ),
        ),
    )

    /// Active in its green, `base0B`, an olive, but its only green: its aqua, `8ABEB7` (`3E999F`
    /// light), reads cyan. Done in its purple, arriving in its blue. Its own grays, but the
    /// light scheme's fills are mixed, its `base01` (0.09 out) past a card's step; the dark
    /// scheme's lines are mixed, as its comment gray `base03` is 0.44 out. Its quieter text is
    /// its own `base04` though within 0.06 of its text: mixed, it fell under that bright comment
    /// gray, the quietest text.
    public static let tomorrow = Theme(
        id: "tomorrow",
        name: "Tomorrow",
        looks: .both(
            light: Palette(
                .tomorrow,
                roles: .init(),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: false,
            ),
            dark: Palette(.tomorrowNight, roles: .init(), grays: .init(line: .mixed), isDark: true),
        ),
    )

    /// Active in its green+2, `9FC59F` (bbatsov/zenburn-emacs): its base16 `base0B` is its dim
    /// green-2. Done in its pink-purple, arriving in its blue. Its own grays, the chip halfway
    /// between `base01` and `base02`, as `base02` is 0.15 out.
    public static let zenburn = Theme(
        id: "zenburn",
        name: "Zenburn",
        looks: .darkOnly(Palette(
            .zenburn.replacing(0x0B, with: 0x9FC59F),
            roles: .init(),
            grays: .init(raised: .between(0x01, 0x02)),
            isDark: true,
        )),
    )
}
