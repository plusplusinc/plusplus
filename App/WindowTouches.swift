import SwiftUI
import UIKit

extension View {
    /// Turns touches off for the whole window while `isOff`, as through a finish's hold before
    /// its way to Log, which holds the screen still. The window's, not the screen's: the bar's
    /// items are hosted apart from the screen, and their glass swelled under a touch with the
    /// item's `allowsHitTesting` off, and with it `disabled` too.
    func windowTouchesOff(_ isOff: Bool) -> some View {
        background { WindowTouches(isOff: isOff) }
    }
}

private struct WindowTouches: UIViewRepresentable {
    let isOff: Bool

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context _: Context) {
        view.window?.isUserInteractionEnabled = !isOff
    }

    static func dismantleUIView(_ view: UIView, coordinator _: ()) {
        view.window?.isUserInteractionEnabled = true
    }
}
