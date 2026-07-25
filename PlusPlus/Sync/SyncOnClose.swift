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

/// The same commit, triggered by a surface becoming HIDDEN rather than
/// unmounting. The catalog roots don't disappear when you leave them (they're
/// a ZStack hidden by opacity, so their navigation paths survive), so
/// `onDisappear` would never fire for them.
private struct SyncsProgramOnHide: ViewModifier {
    let isVisible: Bool
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw = WeightUnit.lb.rawValue

    func body(content: Content) -> some View {
        content.onChange(of: isVisible) { wasVisible, nowVisible in
            guard wasVisible, !nowVisible else { return }
            let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
            GitHubSyncCoordinator.shared.requestSync(context: modelContext, units: units)
        }
    }
}

extension View {
    /// Commit this surface's program changes to GitHub when it closes. For a
    /// surface that unmounts (pushed screens, sheets).
    func syncsProgramOnClose() -> some View { modifier(SyncsProgramOnClose()) }

    /// Commit when this surface stops being the visible one. For the roots,
    /// which stay mounted and merely hide.
    func syncsProgramOnHide(visible: Bool) -> some View {
        modifier(SyncsProgramOnHide(isVisible: visible))
    }
}
