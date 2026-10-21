import SwiftUI

/// The label of a workout's time key: pause and the time in green while it runs; play and the
/// time in gray while paused. The key's button says what a tap does, Pause or Resume, and the
/// time in words.
public struct WorkoutTimeLabel: View {
    private let text: String
    private let isPaused: Bool

    @ObserveHotReload private var hotReload

    public init(_ text: String, isPaused: Bool) {
        self.text = text
        self.isPaused = isPaused
    }

    public var body: some View {
        // Not a `Label`: in a bar, a label shows its icon alone.
        HStack(spacing: Spacing.xs) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .accessibilityHidden(true)
            Text(text)
                .font(.ppWorkoutTime)
        }
        .foregroundStyle(.pp(isPaused ? .textSecondary : .accent))
        .fixedSize()
        .hotReloadable()
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        WorkoutTimeLabel("04:12", isPaused: false)
        WorkoutTimeLabel("04:12", isPaused: true)
        WorkoutTimeLabel("1:04:12", isPaused: false)
    }
    .padding()
    .background(Color.pp(.background))
}
