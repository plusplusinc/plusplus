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
}
