import SwiftUI

/// A one-time offer on a Settings card's ground (`settingsCard()`): a title at a row title's
/// size, read by VoiceOver as a heading, one quieter line under it, then its two buttons
/// leading: the offer as a neutral filled pill (`PillButtonStyle`), not green, since taking it
/// makes nothing in the app, and the way out as plain secondary text at the same height. At
/// accessibility sizes the two stack, the way out under the offer, so neither breaks a word.
/// It draws nothing of its coming and going; whoever shows it closes its room.
public struct OfferCard: View {
    private let title: String
    private let line: String
    private let offer: String
    private let dismiss: String
    private let take: () -> Void
    private let decline: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 44

    public init(
        _ title: String,
        line: String,
        offer: String,
        dismiss: String,
        take: @escaping () -> Void,
        decline: @escaping () -> Void,
    ) {
        self.title = title
        self.line = line
        self.offer = offer
        self.dismiss = dismiss
        self.take = take
        self.decline = decline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(line)
                .font(.ppRowDetail)
                .foregroundStyle(.pp(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, Spacing.sm + Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm + Spacing.xs)
        .settingsCard()
    }

    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        return layout {
            Button(offer, action: take)
                .buttonStyle(.pill)
            Button(action: decline) {
                Text(dismiss)
                    .font(.ppButton)
                    .fontWeight(.regular)
                    .foregroundStyle(.pp(.textSecondary))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    VStack {
        OfferCard(
            "Save your workouts to Apple Health",
            line: "Each workout you finish, with its type and how long it took.",
            offer: "Save to Apple Health",
            dismiss: "Not now",
            take: { },
            decline: { },
        )
        Spacer()
    }
    .padding(Spacing.md)
    .background(Color.pp(.background))
}
