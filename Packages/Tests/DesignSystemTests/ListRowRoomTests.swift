// Runs only where UIKit exists: it hosts a `List`.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// `listRowRoom()` against a real plain `List`'s row: the Workouts list's Create workout row
/// against Add exercise's Create row.
@MainActor
@Suite("A row drawn outside a list")
struct ListRowRoomTests {
    final class Heights {
        var outside: CGFloat = 0
        var inList: CGFloat = 0
    }

    @Test(
        "A Create row outside a list stands as tall as one in a plain list",
        arguments: [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge],
    )
    func asTallAsAListRow(category: UIContentSizeCategory) {
        let heights = Heights()
        let window = UIWindow.sceneless(
            hosting: UIHostingController(rootView: rows(heights)),
            at: category,
        )
        defer { window.isHidden = true }
        window.settle()
        #expect(heights.inList > 0, "The list's row never laid out")
        #expect(
            abs(heights.outside - heights.inList) < 0.5,
            "Outside a list \(heights.outside) pt, in one \(heights.inList) pt",
        )
    }

    private func rows(_ heights: Heights) -> some View {
        VStack(spacing: 0) {
            CreateLabel(title: "Create workout", detail: "Legs, Dumbbells")
                .listRowRoom()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    heights.outside = $0
                }
            List {
                CreateLabel(title: "Create exercise", detail: "Legs, Dumbbells")
                    // The row's background spans the whole row, its insets included.
                    .listRowBackground(
                        Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            heights.inList = $0
                        },
                    )
            }
            .listStyle(.plain)
        }
    }
}

#endif
