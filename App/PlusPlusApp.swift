import DesignSystem
import Features
import SwiftUI

@main
struct PlusPlusApp: App {
    /// Not persisted yet: the welcome plays on every launch. Making it once-per-install needs
    /// somewhere to keep the flag and something to show instead, and neither exists yet.
    @State private var hasFinishedWelcome = false

    var body: some Scene {
        WindowGroup {
            if hasFinishedWelcome {
                PlaceholderView()
            } else {
                WelcomeView { hasFinishedWelcome = true }
            }
        }
    }
}

/// Stands in for whatever the app opens onto once there is something to open onto.
///
/// The app deliberately creates no `ModelContainer` yet. Storage wiring lives in
/// `WorkoutStoreContainer` and takes a schema, so it gets connected when there is a data model
/// worth connecting.
private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text("PlusPlus")
                .font(.ppTitle)
                .foregroundStyle(Color.ppTextPrimary)
            Text("No features yet.")
                .font(.ppSubheadline)
                .foregroundStyle(Color.ppTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ppBackground)
    }
}

#Preview {
    PlaceholderView()
}
