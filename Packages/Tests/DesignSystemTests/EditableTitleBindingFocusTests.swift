// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The caller's binding starts and ends an edit (a tap below a short title, a touch outside an
/// edited one), and the field takes or gives up focus only once SwiftUI's update has ended,
/// as `TitleTextView.Coordinator.followFocus(of:)` says why. The dependency cycle a change
/// inside it logs does not reach a test, so this checks where the focus changes instead.
@MainActor
@Suite("Editable title follows its binding's focus after SwiftUI's update")
struct EditableTitleBindingFocusTests {
    @Observable
    final class Model {
        var name = "Push"
        var isEditing = false
    }

    private struct Host: View {
        let model: Model

        var body: some View {
            @Bindable var model = model
            EditableTitle(
                text: $model.name,
                isEditing: $model.isEditing,
                placeholder: "New routine",
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            .frame(width: 370)
        }
    }

    /// Where each focus change of the field happened: inside SwiftUI's update or after it.
    private final class Changes {
        var insideUpdate = false
        var seen: [(change: String, insideUpdate: Bool)] = []
    }

    @Test("Setting the binding moves focus after SwiftUI's update, never inside it")
    func focusFollowsBindingAfterUpdate() async throws {
        let model = Model()
        let host = UIHostingController(rootView: Host(model: model))
        host.safeAreaRegions = []
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        func field(in view: UIView) -> TitleFieldView? {
            view as? TitleFieldView ?? view.subviews.lazy.compactMap(field(in:)).first
        }
        let field = try #require(field(in: host.view))

        let changes = Changes()
        let center = NotificationCenter.default
        let observers = [
            (UITextView.textDidBeginEditingNotification, "began"),
            (UITextView.textDidEndEditingNotification, "ended"),
        ].map { name, change in
            center.addObserver(forName: name, object: field, queue: nil) { _ in
                MainActor.assumeIsolated {
                    changes.seen.append((change, changes.insideUpdate))
                }
            }
        }
        defer { observers.forEach(center.removeObserver) }

        // Sets the binding, then runs SwiftUI's update for it, marked, and lets what follows run:
        // what the update queued on the main queue runs only once this test's turn on it ends.
        func set(_ isEditing: Bool) async {
            model.isEditing = isEditing
            changes.insideUpdate = true
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // The update did run in the marked span: the field took the look the binding asks
            // for. Without this, an update moved after the span would pass with nothing checked.
            #expect(field.isEditingLook == isEditing, "SwiftUI's update ran outside the span")
            changes.insideUpdate = false
            await withCheckedContinuation { done in
                DispatchQueue.main.async { done.resume() }
            }
            window.settle()
        }

        await set(true)
        #expect(field.isFirstResponder, "Setting the binding to true did not focus the field")
        await set(false)
        #expect(!field.isFirstResponder, "Setting the binding to false kept the field focused")
        #expect(changes.seen.map(\.change) == ["began", "ended"])
        for change in changes.seen {
            #expect(!change.insideUpdate, "Focus \(change.change) inside SwiftUI's update")
        }
    }
}

#endif
