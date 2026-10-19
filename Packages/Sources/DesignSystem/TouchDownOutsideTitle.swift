import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Runs `action` the moment a finger comes down anywhere in this view except on an
    /// `EditableTitle`'s field, and leaves the touch to do what it would have done.
    ///
    /// So a touch outside the title ends its edit in the same motion as its own work: a tap on
    /// a row opens the row, a hold lifts it, a drag scrolls, never a first tap that only closes
    /// the keyboard. Touches on the title keep editing, to move the caret or select.
    public func onTouchDownOutsideTitle(perform action: @escaping () -> Void) -> some View {
        #if os(iOS)
        gesture(TouchDownOutsideTitle(action: action))
        #else
        self
        #endif
    }
}

#if os(iOS)
/// A recognizer that watches touches come down and never recognizes, so it takes nothing from
/// the views and gestures under the finger: UIKit gives every recognizer up the hit view's
/// chain the touch, and one that fails leaves the others, and the views' own touches, as they
/// were.
private struct TouchDownOutsideTitle: UIGestureRecognizerRepresentable {
    var action: () -> Void

    func makeUIGestureRecognizer(context _: Context) -> Recognizer {
        Recognizer()
    }

    func updateUIGestureRecognizer(_ recognizer: Recognizer, context _: Context) {
        recognizer.onTouchDown = action
    }

    final class Recognizer: UIGestureRecognizer {
        var onTouchDown: () -> Void = { }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            // On the field, or on the target behind a short title, which is SwiftUI's and so no
            // view of the field's.
            let fields = view.map(Self.titleFields(in:)) ?? []
            let onTitle = touches.contains { touch in
                let point = touch.location(in: nil)
                return fields.contains { $0.touchTargetInWindow.contains(point) }
            }
            if !onTitle {
                onTouchDown()
            }
            state = .failed
        }

        private static func titleFields(in view: UIView) -> [TitleFieldView] {
            (view as? TitleFieldView).map { [$0] } ?? view.subviews.flatMap(titleFields(in:))
        }
    }
}
#endif
