import SwiftUI

/// PlusPlus's own themes beside its default. Each look is five colors (`Palette`): ground, text,
/// active, done, arriving, as designed; `Palette` moves one in lightness only where a job's
/// ratio needs it, and `ThemeContrastTests` holds every look to them. A theme gives its three
/// colors their jobs freely, so active is not always a green nor done a purple, but active is
/// never a red (`Theme.isRed(_:)`), and done stands apart from active and from to-do.
nonisolated extension Theme {
    /// The order on the Theme screen after PlusPlus: curated, the quiet grounds first and the
    /// loud ones last.
    static let ours: [Self] = [
        .black, .slate, .mono, .midnight, .ocean, .forest, .lavender, .rose, .paper, .mocha,
        .plum, .candy, .sunset, .volt, .phosphor,
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

    /// Cool blue-gray, like a well-made tool: active blue, done green, arriving violet.
    public static let slate = Theme(
        id: "slate",
        name: "Slate",
        looks: .both(
            light: Palette(
                ground: 0xF4F5F7,
                text: 0x1B1E23,
                active: 0x0A66F0,
                done: 0x1A8F60,
                arriving: 0x8250DF,
            ),
            dark: Palette(
                ground: 0x17191D,
                text: 0xE8EAEE,
                active: 0x5AA2FF,
                done: 0x5FD4A0,
                arriving: 0xC9A4FF,
            ),
        ),
    )

    /// No hue at all, told apart by lightness alone: active the strongest tone (white on dark,
    /// black on light), done a mid gray, arriving a gray between them, to-do quieter than done.
    public static let mono = Theme(
        id: "mono",
        name: "Mono",
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

    /// Deep navy: active blue, done pink, arriving aqua.
    public static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        looks: .both(
            light: Palette(
                ground: 0xF3F6FC,
                text: 0x131C30,
                active: 0x1A66E8,
                done: 0xC8358A,
                arriving: 0x0E8F8C,
            ),
            dark: Palette(
                ground: 0x0F1626,
                text: 0xE6ECF8,
                active: 0x5AA8FF,
                done: 0xF28CC4,
                arriving: 0x7DE3E0,
            ),
        ),
    )

    /// Deep sea teal: active aquamarine, done periwinkle, arriving sand.
    public static let ocean = Theme(
        id: "ocean",
        name: "Ocean",
        looks: .both(
            light: Palette(
                ground: 0xEEF7F8,
                text: 0x0D2E37,
                active: 0x087F6B,
                done: 0x5266D6,
                arriving: 0xA66A00,
            ),
            dark: Palette(
                ground: 0x07212B,
                text: 0xDDF1F3,
                active: 0x4FE3C1,
                done: 0xA3B4FF,
                arriving: 0xFFD27A,
            ),
        ),
    )

    /// Moss and bark: active leaf green, done wood tan, arriving pool teal.
    public static let forest = Theme(
        id: "forest",
        name: "Forest",
        looks: .both(
            light: Palette(
                ground: 0xF3F6EC,
                text: 0x1C2A1E,
                active: 0x3E7C17,
                done: 0x96702E,
                arriving: 0x1F8A7C,
            ),
            dark: Palette(
                ground: 0x121C15,
                text: 0xE6EEDD,
                active: 0xB5E05A,
                done: 0xDDBE8C,
                arriving: 0x7CCFC0,
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

    /// Ink on warm paper, at its best in light: active teal, done terracotta, arriving violet.
    public static let paper = Theme(
        id: "paper",
        name: "Paper",
        looks: .both(
            light: Palette(
                ground: 0xF6EFE2,
                text: 0x2B251D,
                active: 0x0E7A70,
                done: 0xBF5A2E,
                arriving: 0x6C55B8,
            ),
            dark: Palette(
                ground: 0x1E1A15,
                text: 0xEFE6D6,
                active: 0x5CCFC2,
                done: 0xF09A74,
                arriving: 0xB7A4F2,
            ),
        ),
    )

    /// Coffee browns: active saffron, done sage, arriving clay.
    public static let mocha = Theme(
        id: "mocha",
        name: "Mocha",
        looks: .both(
            light: Palette(
                ground: 0xF5EDE2,
                text: 0x2E221A,
                active: 0x8A5A00,
                done: 0x4A7C52,
                arriving: 0xB4552B,
            ),
            dark: Palette(
                ground: 0x1F1814,
                text: 0xF2E5D5,
                active: 0xE9C46A,
                done: 0x9FC59A,
                arriving: 0xE8A27E,
            ),
        ),
    )

    /// Dark plum: active orchid pink, done gold, arriving periwinkle.
    public static let plum = Theme(
        id: "plum",
        name: "Plum",
        looks: .both(
            light: Palette(
                ground: 0xFBF4FB,
                text: 0x2B1B33,
                active: 0xB8259A,
                done: 0x96690A,
                arriving: 0x4A63D6,
            ),
            dark: Palette(
                ground: 0x1E1428,
                text: 0xF3E8F6,
                active: 0xF58AD8,
                done: 0xEBC56E,
                arriving: 0x9DB4FF,
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

    /// Dusk embers: active orange, done violet, arriving gold.
    public static let sunset = Theme(
        id: "sunset",
        name: "Sunset",
        looks: .darkOnly(Palette(
            ground: 0x1F1410,
            text: 0xF7E9DD,
            active: 0xFF9F45,
            done: 0xC58CFF,
            arriving: 0xFFD166,
        )),
    )

    /// Near black with an electric edge: active lime, done cyan, arriving coral orange.
    public static let volt = Theme(
        id: "volt",
        name: "Volt",
        looks: .darkOnly(Palette(
            ground: 0x111214,
            text: 0xF2F3F0,
            active: 0xD7FF3F,
            done: 0x5AD1E8,
            arriving: 0xFF9F6B,
        )),
    )

    /// An old green terminal: active phosphor green, done amber, arriving cyan.
    public static let phosphor = Theme(
        id: "phosphor",
        name: "Phosphor",
        looks: .darkOnly(Palette(
            ground: 0x050B06,
            text: 0xB8F5C0,
            active: 0x39FF6A,
            done: 0xFFB000,
            arriving: 0x7DF9FF,
        )),
    )
}
