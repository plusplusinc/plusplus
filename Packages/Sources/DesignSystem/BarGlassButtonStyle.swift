#if os(iOS)
import SwiftUI

/// A button in the bar's own look, drawn outside the bar's own items: its label centered in its
/// own interactive glass, as tall as the search button and `width` wide, a circle when the two
/// match, all of it taking the tap. The label keeps its own colors: the bar's style tints nothing.
/// Under `BarSearchField`'s field, its glass is plain, which blends with the field's where
/// interactive glass showed as a second layer, and its label can fade (`barGlassInteractive`,
/// `barGlassLabelShown`).
public struct BarGlassButtonStyle: ButtonStyle {
    let width: CGFloat

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.barGlassInteractive) private var isInteractive
    @Environment(\.barGlassLabelShown) private var isLabelShown

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isLabelShown ? 1 : 0)
            // Gone before the field's own label runs over it, and back once the field's end has
            // uncovered the button.
            .animation(
                isLabelShown ? .easeOut(duration: 0.15).delay(0.12) : .easeOut(duration: 0.05),
                value: isLabelShown,
            )
            .frame(width: max(width, height), height: height)
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(isInteractive), in: .capsule)
    }
}

extension ButtonStyle where Self == BarGlassButtonStyle {
    /// `.buttonStyle(.barGlass(width: 0))`: a circle as tall as the search button.
    public static func barGlass(width: CGFloat) -> Self {
        BarGlassButtonStyle(width: width)
    }
}

extension EnvironmentValues {
    /// Whether a `BarGlassButtonStyle` button's glass answers a touch.
    @Entry var barGlassInteractive = true
    /// Whether a `BarGlassButtonStyle` button's label shows; its glass stays.
    @Entry var barGlassLabelShown = true
}
#endif
