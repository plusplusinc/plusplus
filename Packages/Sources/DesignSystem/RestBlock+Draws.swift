import SwiftUI

extension RestBlock {
    #if DEBUG
    /// How many times any countdown's timeline has drawn, for the test that a shut rest draws
    /// none (`RestTimelineTests`).
    static var countdownDraws = 0
    #endif

    /// `seconds`, as a countdown draws them, counted in a debug build.
    static func drawing(_ seconds: Double) -> Double {
        #if DEBUG
        countdownDraws += 1
        #endif
        return seconds
    }

    /// A shut rest's figure, "0:00", drawn once in the countdown's font, with no timeline: what a
    /// shut countdown showed, its length 0, so the room lays out as it did.
    static func shutFigure(size: CGFloat, locale: Locale) -> some View {
        Text(text(0, locale: locale))
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityHidden(true)
    }
}
