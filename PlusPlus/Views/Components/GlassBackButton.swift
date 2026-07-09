import SwiftUI

/// The pushed-screen chrome (#198): a bare chevron in the leading
/// toolbar slot — iOS 26 renders toolbar buttons as Liquid Glass
/// circles natively — plus the full-width swipe-back surface. Replaces
/// the v4 flat-header chevron row; titles ride the toolbar inline (#234).
struct GlassBackButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(.body, weight: .semibold))
            }
            .accessibilityIdentifier("backButton")
        }
    }
}

extension View {
    /// One call per pushed screen: system bar shown, system back label
    /// hidden, glass chevron in its place, whole-surface swipe-back.
    func pushedScreenChrome(onBack: @escaping () -> Void) -> some View {
        navigationBarBackButtonHidden(true)
            .toolbar { GlassBackButton(action: onBack) }
            .fullWidthSwipeBack()
    }
}
