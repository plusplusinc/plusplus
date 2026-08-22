import DesignSystem
import SwiftUI

@main
struct PlusPlusApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
    }
}

/// Stands in until the first feature lands.
///
/// The app deliberately creates no `ModelContainer` yet. Storage wiring lives in
/// `WorkoutStoreContainer` and takes a schema, so it gets connected when there is a data model
/// worth connecting — not before.
private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text("PlusPlus")
                .font(.ppScreenTitle)
                .foregroundStyle(Color.ppTextPrimary)
            Text("No features yet.")
                .font(.ppBody)
                .foregroundStyle(Color.ppTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ppBackground)
    }
}

#Preview {
    PlaceholderView()
}
