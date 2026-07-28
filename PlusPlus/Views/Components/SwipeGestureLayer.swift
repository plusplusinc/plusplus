import SwiftUI
import UIKit

/// The UIKit gesture layer behind `SwipeRevealRow` (2026-07-27, #169).
///
/// ⚠️ Why this exists, and why SwiftUI could not: **a SwiftUI `DragGesture`
/// cannot decline a touch.** Its direction guards run inside
/// `.updating`/`.onChanged`, so they decide what the row DOES — but by the time
/// they run the recognizer has already CLAIMED the sequence, and the claim is
/// what starves the enclosing scroll pan. A diagonal flick moved neither the
/// row (the guard said vertical) nor the list (the drag owned the touch). Dave
/// confirmed the dead scroll tracks flick ANGLE exactly, which is that bug and
/// nothing else. `.simultaneousGesture` does not save it: it governs SwiftUI's
/// composition, not the claim.
///
/// UIKit *can* decline. `gestureRecognizerShouldBegin` runs BEFORE the pan takes
/// the sequence, so a vertical drag fails this recognizer outright and the
/// scroll view keeps its touch untouched. This is the escape #169 prescribed
/// ("the known-good escape is a UIKit recognizer") and that #127 already proved
/// on this very screen for the rail's ring gesture.
///
/// Shape follows `RailGestureRecognizer` deliberately: a zero-interaction probe
/// pinned to the row reports geometry, while the recognizers attach to the
/// ENCLOSING `UIScrollView`, where they arbitrate with its pan the way UIKit
/// intends. Each row installs its own pair and gates them to its own bounds, so
/// N rows means N cheap recognizers on one scroll view — fine for a routine's
/// dozen rail rows, which is why the 157-row catalogs went to native
/// `.swipeActions` instead of this.
struct SwipeGestureLayer: UIViewRepresentable {
    /// Mirrors the row's own `enabled`: while a rail ring drag is live, a
    /// second finger must not swipe or activate a row.
    var enabled: Bool
    /// Live horizontal translation, in the row's coordinate space.
    var onChanged: (CGFloat) -> Void
    /// Final translation, plus the flick's projected residual travel — the
    /// input the row's momentum floor (build 31) tests.
    var onEnded: (_ translationX: CGFloat, _ momentumX: CGFloat) -> Void
    /// The sequence died without an end (incoming call, Control Center).
    /// UIKit reports this for real, where SwiftUI's `onEnded` simply never ran.
    var onCancelled: () -> Void
    /// A genuine tap. Arbitration-guaranteed impossible once the pan begins.
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.backgroundColor = .clear
        // The probe is geometry only. It must never take a touch itself, or it
        // would shadow the row content and the revealed action buttons.
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        let coordinator = context.coordinator
        coordinator.enabled = enabled
        coordinator.onChanged = onChanged
        coordinator.onEnded = onEnded
        coordinator.onCancelled = onCancelled
        coordinator.onTap = onTap
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
            // The INNERMOST enclosing scroll view only. Walking to the top
            // would land on the UIWindow and gate every touch in the app
            // (RailGestureRecognizer's bug-hunt finding 2). If SwiftUI ever
            // stops backing ScrollView with UIScrollView we want these
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
        var enabled = true
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat, CGFloat) -> Void)?
        var onCancelled: (() -> Void)?
        var onTap: (() -> Void)?

        private weak var probe: UIView?
        private weak var pan: UIPanGestureRecognizer?
        private weak var tap: UITapGestureRecognizer?

        func attach(to view: UIScrollView, probe: UIView) {
            self.probe = probe
            guard pan?.view !== view else { return }
            detach()

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.name = Self.panName
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            self.pan = pan

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.delegate = self
            // Build 33's law, as genuine ARBITRATION rather than the slop
            // heuristic that failed CI: the tap cannot fire unless the pan has
            // already failed, so a finger-lift that ended a reveal drag can
            // never also activate the row.
            tap.require(toFail: pan)
            // Never swallow a touch bound for a revealed action button or any
            // control inside the row — this recognizer only ADDS an activation.
            tap.cancelsTouchesInView = false
            view.addGestureRecognizer(tap)
            self.tap = tap
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            if let tap { tap.view?.removeGestureRecognizer(tap) }
            pan = nil
            tap = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let probe else { return }
            let translation = recognizer.translation(in: probe).x
            switch recognizer.state {
            case .changed:
                onChanged?(translation)
            case .ended:
                // UIKit's own projection convention for a flick's remaining
                // travel. The row's floor is expressed in POINTS, so this keeps
                // the build-31 threshold meaning exactly what it did under
                // SwiftUI's `predictedEndTranslation`.
                let momentum = recognizer.velocity(in: probe).x * 0.1
                onEnded?(translation, momentum)
            case .cancelled, .failed:
                onCancelled?()
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTap?()
        }

        // MARK: - UIGestureRecognizerDelegate

        /// ⚠️ THE WHOLE POINT. Declining here fails the recognizer before it
        /// takes the sequence, so a vertical drag reaches the scroll pan
        /// untouched — which a SwiftUI guard inside `onChanged` can never do.
        ///
        /// ⚠️ Judged on TRANSLATION, never velocity. Velocity at the instant a
        /// pan wants to begin is one noisy sample, and a thumb pivots at its
        /// base — it reads horizontal for a frame before it goes vertical.
        /// Translation is accumulated intent. (`PopGestureGate` still reads
        /// velocity; that is a separate, older gate.)
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard enabled else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan === self.pan else {
                // The tap already requires the pan to fail; nothing to add.
                return true
            }
            guard let probe else { return false }
            let translation = pan.translation(in: probe)
            // A dead-equal or zero translation is not evidence of a horizontal
            // intent, so it belongs to the scroll.
            return abs(translation.x) > abs(translation.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard enabled, let probe, probe.window != nil else { return false }
            // Gate each row's pair to its OWN bounds. The probe is a background
            // of the row content, so it rides the reveal translation with it —
            // which is what keeps a touch on a revealed DELETE out of this
            // row's tap recognizer (build 36's ordering law, inherited).
            return probe.bounds.contains(touch.location(in: probe))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Coexist with the scroll pan (that is the point of this method)
            // and with the rail's long press, but NEVER with the full-width
            // pop: a pop starting mid-swipe would slide the screen away while
            // a lift committed a reveal the user never saw (#198 review).
            otherGestureRecognizer.name != "plusplus.fullWidthPop"
        }

        private static let panName = "plusplus.swipeReveal"
    }
}
