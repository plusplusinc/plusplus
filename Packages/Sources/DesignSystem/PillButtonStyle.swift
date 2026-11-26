import SwiftUI

/// A flat gray capsule sized to its label, its label in primary text in the body style, at least
/// a tap target tall. It has no ledge: a key does something to the workout, and this only goes
/// somewhere, from a screen with nothing to show, as Log's Go to Workouts. Pressing dims it, as
/// a key does (`keyPress(isPressed:)`); with Reduce Motion too, since a dim is no motion. On a
/// `surface` card it fills in `pillOnSurface` (`.pillOnSurface`), as `surfaceRaised` barely
/// stands off the card.
public struct PillButtonStyle: ButtonStyle {
    /// Its least height at the default text size, a tap target's, scaled with the body style.
    static let touchHeight: CGFloat = 44

    private let fill: ColorToken
    @ScaledMetric(relativeTo: .body) private var minHeight = Self.touchHeight
    @ScaledMetric(relativeTo: .body) private var labelInset: CGFloat = 10

    public init() {
        fill = .surfaceRaised
    }

    init(fill: ColorToken) {
        self.fill = fill
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: minHeight / 2)
        configuration.label
            .font(.ppButton)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, labelInset)
            .frame(minHeight: minHeight)
            .background(shape.fill(.pp(fill)))
            .contentShape(shape)
            .keyPress(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// `.buttonStyle(.pill)`.
    public static var pill: PillButtonStyle {
        PillButtonStyle()
    }

    /// The pill on a `surface` card, as the offer's button.
    static var pillOnSurface: PillButtonStyle {
        PillButtonStyle(fill: .pillOnSurface)
    }
}

#Preview {
    Button("Go to Workouts") { }
        .buttonStyle(.pill)
        .padding()
        .background(Color.pp(.background))
}
