#if os(iOS)
import SwiftUI

/// The line that offers a filter when typed words name one of its choices: "Filter by
/// muscle" leading, gray as the count line's words, and a "+ Back" button per offer trailing,
/// the small capsule Clear and "+ Bench" wear (`SmallCapsuleButton`). Where they won't fit
/// side by side, the buttons go under the words (`LineOrStack`). VoiceOver reads each button
/// as "Add back to Muscle".
public struct FilterOfferLine: View {
    let text: String
    let offers: [Offer]

    /// One offer's button: the choice's name, the filter it joins, and what a tap does.
    public struct Offer: Identifiable {
        public let id: String
        let title: String
        let filterName: String
        let action: () -> Void

        public init(title: String, filterName: String, action: @escaping () -> Void) {
            id = "\(filterName).\(title)"
            self.title = title
            self.filterName = filterName
            self.action = action
        }
    }

    public init(_ text: String, offers: [Offer]) {
        self.text = text
        self.offers = offers
    }

    public var body: some View {
        TextAndButton {
            Text(text)
                .foregroundStyle(Color.pp(.textSecondary))
        } button: {
            HStack(spacing: Spacing.sm) {
                ForEach(offers) { offer in
                    SmallCapsuleButton(
                        systemImage: "plus",
                        title: offer.title,
                        action: offer.action,
                    )
                    .accessibilityLabel("Add \(offer.title.lowercased()) to \(offer.filterName)")
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        FilterOfferLine(
            "Filter by muscle",
            offers: [.init(title: "Back", filterName: "Muscle") { }],
        )
        FilterOfferLine("Filter by", offers: [
            .init(title: "Back", filterName: "Muscle") { },
            .init(title: "Dumbbells", filterName: "Equipment") { },
        ])
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.pp(.background))
}
#endif
