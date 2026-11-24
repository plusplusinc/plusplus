#if os(iOS)
import SwiftUI
import UIKit

/// Whether a finger is down anywhere in a window, the navigation bar's back button included,
/// read when asked rather than drawn (`watchesFingers(_:)`).
///
/// A button acts as the finger lifts, so a press under way is the moment between a person
/// starting something and the app hearing of it: Back pops on the lift, and while the finger is
/// down the screen still reads as staying.
public final class FingerWatch {
    fileprivate var touches: [Weak] = []

    public init() { }

    /// Read from the touches themselves, which UIKit updates until they end.
    public var isDown: Bool {
        touches.contains { $0.touch.map { ![.ended, .cancelled].contains($0.phase) } ?? false }
    }

    fileprivate func began(_ began: Set<UITouch>) {
        touches = touches.filter { $0.touch != nil } + began.map(Weak.init)
    }

    fileprivate struct Weak {
        weak var touch: UITouch?
    }
}

extension View {
    /// Keeps `watch` told of the touches that come down in this view's window.
    public func watchesFingers(_ watch: FingerWatch) -> some View {
        background(FingerDown(watch: watch).accessibilityHidden(true))
    }
}

private struct FingerDown: UIViewRepresentable {
    let watch: FingerWatch

    func makeUIView(context _: Context) -> Watcher {
        Watcher(watch: watch)
    }

    func updateUIView(_ watcher: Watcher, context _: Context) {
        watcher.recognizer.watch = watch
    }

    /// Puts the recognizer on its window, the root of every touched view's chain, so touches in
    /// the bars reach it too, and takes it off as it leaves.
    final class Watcher: UIView {
        let recognizer: Recognizer

        init(watch: FingerWatch) {
            recognizer = Recognizer(watch: watch)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("Not built from a storyboard")
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            recognizer.view?.removeGestureRecognizer(recognizer)
            newWindow?.addGestureRecognizer(recognizer)
        }
    }

    /// Notes each touch as it comes down and fails at once, so it takes nothing from the views
    /// and recognizers under the finger; a recognizer that waited for the lift held Back's tap
    /// until its menu opened instead.
    final class Recognizer: UIGestureRecognizer {
        var watch: FingerWatch

        init(watch: FingerWatch) {
            self.watch = watch
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            watch.began(touches)
            state = .failed
        }
    }
}
#endif
