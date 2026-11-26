import SwiftUI

/// PlusPlus's own themes beside its default, each named for somewhere or something a workout
/// happens, and drawn to look like it, mostly through its ground, which is most of the screen:
/// Pool's is the water, Dawn patrol's the sky. Each look is five colors (`Palette`): ground,
/// text, active, done, arriving, as designed; `Palette` moves one in lightness only where a
/// job's ratio needs it, and `ThemeContrastTests` holds every look to them. A theme gives its three
/// colors their jobs freely, so active is not always a green nor done a purple, but active is
/// never a red (`Theme.isRed(_:)`), done stands apart from active in lightness as well as hue
/// and from to-do, and no light look uses a darkened yellow or gold, which reads as mud.
nonisolated extension Theme {
    /// The order on the Theme screen after PlusPlus: curated, the quiet grounds first and the
    /// playful ones last.
    static let ours: [Self] = [
        .blackBelt, .iron, .chalk, .varsity, .ocean, .pool, .trail, .dawnPatrol, .cooldown, .barre,
        .spin,
    ]

    /// True black, the top rank, for an OLED screen, in PlusPlus dark's own colors: active
    /// green, done purple, arriving blue. A sheet stands on a near-black a step up, as iOS's own
    /// sheets do over black, with every neutral on it stepped from that: in the screen's black
    /// a sheet had no edge, and a card on it none either.
    public static let blackBelt = Theme(
        id: "black-belt",
        name: "Black belt",
        looks: .darkOnly(
            black(ground: 0x000000),
            onSheet: black(ground: 0x1A1A19),
        ),
    )

    private static func black(ground: UInt32) -> Palette {
        Palette(
            ground: ground,
            text: 0xF5F3EE,
            active: 0x46D17C,
            done: 0xB08CF0,
            arriving: 0x5CA8F5,
        )
    }

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
    /// from the next (`Palette.grayStep`). Done sits as near active as that allows, so a
    /// finished exercise's dot stands well clear of an upcoming one's gray and done's text of
    /// the quieter text.
    public static let chalk = Theme(
        id: "chalk",
        name: "Chalk",
        looks: .both(
            light: Palette(
                ground: 0xF4F2EC,
                text: 0x2A2C2B,
                active: 0x1E2120,
                done: 0x464946,
                arriving: 0x4E514E,
            ),
            dark: Palette(
                ground: 0x1B1F1E,
                text: 0xF2F0E8,
                active: 0xF2F0E8,
                done: 0xB8BBB7,
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

    /// A swimming pool, its ground the water's turquoise, brighter and greener than Ocean's sea.
    /// In light, active the navy of a lane line, done the deep water's teal; in dark, deeper
    /// water under aqua, done a pale buoy yellow. Arriving is the lane rope's red in both, for
    /// the moment it arrives: as done, Log's counts and a rest's fill read as warnings. The navy
    /// and the aqua sit far enough from done in lightness that `Palette` keeps done as drawn:
    /// a navy beside the teal moved it to the text's near-black.
    public static let pool = Theme(
        id: "pool",
        name: "Pool",
        looks: .both(
            light: Palette(
                ground: 0x56D6E2,
                text: 0x06283A,
                active: 0x0A2F70,
                done: 0x006070,
                arriving: 0xC8402F,
            ),
            dark: Palette(
                ground: 0x07596A,
                text: 0xEAFBFD,
                active: 0x88DCE5,
                done: 0xFFE9A8,
                arriving: 0xFFB3A6,
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

    /// A run or a surf at first light, its ground the sky. In light the sun is up: a peach sky,
    /// active the slate blue overhead, done the horizon's deep orange, arriving a dusty plum. In
    /// dark it is not yet: the slate blue sky before the sun, active the sun's orange, done a
    /// dusty pink, arriving gold.
    public static let dawnPatrol = Theme(
        id: "dawn-patrol",
        name: "Dawn patrol",
        looks: .both(
            light: Palette(
                ground: 0xF9CDAE,
                text: 0x2A2A3F,
                active: 0x2F4E7A,
                done: 0xC4531A,
                arriving: 0xA8477A,
            ),
            dark: Palette(
                ground: 0x22324A,
                text: 0xFBEEE4,
                active: 0xFF9A3D,
                done: 0xD4829A,
                arriving: 0xFFD166,
            ),
        ),
    )

    /// An ice bath, the calm after the work: pale ice in light and cold slate in dark, active
    /// an icy blue, done a glacial teal, arriving violet.
    public static let cooldown = Theme(
        id: "cooldown",
        name: "Cooldown",
        looks: .both(
            light: Palette(
                ground: 0xD6EEF8,
                text: 0x10283A,
                active: 0x14689C,
                done: 0x1F8577,
                arriving: 0x6A55C8,
            ),
            dark: Palette(
                ground: 0x1E272D,
                text: 0xE6F5FB,
                active: 0x9BE3FF,
                done: 0x8FE3C8,
                arriving: 0xC5B8FF,
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
