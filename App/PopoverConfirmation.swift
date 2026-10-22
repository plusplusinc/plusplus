import SwiftUI
import UIKit

/// One choice in a `popoverConfirmation`, by its title, red when destructive.
struct ConfirmationChoice {
    let title: String
    var isDestructive = false
    let action: () -> Void
}

extension View {
    /// While `isPresented`, a confirmation with no title, UIKit's action sheet, pointing at this
    /// view: from a bar button, a popover, which a tap outside cancels. As SwiftUI's
    /// `confirmationDialog` looks, but a choice runs once the popover has gone, about half a
    /// second after the tap: the dialog ran it about 1.2 s after, the screen still between.
    func popoverConfirmation(
        isPresented: Binding<Bool>,
        choices: [ConfirmationChoice],
    ) -> some View {
        background {
            ConfirmationAnchor(isPresented: isPresented, choices: choices)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The view the action sheet points at, which presents it from the view controller showing.
private struct ConfirmationAnchor: UIViewRepresentable {
    @Binding var isPresented: Bool
    let choices: [ConfirmationChoice]

    final class Coordinator {
        var sheet: UIAlertController?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        if isPresented, coordinator.sheet == nil {
            present(from: view, coordinator)
        } else if !isPresented, let sheet = coordinator.sheet {
            coordinator.sheet = nil
            sheet.dismiss(animated: true)
        }
    }

    private func present(from view: UIView, _ coordinator: Coordinator) {
        guard var presenter = view.window?.rootViewController else {
            isPresented = false
            return
        }
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let isPresented = $isPresented
        let close = {
            coordinator.sheet = nil
            isPresented.wrappedValue = false
        }
        for choice in choices {
            sheet.addAction(UIAlertAction(
                title: choice.title,
                style: choice.isDestructive ? .destructive : .default,
            ) { _ in
                close()
                choice.action()
            })
        }
        // Not shown in a popover, where a tap outside runs it.
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
            close()
        })
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        coordinator.sheet = sheet
        presenter.present(sheet, animated: true)
    }
}
