import SwiftUI

/// PlusPlus's own themes beside its default. Each look is five colors (`Palette`): ground, text,
/// active, done, arriving, as designed; `Palette` moves one in lightness only where a job's
/// ratio needs it, and `ThemeContrastTests` holds every look to them. A theme gives its three
/// colors their jobs freely, so active is not always a green nor done a purple, but active is
/// never a red (`Theme.isRed(_:)`), done stands apart from active in lightness as well as hue
/// and from to-do, and no light look uses a darkened yellow or gold, which reads as mud.
nonisolated extension Theme {
    /// The order on the Theme screen after PlusPlus: curated, the quiet grounds first and the
    /// playful ones last.
    static let ours: [Self] = [
        .black, .iron, .chalk, .navy, .ocean, .forest, .lavender, .rose, .ink, .plum, .candy,
    ]

    /// PlusPlus dark's own colors on true black, for an OLED screen: active green, done purple,
    /// arriving blue.
    public static let black = Theme(
        id: "black",
        name: "Black",
        looks: .darkOnly(Palette(
            ground: 0x000000,
            text: 0xF5F3EE,
            active: 0x46D17C,
            done: 0xB08CF0,
            arriving: 0x5CA8F5,
        )),
    )

    /// Steel and rust: active steel blue, done rust, arriving a paler, clearer blue.
    public static let iron = Theme(
        id: "iron",
        name: "Iron",
        looks: .both(
            light: Palette(
                ground: 0xF3F4F5,
                text: 0x1C1F23,
                active: 0x3F5F7F,
                done: 0xB5562B,
                arriving: 0x2A6FB0,
            ),
            dark: Palette(
                ground: 0x17191C,
                text: 0xE6E8EB,
                active: 0x9DB7D1,
                done: 0xD98A54,
                arriving: 0xCFE3F5,
            ),
        ),
    )

    /// Chalk on a slate board, in grays alone, told apart by three clear steps of lightness:
    /// active the strongest, done the middle, to-do the quietest, each at least 0.15 from the
    /// next (`Palette.grayStep`).
    public static let chalk = Theme(
        id: "chalk",
        name: "Chalk",
        looks: .both(
            light: Palette(
                ground: 0xF4F2EC,
                text: 0x2A2C2B,
                active: 0x1E2120,
                done: 0x5E615D,
                arriving: 0x4E514E,
            ),
            dark: Palette(
                ground: 0x1B1F1E,
                text: 0xF2F0E8,
                active: 0xF2F0E8,
                done: 0x9A9D99,
                arriving: 0xC9CCC8,
            ),
        ),
    )

    /// Navy and brass, sober: active blue, done brass (an amber in light), arriving sky.
    public static let navy = Theme(
        id: "navy",
        name: "Navy",
        looks: .both(
            light: Palette(
                ground: 0xF4F6FB,
                text: 0x121B33,
                active: 0x1F3F99,
                done: 0xB36B00,
                arriving: 0x0F7F9C,
            ),
            dark: Palette(
                ground: 0x0E1830,
                text: 0xE6EBF7,
                active: 0x7FA8F5,
                done: 0xD9B45A,
                arriving: 0x8FD3E8,
            ),
        ),
    )

    /// Sea blue and coral: active sea blue, done coral, arriving seafoam.
    public static let ocean = Theme(
        id: "ocean",
        name: "Ocean",
        looks: .both(
            light: Palette(
                ground: 0xEEF6FA,
                text: 0x0C2C3A,
                active: 0x0B74AD,
                done: 0xC4553F,
                arriving: 0x178A6E,
            ),
            dark: Palette(
                ground: 0x06202E,
                text: 0xDDEFF5,
                active: 0x4CC3F0,
                done: 0xFF9E8A,
                arriving: 0x7FE0C0,
            ),
        ),
    )

    /// Forest green and bark brown, apart in lightness: active leaf green, done bark, arriving
    /// a stream blue.
    public static let forest = Theme(
        id: "forest",
        name: "Forest",
        looks: .both(
            light: Palette(
                ground: 0xF3F5EC,
                text: 0x1B291D,
                active: 0x2E6B34,
                done: 0xA06A35,
                arriving: 0x2C6A86,
            ),
            dark: Palette(
                ground: 0x111B14,
                text: 0xE5ECDD,
                active: 0x6FBF73,
                done: 0xA9764A,
                arriving: 0x8FBFD6,
            ),
        ),
    )

    /// Lavender and sky: active lavender, done sky blue, arriving sage.
    public static let lavender = Theme(
        id: "lavender",
        name: "Lavender",
        looks: .both(
            light: Palette(
                ground: 0xF5F2FB,
                text: 0x28243C,
                active: 0x7B5FD0,
                done: 0x2D76B8,
                arriving: 0x2F8A5F,
            ),
            dark: Palette(
                ground: 0x1C1A2A,
                text: 0xE6E2F4,
                active: 0xB8A4F0,
                done: 0x8FC4F0,
                arriving: 0xA9D4B0,
            ),
        ),
    )

    /// Warm blush: active rose pink, done sage, arriving violet.
    public static let rose = Theme(
        id: "rose",
        name: "Rose",
        looks: .both(
            light: Palette(
                ground: 0xFCF1F2,
                text: 0x33211F,
                active: 0xC2408F,
                done: 0x2F7E4B,
                arriving: 0x7A55C8,
            ),
            dark: Palette(
                ground: 0x241A1E,
                text: 0xF5E8EA,
                active: 0xF58FCB,
                done: 0xA8D8B0,
                arriving: 0xC7B0F5,
            ),
        ),
    )

    /// Fountain-pen ink blue for active and sepia for done, on cream in light and a blue-black
    /// in dark; arriving teal.
    public static let ink = Theme(
        id: "ink",
        name: "Ink",
        looks: .both(
            light: Palette(
                ground: 0xF5EEDD,
                text: 0x23201B,
                active: 0x234FA8,
                done: 0x9C5A32,
                arriving: 0x0F7A70,
            ),
            dark: Palette(
                ground: 0x121722,
                text: 0xE9E6DC,
                active: 0x8FB0F5,
                done: 0xD99A72,
                arriving: 0x6FCFC4,
            ),
        ),
    )

    /// Plum and leaf green: active plum, redder than Lavender's, done leaf green, arriving pink.
    public static let plum = Theme(
        id: "plum",
        name: "Plum",
        looks: .both(
            light: Palette(
                ground: 0xFAF4FB,
                text: 0x2A1A31,
                active: 0x8E2C93,
                done: 0x2E8050,
                arriving: 0xC2407F,
            ),
            dark: Palette(
                ground: 0x1F1226,
                text: 0xF2E7F5,
                active: 0xD486D8,
                done: 0x9AD4A0,
                arriving: 0xF29AC0,
            ),
        ),
    )

    /// Bright and playful on indigo: active cyan (a clear blue in light), done bubblegum pink,
    /// arriving lemon (an orange in light).
    public static let candy = Theme(
        id: "candy",
        name: "Candy",
        looks: .both(
            light: Palette(
                ground: 0xF7F5FF,
                text: 0x211B3D,
                active: 0x0A73C4,
                done: 0xD43C9C,
                arriving: 0xB8570A,
            ),
            dark: Palette(
                ground: 0x181431,
                text: 0xEFEBFF,
                active: 0x4FE0FF,
                done: 0xFF8FD0,
                arriving: 0xFFE066,
            ),
        ),
    )
}
