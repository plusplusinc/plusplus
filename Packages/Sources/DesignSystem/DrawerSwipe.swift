#if os(iOS)
import SwiftUI
import UIKit

/// The swipe that opens a `SideDrawer`, in from the screen's left edge, or closes it, leftward
/// anywhere, as a UIKit pan.
///
/// Opening begins only on a move more rightward than up or down from a touch that came down
/// within `DrawerDrag.edge` of the left edge, so a tap, a hold, or a vertical scroll near the
/// edge is left alone. It is a plain pan, not UIKit's screen-edge pan, which never began on the
/// simulator's synthesized touches, so no UI test could swipe it. Closing begins only on a move
/// more leftward than up or down, so the drawer's own scroll, its taps, and a pushed screen's
/// back swipe, which goes right, are left alone. The scroll views' pans wait for it to fail,
/// which it does on the first move that isn't its own, so a swipe in from the edge never also
/// scrolls.
struct DrawerSwipe: UIGestureRecognizerRepresentable {
    /// Open from the left edge rather than close.
    var opens: Bool
    var isEnabled: Bool
    var onPhase: (DrawerDrag.Phase) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(opens: opens)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context _: Context,
    ) {
        let translation = recognizer.translation(in: nil).x
        switch recognizer.state {
        case .began, .changed:
            onPhase(.changed(translation: translation))
        case .ended:
            onPhase(.ended(translation: translation, velocity: recognizer.velocity(in: nil).x))
        case .cancelled, .failed:
            onPhase(.cancelled)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let opens: Bool
        /// Where the finger came down, across the screen.
        private var touchDownX: CGFloat = 0

        init(opens: Bool) {
            self.opens = opens
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: nil)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            guard opens else { return velocity.x < 0 }
            return velocity.x > 0 && touchDownX <= DrawerDrag.edge
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touchDownX = touch.location(in: nil).x
            return true
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer,
        ) -> Bool {
            other is UIPanGestureRecognizer
        }

        /// SwiftUI's gestures under the finger, a row's tap and its swipe actions among them,
        /// begin on the first touch, and a swipe that had to wait for them would never begin.
        /// They come to nothing beside it: a tap fails as the finger moves, and a row has no
        /// swipe actions on its leading side. A row's hold isn't one: lifted, a row isn't
        /// swiped.
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer,
        ) -> Bool {
            !(other is UIPanGestureRecognizer || other is UILongPressGestureRecognizer)
        }
    }
}
#endif
