// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import Foundation
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

    /// Names wider than a cell of the title's font: emoji and CJK.
    nonisolated static let wideDrafts = [
        "Legs 💪💪💪💪💪💪💪 and back",
        "上半身と下半身の筋力トレーニング",
    ]

    /// The title on screen in a window at `category`, with the field focused when `isEditing`.
    private final class Screen {
        let window: UIWindow
        let host: UIHostingController<AnyView>

        /// `caretAt` puts the caret before that character of `draft`, for a `_` to draw while
        /// editing; nil leaves no selection.
        init(
            _ draft: String,
            isEditing: Bool,
            at category: UIContentSizeCategory,
            caretAt offset: Int? = nil,
        ) {
            host = UIHostingController(rootView: AnyView(
                EditableTitleContent(
                    draft: .constant(draft),
                    // Focused as a tap focuses it, so the text system lays it out as it does
                    // while editing.
                    isFocused: .constant(isEditing),
                    selection: offset.map {
                        let index = draft.index(draft.startIndex, offsetBy: $0)
                        return NSRange(index ..< index, in: draft)
                    },
                    placeholder: "New routine",
                    shownPlaceholder: "New routine",
                    isEditing: isEditing,
                    blinks: false,
                    accessibilityLabel: "Routine name",
                    accessibilityHint: "Renames the routine.",
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

        /// Off screen once a test is done with it, so that it holds no focus while the next
        /// window is measured.
        isolated deinit {
            window.isHidden = true
        }

        /// The title's height once layout has settled.
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

        /// Whether the field is exactly as tall as its text: nothing scrolled inside it, and no
        /// empty line under the name. Within a point, as heights land on the pixel grid.
        var fitsText: Bool {
            func textViews(in view: UIView) -> [UITextView] {
                (view as? UITextView).map { [$0] } ?? view.subviews.flatMap(textViews(in:))
            }
            guard let field = textViews(in: host.view).first else {
                Issue.record("No text view in the title")
                return false
            }
            field.layoutIfNeeded()
            return abs(field.contentSize.height - field.bounds.height) <= 1
        }

        /// Whether the field's text view has the keyboard's focus.
        var isFocused: Bool {
            func focused(in view: UIView) -> Bool {
                view.isFirstResponder || view.subviews.contains(where: focused(in:))
            }
            return focused(in: host.view)
        }

        /// The window's view as drawn, the title and its `_` included, once the title's height
        /// has settled.
        func image() -> UIImage {
            _ = height()
            let bounds = host.view.bounds
            // The window has no scene, so it is never on a screen for `drawHierarchy` to copy;
            // its layers render all the same.
            return UIGraphicsImageRenderer(bounds: bounds).image { context in
                host.view.layer.render(in: context.cgContext)
            }
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
        let fresh = Screen(draft, isEditing: isEditing, at: other).height()
        let freshStart = Screen(draft, isEditing: isEditing, at: start).height()
        let screen = Screen(draft, isEditing: isEditing, at: start)
        _ = screen.height()
        #expect(screen.isFocused == isEditing)
        screen.change(to: other)
        // Within a point: heights land on the pixel grid, a third of a point either way.
        #expect(abs(screen.height() - fresh) < 1, "at \(other.rawValue) after \(start.rawValue)")
        screen.change(to: start)
        #expect(abs(screen.height() - freshStart) < 1, "back at \(start.rawValue)")
    }

    @Test(
        "Large to AX5 and back, at rest and editing: the title is as tall as fresh at each",
        arguments: drafts,
        [false, true],
    )
    func largeToAX5(draft: String, isEditing: Bool) {
        check(draft, isEditing: isEditing, from: Self.large, via: Self.ax5)
    }

    @Test("AX5 to Large and back: the title is as tall as fresh at each", arguments: drafts)
    func ax5ToLarge(draft: String) {
        check(draft, isEditing: false, from: Self.ax5, via: Self.large)
    }

    /// Names whose caret sits mid-word, on line 1 at Large and on a later line at AX5.
    /// The emoji name's caret is mid-way through its run of emoji.
    nonisolated static let carets = [
        ("Arm and back", 9),
        ("Hot beat drills and abs", 11),
        ("Legs 💪💪💪💪💪💪💪 and back", 8),
    ]

    @Test(
        "Editing, the _ is drawn where it is fresh, under the caret, after a size change each way",
        arguments: carets,
    )
    func cursorAfterSizeChange(draft: String, caret: Int) throws {
        for (start, other) in [(Self.large, Self.ax5), (Self.ax5, Self.large)] {
            let fresh = Screen(draft, isEditing: true, at: other, caretAt: caret).image()
            let freshStart = Screen(draft, isEditing: true, at: start, caretAt: caret).image()
            // The images see the `_`: one a cell along draws differently.
            let moved = Screen(draft, isEditing: true, at: start, caretAt: caret + 1).image()
            try #require(!Self.samePixels(moved, freshStart), "the _ is not in the image")
            let screen = Screen(draft, isEditing: true, at: start, caretAt: caret)
            _ = screen.image()
            #expect(screen.isFocused)
            screen.change(to: other)
            #expect(
                Self.samePixels(screen.image(), fresh),
                "at \(other.rawValue) after \(start.rawValue)",
            )
            screen.change(to: start)
            #expect(Self.samePixels(screen.image(), freshStart), "back at \(start.rawValue)")
        }
    }

    /// Whether two images are the same size with every pixel within a few levels per channel,
    /// for antialiasing that can land differently on the pixel grid.
    private static func samePixels(_ one: UIImage, _ other: UIImage) -> Bool {
        guard let first = one.cgImage, let second = other.cgImage,
              first.width == second.width, first.height == second.height
        else { return false }
        let (bytes, otherBytes) = (rgba(first), rgba(second))
        return zip(bytes, otherBytes).allSatisfy { abs(Int($0) - Int($1)) <= 8 }
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buffer
    }

    @Test(
        "A name wider than its cells fits its title, fresh or after a size change",
        arguments: wideDrafts,
    )
    func wideName(draft: String) {
        for isEditing in [false, true] {
            for category in [Self.large, Self.ax5] {
                let screen = Screen(draft, isEditing: isEditing, at: category)
                let state = isEditing ? "editing" : "at rest"
                _ = screen.height()
                #expect(screen.fitsText, "\(state), fresh at \(category.rawValue)")
                let other = category == Self.large ? Self.ax5 : Self.large
                screen.change(to: other)
                _ = screen.height()
                #expect(
                    screen.fitsText,
                    "\(state), at \(other.rawValue) after \(category.rawValue)",
                )
            }
        }
    }
}

#endif
