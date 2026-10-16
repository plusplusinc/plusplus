#if os(iOS)
import SwiftUI
import UIKit

/// A hold on a rail's row that lifts it, then the drag that follows, as a UIKit long press.
///
/// SwiftUI's own long press stops a scroll view from scrolling, and swallows a tap. UIKit's
/// composes with the scroll view's pan as a table's reorder does: a press that moves before the
/// hold fires fails it and scrolls, and once it fires, the pan can't begin and the tap is
/// cancelled. It goes outside a row's tap and swipe actions: inside a SwiftUI tap, which has no
/// time limit and so never fails during a still hold, it never began.
///
/// A press on the node, in the rail column, fails as the hold fires, so it lifts nothing and
/// can still scroll.
struct RailLiftGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    /// How wide the rail column is, where a press lifts nothing.
    var columnWidth: CGFloat
    /// Each step of the drag, with where the finger is.
    var onPhase: (RailDrag.Phase, RailDrag.Finger) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = RailDrag.hold
        recognizer.allowableMovement = RailDrag.allowableMovement
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context,
    ) {
        recognizer.isEnabled = isEnabled
        context.coordinator.columnWidth = columnWidth
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context,
    ) {
        let finger = RailDrag.Finger(
            inRail: context.converter.location(in: .named(RailDrag.space)).y,
            onScreen: context.converter.location(in: .global).y,
        )
        switch recognizer.state {
        case .began: onPhase(.began, finger)
        case .changed: onPhase(.changed, finger)
        case .ended: onPhase(.ended, finger)
        case .cancelled, .failed: onPhase(.cancelled, finger)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let converter: CoordinateSpaceConverter
        var columnWidth: CGFloat = 0

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
            converter.location(in: .named(RailDrag.space)).x > columnWidth
        }
    }
}
#endif
