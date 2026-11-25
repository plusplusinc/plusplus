import SwiftUI

/// The themes from base16 (their palettes and license: `Base16+Schemes.swift`), Ayu to Monokai
/// here and the rest in `Themes+Base16+NToZ.swift`. Each gives its three hues the jobs
/// PlusPlus's green, purple, and blue do, by what they mean in the theme's own home (its site,
/// its editor UI, its docs), which each comment names:
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
///
/// The neutrals are the theme's own grays by base16's meanings (`Base16.Grays`) wherever they
/// keep the steps the screens rely on; each comment names the ones it mixes instead, and why.
/// Steps are OKLab lightness from the background toward the text: PlusPlus's card is about
/// 0.04, its chip 0.07, its lines 0.15 to 0.21. A card goes from 0.02 to 0.08, a chip at least
/// 0.025 past the card and no further than 0.14, a line at least 0.07 past the card and no
/// further than 0.26, and the quieter text at least 0.09 short of the text. A fill whose own
/// color is a tint (Nord light's blue, Horizon light's salmon) reads as selected, so it is mixed.
nonisolated extension Theme {
    /// A dark scheme whose `base01` sits below its background: that is its well, sunk below the
    /// screen, and its card is mixed.
    static let sunkenBase01 = Base16.Grays(surface: .mixed, well: .slot(0x01))

    /// Active in its accent, the amber orange of Ayu's own UI (`common.accent`, `F29718` light,
    /// `E6B450` dark, ayu-theme/ayu-colors `themes/*.yaml`): base16's orange keyword, `base09`,
    /// the nearest in both looks, as its amber `base0A` darkens to a brown on the light
    /// background. Done in its purple, arriving in its blue. Its own grays throughout.
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
    /// color for links. Its own grays; Mocha's mantle (`base01`) is darker than its base, so it
    /// is the well, and the card is mixed.
    public static let catppuccin = Theme(
        id: "catppuccin",
        name: "Catppuccin",
        looks: .both(
            light: Palette(.catppuccinLatte, roles: .init(accent: 0x0E, done: 0x0B), isDark: false),
            dark: Palette(
                .catppuccinMocha,
                roles: .init(accent: 0x0E, done: 0x0B),
                grays: sunkenBase01,
                isDark: true,
            ),
        ),
    )

    /// Active in its purple (`base0D` here), the color Dracula is known by and the spec's
    /// focus color (draculatheme.com/spec). Done in its green; arriving in its cyan, the
    /// spec's color for links, as it has no blue. Its own grays; its `base01` is darker than its
    /// background, so it is the well, and the card is mixed.
    public static let dracula = Theme(
        id: "dracula",
        name: "Dracula",
        looks: .darkOnly(Palette(
            .dracula,
            roles: .init(accent: 0x0D, done: 0x0B, railJoin: 0x0C),
            grays: sunkenBase01,
            isDark: true,
        )),
    )

    /// Active in its green, the forest's and its status line's first color
    /// (sainnhe/everforest `palette.md`, `statusline1`). Done in its purple, moved a step apart
    /// in lightness where it shares the green's; arriving in its blue. Its own grays throughout.
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
    /// arriving its blue. Its own grays; the dark scheme's chip is halfway between its `base01`
    /// and `base02`, as `base02` alone (0.16) is past a chip's step.
    public static let github = Theme(
        id: "github",
        name: "GitHub",
        looks: .both(
            light: Palette(.github, roles: .init(), isDark: false),
            dark: Palette(
                .githubDark,
                roles: .init(),
                grays: .init(raised: .between(0x01, 0x02)),
                isDark: true,
            ),
        ),
    )

    /// Active in its aqua. Gruvbox (morhetz/gruvbox) names no accent; its warm yellow and
    /// orange are what it is known by, but on the light background its faded yellow darkens to
    /// a brown and its orange is a rust red, so it leads with the next of its "retro groove"
    /// colors in both looks. Done in its purple, arriving in its blue. Its own grays (bg1, bg2,
    /// and between bg2 and bg3), but the quieter text is mixed: its `base04`, fg4, is within
    /// 0.07 of its text.
    public static let gruvbox = Theme(
        id: "gruvbox",
        name: "Gruvbox",
        looks: .both(
            light: Palette(
                .gruvboxLightMedium,
                roles: .init(accent: 0x0C),
                grays: .init(textSecondary: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .gruvboxDarkMedium,
                roles: .init(accent: 0x0C),
                grays: .init(textSecondary: .mixed),
                isDark: true,
            ),
        ),
    )

    /// Horizon's own accent is its pink-red (`E95378`: its buttons' badge, cursor, and links in
    /// jolaleye/horizon-theme-vscode), a red, so active leads with its turquoise, its
    /// functions' color: `base0E` in the light scheme, `base0C` in the dark. Done in its
    /// purple: the dark scheme's `base0E`; the light scheme has none, so it takes Horizon
    /// Bright's own keyword purple, `8A31B9`. Arriving in its strings' warm orange, as it has
    /// no blue: `base09` light, `base0A` dark, the slots its strings' color is in. Its own
    /// grays, but the light scheme's fills are mixed: its `base01` and `base02` are a salmon
    /// pink (`FADAD1`, `F9CBBE`) that made every card and chip a highlight.
    public static let horizon = Theme(
        id: "horizon",
        name: "Horizon",
        looks: .both(
            light: Palette(
                .horizonLight.replacing(0x0F, with: 0x8A31B9),
                roles: .init(accent: 0x0E, done: 0x0F, railJoin: 0x09),
                grays: .init(surface: .mixed, raised: .mixed),
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
    /// done in its oni violet; arriving in its yellow. Its own grays; its `base01`, sumi ink, is
    /// darker than its background, so it is the well, and the card is mixed.
    public static let kanagawa = Theme(
        id: "kanagawa",
        name: "Kanagawa",
        looks: .darkOnly(Palette(
            .kanagawa,
            roles: .init(accent: 0x0D, railJoin: 0x0A),
            grays: sunkenBase01,
            isDark: true,
        )),
    )

    /// Active in its teal, `80CBC4`: Material Theme's accent comes from the theme
    /// (material-theme.com/docs/configuration/accents), and its own is that teal, which
    /// base16's lighter scheme keeps as `base05` and its dark one leaves out, so the dark look
    /// takes it into `base0F` (an unused red). Done in its purple, arriving in its blue. The
    /// light scheme's `base05` is the teal, so its text is `base07`. Its own grays, but the light
    /// scheme's chip and lines are mixed: its `base02` is a pale teal 0.02 past its card, and
    /// its lines (0.09) would sit almost on the chip.
    public static let material = Theme(
        id: "material",
        name: "Material",
        looks: .both(
            light: Palette(
                .materialLighter,
                roles: .init(text: 0x07, accent: 0x05),
                grays: .init(raised: .mixed, line: .mixed),
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
    /// color; done in its purple, arriving in its blue. Its own grays throughout.
    public static let monokai = Theme(
        id: "monokai",
        name: "Monokai",
        looks: .darkOnly(Palette(.monokai, roles: .init(), isDark: true)),
    )
}
