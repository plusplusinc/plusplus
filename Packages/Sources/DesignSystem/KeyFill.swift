import SwiftUI

/// How far a key's face has filled (`PrimaryKeyButtonStyle.primaryKey(filling:)`): running from
/// empty to full over `length` seconds, full at `ends`, or held where it stands with
/// `pausedLeft` seconds left.
public struct KeyFill: Equatable, Sendable {
    public let length: Double
    public let ends: Date
    public let pausedLeft: Double?

    public init(length: Double, ends: Date, pausedLeft: Double? = nil) {
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
    }

    /// The share filled at `date`, from 0 to 1.
    public func share(at date: Date) -> Double {
        guard length > 0 else { return 1 }
        let left = pausedLeft ?? ends.timeIntervalSince(date)
        return min(1, max(0, 1 - left / length))
    }
}

/// A key face's fill in the done purple from its leading edge, redrawn each frame while it
/// runs.
struct FillingFace: View {
    let filling: KeyFill

    var body: some View {
        TimelineView(.animation(paused: filling.pausedLeft != nil)) { context in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.pp(.done))
                    .frame(width: geometry.size.width * filling.share(at: context.date))
            }
        }
    }
}
