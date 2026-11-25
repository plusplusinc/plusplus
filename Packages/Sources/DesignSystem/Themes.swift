import SwiftUI

/// PlusPlus's own themes beside its default. Each look is five colors (`Palette`): ground, text,
/// active, done, arriving, as designed; `Palette` moves one in lightness only where a job's
/// ratio needs it, and `ThemeContrastTests` holds every look to them. A theme gives its three
/// colors their jobs freely, so active is not always a green nor done a purple, but active is
/// never a red (`Theme.isRed(_:)`), and done stands apart from active and from to-do.
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

    /// Steel and rust: active steel blue, done rust, arriving brass.
    public static let iron = Theme(
        id: "iron",
        name: "Iron",
        looks: .both(
            light: Palette(
                ground: 0xF3F4F5,
                text: 0x1C1F23,
                active: 0x3F5F7F,
                done: 0xB5562B,
                arriving: 0x7A6A1F,
            ),
            dark: Palette(
                ground: 0x17191C,
                text: 0xE6E8EB,
                active: 0x9DB7D1,
                done: 0xD98A54,
                arriving: 0xD8C27A,
            ),
        ),
    )

    /// No hue at all, told apart by lightness alone: active the strongest tone (white on dark,
    /// black on light), done a mid gray, arriving a gray between them, to-do quieter than done.
    /// The light look's done is `8C8C8C`, as the dark's, not the darker `6E6E6E` first drawn:
    /// there the rail had no gray left that stood apart from both done and arriving.
    public static let chalk = Theme(
        id: "chalk",
        name: "Chalk",
        looks: .both(
            light: Palette(
                ground: 0xFAFAFA,
                text: 0x1A1A1A,
                active: 0x000000,
                done: 0x8C8C8C,
                arriving: 0x4A4A4A,
            ),
            dark: Palette(
                ground: 0x111111,
                text: 0xEDEDED,
                active: 0xFFFFFF,
                done: 0x8C8C8C,
                arriving: 0xBDBDBD,
            ),
        ),
    )

    /// Navy and brass, sober: active blue, done brass, arriving sky.
    public static let navy = Theme(
        id: "navy",
        name: "Navy",
        looks: .both(
            light: Palette(
                ground: 0xF4F6FB,
                text: 0x121B33,
                active: 0x1F3F99,
                done: 0x8F6B10,
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

    /// Blue water: active sea blue, done seafoam, arriving sand.
    public static let ocean = Theme(
        id: "ocean",
        name: "Ocean",
        looks: .both(
            light: Palette(
                ground: 0xEEF6FA,
                text: 0x0C2C3A,
                active: 0x0B74AD,
                done: 0x178A6E,
                arriving: 0x96701A,
            ),
            dark: Palette(
                ground: 0x06202E,
                text: 0xDDEFF5,
                active: 0x4CC3F0,
                done: 0x7FE0C0,
                arriving: 0xEAD2A0,
            ),
        ),
    )

    /// Forest green and bark: active leaf green, done bark brown, arriving ochre.
    public static let forest = Theme(
        id: "forest",
        name: "Forest",
        looks: .both(
            light: Palette(
                ground: 0xF3F5EC,
                text: 0x1B291D,
                active: 0x2E6B34,
                done: 0x8A5A2B,
                arriving: 0x8A7A12,
            ),
            dark: Palette(
                ground: 0x111B14,
                text: 0xE5ECDD,
                active: 0x6FBF73,
                done: 0xC9A06F,
                arriving: 0xD9C36A,
            ),
        ),
    )

    /// Soft violet dusk: active lavender, done sage green, arriving apricot.
    public static let lavender = Theme(
        id: "lavender",
        name: "Lavender",
        looks: .both(
            light: Palette(
                ground: 0xF4F1FB,
                text: 0x29253F,
                active: 0x7C3AED,
                done: 0x2A8A4E,
                arriving: 0xC0621A,
            ),
            dark: Palette(
                ground: 0x1E1D2E,
                text: 0xE4E1F5,
                active: 0xC6A0F6,
                done: 0xA6DA95,
                arriving: 0xF5BD8F,
            ),
        ),
    )

    /// Warm blush: active mint, done rose, arriving honey.
    public static let rose = Theme(
        id: "rose",
        name: "Rose",
        looks: .both(
            light: Palette(
                ground: 0xFCF1F2,
                text: 0x33211F,
                active: 0x2F7E4B,
                done: 0xC74A77,
                arriving: 0xA16E12,
            ),
            dark: Palette(
                ground: 0x241A1E,
                text: 0xF5E8EA,
                active: 0xA8D8B0,
                done: 0xF29AB5,
                arriving: 0xEDC98F,
            ),
        ),
    )

    /// Fountain-pen ink blue for active and sepia for done, on cream in light and warm near-black
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
                ground: 0x1F1C17,
                text: 0xEFE7D6,
                active: 0x8FB0F5,
                done: 0xD99A72,
                arriving: 0x6FCFC4,
            ),
        ),
    )

    /// Plum and gold: active plum purple, done gold, arriving pink.
    public static let plum = Theme(
        id: "plum",
        name: "Plum",
        looks: .both(
            light: Palette(
                ground: 0xFAF4FB,
                text: 0x2A1A31,
                active: 0x7A2E9E,
                done: 0x96690A,
                arriving: 0xC2407F,
            ),
            dark: Palette(
                ground: 0x1F1226,
                text: 0xF2E7F5,
                active: 0xC58BF2,
                done: 0xE6C063,
                arriving: 0xF29AC0,
            ),
        ),
    )

    /// Bright and playful on indigo: active cyan, done bubblegum pink, arriving lemon.
    public static let candy = Theme(
        id: "candy",
        name: "Candy",
        looks: .both(
            light: Palette(
                ground: 0xF7F5FF,
                text: 0x211B3D,
                active: 0x067FA3,
                done: 0xD43C9C,
                arriving: 0x9A7400,
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
