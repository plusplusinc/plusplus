import SwiftUI
import UIKit

/// UIActivityViewController wrapped for SwiftUI — used instead of
/// ShareLink where the share needs per-activity content (#178).
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The human sentence that accompanies a shared link everywhere EXCEPT
/// the pasteboard: Copy should take just the URL (Dave, #178), while
/// Messages/Mail still compose "My Push Day routine on PlusPlus" + link.
final class ShareMessageItem: NSObject, UIActivityItemSource {
    private let text: String
    private let subject: String

    init(text: String, subject: String) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        activityType == .copyToPasteboard ? nil : text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}
