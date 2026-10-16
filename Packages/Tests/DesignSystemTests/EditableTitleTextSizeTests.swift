// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The title's height when the text size changes while it is on screen, as the system changes
/// it: the window's content size category, live. A snapshot draws each size fresh, so it cannot
/// see a height kept from the size before.
@MainActor
@Suite("Editable title after a text size change")
struct EditableTitleTextSizeTests {
    private static let width: CGFloat = 370
    private static let large = UIContentSizeCategory.large
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// A named title, the placeholder, and a name that wraps at both sizes.
    nonisolated static let drafts = ["Push", "", "Hot beat drills and abs and arms"]

    /// Names the cell model wraps to fewer lines than the field does: emoji and CJK are wider
    /// than a cell of the title's font.
    nonisolated static let wideDrafts = [
        "Legs 💪💪💪💪💪💪💪 and back",
        "上半身と下半身の筋力トレーニング",
    ]

    /// The title on screen in a window at `category`, with the field focused when `isEditing`.
    private final class Screen {
        let window: UIWindow
        let host: UIHostingController<AnyView>

        init(
            _ draft: String,
            isEditing: Bool,
            at category: UIContentSizeCategory,
        ) {
            host = UIHostingController(rootView: AnyView(
                EditableTitleContent(
                    draft: .constant(draft),
                    caret: Caret(),
                    selection: .constant(nil),
                    placeholder: "New routine",
                    shownPlaceholder: "New routine",
                    isEditing: isEditing,
                    blinks: false,
                    accessibilityLabel: "Routine name",
                    accessibilityHint: "Renames the routine.",
                    behavior: FocusOnAppear(isOn: isEditing),
                )
                // The routine screen scrolls, so the title is as tall as it asks to be.
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: EditableTitleTextSizeTests.width),
            ))
            host.safeAreaRegions = []
            // The package's tests run with no host app, so there is no scene for a window to
            // join; a window without one still lays out, takes traits, and focuses a field.
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.traitOverrides.preferredContentSizeCategory = category
            window.rootViewController = host
            window.makeKeyAndVisible()
        }

        /// The title's height once its measurements have settled: they reach the layout over a
        /// few passes, each measured geometry updating state for the next.
        func height() -> CGFloat {
            var last = -1.0
            for _ in 0 ..< 50 {
                window.layoutIfNeeded()
                RunLoop.main.run(mode: .default, before: .now)
                let height = host
                    .sizeThatFits(in: CGSize(
                        width: EditableTitleTextSizeTests.width,
                        height: .infinity,
                    ))
                    .height
                if height == last {
                    return height
                }
                last = height
            }
            Issue.record("The title's height never settled; last \(last)")
            return last
        }

        /// Whether the field is tall enough for all of its text, rather than scrolling it inside.
        var showsAllText: Bool {
            func textViews(in view: UIView) -> [UITextView] {
                (view as? UITextView).map { [$0] } ?? view.subviews.flatMap(textViews(in:))
            }
            guard let field = textViews(in: host.view).first else {
                Issue.record("No text view in the title")
                return false
            }
            field.layoutIfNeeded()
            // Within a point, as heights land on the pixel grid.
            return field.contentSize.height <= field.bounds.height + 1
        }

        /// Whether the field's text view has the keyboard's focus.
        var isFocused: Bool {
            func focused(in view: UIView) -> Bool {
                view.isFirstResponder || view.subviews.contains(where: focused(in:))
            }
            return focused(in: host.view)
        }

        /// The height fresh at `category`, the window then taken off screen so that it holds no
        /// focus while the next one is measured.
        static func freshHeight(
            _ draft: String,
            isEditing: Bool,
            at category: UIContentSizeCategory,
        ) -> CGFloat {
            let screen = Screen(draft, isEditing: isEditing, at: category)
            defer { screen.window.isHidden = true }
            return screen.height()
        }

        func change(to category: UIContentSizeCategory) {
            window.traitOverrides.preferredContentSizeCategory = category
        }
    }

    private func check(
        _ draft: String,
        isEditing: Bool,
        from start: UIContentSizeCategory,
        via other: UIContentSizeCategory,
    ) {
        let fresh = Screen.freshHeight(draft, isEditing: isEditing, at: other)
        let freshStart = Screen.freshHeight(draft, isEditing: isEditing, at: start)
        let screen = Screen(draft, isEditing: isEditing, at: start)
        _ = screen.height()
        #expect(screen.isFocused == isEditing)
        screen.change(to: other)
        // Within a point: heights land on the pixel grid, a third of a point either way.
        #expect(abs(screen.height() - fresh) < 1, "at \(other.rawValue) after \(start.rawValue)")
        screen.change(to: start)
        #expect(abs(screen.height() - freshStart) < 1, "back at \(start.rawValue)")
    }

    @Test("Large to AX5 and back: the title is as tall as fresh at each", arguments: drafts)
    func largeToAX5(draft: String) {
        check(draft, isEditing: false, from: Self.large, via: Self.ax5)
    }

    @Test("AX5 to Large and back: the title is as tall as fresh at each", arguments: drafts)
    func ax5ToLarge(draft: String) {
        check(draft, isEditing: false, from: Self.ax5, via: Self.large)
    }

    @Test(
        "A name wider than its cells is never cut off, fresh or after a size change",
        arguments: wideDrafts,
    )
    func wideName(draft: String) {
        for isEditing in [false, true] {
            for category in [Self.large, Self.ax5] {
                let screen = Screen(draft, isEditing: isEditing, at: category)
                defer { screen.window.isHidden = true }
                let state = isEditing ? "editing" : "at rest"
                _ = screen.height()
                #expect(screen.showsAllText, "\(state), fresh at \(category.rawValue)")
                let other = category == Self.large ? Self.ax5 : Self.large
                screen.change(to: other)
                _ = screen.height()
                #expect(
                    screen.showsAllText,
                    "\(state), at \(other.rawValue) after \(category.rawValue)",
                )
            }
        }
    }

    @Test("While editing, Large to AX5 and back", arguments: drafts)
    func whileEditing(draft: String) {
        check(draft, isEditing: true, from: Self.large, via: Self.ax5)
    }
}

/// Focuses the field as it appears, as a tap does, so the text system lays it out as it does
/// while editing.
private struct FocusOnAppear: ViewModifier {
    let isOn: Bool
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onAppear { isFocused = isOn }
    }
}

#endif
