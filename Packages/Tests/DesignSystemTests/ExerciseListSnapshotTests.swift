// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The parts of Add exercise drawn here: the bar's search, closed and open, with the leading
/// button it covers, the checklist Customize pushes, and the filters' buttons, chips, count
/// line, offer line, Create row, and Also needs heading. The screens live in the
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
            isOpen: .constant(isOpen),
            prompt: "Search",
            width: Self.screenWidth - 2 * Spacing.md,
            leading: leading,
        )
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.pp(.background))
    }

    /// Close as Add exercise draws it: the system's X in a glass circle.
    private var close: some View {
        Button(role: .close) { } label: {
            Label("Close", systemImage: "xmark").labelStyle(.iconOnly)
        }
        .font(.body.weight(.medium))
        .buttonStyle(.barGlass(width: 0))
    }

    @Test("Closed with Close: the system's X leads the bar, as Add exercise's")
    func closedBesideClose() {
        assertThemedSnapshots(of: bar(isOpen: false) { close }, width: Self.screenWidth)
    }

    @Test("Open, the field spans the bar in Close's place, its X where the search button was")
    func openOverClose() {
        assertThemedSnapshots(of: bar(isOpen: true) { close }, width: Self.screenWidth)
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

    /// The filter buttons as Add exercise lays them out: one line that scrolls sideways.
    private func filterRow(_ labels: [(String, Bool)]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(labels, id: \.0) { FilterLabel($0.0, isOn: $0.1) }
            }
            .padding(.horizontal, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @Test("The filter buttons, off: three alike, each a capsule with its name and a chevron")
    func filtersOff() {
        assertThemedSnapshots(
            of: filterRow([("Muscle", false), ("Kind", false), ("Equipment", false)])
                .padding(.vertical, Spacing.sm)
                .background(Color.pp(.background)),
            width: Self.screenWidth,
        )
    }

    @Test("The filter buttons with choices, light, over the count and Clear, which stack at AX5")
    func filtersOn() {
        assertThemedSnapshots(
            of: VStack(alignment: .leading, spacing: Spacing.sm + Spacing.xs) {
                filterRow([("Chest, Back", true), ("Stretch", true), ("Dumbbells, Bench", true)])
                FilterCount("4 exercises") { }
                    .padding(.horizontal, Spacing.md)
            }
            .padding(.vertical, Spacing.sm)
            .background(Color.pp(.background)),
            width: Self.screenWidth,
        )
    }

    @Test("One offer under the filter buttons: its button beside the words, alone at AX5")
    func oneOffer() {
        assertThemedSnapshots(
            of: VStack(alignment: .leading, spacing: Spacing.sm + Spacing.xs) {
                filterRow([("Muscle", false), ("Kind", false), ("Equipment", false)])
                FilterLines(
                    count: nil,
                    offer: FilterOfferLine(
                        "Filter by muscle",
                        offers: [.init(title: "Back", filterName: "Muscle") { }],
                    ),
                )
                .padding(.horizontal, Spacing.md)
            }
            .padding(.vertical, Spacing.sm)
            .background(Color.pp(.background)),
            width: Self.screenWidth,
        )
    }

    @Test("Two offers over the count line: a row beside the words, alone one under another at AX5")
    func twoOffers() {
        assertThemedSnapshots(
            of: FilterLines(
                count: FilterCount("23 exercises") { },
                offer: FilterOfferLine("Filter by", offers: [
                    .init(title: "Back", filterName: "Muscle") { },
                    .init(title: "Dumbbells", filterName: "Equipment") { },
                ]),
            )
            .padding(Spacing.md)
            .background(Color.pp(.background)),
            width: Self.screenWidth,
        )
    }

    @Test("Three long offers, too wide for a row beside the words, show alone")
    func threeLongOffers() {
        assertThemedSnapshots(
            of: FilterOfferLine("Filter by", offers: [
                .init(title: "Medicine ball", filterName: "Equipment") { },
                .init(title: "Balance board", filterName: "Equipment") { },
                .init(title: "Stretch", filterName: "Kind") { },
            ])
            .padding(Spacing.md)
            .background(Color.pp(.background)),
            width: Self.screenWidth,
        )
    }

    @Test("The equipment chips wrap, the chosen ones light; the title and Done stack at AX5")
    func equipmentChips() {
        let items = [
            "No equipment", "Dumbbells", "Kettlebell", "Barbell", "Medicine ball",
            "Bench", "Band", "Pull-up bar", "Rings", "Balance board",
        ]
        assertThemedSnapshots(
            of: ChipSheet(
                title: "Equipment",
                items: items,
                chosen: .constant(["No equipment", "Dumbbells"]),
                name: { $0 },
                onDone: { },
            )
            .background(Color.pp(.surface)),
            width: Self.screenWidth,
        )
    }

    @Test("Nothing matching: Create with what it carries, over Also needs a bench and its row")
    func nothingMatching() {
        assertThemedSnapshots(
            of: VStack(alignment: .leading, spacing: Spacing.md) {
                FilterCount("0 exercises") { }
                CreateLabel(title: "Create exercise", detail: "Chest, Dumbbells")
                    .font(.ppRowTitle)
                    .makesSomething()
                NeedsHeader(title: "Also needs a bench", addTitle: "Bench") { }
                RowLabel(title: "Dumbbell bench press", detail: "Dumbbells, bench")
            }
            .padding(Spacing.md)
            .background(Color.pp(.background)),
            width: Self.screenWidth,
        )
    }
}

#endif
