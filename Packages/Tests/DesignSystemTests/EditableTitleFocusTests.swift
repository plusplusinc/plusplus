// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// What sits under the title stays put as an edit starts and ends: by Return, and by the field
/// giving up focus, as it does when a sheet takes it or a touch lands outside the title. Every
/// layout pass is seen, so a height the title takes for a moment counts.
@MainActor
@Suite("Editable title holds its height into and out of editing")
struct EditableTitleFocusTests {
    private nonisolated static let large = UIContentSizeCategory.large
    private nonisolated static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// A name on one line, one that wraps, the placeholder, and a suggestion, as (name,
    /// suggestion).
    nonisolated static let titles: [(String, String?)] = [
        ("Push", nil),
        ("Hot beat drills and abs and arms", nil),
        ("", nil),
        ("", "Squat and pull"),
    ]

    /// Every place the view under the title was laid out at.
    private final class Log {
        var tops: [CGFloat] = []
    }

    private struct Host: View {
        @State var name: String
        @State var isEditing = false
        let suggestion: String?
        let log: Log

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                EditableTitle(
                    text: $name,
                    isEditing: $isEditing,
                    placeholder: "New routine",
                    suggestion: suggestion,
                    accessibilityLabel: "Routine name",
                    accessibilityHint: "Renames the routine.",
                )
                Color.clear
                    .frame(height: 44)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                        log.tops.append($0)
                    }
            }
            .frame(width: 370)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private final class Screen {
        let window: UIWindow
        let field: UITextView
        let log = Log()

        init(_ name: String, suggestion: String?, at category: UIContentSizeCategory) throws {
            let host = UIHostingController(rootView: Host(
                name: name,
                suggestion: suggestion,
                log: log,
            ))
            host.safeAreaRegions = []
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.traitOverrides.preferredContentSizeCategory = category
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            func field(in view: UIView) -> UITextView? {
                view as? UITextView ?? view.subviews.lazy.compactMap(field(in:)).first
            }
            self.field = try #require(field(in: host.view))
            settle()
        }

        isolated deinit {
            window.isHidden = true
        }

        /// Lets every update the last step started reach the layout.
        func settle() {
            for _ in 0 ..< 10 {
                window.layoutIfNeeded()
                RunLoop.main.run(mode: .default, before: .now)
            }
        }
    }

    /// Starts an edit, as a tap does, and ends it with `end`, then checks that the view under
    /// the title was only ever laid out in one place.
    private func check(
        _ title: (String, String?),
        at category: UIContentSizeCategory,
        ending: String,
        end: (UITextView) -> Void,
    ) throws {
        let screen = try Screen(title.0, suggestion: title.1, at: category)
        try #require(screen.field.becomeFirstResponder())
        screen.settle()
        try #require(screen.field.isFirstResponder)
        end(screen.field)
        screen.settle()
        #expect(!screen.field.isFirstResponder, "\(ending) did not end the edit")
        let first = try #require(screen.log.tops.first)
        #expect(
            screen.log.tops.allSatisfy { abs($0 - first) < 0.5 },
            "\(ending), \(category.rawValue): laid out at \(screen.log.tops)",
        )
    }

    @Test("Return leaves everything under the title in place", arguments: titles, [large, ax5])
    func endByReturn(title: (String, String?), category: UIContentSizeCategory) throws {
        // As the keyboard sends it: asked of the delegate first, which refuses it.
        try check(title, at: category, ending: "Return") { field in
            let range = field.selectedRange
            if field.delegate?.textView?(field, shouldChangeTextIn: range, replacementText: "\n")
                ?? true
            {
                field.insertText("\n")
            }
        }
    }

    @Test(
        "Giving up focus leaves everything under the title in place",
        arguments: titles,
        [large, ax5],
    )
    func endByResigning(title: (String, String?), category: UIContentSizeCategory) throws {
        try check(title, at: category, ending: "Resigning") { _ = $0.resignFirstResponder() }
    }
}

#endif
