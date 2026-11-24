#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// Calls `arrived` each time the screen this view is in has finished appearing: for a pushed
    /// screen, once the push has slid it fully in. SwiftUI's `onAppear` and `task` start as the
    /// push begins, and it says nothing when the push ends; UIKit tells the screen's view
    /// controller, and with it the controller this adds as its child, in `viewDidAppear(_:)`.
    ///
    /// Calls `leaving` the moment the screen begins to go, in `viewWillDisappear(_:)`: as a pop
    /// starts, before a `navigationDestination`'s binding hears of it.
    public func onScreenArrival(
        _ arrived: @escaping () -> Void,
        leaving: @escaping () -> Void = { },
    ) -> some View {
        background(ScreenArrival(arrived: arrived, leaving: leaving).accessibilityHidden(true))
    }
}

private struct ScreenArrival: UIViewControllerRepresentable {
    let arrived: () -> Void
    let leaving: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        Controller(arrived: arrived, leaving: leaving)
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.arrived = arrived
        controller.leaving = leaving
    }

    final class Controller: UIViewController {
        var arrived: () -> Void
        var leaving: () -> Void

        init(arrived: @escaping () -> Void, leaving: @escaping () -> Void) {
            self.arrived = arrived
            self.leaving = leaving
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

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            leaving()
        }
    }
}
#endif
