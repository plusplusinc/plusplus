#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// Calls `arrived` each time the screen this view is in has finished appearing: for a pushed
    /// screen, once the push has slid it fully in. SwiftUI's `onAppear` and `task` start as the
    /// push begins, and it says nothing when the push ends; UIKit tells the screen's view
    /// controller, and with it the controller this adds as its child, in `viewDidAppear(_:)`.
    public func onScreenArrival(_ arrived: @escaping () -> Void) -> some View {
        background(ScreenArrival(arrived: arrived).accessibilityHidden(true))
    }
}

private struct ScreenArrival: UIViewControllerRepresentable {
    let arrived: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        Controller(arrived: arrived)
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.arrived = arrived
    }

    final class Controller: UIViewController {
        var arrived: () -> Void

        init(arrived: @escaping () -> Void) {
            self.arrived = arrived
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("Not built from a storyboard")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            arrived()
        }
    }
}
#endif
