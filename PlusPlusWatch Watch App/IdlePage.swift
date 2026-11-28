#if canImport(Session)
import DesignSystem
import SwiftUI

/// The Watch app with no workout running: the "++", "No workout running", and where to start
/// one. Start on the phone brings the app up by itself on the workout's set page.
struct IdlePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "++")
                .ppWatchFont(.mark)
                .foregroundStyle(Color.pp(.accent))
                .accessibilityHidden(true)
            Text("No workout running")
                .ppWatchFont(.title)
                .foregroundStyle(Color.pp(.textPrimary))
            Text("Start one on your iPhone and it opens here.")
                .ppWatchFont(.body)
                .foregroundStyle(Color.pp(.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, WatchPage.sideInset)
    }
}

#Preview {
    IdlePage()
        .preferredColorScheme(.dark)
}
#endif
