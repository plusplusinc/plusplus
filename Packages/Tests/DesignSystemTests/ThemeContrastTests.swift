import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Every theme, in every look it has, keeps the ratios its colors' jobs need, so a theme reads as
/// PlusPlus does: what is active and the text at WCAG 2's 4.5:1, the rail's marks at 3:1 for
/// graphics on the screen and on `well` (where a held superset's rows show), and done apart from
/// active in lightness as well as hue. A palette can change with every snapshot re-recorded in
/// good faith, so this computes the ratios from the colors as they resolve; a failure names the
/// theme, the look, the two tokens, and the ratio.
@Suite("Theme contrast")
nonisolated struct ThemeContrastTests {
    /// One theme in one look, at a contrast setting, on the screen or on a sheet. PlusPlus's
    /// colorsets also have Increase Contrast variants; the other themes' looks have one value
    /// each, and Black belt a second on a sheet.
    struct Look: CustomTestStringConvertible, Sendable {
        let theme: Theme
        let scheme: ColorScheme
        let contrast: ColorSchemeContrast
        var onSheet = false

        var testDescription: String {
            let increased = contrast == .increased ? ", increased contrast" : ""
            let sheet = onSheet ? ", on a sheet" : ""
            return "\(theme.name) \(scheme == .dark ? "dark" : "light")\(increased)\(sheet)"
        }

        func color(_ token: ColorToken) -> Color.Resolved {
            var environment = EnvironmentValues()
            environment.theme = theme
            environment.colorScheme = scheme
            environment._colorSchemeContrast = contrast
            environment.isOnSheet = onSheet
            return theme.resolve(token, in: environment)
        }
    }

    static let looks: [Look] = Theme.all.flatMap { theme in
        theme.schemes.flatMap { scheme in
            let contrasts: [ColorSchemeContrast] = theme == .plusPlus
                ? [.standard, .increased]
                : [.standard]
            let sheets = theme.hasSheetLook ? [false, true] : [false]
            return contrasts.flatMap { contrast in
                sheets.map { Look(theme: theme, scheme: scheme, contrast: contrast, onSheet: $0) }
            }
        }
    }

    /// The pairs that must keep a ratio: a token drawn, the ground it is drawn on, the ratio.
    /// Text is `textPrimary` and `textSecondary`; `textTertiary`, a finished exercise's detail
    /// line, is 3.9:1 in PlusPlus dark and is held to the rail's 3:1, as it draws in `rail`'s
    /// color in every other theme's look.
    private static let pairs: [Pair] = [
        Pair(.accent, on: .background, 4.5),
        Pair(.textPrimary, on: .background, 4.5),
        Pair(.textPrimary, on: .surface, 4.5),
        Pair(.textPrimary, on: .surfaceRaised, 4.5),
        Pair(.textPrimary, on: .selectionFill, 4.5),
        Pair(.textSecondary, on: .background, 4.5),
        Pair(.textSecondary, on: .surface, 4.5),
        Pair(.textSecondary, on: .surfaceRaised, 4.5),
        Pair(.textSecondary, on: .selectionFill, 4.5),
        Pair(.onPrimaryKey, on: .primaryKey, 4.5),
        Pair(.onPrimaryKey, on: .accent, 4.5),
    ] + [ColorToken.rail, .railJoin, .done, .accent, .textTertiary].flatMap { mark in
        [Pair(mark, on: .background, 3), Pair(mark, on: .well, 3)]
    }

    /// Done drawn as text (Log's counts and figures) on the screen and on a card, and a count
    /// key's label ("Log early") over the key's done fill.
    private static let doneTextPairs: [Pair] = [
        Pair(.doneText, on: .background, 4.5),
        Pair(.doneText, on: .surface, 4.5),
        Pair(.onPrimaryKey, on: .doneText, 4.5),
    ]

    private struct Pair {
        let drawn: ColorToken
        let ground: ColorToken
        let ratio: Double

        init(_ drawn: ColorToken, on ground: ColorToken, _ ratio: Double) {
            (self.drawn, self.ground, self.ratio) = (drawn, ground, ratio)
        }
    }

    @Test(
        "Active and text keep 4.5:1, and the rail's marks 3:1, in every theme and look",
        arguments: looks,
    )
    func ratiosHold(look: Look) {
        for pair in Self.pairs + Self.doneTextPairs {
            let ratio = Self.contrast(look.color(pair.drawn), look.color(pair.ground))
            #expect(
                ratio >= pair.ratio,
                """
                \(look.testDescription): \(pair.drawn) on \(pair.ground) is \
                \(Self.shown(ratio)):1, under \(Self.shown(pair.ratio)):1. Move the theme's \
                color in lightness in Themes.swift, its hue kept.
                """,
            )
        }
    }

    /// Two 4 pt bars side by side read as one color unless apart in lightness as well as hue:
    /// 0.08 in OKLab for any two hues (a green beside a brown or a pink of one lightness read as
    /// one), 0.12 where the hues are close (a purple beside a blue), 0.15 for two grays.
    /// PlusPlus dark keeps its own 0.05. PlusPlus light is held to nothing here: its colorsets
    /// are `main`'s as they were before themes, where done (7A4FD0) and active (158645) share a
    /// lightness and stand apart only by hue, 142°; this card leaves PlusPlus's look as it was.
    @Test(
        "Done stands apart from active in lightness, further where hue can't help",
        arguments: looks,
    )
    func doneStandsApart(look: Look) {
        guard look.theme != .plusPlus || look.scheme == .dark else { return }
        let accentRGB = RGB(look.color(.accent))
        let doneRGB = RGB(look.color(.done))
        let (accent, done) = (OKLab(accentRGB).lightness, OKLab(doneRGB).lightness)
        let hues = OKLab(accentRGB).hueDistance(to: OKLab(doneRGB))
        let needed = look.theme == .plusPlus ? 0.05 : Palette.doneGap(doneRGB, accentRGB)
        #expect(
            needed >= Palette.lightnessGap || look.theme == .plusPlus,
            "\(look.testDescription): done needs only \(Self.shown(needed)) from accent",
        )
        #expect(
            abs(accent - done) >= needed,
            """
            \(look.testDescription): done and accent are \(Self.shown(abs(accent - done))) apart \
            in OKLab lightness, under \(Self.shown(needed)) for hues \(Int(hues))° apart.
            """,
        )
    }

    /// A theme of grays (Chalk) has only lightness: active the strongest, furthest from the
    /// ground, done the middle, to-do the quietest, each `Palette.grayStep` from the next; and
    /// done's text (Log's counts) a step from the quieter text beside it, as text is from it.
    @Test("In a theme of grays, active, done, and to-do are three clear steps", arguments: looks)
    func graysStepApart(look: Look) {
        let (accent, done) = (RGB(look.color(.accent)), RGB(look.color(.done)))
        guard Palette.isGray(accent), Palette.isGray(done) else { return }
        let ground = Self.lightness(look.color(.background))
        let steps = [accent, done, RGB(look.color(.toDo))].map {
            abs(OKLab($0).lightness - ground)
        }
        #expect(
            steps[0] - steps[1] >= Palette.grayStep && steps[1] - steps[2] >= Palette.grayStep,
            """
            \(look.testDescription): active, done, and to-do stand \
            \(steps.map(Self.shown)) from the ground, not \(Palette.grayStep) steps down
            """,
        )
        let textGap = abs(
            Self.lightness(look.color(.doneText)) - Self.lightness(look.color(.textSecondary)),
        )
        #expect(
            textGap >= Palette.textStep,
            "\(look.testDescription): doneText is \(Self.shown(textGap)) from textSecondary",
        )
    }

    /// A set done and a set still to do sit side by side as bars; where done is a gray (Chalk),
    /// lightness is all that tells them apart, and to-do is the quieter, nearer the background.
    @Test("A set still to do stands apart from a done one, and quieter", arguments: looks)
    func toDoStandsApartFromDone(look: Look) {
        let done = Self.lightness(look.color(.done))
        let toDo = Self.lightness(look.color(.toDo))
        let background = Self.lightness(look.color(.background))
        let needed = look.theme == .plusPlus ? 0.10 : Palette.toDoGap(RGB(look.color(.done)))
        #expect(
            abs(done - toDo) >= needed,
            "\(look.testDescription): done and toDo are \(Self.shown(abs(done - toDo))) apart",
        )
        #expect(
            abs(toDo - background) < abs(done - background),
            "\(look.testDescription): toDo is further from the background than done",
        )
    }

    /// A finished exercise's node (`done`) and an upcoming one (`rail`) side by side on a rail:
    /// they differ by hue as much as lightness, a purple beside a gray, so the guarantee is a
    /// distance in OKLab, `Palette.nodeGap(_:)`, not a contrast ratio: further where done is a
    /// gray as well (Chalk).
    @Test("A finished node stands apart from an upcoming one", arguments: looks)
    func nodesStandApart(look: Look) {
        let doneRGB = RGB(look.color(.done))
        let (done, rail) = (OKLab(doneRGB), OKLab(RGB(look.color(.rail))))
        let distance = (
            pow(done.lightness - rail.lightness, 2) + pow(done.greenRed - rail.greenRed, 2)
                + pow(done.blueYellow - rail.blueYellow, 2),
        ).squareRoot()
        #expect(
            distance >= Palette.nodeGap(doneRGB),
            "\(look.testDescription): done and rail are \(Self.shown(distance)) apart in OKLab",
        )
    }

    /// A row joining a rail draws its node in `railJoin`, then settles to `rail`: unless the two
    /// stand apart, the arrival shows nothing. In Chalk only lightness tells them apart.
    @Test("An arriving node stands apart from a resting one", arguments: looks)
    func arrivingStandsApart(look: Look) {
        let joinRGB = RGB(look.color(.railJoin))
        let (join, rail) = (OKLab(joinRGB), OKLab(RGB(look.color(.rail))))
        let distance = (
            pow(join.lightness - rail.lightness, 2) + pow(join.greenRed - rail.greenRed, 2)
                + pow(join.blueYellow - rail.blueYellow, 2),
        ).squareRoot()
        #expect(
            distance >= Palette.nodeGap(joinRGB),
            "\(look.testDescription): railJoin and rail are \(Self.shown(distance)) apart in OKLab",
        )
    }

    /// A detail line in `textSecondary` reads a step down from the name above it in
    /// `textPrimary`, not as the same text.
    @Test("The quieter text is a step down from the text", arguments: looks)
    func quieterTextStepsDown(look: Look) {
        let step = abs(
            Self.lightness(look.color(.textPrimary)) - Self.lightness(look.color(.textSecondary)),
        )
        #expect(
            step >= Palette.textStep,
            "\(look.testDescription): textSecondary is \(Self.shown(step)) from textPrimary",
        )
    }

    /// A sheet in the screen's own color shows its edge where the screen dims around it, which
    /// true black can't: there a sheet stands on a ground of its own, as far from the screen's as
    /// PlusPlus dark's card stands from its ground (1.13:1).
    @Test("Over true black, a sheet stands a step off the screen", arguments: looks)
    func sheetStandsOffBlack(look: Look) {
        let ground = look.color(.background)
        let black = RGB(0x000000).resolved()
        guard !look.onSheet, Self.contrast(ground, black) < 1.08 else { return }
        #expect(look.theme.hasSheetLook, "\(look.testDescription): a black ground, no sheet look")
        let sheet = Look(
            theme: look.theme,
            scheme: look.scheme,
            contrast: look.contrast,
            onSheet: true,
        )
        let step = Self.contrast(sheet.color(.background), ground)
        #expect(step >= 1.13, "\(look.testDescription): a sheet is \(Self.shown(step)):1 off it")
    }

    private static func shown(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    @Test("No theme's active color is a red", arguments: looks)
    func activeIsNeverRed(look: Look) {
        #expect(
            !Theme.isRed(look.color(.accent)),
            "\(look.testDescription): accent reads as a red (Theme.isRed); lead with another color",
        )
    }

    @Test("Every color but the dim and the shadow is opaque", arguments: looks)
    func colorsAreOpaque(look: Look) {
        for token in ColorToken.allCases where token != .dim && token != .shadow {
            #expect(
                look.color(token).opacity == 1,
                "\(look.testDescription): \(token) is not opaque",
            )
        }
    }

    @Test("The red rule: reds, corals, and rust are red; oranges, pinks, and grays are not")
    func redRule() {
        func isRed(_ hex: UInt32) -> Bool {
            Theme.isRed(RGB(hex).resolved())
        }
        #expect(isRed(0xFF0000))
        #expect(isRed(0xE0115F))
        #expect(isRed(0xDC143C))
        #expect(isRed(0xF08080))
        #expect(isRed(0xB7410E))
        #expect(!isRed(0xFF8C00))
        #expect(!isRed(0xCC5500))
        #expect(!isRed(0xC71585))
        #expect(!isRed(0x9E9E9E))
    }

    /// WCAG 2's contrast ratio.
    private static func contrast(_ first: Color.Resolved, _ second: Color.Resolved) -> Double {
        let (one, two) = (luminance(first), luminance(second))
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    /// WCAG 2's relative luminance. `Color.Resolved`'s components are already linear sRGB.
    private static func luminance(_ color: Color.Resolved) -> Double {
        0.2126 * Double(color.linearRed) + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
    }

    private static func lightness(_ color: Color.Resolved) -> Double {
        OKLab(RGB(color)).lightness
    }
}
