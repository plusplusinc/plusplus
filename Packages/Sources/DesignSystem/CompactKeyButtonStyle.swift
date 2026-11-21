import SwiftUI

/// The secondary key's look at a compact size: a capsule sized to its label, on the raised gray
/// fill with a ledge of the well's color, its label in primary text in the body style, at least
/// a tap target tall. Pressing pushes it down onto its ledge, as the primary key does. For a way
/// to go somewhere from a screen with nothing to show, as Log's Go to Workouts.
public struct CompactKeyButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var labelInset: CGFloat = 10
    private static let ledge: CGFloat = 3

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: minHeight / 2)
        configuration.label
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, labelInset)
            .frame(minHeight: minHeight)
            .background(shape.fill(.pp(.surfaceRaised)))
            .contentShape(shape)
            .offset(y: configuration.isPressed ? Self.ledge : 0)
            .keyPressAnimation(isPressed: configuration.isPressed)
            .background(shape.fill(.pp(.well)).offset(y: Self.ledge))
            .padding(.bottom, Self.ledge)
    }
}

extension ButtonStyle where Self == CompactKeyButtonStyle {
    /// `.buttonStyle(.compactKey)`.
    public static var compactKey: CompactKeyButtonStyle {
        CompactKeyButtonStyle()
    }
}

#Preview {
    Button("Go to Workouts") { }
        .buttonStyle(.compactKey)
        .padding()
        .background(Color.pp(.background))
}
