import SwiftUI
import UIKit

extension View {
    /// Keeps `scheme` on the phone's own light or dark, whatever the window is held to: the
    /// screen's, which the held appearance never reaches. The environment's `colorScheme`, and the
    /// window scene's traits, are the held one, dark under a dark-only theme even on a light
    /// phone. The screen tells nothing of a change, so it is read as the view comes on screen, as
    /// the scene's own traits change (Auto under a theme with both looks), and each time the app
    /// becomes active, which a change from Control Center or the Settings app makes it do.
    func phoneScheme(_ scheme: Binding<ColorScheme>) -> some View {
        background { PhoneSchemeProbe(scheme: scheme) }
    }
}

private struct PhoneSchemeProbe: UIViewRepresentable {
    @Binding var scheme: ColorScheme

    func makeUIView(context _: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = { scheme = $0 }
        return view
    }

    func updateUIView(_ view: ProbeView, context _: Context) {
        view.onChange = { scheme = $0 }
    }

    final class ProbeView: UIView {
        var onChange: (ColorScheme) -> Void = { _ in }
        private var registration: (any UITraitChangeRegistration)?
        private weak var watched: UIWindowScene?
        private var reported: ColorScheme?

        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reread),
                name: UIApplication.didBecomeActiveNotification,
                object: nil,
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let registration {
                watched?.unregisterForTraitChanges(registration)
                self.registration = nil
            }
            guard let scene = window?.windowScene else { return }
            watched = scene
            reread()
            registration = scene.registerForTraitChanges(
                [UITraitUserInterfaceStyle.self],
            ) { [weak self] (_: UIWindowScene, _: UITraitCollection) in
                self?.reread()
            }
        }

        @objc private func reread() {
            guard let screen = window?.windowScene?.screen else { return }
            let read: ColorScheme = screen.traitCollection.userInterfaceStyle == .light
                ? .light : .dark
            guard read != reported else { return }
            reported = read
            // After the update under way: a trait change can arrive during one, and state set
            // during a view update is dropped with a warning.
            DispatchQueue.main.async { [onChange] in onChange(read) }
        }
    }
}
