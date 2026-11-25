import SwiftUI

/// The themes from base16 (their palettes and license: `Base16+Schemes.swift`). Each leads with
/// the color it is known by as `accent`, never a red (`Theme.isRed(_:)`); `done` is a slot apart
/// from it in lightness; a slot that meets its ratios as given wins over one that must be moved.
/// `ThemeContrastTests` holds every look to them. Where a theme's two looks use different slots
/// for a job, or keep a slot that had to move, its comment says why.
nonisolated extension Theme {
    /// Active in its orange, the accent it is known by; done in its green. Every color of the
    /// light look is pastel, under 3.3:1 on its background, so each moves darker.
    public static let ayu = Theme(
        id: "ayu",
        name: "Ayu",
        looks: .both(
            light: Palette(
                .ayuLight,
                roles: .init(text: 0x06, accent: 0x09, done: 0x0B),
                isDark: false,
            ),
            dark: Palette(.ayuDark, roles: .init(accent: 0x09, done: 0x0B), isDark: true),
        ),
    )

    /// Active in its mauve, the flavor's signature; done in its green, apart in lightness.
    public static let catppuccin = Theme(
        id: "catppuccin",
        name: "Catppuccin",
        looks: .both(
            light: Palette(.catppuccinLatte, roles: .init(accent: 0x0E, done: 0x0B), isDark: false),
            dark: Palette(.catppuccinMocha, roles: .init(accent: 0x0E, done: 0x0B), isDark: true),
        ),
    )

    /// Active in its purple (`base0D` here), what Dracula is known by. Its pink sits at the
    /// purple's lightness, so done is its green; arriving is the pink.
    public static let dracula = Theme(
        id: "dracula",
        name: "Dracula",
        looks: .darkOnly(Palette(
            .dracula,
            roles: .init(accent: 0x0D, done: 0x0B, railJoin: 0x0E),
            isDark: true,
        )),
    )

    /// Active in its green, the forest. Done stays its purple, moved a step apart in lightness:
    /// every other hue of the dark look shares the green's lightness, bar the red.
    public static let everforest = Theme(
        id: "everforest",
        name: "Everforest",
        looks: .both(
            light: Palette(.everforestLightMedium, roles: .init(text: 0x06), isDark: false),
            dark: Palette(.everforest, roles: .init(), isDark: true),
        ),
    )

    /// Active in its link blue. Done stays its purple, GitHub's own color for merged, moved a
    /// step apart in lightness rather than swapped for its orange.
    public static let github = Theme(
        id: "github",
        name: "GitHub",
        looks: .both(
            light: Palette(.github, roles: .init(accent: 0x0D, railJoin: 0x0B), isDark: false),
            dark: Palette(.githubDark, roles: .init(accent: 0x0D, railJoin: 0x0B), isDark: true),
        ),
    )

    /// Active in its yellow, the warm color it is known by; the light scheme's is 3.3:1 and
    /// moves darker, as its orange, the one other candidate that passes there, reads as a rust
    /// red. Done in its blue, arriving in its aqua.
    public static let gruvbox = Theme(
        id: "gruvbox",
        name: "Gruvbox",
        looks: .both(
            light: Palette(
                .gruvboxLightMedium,
                roles: .init(accent: 0x0A, done: 0x0D, railJoin: 0x0C),
                isDark: false,
            ),
            dark: Palette(
                .gruvboxDarkMedium,
                roles: .init(accent: 0x0A, done: 0x0D, railJoin: 0x0C),
                isDark: true,
            ),
        ),
    )

    /// Known for its pink-red, so active leads with its turquoise (`base0E` in the light
    /// scheme, `base0C` in the dark: the light one's `base0C` is a red). Done in its warm orange.
    public static let horizon = Theme(
        id: "horizon",
        name: "Horizon",
        looks: .both(
            light: Palette(.horizonLight, roles: .init(accent: 0x0E, done: 0x09), isDark: false),
            dark: Palette(.horizonDark, roles: .init(accent: 0x0C, done: 0x09), isDark: true),
        ),
    )

    /// Active in its wave blue, the Great Wave's; done in its violet; arriving in its yellow.
    public static let kanagawa = Theme(
        id: "kanagawa",
        name: "Kanagawa",
        looks: .darkOnly(Palette(
            .kanagawa,
            roles: .init(accent: 0x0D, railJoin: 0x0A),
            isDark: true,
        )),
    )

    /// Active in its purple: its cyan, as known, is 2.6:1 on the light background. Done in the
    /// cyan. The light scheme's `base05` is that cyan, so its text is `base07`.
    public static let material = Theme(
        id: "material",
        name: "Material",
        looks: .both(
            light: Palette(
                .materialLighter,
                roles: .init(text: 0x07, accent: 0x0E, done: 0x0C),
                isDark: false,
            ),
            dark: Palette(.material, roles: .init(accent: 0x0E, done: 0x0C), isDark: true),
        ),
    )

    /// Known for its pink-red, so active leads with its green; done in its purple.
    public static let monokai = Theme(
        id: "monokai",
        name: "Monokai",
        looks: .darkOnly(Palette(.monokai, roles: .init(), isDark: true)),
    )

    /// Active in its frost blue (`base0C`), what the theme is known by, not its green; arriving
    /// in its yellow (`base0A`), since its blue (`base0D`) sat beside the frost. The light
    /// scheme's `base0E` is a raspberry at the frost's lightness, so done there is its green.
    public static let nord = Theme(
        id: "nord",
        name: "Nord",
        looks: .both(
            light: Palette(
                .nordLight,
                roles: .init(accent: 0x0C, done: 0x0B, railJoin: 0x0A),
                isDark: false,
            ),
            dark: Palette(.nord, roles: .init(accent: 0x0C, railJoin: 0x0A), isDark: true),
        ),
    )

    /// Active in its keyword purple: its blue is 3.9:1 on the light background. Done in its
    /// green, arriving in the blue.
    public static let one = Theme(
        id: "one",
        name: "One",
        looks: .both(
            light: Palette(.oneLight, roles: .init(accent: 0x0E, done: 0x0B), isDark: false),
            dark: Palette(.onedark, roles: .init(accent: 0x0E, done: 0x0B), isDark: true),
        ),
    )

    /// Known for its pink, a red here, so active leads with its IBM blue. Done is `base0C`: a
    /// deep purple in the light scheme, cyan in the dark, where the purple shares the blue's
    /// lightness. Arriving in green, or the light scheme's brown, where the green is too faint.
    public static let oxocarbon = Theme(
        id: "oxocarbon",
        name: "Oxocarbon",
        looks: .both(
            light: Palette(
                .oxocarbonLight,
                roles: .init(text: 0x06, accent: 0x0D, done: 0x0C, railJoin: 0x0F),
                isDark: false,
            ),
            dark: Palette(
                .oxocarbonDark,
                roles: .init(accent: 0x0D, done: 0x0C, railJoin: 0x0B),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue; done in its orange (light) and amber (dark), `base0A`; its purple
    /// and green share the blue's lightness. Text is `base07`: the dark scheme's `base05` is a
    /// mid gray that read washed out on the workout screen.
    public static let paperColor = Theme(
        id: "papercolor",
        name: "PaperColor",
        looks: .both(
            light: Palette(
                .papercolorLight,
                roles: .init(text: 0x07, accent: 0x0D, done: 0x0A, railJoin: 0x0C),
                isDark: false,
            ),
            dark: Palette(
                .papercolorDark,
                roles: .init(text: 0x07, accent: 0x0D, done: 0x0A, railJoin: 0x0C),
                isDark: true,
            ),
        ),
    )

    /// Known for its rose, a red, so active leads with its pine: pine in Dawn, foam in the
    /// dark, where pine is 3.4:1. Done in iris, or in the dark in pine, apart from the foam in
    /// lightness where iris is not. Arriving in love.
    public static let rosePine = Theme(
        id: "rose-pine",
        name: "Rosé Pine",
        looks: .both(
            light: Palette(
                .rosePineDawn,
                roles: .init(accent: 0x0B, done: 0x0D, railJoin: 0x08),
                isDark: false,
            ),
            dark: Palette(
                .rosePine,
                roles: .init(accent: 0x0C, done: 0x0B, railJoin: 0x08),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, or its cyan in the dark, where the blue is 3.9:1. Done in its
    /// violet, kept in the light look and moved a step apart in lightness: its one other
    /// passing color there is the cyan the dark look is active in.
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
                roles: .init(text: 0x06, accent: 0x0C, railJoin: 0x0D),
                isDark: true,
            ),
        ),
    )

    /// Active in its blue, or its cyan in the dark, where the blue is 4.1:1; no color of the
    /// light scheme reaches 4.5:1, so its blue moves darker. Done in its violet, arriving in
    /// its orange. Text is `base06`: `base05` is 5:1, leaving no room for a quieter text.
    public static let solarized = Theme(
        id: "solarized",
        name: "Solarized",
        looks: .both(
            light: Palette(
                .solarizedLight,
                roles: .init(text: 0x06, accent: 0x0D, railJoin: 0x09),
                isDark: false,
            ),
            dark: Palette(
                .solarizedDark,
                roles: .init(text: 0x06, accent: 0x0C, railJoin: 0x09),
                isDark: true,
            ),
        ),
    )

    /// Active in its purple, the night's; done in its orange (light) and its pale cyan (dark),
    /// the colors apart from the purple in lightness.
    public static let tokyoNight = Theme(
        id: "tokyo-night",
        name: "Tokyo Night",
        looks: .both(
            light: Palette(.tokyoNightLight, roles: .init(accent: 0x0E, done: 0x09), isDark: false),
            dark: Palette(.tokyoNightDark, roles: .init(accent: 0x0E, done: 0x0C), isDark: true),
        ),
    )

    /// Active in its blue; its purple shares the blue's lightness, so done is its green.
    public static let tomorrow = Theme(
        id: "tomorrow",
        name: "Tomorrow",
        looks: .both(
            light: Palette(
                .tomorrow,
                roles: .init(accent: 0x0D, done: 0x0B, railJoin: 0x0C),
                isDark: false,
            ),
            dark: Palette(
                .tomorrowNight,
                roles: .init(accent: 0x0D, done: 0x0B, railJoin: 0x0C),
                isDark: true,
            ),
        ),
    )

    /// Active in its khaki yellow, the color it is known by; done in its pink-purple; arriving
    /// in its cyan.
    public static let zenburn = Theme(
        id: "zenburn",
        name: "Zenburn",
        looks: .darkOnly(Palette(
            .zenburn,
            roles: .init(accent: 0x0A, railJoin: 0x0C),
            isDark: true,
        )),
    )
}
