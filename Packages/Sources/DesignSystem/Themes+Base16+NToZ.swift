import SwiftUI

/// The base16 themes from Nord to Zenburn, by the rules in `Themes+Base16.swift`.
nonisolated extension Theme {
    /// Active in its frost blue (`base0C`), what the theme is known by (nordtheme.com's
    /// `nord8`, its primary accent), settled with the maintainer. Done in its purple, `nord15`
    /// (`B48EAD`), in both looks: base16's light scheme has a raspberry that reads as a red in
    /// its purple slot, so it takes `nord15` back, darkened for the light background. Arriving in
    /// its yellow, as its blue (`base0D`) sits beside the frost. Its own grays, the Polar Night
    /// steps, but the dark scheme's lines and quieter text are mixed: nord1 to nord3 sit within
    /// 0.13 of its background, so a line between them barely shows on a card, and its `base04`,
    /// nord4, is within 0.04 of its text. The light scheme's fills are mixed: base16's
    /// `base01` and `base02` there are a pale blue (`C2D0E7`), so cards and chips read as
    /// selected.
    public static let nord = Theme(
        id: "nord",
        name: "Nord",
        looks: .both(
            light: Palette(
                .nordLight.replacing(0x0E, with: 0xB48EAD),
                roles: .init(accent: 0x0C, railJoin: 0x0A),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .nord,
                roles: .init(accent: 0x0C, railJoin: 0x0A),
                grays: .init(line: .mixed, textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue: Atom's One UI takes its accent from the syntax background's hue,
    /// blue (`@ui-hue` 220, atom/atom `one-dark-ui` and `one-light-ui`). Done in its purple,
    /// set a step apart from the blue in lightness (`Palette.doneGap`); arriving in its cyan. Its
    /// own grays, but the dark scheme's quieter text is mixed: its
    /// `base04` is a step from its comment gray, far under 4.5:1, and its text is low already.
    public static let one = Theme(
        id: "one",
        name: "One",
        looks: .both(
            light: Palette(.oneLight, roles: .init(accent: 0x0D, railJoin: 0x0C), isDark: false),
            dark: Palette(
                .onedark,
                roles: .init(accent: 0x0D, railJoin: 0x0C),
                grays: .init(textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its IBM blue, `0F62FE`, Carbon's primary button and link color
    /// (carbondesignsystem.com, `$button-primary`), "centered around a vibrant set of blues"
    /// (nyoom-engineering/oxocarbon.nvim). Done in its purple, set a step apart from the blue
    /// in lightness (`Palette.doneGap`); arriving in its teal, `08BDBA`,
    /// `base07` in both of oxocarbon.nvim's palettes; base16's light scheme has a gray there
    /// and a purple in `base0C`, so it takes the teal back. Its own grays (Carbon's gray steps),
    /// the chip halfway between `base01` and `base02`, as `base02` is 0.14 out; the dark
    /// scheme's quieter text is mixed, as its `base04` is within 0.06 of its text.
    public static let oxocarbon = Theme(
        id: "oxocarbon",
        name: "Oxocarbon",
        looks: .both(
            light: Palette(
                .oxocarbonLight.replacing(0x07, with: 0x08BDBA),
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x07),
                grays: .init(raised: .between(0x01, 0x02)),
                isDark: false,
            ),
            dark: Palette(
                .oxocarbonDark,
                roles: .init(accent: 0x0D, railJoin: 0x07),
                grays: .init(raised: .between(0x01, 0x02), textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in the one color PaperColor calls its accent, `color12`
    /// (NLKNguyen/papercolor-theme `DESIGN.md`): its orange in light, darkened a step to a
    /// burnt orange, and its amber in dark; `base0A` in both. Done in its purple, arriving in
    /// its blue. Text is `base07`: the dark scheme's `base05` is a mid gray that read washed out
    /// on the workout screen. Its fills are mixed: its `base01` is 0.11 to 0.13 from its
    /// background, a mid gray past a card's step. The light scheme's lines are mixed too, as
    /// its `base02` and `base03` are past a line's; the dark scheme's are its own.
    public static let paperColor = Theme(
        id: "papercolor",
        name: "PaperColor",
        looks: .both(
            light: Palette(
                .papercolorLight,
                roles: .init(text: 0x07, accent: 0x0A),
                grays: .init(surface: .mixed, raised: .mixed, line: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .papercolorDark,
                roles: .init(text: 0x07, accent: 0x0A),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its pine, Rosé Pine's color for "added content" and "constructive or
    /// affirmative signals" (rosepinetheme.com/en/palette/pine), and half its name; its rose
    /// and love are reds. Done in its iris, arriving in its foam, its terminal blue. Its own
    /// grays throughout: Dawn's card is its `surface`, lighter than its base, as a grouped list's
    /// cards are on iOS.
    public static let rosePine = Theme(
        id: "rose-pine",
        name: "Rosé Pine",
        looks: .both(
            light: Palette(.rosePineDawn, roles: .init(done: 0x0D, railJoin: 0x0C), isDark: false),
            dark: Palette(.rosePine, roles: .init(done: 0x0D, railJoin: 0x0C), isDark: true),
        ),
    )

    /// Active in its blue, Selenized's values (jan-warchol/selenized `the-values.md`) naming no
    /// accent of their own; done in its violet, set a step apart from the blue in lightness
    /// (`Palette.doneGap`); arriving in its cyan. Its own grays throughout.
    public static let selenized = Theme(
        id: "selenized",
        name: "Selenized",
        looks: .both(
            light: Palette(
                .selenizedLight,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x0C),
                isDark: false,
            ),
            dark: Palette(
                .selenizedDark,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x0C),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, Solarized naming no accent of its own (ethanschoonover.com/solarized:
    /// "eight accent colors"); no color of the light scheme reaches 4.5:1, so its blue darkens
    /// a step there. Done in its violet, set a step apart from the blue in lightness
    /// (`Palette.doneGap`); arriving in its cyan. Text is `base06`: `base05` is
    /// 5:1, leaving no room for a quieter text. Its card is its background highlight
    /// (`base01`); its chip and lines are mixed, as base16 puts its content grays in `base02`
    /// and `base03`, 0.26 to 0.32 out.
    public static let solarized = Theme(
        id: "solarized",
        name: "Solarized",
        looks: .both(
            light: Palette(
                .solarizedLight,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x0C),
                grays: .init(raised: .mixed, line: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .solarizedDark,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x0C),
                grays: .init(raised: .mixed, line: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, its titles', directories', and normal mode's color
    /// (folke/tokyonight.nvim); done in its magenta, set a step apart from the blue in
    /// lightness (`Palette.doneGap`); arriving in its cyan. Text is `base08`,
    /// which holds Tokyo Night's own foreground in both schemes (`C0CAF5`, `343B58`); their
    /// `base05` is a dim lavender gray. The dark scheme's `base0D` holds `blue1` (`2AC3DE`), a
    /// cyan, and its `base0C` a near-white `B4F9F8`, so they take tokyonight's `blue` (`7AA2F7`)
    /// and `cyan` (`7DCFFF`) back. Its own grays. In the light scheme its chip is `base02`,
    /// lighter than its background, and its lines and quieter text are mixed: `base02` to
    /// `base03` spans only 0.08, and its `base04` is within 0.08 of its text. The dark scheme's
    /// `base01` is darker than its background, so it is the well, and the card is mixed.
    public static let tokyoNight = Theme(
        id: "tokyo-night",
        name: "Tokyo Night",
        looks: .both(
            light: Palette(
                .tokyoNightLight,
                roles: .init(text: 0x08, accent: 0x0D, railJoin: 0x0C),
                grays: .init(line: .mixed, textSecondary: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .tokyoNightDark.replacing(0x0D, with: 0x7AA2F7).replacing(0x0C, with: 0x7DCFFF),
                roles: .init(text: 0x08, accent: 0x0D, railJoin: 0x0C),
                grays: sunkenBase01,
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, its functions' and directories' color (chriskempson/tomorrow-theme,
    /// `vim/colors`); its status line's yellow darkens to a brown on white. Done in its purple,
    /// moved a step apart in lightness; arriving in its aqua. Its own grays, but the light
    /// scheme's fills are mixed, its `base01` (0.09 out) past a card's step; the dark scheme's
    /// lines are mixed, as its comment gray `base03` is 0.44 out. Its quieter text is its own
    /// `base04` though within 0.06 of its text: mixed, it fell under that bright comment gray,
    /// the quietest text.
    public static let tomorrow = Theme(
        id: "tomorrow",
        name: "Tomorrow",
        looks: .both(
            light: Palette(
                .tomorrow,
                roles: .init(accent: 0x0D, railJoin: 0x0C),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .tomorrowNight,
                roles: .init(accent: 0x0D, railJoin: 0x0C),
                grays: .init(line: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Active in its khaki yellow, its status line's and keywords' color (jnurmine/Zenburn,
    /// `StatusLine` `CCDC90`, `Keyword` `F0DFAF`); done in its pink-purple; arriving in its
    /// blue. Its own grays, the chip halfway between `base01` and `base02`, as `base02` is 0.15
    /// out.
    public static let zenburn = Theme(
        id: "zenburn",
        name: "Zenburn",
        looks: .darkOnly(Palette(
            .zenburn,
            roles: .init(accent: 0x0A),
            grays: .init(raised: .between(0x01, 0x02)),
            isDark: true,
        )),
    )
}
