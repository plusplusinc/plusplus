import SwiftUI
import UIKit

extension View {
    /// Keeps `scheme` on the phone's own light or dark, whatever the window is held to: the
    /// window's scene, whose traits the window's held appearance never reaches. The environment's
    /// `colorScheme` is the held one, dark under a dark-only theme even on a light phone.
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

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let registration {
                watched?.unregisterForTraitChanges(registration)
                self.registration = nil
            }
            guard let scene = window?.windowScene else { return }
            watched = scene
            report(scene.traitCollection)
            registration = scene.registerForTraitChanges(
                [UITraitUserInterfaceStyle.self],
            ) { [weak self] (scene: UIWindowScene, _: UITraitCollection) in
                self?.report(scene.traitCollection)
            }
        }

        private func report(_ traits: UITraitCollection) {
            onChange(traits.userInterfaceStyle == .light ? .light : .dark)
        }
    }
}
