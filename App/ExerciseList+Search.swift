import DesignSystem
import SwiftUI

/// Search as `BarSearchField`, one bar item holding the host's leading button and the round
/// search button, spanning the bar between its margins. A bar item hugs its content, so the item
/// gets its width from the screen's. The bar's own inline title is removed and `BarSearchField`
/// draws the title, centered on the screen, for its field to cover; the screen keeps it as its
/// navigation title.
struct SearchField<Leading: View>: ViewModifier {
    @Binding var text: String
    let title: LocalizedStringKey
    let leading: Leading
    let onOpen: () -> Void

    /// The screen's width, which the item spans but for the bar's margins.
    @State private var width: CGFloat = 0
    /// The screen's middle in global coordinates, where a drawn title centers.
    @State private var midX: CGFloat = 0
    /// Held here, not in the item: the bar reads its item's elements again only as the host's
    /// state changes (`BarSearchField`).
    @State private var isOpen = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
                midX = $0
            }
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BarSearchField(
                        text: $text,
                        // `BarSearchField` turns it inside the open's animation, so `onOpen`
                        // runs in that transaction, not after it, as an `onChange` would.
                        isOpen: Binding {
                            isOpen
                        } set: { open in
                            isOpen = open
                            if open {
                                onOpen()
                            }
                        },
                        prompt: "Search",
                        width: width - 2 * Spacing.md,
                        title: title,
                        titleCenterX: midX,
                    ) { leading }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            // As the system's search does: a drag down the list drops the keyboard.
            .scrollDismissesKeyboard(.immediately)
    }
}

