// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The parts of Exercises and Add exercise drawn here: the bar's search, closed and open, with
/// the leading button it covers, and the checklist New exercise pushes. The screens live in the
/// app, which has no test target; the search's motion, its glass (which a snapshot doesn't
/// draw), and Add exercise's title (placed from the item's measured frame, which a snapshot
/// draws before it is measured) are checked on the simulator.
@Suite("Exercise list")
struct ExerciseListSnapshotTests {
    private static let screenWidth: CGFloat = 390

    /// The bar's item, between the bar's margins, over the screen's background.
    private func bar(isOpen: Bool, @ViewBuilder leading: () -> some View) -> some View {
        BarSearchField(
            text: .constant(""),
            prompt: "Search",
            width: Self.screenWidth - 2 * Spacing.md,
            title: nil,
            titleCenterX: 0,
            isOpen: isOpen,
            leading: leading,
        )
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.pp(.background))
    }

    /// ++ as Exercises draws it in the search's item: green, in a glass capsule.
    private var plusPlus: some View {
        Button { } label: {
            Text(verbatim: "++")
                .font(.ppMark)
                .foregroundStyle(.pp(.accent))
                .fixedSize()
                .frame(width: 20)
        }
        .buttonStyle(.barGlass(width: 20 + 2 * Spacing.md))
    }

    /// Close as Add exercise draws it: the system's X in a glass circle.
    private var close: some View {
        Button(role: .close) { } label: {
            Label("Close", systemImage: "xmark").labelStyle(.iconOnly)
        }
        .font(.body.weight(.medium))
        .buttonStyle(.barGlass(width: 0))
    }

    @Test("Closed, ++ leads the bar and the round search button ends it")
    func closedBesideMenu() {
        assertThemedSnapshots(of: bar(isOpen: false) { plusPlus }, width: Self.screenWidth)
    }

    @Test("Open, the field spans the bar over ++, its X where the search button was")
    func openOverMenu() {
        assertThemedSnapshots(of: bar(isOpen: true) { plusPlus }, width: Self.screenWidth)
    }

    @Test("Closed with Close: the system's X leads the bar, as Add exercise's")
    func closedBesideClose() {
        assertThemedSnapshots(of: bar(isOpen: false) { close }, width: Self.screenWidth)
    }

    @Test("The checklist: an empty gray circle per row, filled green with a check once checked")
    func checklist() {
        let groups = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"]
        assertThemedSnapshots(
            of: NavigationStack {
                Checklist(
                    title: "Muscle groups",
                    items: groups,
                    checked: .constant(["Back", "Shoulders"]),
                ) { $0 }
            }
            .frame(height: 560),
            width: Self.screenWidth,
        )
    }
}

#endif
