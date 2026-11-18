import SwiftUI

extension View {
    /// Shown to VoiceOver and the UI tests only while `isShown`. A bar item ignores
    /// `accessibilityHidden`: the bar's title, and Add exercise's + under `hiddenBehindDrawer()`,
    /// were read out while faded away.
    public func accessibilityShown(_ isShown: Bool) -> some View {
        accessibilityRepresentation {
            if isShown {
                self
            }
        }
    }
}
