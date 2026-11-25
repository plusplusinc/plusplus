import SwiftUI

/// The themes from base16 (their palettes and license: `Base16+Schemes.swift`), Ayu to Monokai
/// here and the rest in `Themes+Base16+NToZ.swift`. Every theme gives its colors PlusPlus's
/// meanings, which come before what the theme is known by:
/// - `accent`, what is active and the + that makes something, is the theme's green: the
///   nicest it has, as a + key and a set bar, in both looks. Usually `base0B`; a theme takes its
///   aqua where that reads greener and `base0B` is a yellow-olive or darkens to one, and its own
///   source's green where base16's file has none or a dull one. Each comment says which and
///   why. Never a red (`Theme.isRed(_:)`).
/// - `done` is the theme's purple.
/// - `railJoin`, what is arriving, is its blue; its cyan where it has no blue.
///
/// A theme's light and dark looks use the same slots. Where one has to darken to reach its
/// ratio on a light background, `Palette` moves it in lightness only.
/// `ThemeContrastTests` holds every look to the ratios.
///
/// The neutrals are the theme's own grays by base16's meanings (`Base16.Grays`) wherever they
/// keep the steps the screens rely on; each comment names the ones it mixes instead, and why.
/// Steps are OKLab lightness from the background toward the text: PlusPlus's card is about
/// 0.04, its chip 0.07, its lines 0.15 to 0.21. A card goes from 0.02 to 0.08, a chip at least
/// 0.025 past the card and no further than 0.14, a line at least 0.07 past the card and no
/// further than 0.26, and the quieter text at least 0.09 short of the text (`Palette.textStep`:
/// where a scheme's text is softer, it is moved that far, in lightness only). A fill whose own
/// color is a tint (Nord light's blue, Horizon light's salmon) reads as selected, so it is mixed.
nonisolated extension Theme {
    /// A dark scheme whose `base01` sits below its background: that is its well, sunk below the
    /// screen, and its card is mixed.
    static let sunkenBase01 = Base16.Grays(surface: .mixed, well: .slot(0x01))

    /// Active in its green, `base0B`. Done in its purple, arriving in its blue. Its own grays
    /// throughout.
    public static let ayu = Theme(
        id: "ayu",
        name: "Ayu",
        looks: .both(
            light: Palette(.ayuLight, roles: .init(text: 0x06), isDark: false),
            dark: Palette(.ayuDark, roles: .init(), isDark: true),
        ),
    )

    /// Active in its green, done in its mauve, arriving in its blue. Its own grays; Mocha's
    /// mantle (`base01`) is darker than its base, so it is the well, and the card is mixed.
    public static let catppuccin = Theme(
        id: "catppuccin",
        name: "Catppuccin",
        looks: .both(
            light: Palette(.catppuccinLatte, roles: .init(), isDark: false),
            dark: Palette(
                .catppuccinMocha,
                roles: .init(),
                grays: sunkenBase01,
                isDark: true,
            ),
        ),
    )

    /// Active in its green, done in its purple (`base0D` here), arriving in its cyan, as it has
    /// no blue. Its own grays; its `base01` is darker than its background, so it is the well, and
    /// the card is mixed.
    public static let dracula = Theme(
        id: "dracula",
        name: "Dracula",
        looks: .darkOnly(Palette(
            .dracula,
            roles: .init(done: 0x0D, railJoin: 0x0C),
            grays: sunkenBase01,
            isDark: true,
        )),
    )

    /// Active in its aqua, `base0C`, in both looks: its green (`base0B`) darkens to an olive on
    /// the light background, and in the dark look the aqua is the cleaner green beside a sage.
    /// Done in its purple, arriving in its blue. Its own grays throughout.
    public static let everforest = Theme(
        id: "everforest",
        name: "Everforest",
        looks: .both(
            light: Palette(
                .everforestLightMedium,
                roles: .init(text: 0x06, accent: 0x0C),
                isDark: false,
            ),
            dark: Palette(.everforest, roles: .init(accent: 0x0C), isDark: true),
        ),
    )

    /// Active in its green, done in its purple, arriving in its blue: Primer's own meanings
    /// (primer.style), green `success` and its primary buttons, purple `done`, blue `accent`.
    /// Its own grays; the dark scheme's chip is halfway between its `base01` and `base02`, as
    /// `base02` alone (0.16) is past a chip's step.
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

    /// Active in its aqua, `base0C`, in both looks: its green (`base0B`) is a yellow-olive, and
    /// the aqua reads as the clean green. Done in its purple, arriving in its blue. Its own grays
    /// (bg1, bg2, and between bg2 and bg3), but the quieter text is mixed: its `base04`, fg4,
    /// is within 0.07 of its text.
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

    /// Its base16 files put a red in `base0D` and, in the dark scheme, a peach in `base0B`, so
    /// it takes its own terminal colors (jolaleye/horizon-theme-vscode, the same in both
    /// looks): active in its green, `29D398`, done in its purple, arriving in its blue,
    /// `26BBD9`. The dark scheme's purple is its `base0E`; the light scheme has none, so it
    /// takes Horizon Bright's keyword purple, `8A31B9`. Its own grays, but the light scheme's
    /// fills are mixed: its `base01` and `base02` are a salmon pink (`FADAD1`, `F9CBBE`) that
    /// made every card and chip a highlight.
    public static let horizon = Theme(
        id: "horizon",
        name: "Horizon",
        looks: .both(
            light: Palette(
                .horizonLight.replacing(0x0B, with: 0x29D398).replacing(0x0D, with: 0x26BBD9)
                    .replacing(0x0F, with: 0x8A31B9),
                roles: .init(done: 0x0F),
                grays: .init(surface: .mixed, raised: .mixed),
                isDark: false,
            ),
            dark: Palette(
                .horizonDark.replacing(0x0B, with: 0x29D398).replacing(0x0D, with: 0x26BBD9),
                roles: .init(),
                isDark: true,
            ),
        ),
    )

    /// Active in its spring green, `98BB6C`, its strings' color (rebelot/kanagawa.nvim): its
    /// base16 `base0B` is the duller autumn green. Done in its oni violet, arriving in its
    /// crystal blue. Its own grays; its `base01`, sumi ink, is darker than its background, so
    /// it is the well, and the card is mixed. Its chips are mixed too: its `base02` is the navy
    /// it selects text with, `223249`, which made every filter and equipment chip read as picked.
    public static let kanagawa = Theme(
        id: "kanagawa",
        name: "Kanagawa",
        looks: .darkOnly(Palette(
            .kanagawa.replacing(0x0B, with: 0x98BB6C),
            roles: .init(),
            grays: Base16.Grays(surface: .mixed, raised: .mixed, well: .slot(0x01)),
            isDark: true,
        )),
    )

    /// Active in its green, done in its purple, arriving in its blue. The light scheme's
    /// `base05` is its teal, so its text is `base07`. Its own grays, but the light scheme's chip
    /// and lines are mixed: its `base02` is a pale teal 0.02 past its card, and its lines (0.09)
    /// would sit almost on the chip.
    public static let material = Theme(
        id: "material",
        name: "Material",
        looks: .both(
            light: Palette(
                .materialLighter,
                roles: .init(text: 0x07),
                grays: .init(raised: .mixed, line: .mixed),
                isDark: false,
            ),
            dark: Palette(.material, roles: .init(), isDark: true),
        ),
    )

    /// Active in its green, done in its purple, arriving in its blue. Its own grays throughout.
    public static let monokai = Theme(
        id: "monokai",
        name: "Monokai",
        looks: .darkOnly(Palette(.monokai, roles: .init(), isDark: true)),
    )
}
