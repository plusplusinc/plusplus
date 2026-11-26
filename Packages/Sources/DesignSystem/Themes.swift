import SwiftUI

/// PlusPlus's own themes beside its default, each named for somewhere or something a workout
/// happens, and drawn to look like it. Each look is five colors (`Palette`): ground, text,
/// active, done, arriving, as designed; `Palette` moves one in lightness only where a job's
/// ratio needs it, and `ThemeContrastTests` holds every look to them. A theme gives its three
/// colors their jobs freely, so active is not always a green nor done a purple, but active is
/// never a red (`Theme.isRed(_:)`), done stands apart from active in lightness as well as hue
/// and from to-do, and no light look uses a darkened yellow or gold, which reads as mud.
nonisolated extension Theme {
    /// The order on the Theme screen after PlusPlus: curated, the quiet grounds first and the
    /// playful ones last.
    static let ours: [Self] = [
        .blackBelt, .iron, .chalk, .varsity, .ocean, .pool, .trail, .court, .track, .sunrise,
        .cooldown, .barre, .logbook, .plum, .spin,
    ]

    /// True black, the top rank, for an OLED screen, in PlusPlus dark's own colors: active
    /// green, done purple, arriving blue.
    public static let blackBelt = Theme(
        id: "black-belt",
        name: "Black belt",
        looks: .darkOnly(Palette(
            ground: 0x000000,
            text: 0xF5F3EE,
            active: 0x46D17C,
            done: 0xB08CF0,
            arriving: 0x5CA8F5,
        )),
    )

    /// The weight room's steel and rust: active steel blue, done rust, arriving a paler,
    /// clearer blue.
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

    /// A workout written on a chalkboard, in grays alone, told apart by three clear steps of
    /// lightness: active the strongest, done the middle, to-do the quietest, each at least 0.15
    /// from the next (`Palette.grayStep`).
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

    /// Navy and gold, the team-jacket colors: active blue, done gold (an amber in light),
    /// arriving sky.
    public static let varsity = Theme(
        id: "varsity",
        name: "Varsity",
        looks: .both(
            light: Palette(
                ground: 0xF4F6FB,
                text: 0x121B33,
                active: 0x1F3F99,
                done: 0xC26A00,
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

    /// Open water, for swimming and surfing: active sea blue, done coral, arriving seafoam.
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

    /// A swimming pool, brighter and greener than Ocean's sea: active the water's turquoise,
    /// done the dark blue of a lane line, arriving the red of a lane rope.
    public static let pool = Theme(
        id: "pool",
        name: "Pool",
        looks: .both(
            light: Palette(
                ground: 0xC4EEF3,
                text: 0x0B2A3A,
                active: 0x007C89,
                done: 0x1B3F9E,
                arriving: 0xC8402F,
            ),
            dark: Palette(
                ground: 0x053E4A,
                text: 0xE6FAFB,
                active: 0x3FE0E8,
                done: 0x7C9BFF,
                arriving: 0xFF8A7A,
            ),
        ),
    )

    /// A trail run, forest green and bark brown, apart in lightness: active leaf green, done
    /// bark, arriving a stream blue.
    public static let trail = Theme(
        id: "trail",
        name: "Trail",
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

    /// A basketball court, maple hardwood with painted blue lines: active the lines' blue,
    /// done the ball's orange, arriving green.
    public static let court = Theme(
        id: "court",
        name: "Court",
        looks: .both(
            light: Palette(
                ground: 0xF3E3C8,
                text: 0x2E2117,
                active: 0x1D5FBF,
                done: 0xB5561A,
                arriving: 0x2F7D4B,
            ),
            dark: Palette(
                ground: 0x2A1D11,
                text: 0xF3E6D2,
                active: 0x6FA8FF,
                done: 0xCF6E26,
                arriving: 0x8FD4A0,
            ),
        ),
    )

    /// A running track, brick-red rubber around a green infield: active the infield's green,
    /// done the track's brick, arriving a lane line's blue.
    public static let track = Theme(
        id: "track",
        name: "Track",
        looks: .both(
            light: Palette(
                ground: 0xF6DDD2,
                text: 0x3A1A14,
                active: 0x23803A,
                done: 0xB4442C,
                arriving: 0x2A6FB0,
            ),
            dark: Palette(
                ground: 0x351813,
                text: 0xF6E7E0,
                active: 0x7BD88A,
                done: 0xD9694E,
                arriving: 0x9CC8F0,
            ),
        ),
    )

    /// A run at dawn, peach sky over the last of the night's indigo, best in light: active the
    /// indigo, done the sun's orange, arriving pink.
    public static let sunrise = Theme(
        id: "sunrise",
        name: "Sunrise",
        looks: .both(
            light: Palette(
                ground: 0xFFEDDF,
                text: 0x3A2A24,
                active: 0x4458C9,
                done: 0xD2662E,
                arriving: 0xC8478F,
            ),
            dark: Palette(
                ground: 0x1B1730,
                text: 0xF6EADF,
                active: 0x9AA8FF,
                done: 0xFFB37A,
                arriving: 0xFF9AC8,
            ),
        ),
    )

    /// Lavender and sky, the calm after the work: active lavender, done a denim blue, arriving
    /// sage.
    public static let cooldown = Theme(
        id: "cooldown",
        name: "Cooldown",
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
                done: 0x5C8FB8,
                arriving: 0xA9D4B0,
            ),
        ),
    )

    /// Ballet pink with sage, for a barre class: active rose pink, done sage, arriving violet.
    public static let barre = Theme(
        id: "barre",
        name: "Barre",
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

    /// Ink on cream paper, a training log: fountain-pen blue for active and sepia for done, on
    /// cream in light and a blue-black in dark; arriving teal.
    public static let logbook = Theme(
        id: "logbook",
        name: "Logbook",
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

    /// Plum and leaf green: active plum, redder than Cooldown's, done leaf green, arriving pink.
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

    /// A dark spin studio under cyan and pink lights: active cyan (a clear blue in light), done
    /// pink, arriving lemon (an orange in light).
    public static let spin = Theme(
        id: "spin",
        name: "Spin",
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
