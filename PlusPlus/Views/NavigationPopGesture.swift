import SwiftUI
import UIKit

/// Full-width swipe-back (#198): the system's interactive pop only
/// listens at the screen's left edge; this attaches a full-surface pan
/// that drives the SAME transition, so any rightward swipe on a pushed
/// screen tracks the finger back — the GitHub-app feel.
///
/// Mechanism: a zero-size probe (RailGestureRecognizer's pattern) finds
/// the enclosing UINavigationController and adds a UIPanGestureRecognizer
/// re-targeted at the system interactivePopGestureRecognizer's action
/// targets. Reading those targets uses a private KVC key — the
/// industry-standard trick; if the key ever vanishes the feature
/// degrades to a no-op and pushed screens fall back to the glass back
/// button (tap-only — the hidden system back also disables the edge
/// swipe, which is pre-#198 parity, not a regression).
struct NavigationPopGestureProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> PopGestureProbeView {
        PopGestureProbeView()
    }

    func updateUIView(_ uiView: PopGestureProbeView, context: Context) {}
}

final class PopGestureProbeView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, let navigationController = findNavigationController() else { return }
        attachFullWidthPop(to: navigationController)
    }

    private func findNavigationController() -> UINavigationController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let navigation = current as? UINavigationController { return navigation }
            if let viewController = current as? UIViewController,
               let navigation = viewController.navigationController {
                return navigation
            }
            responder = current.next
        }
        return nil
    }

    private func attachFullWidthPop(to navigationController: UINavigationController) {
        guard let edgeGesture = navigationController.interactivePopGestureRecognizer,
              let gestureView = edgeGesture.view,
              !(gestureView.gestureRecognizers ?? []).contains(where: { $0.name == "plusplus.fullWidthPop" })
        else { return }

        // The system recognizer's targets drive UIKit's percent-driven
        // pop transition. Private KVC key; guarded so failure is silent.
        guard let targets = edgeGesture.value(forKey: "targets") as? NSMutableArray, targets.count > 0 else { return }

        let pan = UIPanGestureRecognizer()
        pan.name = "plusplus.fullWidthPop"
        pan.maximumNumberOfTouches = 1
        pan.setValue(targets, forKey: "targets")
        pan.delegate = PopGestureGate.shared
        PopGestureGate.shared.register(navigationController: navigationController, for: pan)
        gestureView.addGestureRecognizer(pan)
    }
}

/// Gates the full-width pan so it only begins as a deliberate rightward
/// back-swipe on a pushed screen, and never steals vertical scrolling.
final class PopGestureGate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureGate()

    private let controllers = NSMapTable<UIPanGestureRecognizer, UINavigationController>(
        keyOptions: .weakMemory, valueOptions: .weakMemory
    )

    func register(navigationController: UINavigationController, for pan: UIPanGestureRecognizer) {
        controllers.setObject(navigationController, forKey: pan)
    }

    /// Raised while any SwipeRevealRow is open: closing a row is by
    /// design a rightward horizontal drag, indistinguishable from a
    /// back-swipe — the row wins, the pop stands down (#198 review).
    /// Clamped non-negative at every mutation site; main-thread only.
    static var suppressionCount = 0

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard Self.suppressionCount == 0,
              let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let navigationController = controllers.object(forKey: pan),
              navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil
        else { return false }
        let velocity = pan.velocity(in: pan.view)
        // Rightward and decisively horizontal.
        return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // A horizontally-scrollable scroll view that can still scroll
        // left keeps its pan; the pop only wins where content can't use
        // the drag (vertical lists, static screens).
        if let scrollPan = otherGestureRecognizer as? UIPanGestureRecognizer,
           let scrollView = scrollPan.view as? UIScrollView,
           scrollView.contentSize.width > scrollView.bounds.width + 1 {
            return scrollView.contentOffset.x > -scrollView.adjustedContentInset.left
        }
        return false
    }
}

extension View {
    /// Apply to a pushed screen to make the whole surface swipe back.
    func fullWidthSwipeBack() -> some View {
        background(NavigationPopGestureProbe().frame(width: 0, height: 0))
    }
}
