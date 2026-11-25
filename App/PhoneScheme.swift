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
        modifier(PhoneSchemeReader(scheme: scheme))
    }
}

private struct PhoneSchemeReader: ViewModifier {
    @Binding var scheme: ColorScheme
    /// Bumped as the app becomes active, for the probe to read the screen again.
    @State private var activations = 0

    func body(content: Content) -> some View {
        content
            .background { PhoneSchemeProbe(scheme: $scheme, activations: activations) }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification,
            )) { _ in
                activations += 1
            }
    }
}

private struct PhoneSchemeProbe: UIViewRepresentable {
    @Binding var scheme: ColorScheme
    let activations: Int

    func makeUIView(context _: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = { scheme = $0 }
        return view
    }

    func updateUIView(_ view: ProbeView, context _: Context) {
        view.onChange = { scheme = $0 }
        view.reread()
    }

    final class ProbeView: UIView {
        var onChange: (ColorScheme) -> Void = { _ in }
        private var registration: (any UITraitChangeRegistration)?
        private weak var watched: UIWindowScene?

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

        func reread() {
            guard let screen = window?.windowScene?.screen else { return }
            let read: ColorScheme = screen.traitCollection.userInterfaceStyle == .light
                ? .light : .dark
            guard read != reported else { return }
            reported = read
            // After the update under way: `updateUIView` calls this, and state set during a
            // view update is dropped with a warning.
            DispatchQueue.main.async { [onChange] in onChange(read) }
        }

        private var reported: ColorScheme?
    }
}
