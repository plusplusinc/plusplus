import SwiftUI

/// The one key a screen is for, such as Start: full width, a light fill on a ledge, label
/// centered. Pressing pushes the key down onto its ledge, which stays put, so nothing around it
/// moves, and letting go lets it back up, each in 0.06 s, easing out. Not green: green is for
/// data and the + that floats above it. A screen places it in a bar at its bottom with
/// `primaryKeyBar` (`PrimaryKeyBar.swift`).
///
/// A capsule, its ends fully round, on a ledge of the same shape. A label that wraps, at the
/// largest text sizes, makes the key taller with the same round corners and straight sides
/// between them: as a capsule it went oval, and the label's first and last lines stood out past
/// its edge. At the accessibility sizes the label's side padding is smaller, so a short label, as
/// an exercise's name on the way back, stays on one line and the key a capsule; with none, a
/// label that just fit ran into the round ends.
public struct PrimaryKeyButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: Self.textStyle) private var minHeight = Self.faceHeight
    /// Above and below the label, inside the minimum height for one line, so a wrapped label's
    /// first and last lines stay clear of the round corners.
    @ScaledMetric(relativeTo: Self.textStyle) private var labelInset: CGFloat = 12
    /// The face's height for one line of label, at the default text size: with its ledge, as tall
    /// as a tab bar floats, measured on the Files app's on iOS 27.2.
    fileprivate static let faceHeight: CGFloat = 58
    /// What `faceHeight` scales with: the label's text style.
    fileprivate static let textStyle = Font.TextStyle.title3
    /// The face's fill, its ledge's, and its label's color: the light primary key's, or a
    /// secondary key's on the same shape (`secondaryKey`).
    fileprivate var fill: ColorToken = .primaryKey
    fileprivate var ledgeFill: ColorToken = .borderStrong
    fileprivate var labelColor: ColorToken = .onPrimaryKey
    /// How far the key goes down onto its ledge when pressed, and how far the ledge shows below it.
    static let ledge: CGFloat = 4
    /// In `primaryKeyBar`, how far the key's ledge sits above the screen's bottom, and the key
    /// from its sides: where a tab bar floats, measured on the Files app's on iOS 27.2. Not
    /// concentric with the screen's corners, as a tab bar isn't either.
    static let lowInset: CGFloat = 21
    /// In `primaryKeyBar`, between the key's top and the floating button's bottom.
    static let floatingGap = Spacing.md
    /// In `primaryKeyBar`, the room above the key's face, inside the bar.
    static let barTop = Spacing.sm
    /// The press and the release: a quick ease-out both ways, so the key reads as struck.
    private static let press = Animation.easeOut(duration: 0.06)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init() { }

    /// How far the face has filled with the done purple, from its leading edge; nil for none.
    fileprivate var filling: KeyFill?

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: minHeight / 2)
        face(configuration.label, color: labelColor)
            // Over the fill, the label in the light key's dark, switching where the fill's edge
            // crosses it.
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
            .offset(y: configuration.isPressed ? Self.ledge : 0)
            .animation(Self.press, value: configuration.isPressed)
            .background(shape.fill(.pp(ledgeFill)).offset(y: Self.ledge))
            .padding(.bottom, Self.ledge)
    }

    /// The label on the key's face, in `color`, padded to the face's size.
    private func face(_ label: Configuration.Label, color: ColorToken) -> some View {
        label
            .font(.ppPrimaryKey)
            .foregroundStyle(.pp(color))
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Spacing.md : Spacing.lg)
            .padding(.vertical, labelInset)
            .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

extension ButtonStyle where Self == PrimaryKeyButtonStyle {
    /// `.buttonStyle(.primaryKey)`.
    public static var primaryKey: PrimaryKeyButtonStyle {
        PrimaryKeyButtonStyle()
    }

    /// A key in the primary key's place and shape, quieter: a dark raised fill on a ledge of the
    /// well's color, its label in the text's own color, as +15 s beside a count (`CountKeys`).
    public static var secondaryKey: PrimaryKeyButtonStyle {
        var style = PrimaryKeyButtonStyle()
        style.fill = .surfaceRaised
        style.ledgeFill = .well
        style.labelColor = .textPrimary
        return style
    }

    /// A timed set's log key: the secondary key's gray face, filling with the done purple from
    /// its leading edge as `filling` runs, its label light over the gray and dark over the
    /// purple, switching where the fill's edge crosses it.
    public static func countKey(filling: KeyFill) -> PrimaryKeyButtonStyle {
        var style = PrimaryKeyButtonStyle.secondaryKey
        style.filling = filling
        return style
    }
}

#Preview {
    Button("Start", systemImage: "play.fill") { }
        .buttonStyle(.primaryKey)
        .padding()
        .background(Color.pp(.background))
}
