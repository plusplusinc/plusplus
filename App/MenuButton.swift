import DesignSystem
import Session
import SwiftUI

/// ++, leading in a screen's bar: opens the drawer, and takes VoiceOver's focus back as it closes.
///
/// It is the bar's own item, or, with `drawsGlass`, drawn inside another item (the search's in
/// Exercises, `BarSearchField`) in its own glass, as the bar draws it, pixel for pixel.
struct MenuButton: View {
    let session: RoutineSession
    /// Whether it draws its own glass, for an item that holds it alongside other controls.
    var drawsGlass = false

    @AccessibilityFocusState private var isFocused: Bool
    @Environment(\.displayScale) private var displayScale

    private static let markWidth: CGFloat = 20
    /// The glass's width as the bar draws it: the mark and the bar's padding on either side.
    private static let glassWidth: CGFloat = markWidth + 2 * Spacing.md
    /// A plus sits on the font's math axis, about a point below the middle of its line, so the
    /// mark is lifted to look centered in the round button.
    private static let markLift: CGFloat = 1

    var body: some View {
        if drawsGlass {
            button.buttonStyle(.barGlass(width: Self.glassWidth))
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            session.openDrawer()
        } label: {
            Text(verbatim: "++")
                .font(.ppMark)
                .foregroundStyle(.pp(.accent))
                // The bar sets its pluses a pixel further apart than a plain `Text` does; drawn
                // without the pixel, the second plus sat a pixel left of the bar's. The pixel
                // trails the second plus too, and the half-pixel offset recenters the mark.
                .kerning(drawsGlass ? 1 / displayScale : 0)
                // The glass sizes itself to its label. Reserving less width than the mark's
                // advance draws the mark large in a compact button.
                .fixedSize()
                .frame(width: Self.markWidth)
                .offset(x: drawsGlass ? 1 / (2 * displayScale) : 0, y: -Self.markLift)
        }
        .accessibilityLabel("Menu")
        .hiddenBehindDrawer()
        .accessibilityFocused($isFocused)
        .onChange(of: session.isDrawerOpen) { _, isOpen in
            if !isOpen {
                isFocused = true
            }
        }
    }
}
