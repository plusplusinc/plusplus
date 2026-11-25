import SwiftUI

/// The themes from base16 (their palettes and license: `Base16+Schemes.swift`). Each gives its
/// three hues the jobs PlusPlus's green, purple, and blue do, by what they mean in the theme's
/// own home (its site, its editor UI, its docs), which each comment names:
/// - `accent`, what is active and the + that makes something, is the color the theme's home
///   uses for its main action or accent, or for "add" where it has one; never a red
///   (`Theme.isRed(_:)`).
/// - `done` is the theme's purple, so purple reads as done whichever theme is chosen; its green
///   where active is the purple.
/// - `railJoin`, what is arriving, is its blue; its cyan or yellow where active is the blue.
///
/// A theme's light and dark looks use the same colors. Where one has to darken to reach its
/// ratio on a light background, `Palette` moves it in lightness only; where that would lose the
/// color (a yellow gone brown), the theme leads with its next color in both looks.
/// `ThemeContrastTests` holds every look to the ratios.
nonisolated extension Theme {
    /// Active in its accent, the amber orange of Ayu's own UI (`common.accent`, `F29718` light,
    /// `E6B450` dark, ayu-theme/ayu-colors `themes/*.yaml`): base16's orange keyword, `base09`,
    /// the nearest in both looks, as its amber `base0A` darkens to a brown on the light
    /// background. Done in its purple, arriving in its blue.
    public static let ayu = Theme(
        id: "ayu",
        name: "Ayu",
        looks: .both(
            light: Palette(.ayuLight, roles: .init(text: 0x06, accent: 0x09), isDark: false),
            dark: Palette(.ayuDark, roles: .init(accent: 0x09), isDark: true),
        ),
    )

    /// Active in its mauve, the accent every Catppuccin port defaults to ("`mauve` is our
    /// default", catppuccin/vscode). Done in its green, arriving in its blue, the style guide's
    /// color for links.
    public static let catppuccin = Theme(
        id: "catppuccin",
        name: "Catppuccin",
        looks: .both(
            light: Palette(.catppuccinLatte, roles: .init(accent: 0x0E, done: 0x0B), isDark: false),
            dark: Palette(.catppuccinMocha, roles: .init(accent: 0x0E, done: 0x0B), isDark: true),
        ),
    )

    /// Active in its purple (`base0D` here), the color Dracula is known by and the spec's
    /// focus color (draculatheme.com/spec). Done in its green; arriving in its cyan, the
    /// spec's color for links, as it has no blue.
    public static let dracula = Theme(
        id: "dracula",
        name: "Dracula",
        looks: .darkOnly(Palette(
            .dracula,
            roles: .init(accent: 0x0D, done: 0x0B, railJoin: 0x0C),
            isDark: true,
        )),
    )

    /// Active in its green, the forest's and its status line's first color
    /// (sainnhe/everforest `palette.md`, `statusline1`). Done in its purple, moved a step apart
    /// in lightness where it shares the green's; arriving in its blue.
    public static let everforest = Theme(
        id: "everforest",
        name: "Everforest",
        looks: .both(
            light: Palette(.everforestLightMedium, roles: .init(text: 0x06), isDark: false),
            dark: Palette(.everforest, roles: .init(), isDark: true),
        ),
    )

    /// GitHub's own meanings (Primer's color roles, primer.style): green is `success`, its
    /// primary buttons, the one that creates something; purple is `done`, completed and merged;
    /// blue is `accent`, links and what is selected. So active is its green, done its purple,
    /// arriving its blue.
    public static let github = Theme(
        id: "github",
        name: "GitHub",
        looks: .both(
            light: Palette(.github, roles: .init(), isDark: false),
            dark: Palette(.githubDark, roles: .init(), isDark: true),
        ),
    )

    /// Active in its aqua. Gruvbox (morhetz/gruvbox) names no accent; its warm yellow and
    /// orange are what it is known by, but on the light background its faded yellow darkens to
    /// a brown and its orange is a rust red, so it leads with the next of its "retro groove"
    /// colors in both looks. Done in its purple, arriving in its blue.
    public static let gruvbox = Theme(
        id: "gruvbox",
        name: "Gruvbox",
        looks: .both(
            light: Palette(.gruvboxLightMedium, roles: .init(accent: 0x0C), isDark: false),
            dark: Palette(.gruvboxDarkMedium, roles: .init(accent: 0x0C), isDark: true),
        ),
    )

    /// Horizon's own accent is its pink-red (`E95378`: its buttons' badge, cursor, and links in
    /// jolaleye/horizon-theme-vscode), a red, so active leads with its turquoise, its
    /// functions' color: `base0E` in the light scheme, `base0C` in the dark. Done in its
    /// purple: the dark scheme's `base0E`; the light scheme has none, so it takes Horizon
    /// Bright's own keyword purple, `8A31B9`. Arriving in its strings' warm orange, as it has
    /// no blue: `base09` light, `base0A` dark, the slots its strings' color is in.
    public static let horizon = Theme(
        id: "horizon",
        name: "Horizon",
        looks: .both(
            light: Palette(
                .horizonLight.replacing(0x0F, with: 0x8A31B9),
                roles: .init(accent: 0x0E, done: 0x0F, railJoin: 0x09),
                isDark: false,
            ),
            dark: Palette(
                .horizonDark,
                roles: .init(accent: 0x0C, railJoin: 0x0A),
                isDark: true,
            ),
        ),
    )

    /// Active in its crystal blue, its functions' and titles' color (rebelot/kanagawa.nvim);
    /// done in its oni violet; arriving in its yellow.
    public static let kanagawa = Theme(
        id: "kanagawa",
        name: "Kanagawa",
        looks: .darkOnly(Palette(
            .kanagawa,
            roles: .init(accent: 0x0D, railJoin: 0x0A),
            isDark: true,
        )),
    )

    /// Active in its teal, `80CBC4`: Material Theme's accent comes from the theme
    /// (material-theme.com/docs/configuration/accents), and its own is that teal, which
    /// base16's lighter scheme keeps as `base05` and its dark one leaves out, so the dark look
    /// takes it into `base0F` (an unused red). Done in its purple, arriving in its blue. The
    /// light scheme's `base05` is the teal, so its text is `base07`.
    public static let material = Theme(
        id: "material",
        name: "Material",
        looks: .both(
            light: Palette(
                .materialLighter,
                roles: .init(text: 0x07, accent: 0x05),
                isDark: false,
            ),
            dark: Palette(
                .material.replacing(0x0F, with: 0x80CBC4),
                roles: .init(accent: 0x0F),
                isDark: true,
            ),
        ),
    )

    /// Monokai's own color is its pink-red, so active leads with its green, its functions'
    /// color; done in its purple, arriving in its blue.
    public static let monokai = Theme(
        id: "monokai",
        name: "Monokai",
        looks: .darkOnly(Palette(.monokai, roles: .init(), isDark: true)),
    )

    /// Active in its frost blue (`base0C`), what the theme is known by (nordtheme.com's
    /// `nord8`, its primary accent), settled with the maintainer. Done in its purple slot,
    /// `base0E`, in both looks: the light scheme's is a deep raspberry. Arriving in its yellow,
    /// as its blue (`base0D`) sits beside the frost.
    public static let nord = Theme(
        id: "nord",
        name: "Nord",
        looks: .both(
            light: Palette(.nordLight, roles: .init(accent: 0x0C, railJoin: 0x0A), isDark: false),
            dark: Palette(.nord, roles: .init(accent: 0x0C, railJoin: 0x0A), isDark: true),
        ),
    )

    /// Active in its blue: Atom's One UI takes its accent from the syntax background's hue,
    /// blue (`@ui-hue` 220, atom/atom `one-dark-ui` and `one-light-ui`). Done in its purple,
    /// arriving in its cyan.
    public static let one = Theme(
        id: "one",
        name: "One",
        looks: .both(
            light: Palette(.oneLight, roles: .init(accent: 0x0D, railJoin: 0x0C), isDark: false),
            dark: Palette(.onedark, roles: .init(accent: 0x0D, railJoin: 0x0C), isDark: true),
        ),
    )

    /// Active in its IBM blue, `0F62FE`, Carbon's primary button and link color
    /// (carbondesignsystem.com, `$button-primary`), "centered around a vibrant set of blues"
    /// (nyoom-engineering/oxocarbon.nvim). Done in its purple; arriving in its teal, `08BDBA`,
    /// `base07` in both of oxocarbon.nvim's palettes; base16's light scheme has a gray there
    /// and a purple in `base0C`, so it takes the teal back.
    public static let oxocarbon = Theme(
        id: "oxocarbon",
        name: "Oxocarbon",
        looks: .both(
            light: Palette(
                .oxocarbonLight.replacing(0x07, with: 0x08BDBA),
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x07),
                isDark: false,
            ),
            dark: Palette(
                .oxocarbonDark,
                roles: .init(accent: 0x0D, railJoin: 0x07),
                isDark: true,
            ),
        ),
    )

    /// Active in the one color PaperColor calls its accent, `color12`
    /// (NLKNguyen/papercolor-theme `DESIGN.md`): its orange in light, darkened a step to a
    /// burnt orange, and its amber in dark; `base0A` in both. Done in its purple, arriving in
    /// its blue. Text is `base07`: the dark scheme's `base05` is a mid gray that read washed out
    /// on the workout screen.
    public static let paperColor = Theme(
        id: "papercolor",
        name: "PaperColor",
        looks: .both(
            light: Palette(
                .papercolorLight,
                roles: .init(text: 0x07, accent: 0x0A),
                isDark: false,
            ),
            dark: Palette(
                .papercolorDark,
                roles: .init(text: 0x07, accent: 0x0A),
                isDark: true,
            ),
        ),
    )

    /// Active in its pine, Rosé Pine's color for "added content" and "constructive or
    /// affirmative signals" (rosepinetheme.com/en/palette/pine), and half its name; its rose
    /// and love are reds. Done in its iris, arriving in its foam, its terminal blue.
    public static let rosePine = Theme(
        id: "rose-pine",
        name: "Rosé Pine",
        looks: .both(
            light: Palette(.rosePineDawn, roles: .init(done: 0x0D, railJoin: 0x0C), isDark: false),
            dark: Palette(.rosePine, roles: .init(done: 0x0D, railJoin: 0x0C), isDark: true),
        ),
    )

    /// Active in its blue, Selenized's values (jan-warchol/selenized `the-values.md`) naming no
    /// accent of their own; done in its violet, arriving in its cyan.
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
    /// a step there. Done in its violet, arriving in its cyan. Text is `base06`: `base05` is
    /// 5:1, leaving no room for a quieter text.
    public static let solarized = Theme(
        id: "solarized",
        name: "Solarized",
        looks: .both(
            light: Palette(
                .solarizedLight,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x0C),
                isDark: false,
            ),
            dark: Palette(
                .solarizedDark,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x0C),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, its titles', directories', and normal mode's color
    /// (folke/tokyonight.nvim); done in its magenta, arriving in its cyan. Text is `base08`,
    /// which holds Tokyo Night's own foreground in both schemes (`C0CAF5`, `343B58`); their
    /// `base05` is a dim lavender gray.
    public static let tokyoNight = Theme(
        id: "tokyo-night",
        name: "Tokyo Night",
        looks: .both(
            light: Palette(
                .tokyoNightLight,
                roles: .init(text: 0x08, accent: 0x0D, railJoin: 0x0C),
                isDark: false,
            ),
            dark: Palette(
                .tokyoNightDark,
                roles: .init(text: 0x08, accent: 0x0D, railJoin: 0x0C),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, its functions' and directories' color (chriskempson/tomorrow-theme,
    /// `vim/colors`); its status line's yellow darkens to a brown on white. Done in its purple,
    /// moved a step apart in lightness; arriving in its aqua.
    public static let tomorrow = Theme(
        id: "tomorrow",
        name: "Tomorrow",
        looks: .both(
            light: Palette(.tomorrow, roles: .init(accent: 0x0D, railJoin: 0x0C), isDark: false),
            dark: Palette(.tomorrowNight, roles: .init(accent: 0x0D, railJoin: 0x0C), isDark: true),
        ),
    )

    /// Active in its khaki yellow, its status line's and keywords' color (jnurmine/Zenburn,
    /// `StatusLine` `CCDC90`, `Keyword` `F0DFAF`); done in its pink-purple; arriving in its
    /// blue.
    public static let zenburn = Theme(
        id: "zenburn",
        name: "Zenburn",
        looks: .darkOnly(Palette(.zenburn, roles: .init(accent: 0x0A), isDark: true)),
    )
}
