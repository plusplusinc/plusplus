import SwiftUI
import SwiftData
import PlusPlusKit

/// Fire a debounced, dirty-gated GitHub sync when an editing surface closes, so
/// a batch of program edits reaches the repo at the natural boundary (leaving
/// the catalog, an exercise editor, a routine) instead of waiting for the next
/// app foreground. It's a no-op unless GitHub is connected and something
/// actually changed, so attaching it broadly is cheap — see
/// `GitHubSyncCoordinator.requestSync`.
private struct SyncsProgramOnClose: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw = WeightUnit.lb.rawValue

    func body(content: Content) -> some View {
        content.onDisappear {
            let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
            GitHubSyncCoordinator.shared.requestSync(context: modelContext, units: units)
        }
    }
}

extension View {
    /// Commit this surface's program changes to GitHub when it closes.
    func syncsProgramOnClose() -> some View { modifier(SyncsProgramOnClose()) }
}
