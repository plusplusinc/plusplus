#if !canImport(Session)
import SwiftUI

/// The Watch app while the target does not yet link the package's products (`WorkoutStore`,
/// `DesignSystem`): the idle page in stock type, so the phone's build carries a Watch app that
/// opens. Linking them in Xcode compiles the real app (`PlusPlusWatchApp`) in its place and
/// leaves this file empty; delete it then.
@main
struct UnlinkedWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "++")
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .foregroundStyle(.green)
                Text("No workout running")
                    .font(.headline)
                Text("Start one on your iPhone and it opens here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
