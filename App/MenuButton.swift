import DesignSystem
import SwiftUI

/// ++, leading in a screen's bar: opens the drawer, and takes VoiceOver's focus back as it closes.
struct MenuButton: View {
    let session: RoutineSession

    @AccessibilityFocusState private var isFocused: Bool
    @ObserveHotReload private var hotReload

    private static let markWidth: CGFloat = 20
    /// A plus sits on the font's math axis, about a point below the middle of its line, so the
    /// mark is lifted to look centered in the round button.
    private static let markLift: CGFloat = 1

    var body: some View {
        Button {
            session.isDrawerOpen = true
        } label: {
            Text(verbatim: "++")
                .font(.ppMark)
                .foregroundStyle(.pp(.accent))
                // The glass sizes itself to its label. Reserving less width than the mark's
                // advance draws the mark large in a compact button.
                .fixedSize()
                .frame(width: Self.markWidth)
                .offset(y: -Self.markLift)
        }
        .accessibilityLabel("Menu")
        .accessibilityFocused($isFocused)
        .onChange(of: session.isDrawerOpen) { _, isOpen in
            if !isOpen {
                isFocused = true
            }
        }
        .hotReloadable()
    }
}
