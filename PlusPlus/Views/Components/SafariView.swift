import SwiftUI
import SafariServices

/// In-app Safari (`SFSafariViewController`) for flows that should stay inside
/// the app rather than kick the user out to the system browser. Used by the
/// GitHub sync tray's "Create repo" step when the GitHub app isn't installed
/// to handle the universal link, so github.new opens in a dismissible sheet.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
