import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Void's colors, on the black screen and on a sheet, keep the ratios their jobs need, as
/// PlusPlus's do: text and active at WCAG 2's 4.5:1, the rail's marks at 3:1 on the screen and on
/// `well`. A palette can change with every snapshot re-recorded in good faith, so this computes
/// the ratios from the colors as they resolve; a failure names the ground, the two tokens, and
/// the ratio.
@Suite("Void")
nonisolated struct VoidTests {
    /// Void's screen, or a sheet over it.
    struct Ground: CustomTestStringConvertible, Sendable {
        let onSheet: Bool

        var testDescription: String {
            onSheet ? "Void, on a sheet" : "Void"
        }

        /// As `Color.pp` resolves it with the switch on, in `scheme`: dark by default, where the
        /// switch draws true black.
        func color(_ token: ColorToken, in scheme: ColorScheme = .dark) -> Color.Resolved {
            var environment = EnvironmentValues()
            environment.isVoid = true
            environment.isOnSheet = onSheet
            environment.colorScheme = scheme
            return TokenColor(token: token).resolve(in: environment)
        }
    }

    static let grounds = [Ground(onSheet: false), Ground(onSheet: true)]

    /// The pairs that must keep a ratio: a token drawn, the ground it is drawn on, the ratio. The
    /// quieter text is held on the screen, a card, and a chip or cell, on the sheet as on the
    /// screen. `textTertiary`, a finished exercise's detail line, is held to the rail's 3:1, as it
    /// draws in `rail`'s color.
    private static let pairs: [Pair] = [
        Pair(.accent, on: .background, 4.5),
        Pair(.done, on: .background, 4.5),
        Pair(.textPrimary, on: .background, 4.5),
        Pair(.textPrimary, on: .surface, 4.5),
        Pair(.textPrimary, on: .surfaceRaised, 4.5),
        Pair(.textSecondary, on: .background, 4.5),
        Pair(.textSecondary, on: .surface, 4.5),
        Pair(.textSecondary, on: .surfaceRaised, 4.5),
        Pair(.onPrimaryKey, on: .primaryKey, 4.5),
        Pair(.onPrimaryKey, on: .accent, 4.5),
        Pair(.onPrimaryKey, on: .done, 4.5),
    ] + [ColorToken.rail, .railJoin, .done, .accent, .textTertiary].flatMap { mark in
        [Pair(mark, on: .background, 3), Pair(mark, on: .well, 3)]
    }

    private struct Pair {
        let drawn: ColorToken
        let ground: ColorToken
        let ratio: Double

        init(_ drawn: ColorToken, on ground: ColorToken, _ ratio: Double) {
            (self.drawn, self.ground, self.ratio) = (drawn, ground, ratio)
        }
    }

    @Test("Text and active keep 4.5:1, and the rail's marks 3:1", arguments: grounds)
    func ratiosHold(ground: Ground) {
        for pair in Self.pairs {
            let ratio = wcagContrast(ground.color(pair.drawn), ground.color(pair.ground))
            #expect(
                ratio >= pair.ratio,
                """
                \(ground.testDescription): \(pair.drawn) on \(pair.ground) is \
                \(Self.shown(ratio)):1, under \(Self.shown(pair.ratio)):1
                """,
            )
        }
    }

    /// A sheet in the screen's black shows no edge where the screen dims around it: it stands
    /// on a gray of its own, at least as far off as PlusPlus dark's card stands from its ground.
    @Test("A sheet stands a step off the black screen")
    func sheetStandsOffBlack() {
        let (screen, sheet) = (Self.grounds[0], Self.grounds[1])
        #expect(screen.color(.background) == RGB(0x000000).resolved())
        let step = wcagContrast(sheet.color(.background), screen.color(.background))
        #expect(step >= 1.13, "A sheet is \(Self.shown(step)):1 off the screen")
    }

    /// Drawn as iOS draws its own dark: no gray leans warm. A gray's red never runs past its
    /// blue, as a brown's does (PlusPlus's warm grays did, in a review of the black look).
    @Test("Every gray is neutral, not warm", arguments: grounds)
    func graysAreNeutral(ground: Ground) {
        let grays: [ColorToken] = [
            .background, .surface, .surfaceRaised, .selectionFill, .borderStrong, .separator,
            .toDo, .well, .textSecondary, .rail, .textPrimary,
        ]
        for token in grays {
            let color = ground.color(token)
            #expect(
                color.red <= color.blue + 1 / 255,
                "\(ground.testDescription): \(token) leans warm",
            )
        }
    }

    @Test("Every color but the dim and the shadow is opaque", arguments: grounds)
    func colorsAreOpaque(ground: Ground) {
        for token in ColorToken.allCases where token != .dim && token != .shadow {
            #expect(ground.color(token).opacity == 1, "\(ground.testDescription): \(token)")
        }
    }

    /// The switch makes dark true black and leaves light alone: with it on, a light scheme draws
    /// PlusPlus's own light colors.
    @Test("With the switch on, light draws PlusPlus's light colors", arguments: grounds)
    func lightUnchanged(ground: Ground) {
        var plain = EnvironmentValues()
        plain.colorScheme = .light
        plain.isOnSheet = ground.onSheet
        for token in ColorToken.allCases {
            #expect(
                ground.color(token, in: .light) == TokenColor(token: token).resolve(in: plain),
                "\(ground.testDescription): \(token)",
            )
        }
    }

    private static func shown(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
