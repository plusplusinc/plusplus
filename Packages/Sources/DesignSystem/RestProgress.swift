import SwiftUI

/// The rest's progress: a thin bar with round ends, as wide as the text column, whose fill, in the
/// countdown's own color over a quiet gray track, runs left to right at one rate for the rest's
/// length, full at 0:00. Drawn, not a `ProgressView`: the linear style takes neither a track color
/// nor a height, and its fill jumps when its value changes. `length` is animatable, so + and −,
/// which change it on the glide's animation (`SetMotion.restGlide`), glide the fill back or on
/// rather than jumping it; `starts` stays put through them. Not the end: as a rest opened, the
/// line's end, the distant past, ran to the rest's on the open's curve, and the bar drew full
/// until it got there. Paused, it holds at `pausedLeft`. Hidden from VoiceOver: the countdown
/// says the time left.
struct RestProgress: View, Animatable {
    let starts: Double
    var length: Double
    let pausedLeft: Double?

    @ScaledMetric(relativeTo: .body) private var height = Self.height

    /// The bar's height, a little thicker than the rail's line.
    static let height: CGFloat = 4

    var animatableData: Double {
        get { length }
        set { length = newValue }
    }

    var body: some View {
        // Frame by frame, so the fill runs on steadily rather than stepping each second.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: pausedLeft != nil)) { context in
            let share = share(at: context.date.timeIntervalSinceReferenceDate)
            Capsule()
                .fill(.pp(.borderStrong))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.pp(.textPrimary))
                            .frame(width: max(proxy.size.width * share, share > 0 ? height : 0))
                    }
                }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The share of the rest gone at `now`, from 0 to 1.
    private func share(at now: Double) -> CGFloat {
        guard length > 0 else { return 1 }
        let left = pausedLeft ?? (starts + length - now)
        return CGFloat(min(max(1 - left / length, 0), 1))
    }
}
