#if os(iOS)
import SwiftUI

/// A button in the bar's own look, drawn outside the bar's own items: its label centered in its
/// own interactive glass, as tall as the search button and `width` wide, a circle when the two
/// match, all of it taking the tap. The label keeps its own colors: the bar's style tints nothing.
/// Under `BarSearchField`'s field, its glass is plain, which blends with the field's where
/// interactive glass showed as a second layer, and its label fades with the field's motion
/// (`barGlassInteractive`, `barGlassLabelOpacity`), and its glass gives way to the field's from
/// its trailing edge, keeping its own room (`barGlassWidth`).
public struct BarGlassButtonStyle: ButtonStyle {
    let width: CGFloat

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.barGlassInteractive) private var isInteractive
    @Environment(\.barGlassLabelOpacity) private var labelOpacity
    @Environment(\.barGlassWidth) private var glassWidth

    public func makeBody(configuration: Configuration) -> some View {
        let fullWidth = max(width, height)
        let shown = min(glassWidth ?? fullWidth, fullWidth)
        configuration.label
            .opacity(labelOpacity)
            .frame(width: fullWidth, height: height)
            // Narrower than it is tall, a round drop rather than a sliver of capsule.
            .frame(width: shown, height: min(shown, height), alignment: .leading)
            .clipped()
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(isInteractive), in: .capsule)
            .frame(width: fullWidth, height: height, alignment: .leading)
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
    /// How much a `BarGlassButtonStyle` button's label shows; its glass stays.
    @Entry var barGlassLabelOpacity: CGFloat = 1
    /// How much of a `BarGlassButtonStyle` button's glass shows, from its leading edge; nil for
    /// all of it. The button keeps its room either way.
    @Entry var barGlassWidth: CGFloat?
}
#endif
