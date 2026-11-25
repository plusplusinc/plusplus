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
    /// One theme in one look, at a contrast setting. PlusPlus's colorsets also have Increase
    /// Contrast variants; the base16 looks have one value each.
    struct Look: CustomTestStringConvertible, Sendable {
        let theme: Theme
        let scheme: ColorScheme
        let contrast: ColorSchemeContrast

        var testDescription: String {
            let increased = contrast == .increased ? ", increased contrast" : ""
            return "\(theme.name) \(scheme == .dark ? "dark" : "light")\(increased)"
        }

        func color(_ token: ColorToken) -> Color.Resolved {
            var environment = EnvironmentValues()
            environment.theme = theme
            environment.colorScheme = scheme
            environment._colorSchemeContrast = contrast
            return theme.resolve(token, in: environment)
        }
    }

    static let looks: [Look] = Theme.all.flatMap { theme in
        theme.schemes.flatMap { scheme in
            let contrasts: [ColorSchemeContrast] = theme == .plusPlus
                ? [.standard, .increased]
                : [.standard]
            return contrasts.map { Look(theme: theme, scheme: scheme, contrast: $0) }
        }
    }

    /// The pairs that must keep a ratio: a token drawn, the ground it is drawn on, the ratio.
    /// Text is `textPrimary` and `textSecondary`; `textTertiary`, a finished exercise's detail
    /// line, is 3.9:1 in PlusPlus dark and is held to the rail's 3:1, as it draws in `rail`'s
    /// color in every base16 look.
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

    /// Done drawn as text (Log's counts and figures) on the screen and on a card, and under a
    /// done day's number, which draws in the background's color on it. PlusPlus light's purple
    /// is 4.26:1 on its white and has its own card, so the pairs hold the base16 looks.
    private static let doneTextPairs: [Pair] = [
        Pair(.doneText, on: .background, 4.5),
        Pair(.doneText, on: .surface, 4.5),
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
        let doneText = look.theme == .plusPlus ? [] : Self.doneTextPairs
        for pair in Self.pairs + doneText {
            let ratio = Self.contrast(look.color(pair.drawn), look.color(pair.ground))
            #expect(
                ratio >= pair.ratio,
                """
                \(look.testDescription): \(pair.drawn) on \(pair.ground) is \
                \(Self.shown(ratio)):1, under \(Self.shown(pair.ratio)):1. Pick another \
                of the theme's slots (Base16.Roles) before moving a value.
                """,
            )
        }
    }

    /// Two 4 pt bars side by side whose hues are close (a purple beside a blue) read as one color
    /// unless further apart in lightness (`Palette.doneGap`).
    @Test(
        "Done stands apart from active, further where their hues are close, and to-do from done",
        arguments: looks,
    )
    func doneStandsApart(look: Look) {
        let accentLab = OKLab(RGB(look.color(.accent)))
        let doneLab = OKLab(RGB(look.color(.done)))
        let (accent, done) = (accentLab.lightness, doneLab.lightness)
        let toDo = Self.lightness(look.color(.toDo))
        let hues = accentLab.hueDistance(to: doneLab)
        let needed = hues < Palette.closeHues ? Palette.closeHueGap : Palette.lightnessGap
        #expect(
            abs(accent - done) >= needed,
            """
            \(look.testDescription): done and accent are \(Self.shown(abs(accent - done))) apart \
            in OKLab lightness, under \(Self.shown(needed)) for hues \(Int(hues))° apart.
            """,
        )
        #expect(
            abs(done - toDo) >= 0.10,
            "\(look.testDescription): done and toDo are \(Self.shown(abs(done - toDo))) apart",
        )
    }

    /// A finished exercise's node (`done`) and an upcoming one (`rail`) side by side on a rail:
    /// they differ by hue as much as lightness, a purple beside a gray, so the guarantee is a
    /// distance in OKLab, `Palette.nodeDistance`, not a contrast ratio.
    @Test("A finished node stands apart from an upcoming one", arguments: looks)
    func nodesStandApart(look: Look) {
        let (done, rail) = (OKLab(RGB(look.color(.done))), OKLab(RGB(look.color(.rail))))
        let distance = (
            pow(done.lightness - rail.lightness, 2) + pow(done.greenRed - rail.greenRed, 2)
                + pow(done.blueYellow - rail.blueYellow, 2),
        ).squareRoot()
        #expect(
            distance >= Palette.nodeDistance,
            "\(look.testDescription): done and rail are \(Self.shown(distance)) apart in OKLab",
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
        #expect(isRed(0xF92672))
        #expect(isRed(0xE93C58))
        #expect(isRed(0xEBBCBA))
        #expect(isRed(0xAF3A03))
        #expect(!isRed(0xFE8019))
        #expect(!isRed(0xFE640B))
        #expect(!isRed(0xFF79C6))
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
