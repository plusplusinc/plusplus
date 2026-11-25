// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The themes as they are drawn: the Theme screen's cards, each in its own theme's colors over
/// the page around it, and a workout mid-set drawn in two base16 themes, in light and dark. What
/// every theme's colors keep (their ratios, active never red) is `ThemeContrastTests`'; these
/// hold how they land on screen.
@Suite("Themes")
struct ThemeSnapshotTests {
    private static let width: CGFloat = 390

    /// Cards on the Theme screen: PlusPlus in use, with its outline and check; Dracula, dark
    /// only; Tokyo Night, whose name is the longest. Under them, Settings' card, which opens the
    /// themes.
    @Test("Theme cards: in use, dark only, a long name, and Settings' card that opens them")
    func cards() {
        let view = VStack(spacing: Spacing.sm) {
            ThemeCard(theme: .plusPlus, scheme: .dark, mark: .checked(true))
            ThemeCard(theme: .dracula, scheme: .dark, mark: .checked(false))
            ThemeCard(theme: .tokyoNight, scheme: .dark, mark: .checked(false))
            ThemeCard(theme: .nord, scheme: .dark, mark: .opens)
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: view, width: Self.width)
    }

    @Test("A workout mid-set in Gruvbox: active in its aqua, done in its purple")
    func gruvboxMidSet() {
        assertThemedSnapshots(of: midSet(in: .gruvbox), width: Self.width, includingLight: true)
    }

    @Test("A workout mid-set in Nord: active in its green, done in its purple")
    func nordMidSet() {
        assertThemedSnapshots(of: midSet(in: .nord), width: Self.width, includingLight: true)
    }

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
        var bars: SetProgress?
    }

    /// A finished exercise, the current one on its second set of three, and one to come: every
    /// rail color, the set bars, and the current exercise's figures.
    private func midSet(in theme: Theme) -> some View {
        let finished = Row(title: "Push-up", detail: ["3 × 10 reps"])
        let current = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            focus: RowFocus(
                place: SetPlace(word: "Set", number: 2, total: 3),
                equipment: ["Dumbbells", "Bench"],
                figures: [.init(number: "10", unit: "reps"), .init(number: "25", unit: "lb/side")],
                spokenFigures: "10 reps, 25 pounds a side",
            ),
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
        )
        let rows = [finished, current, Row(title: "Incline push-up", detail: ["3 × 10 reps"])]
        return Rail(rows, links: [], current: current.id, done: [finished.id]) { row in
            RowLabel(title: row.title, detail: row.detail, focus: row.focus, bars: row.bars)
                .padding(.top, row.focus == nil ? 0 : Spacing.lg)
                .railRow()
        } end: {
            FloatingButtonRoom()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
        .environment(\.theme, theme)
    }
}

#endif
