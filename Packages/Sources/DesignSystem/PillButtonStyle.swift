import SwiftUI

/// A flat gray capsule sized to its label, its label in primary text in the body style, at least
/// a tap target tall. It has no ledge: a key does something to the workout, and this only goes
/// somewhere, from a screen with nothing to show, as Log's Go to Workouts. Pressing dims it, as
/// a key does (`keyPress(isPressed:)`); with Reduce Motion too, since a dim is no motion. In
/// green, as the + that adds an exercise is, for a control that starts something
/// (`.greenPill`); filling with the done purple from its leading edge as a rest's key does
/// (`.pill(filling:)`).
public struct PillButtonStyle: ButtonStyle {
    /// Its least height at the default text size, a tap target's, scaled with the body style.
    static let touchHeight: CGFloat = 44

    fileprivate var fill: ColorToken = .surfaceRaised
    fileprivate var labelColor: ColorToken = .textPrimary
    fileprivate var filling: KeyFill?
    fileprivate var widens = false
    /// Its least height at the default text size.
    fileprivate var height = Self.touchHeight
    /// How the body style scales at the text size now, which the height and insets scale by.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// Above and below the label; less on a pill shorter than a tap target, so one line still
    /// fits its height.
    private var labelInset: CGFloat {
        (Self.labelInset - max(0, Self.touchHeight - height) / 2) * scale
    }

    private var minHeight: CGFloat {
        height * scale
    }

    private static let labelInset: CGFloat = 10

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: minHeight / 2)
        face(configuration.label, color: labelColor)
            // Over the fill, the label in the dark of a filled key, switching where the fill's
            // edge crosses it, as on the rest's key (`PrimaryKeyButtonStyle.countKey`).
            .overlay {
                if let filling {
                    face(configuration.label, color: .onPrimaryKey)
                        .mask(alignment: .leading) { FillingFace(filling: filling, color: .done) }
                        .accessibilityHidden(true)
                }
            }
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(.pp(fill))
                    if let filling {
                        FillingFace(filling: filling).clipShape(shape)
                    }
                }
            }
            .contentShape(shape)
            .keyPress(isPressed: configuration.isPressed)
    }

    private func face(_ label: Configuration.Label, color: ColorToken) -> some View {
        label
            .font(.ppButton)
            .foregroundStyle(.pp(color))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, labelInset)
            .frame(maxWidth: widens ? .infinity : nil, minHeight: minHeight)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// `.buttonStyle(.pill)`.
    public static var pill: PillButtonStyle {
        PillButtonStyle()
    }

    /// The pill filling with the done purple from its leading edge as `filling` runs, as the
    /// note's OK on Log.
    public static func pill(filling: KeyFill?) -> PillButtonStyle {
        var style = PillButtonStyle()
        style.filling = filling
        return style
    }

    /// The pill in green, the + that adds an exercise's fill and its label's color, `height`
    /// tall at the default text size and as wide as it is given when it `widens`.
    public static func greenPill(height: CGFloat? = nil, widens: Bool = false) -> PillButtonStyle {
        var style = PillButtonStyle()
        style.fill = .accent
        style.labelColor = .onPrimaryKey
        style.widens = widens
        if let height {
            style.height = height
        }
        return style
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        Button("Go to Workouts") { }
            .buttonStyle(.pill)
        Button("Sync to Apple Health") { }
            .buttonStyle(.greenPill(height: 50, widens: true))
        Button("OK") { }
            .buttonStyle(.pill(filling: KeyFill(length: 5, ends: .now.addingTimeInterval(3))))
    }
    .padding()
    .background(Color.pp(.background))
}
