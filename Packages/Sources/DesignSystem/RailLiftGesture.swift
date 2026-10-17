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
/// A press on the node, in the rail column, holds the node when `allowsColumn`; otherwise it
/// fails as the hold fires, so it lifts nothing and can still scroll. Either way a press that
/// moves first scrolls.
struct RailLiftGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    /// How wide the rail column is, where a press holds the node rather than lifting the row.
    var columnWidth: CGFloat
    var allowsColumn: Bool
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
        context.coordinator.allowsColumn = allowsColumn
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context,
    ) {
        let inRail = context.converter.location(in: .named(RailDrag.space))
        let finger = RailDrag.Finger(
            inRail: inRail.y,
            inScrollView: context.converter.location(in: .named(RailDrag.scrollSpace)).y,
            inColumn: inRail.x <= context.coordinator.columnWidth,
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
        var allowsColumn = false

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
            allowsColumn || converter.location(in: .named(RailDrag.space)).x > columnWidth
        }
    }
}
#endif
