import SwiftUI

/// The label of a workout's time key: pause and the time in white while it runs; while paused,
/// play stays white, since it is what a tap does, and only the stopped time turns gray. The
/// key's button says what a tap does, Pause or Resume, and the time in words.
///
/// The icon is drawn in the time's font, on its baseline, so it scales and sits with the
/// digits, and it keeps the width of the wider of its two symbols, so the key holds its width
/// as it swaps. The time is SF Mono, so its digits hold still as they tick.
public struct WorkoutTimeLabel: View {
    private let text: String
    private let seconds: Double
    private let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `seconds`, the time as a number: by it the changing digits roll up as a second goes, as
    /// a countdown's roll down (`RestBlock.countdown`), on the same curve.
    public init(_ text: String, seconds: Double = 0, isPaused: Bool) {
        self.text = text
        self.seconds = seconds
        self.isPaused = isPaused
    }

    public var body: some View {
        // Not a `Label`: in a bar, a label shows its icon alone.
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            ZStack {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Image(systemName: symbol).hidden()
                }
                Image(systemName: isPaused ? Self.play : Self.pause)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.pp(.textPrimary))
            .imageScale(.small)
            .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.pp(isPaused ? .textSecondary : .textPrimary))
                .contentTransition(reduceMotion ? .identity : .numericText(value: seconds))
                .animation(reduceMotion ? nil : SetMotion.restRoll, value: text)
        }
        .font(.ppWorkoutTime)
        .padding(.horizontal, Spacing.xs)
        .fixedSize()
        // The icon's replace and the time's color change play on a pause or a resume.
        .animation(.snappy(duration: 0.2), value: isPaused)
    }

    private static let pause = "pause.fill"
    private static let play = "play.fill"
    private static let symbols = [pause, play]
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
