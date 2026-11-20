import SwiftUI

/// How far a key's face has filled (`PrimaryKeyButtonStyle.countKey(filling:)`): running from
/// empty to full over `length` seconds, full at `ends`, or held where it stands with
/// `pausedLeft` seconds left; or full once its set is logged (`isLogged`), early or run out.
public struct KeyFill: Equatable, Sendable {
    public let length: Double
    public let ends: Date
    public let pausedLeft: Double?
    /// Held by a pause: the fill takes the gray the paused count does, and its purple back on
    /// resume. A fill held by its log stays purple.
    public let isPaused: Bool
    /// The set is logged: the fill is full. Logged early, it runs on to full from where it was,
    /// quickly, easing out, rather than jumping or running back to the seconds done.
    public let isLogged: Bool

    public init(
        length: Double,
        ends: Date,
        pausedLeft: Double? = nil,
        isPaused: Bool = false,
        isLogged: Bool = false,
    ) {
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.isPaused = isPaused
        self.isLogged = isLogged
    }

    /// The share filled at `date`, from 0 to 1.
    public func share(at date: Date) -> Double {
        guard length > 0, !isLogged else { return 1 }
        let left = pausedLeft ?? ends.timeIntervalSince(date)
        return min(1, max(0, 1 - left / length))
    }

    /// "12 of 30 seconds done" at `date`, as VoiceOver hears the key's fill: the seconds done as
    /// the count shows them, its time left rounded up. Nil once logged.
    public func spokenDone(at date: Date) -> String? {
        guard !isLogged, length > 0 else { return nil }
        let total = Int(length.rounded())
        let left = Int(min(length, max(0, pausedLeft ?? ends.timeIntervalSince(date))).rounded(.up))
        return String(localized: "\(max(0, total - left)) of \(total) seconds done")
    }

    /// Whether the fill stands still: paused, or logged.
    var holds: Bool {
        pausedLeft != nil || isLogged
    }

    /// The run on to full as a set is logged early: as quick as half a key's swap, easing out.
    static let runOn = Animation.easeOut(duration: PrimaryKeyButtonStyle.swapHalf)
}

/// A key face's fill from its leading edge, redrawn each frame while it runs, in `color`: the
/// done purple, gray while paused. As a mask, the part of the label over it.
struct FillingFace: View {
    let filling: KeyFill
    var color: ColorToken?

    var body: some View {
        TimelineView(.animation(paused: filling.holds)) { context in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.pp(color ?? (filling.isPaused ? .textSecondary : .done)))
                    .frame(width: geometry.size.width * filling.share(at: context.date))
                    .animation(KeyFill.runOn, value: filling.isLogged)
            }
        }
    }
}
