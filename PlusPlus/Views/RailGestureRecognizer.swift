import SwiftUI
import UIKit

/// UIKit long-press layer for the rail's direct-manipulation gestures.
///
/// Third strike on the detail-view scroll bug (#92 fixed layout, #99
/// switched to simultaneousGesture): SwiftUI's LongPressGesture starves
/// UIScrollView's pan in ANY composition — sequenced, simultaneous,
/// either order — so rows could be dragged but an overflowing list could
/// not scroll. UIKit's UILongPressGestureRecognizer is the primitive the
/// system's own drag-to-reorder is built on and arbitrates correctly:
/// early movement hands the touch to the scroll pan, a stationary hold
/// fires the press, and the view then disables scrolling for the
/// duration of the drag.
///
/// The zero-sized probe view pins to the rail content's top-leading
/// corner; the recognizer attaches to the enclosing UIScrollView (found
/// by walking superviews once the probe lands in a window, falling back
/// to the root hosting view) and reports locations in the probe's —
/// i.e. the rail content's — coordinate space.
struct RailGestureRecognizer: UIViewRepresentable {
    /// Return false to leave a touch alone (gaps, the add row, buttons):
    /// the recognizer never starts for it, so taps and swipes there are
    /// untouched by the long-press machinery.
    var shouldReceive: (CGPoint) -> Bool
    var began: (CGPoint) -> Void
    var moved: (CGPoint) -> Void
    var ended: (_ location: CGPoint, _ cancelled: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.shouldReceive = shouldReceive
        context.coordinator.began = began
        context.coordinator.moved = moved
        context.coordinator.ended = ended
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                coordinator?.detach()
                return
            }
            // Attach to the enclosing scroll view ONLY: its recognizer
            // sees every touch on the list and loses to the scroll pan
            // the way UIKit intends. No fallback — walking to the top
            // would land on the UIWindow and intercept holds app-wide
            // (bug hunt finding 2); SwiftUI's ScrollView is
            // UIScrollView-backed, and if that ever changes we want the
            // gestures dead, not global.
            var host: UIView = self
            var scrollView: UIScrollView?
            while let superview = host.superview {
                host = superview
                if scrollView == nil, let found = host as? UIScrollView {
                    scrollView = found
                }
            }
            if let scrollView {
                coordinator?.attach(to: scrollView, probe: self)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldReceive: ((CGPoint) -> Bool)?
        var began: ((CGPoint) -> Void)?
        var moved: ((CGPoint) -> Void)?
        var ended: ((CGPoint, Bool) -> Void)?

        private weak var probe: UIView?
        private weak var recognizer: UILongPressGestureRecognizer?

        func attach(to view: UIView, probe: UIView) {
            self.probe = probe
            guard recognizer?.view !== view else { return }
            detach()
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handle))
            press.minimumPressDuration = 0.35
            press.allowableMovement = 10
            press.delegate = self
            view.addGestureRecognizer(press)
            recognizer = press
        }

        func detach() {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
        }

        @objc private func handle(_ press: UILongPressGestureRecognizer) {
            guard let probe else { return }
            let location = press.location(in: probe)
            switch press.state {
            case .began: began?(location)
            case .changed: moved?(location)
            case .ended: ended?(location, false)
            case .cancelled, .failed: ended?(location, true)
            default: break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let probe, let shouldReceive else { return false }
            return shouldReceive(touch.location(in: probe))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
