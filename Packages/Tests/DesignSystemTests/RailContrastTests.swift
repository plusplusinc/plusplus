import DesignSystem
import Foundation
import SwiftUI
import Testing

/// The rail's line, loops, and nodes are its only marks: a row's place in the workout, and a
/// superset's members, read from them alone. WCAG 2's 3:1 for graphics holds them legible on the
/// screen and on `well`, where a held superset's rows show. A colorset can change with every
/// snapshot re-recorded in good faith, so this computes the ratios from the colors themselves.
@Suite("Rail contrast")
struct RailContrastTests {
    /// What `RailRow` and `RailStrokes` fill the line, loops, and nodes with, at rest and arriving,
    /// and the current node's and its pulse's green (`Rail+Stops`, `RailPulse`). A raised row's
    /// node is drawn on its card, not on these grounds, and a row's set bars (`toDo`, `done`) are
    /// its label's, not the rail's.
    private static let marks: [ColorToken] = [.rail, .railJoin, .done, .accent]
    private static let grounds: [ColorToken] = [.background, .well]

    @Test(
        "Every color the rail draws in keeps 3:1 on the background and a well, dark and light",
        arguments: [ColorScheme.dark, .light], [ColorSchemeContrast.standard, .increased],
    )
    func railColorsKeepContrast(scheme: ColorScheme, contrast: ColorSchemeContrast) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        environment._colorSchemeContrast = contrast
        for mark in Self.marks {
            for ground in Self.grounds {
                let (drawn, under) = (
                    Color.pp(mark).resolve(in: environment),
                    Color.pp(ground).resolve(in: environment),
                )
                // The ratio is of opaque colors; a see-through one would read nearer its ground.
                #expect(drawn.opacity == 1 && under.opacity == 1, "\(mark) or \(ground) not opaque")
                let ratio = wcagContrast(drawn, under)
                #expect(
                    ratio >= 3,
                    """
                    \(mark) on \(ground) is \(String(format: "%.2f", ratio)):1. Pick a color with \
                    at least 3:1 on both.
                    """,
                )
            }
        }
    }
}
