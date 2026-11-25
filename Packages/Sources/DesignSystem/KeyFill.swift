import SwiftUI

/// How far a key's face has filled (`PrimaryKeyButtonStyle.countKey(filling:)`): running from
/// empty to full over `length` seconds, full at `ends`, or held where it stands with
/// `pausedLeft` seconds left; or full once its count is over (`isOver`): a timed set logged,
/// early or run out, or a rest ended, skipped or run out.
public struct KeyFill: Equatable, Sendable {
    public let length: Double
    public let ends: Date
    public let pausedLeft: Double?
    /// The count is over: the fill is full. Ended early, it runs on to full from where it was,
    /// quickly, easing out, rather than jumping or running back to the seconds done.
    public let isOver: Bool

    public init(
        length: Double,
        ends: Date,
        pausedLeft: Double? = nil,
        isOver: Bool = false,
    ) {
        self.length = length
        self.ends = ends
        self.pausedLeft = pausedLeft
        self.isOver = isOver
    }

    /// A count's fill once it is over (a set logged, a rest ended), early or run out: full, held
    /// for its beat.
    public static let over = Self(length: 1, ends: .distantPast, isOver: true)

    /// The share filled at `date`, from 0 to 1.
    public func share(at date: Date) -> Double {
        guard length > 0, !isOver else { return 1 }
        return 1 - left(at: date) / length
    }

    /// "12 of 30 seconds done" at `date`, as VoiceOver hears a timed set's fill: the seconds done
    /// as the count shows them, its time left rounded up. Nil once over.
    public func spokenDone(at date: Date) -> String? {
        guard !isOver, length > 0 else { return nil }
        let total = Int(length.rounded())
        let done = max(0, total - Int(left(at: date).rounded(.up)))
        return String(localized: "\(done) of \(total) seconds done")
    }

    /// "35 seconds left" at `date`, as VoiceOver hears a rest's fill, the time spoken as the
    /// rest's count is (`RestBlock.spoken`). Nil once over.
    public func spokenLeft(at date: Date, locale: Locale) -> String? {
        guard !isOver, length > 0 else { return nil }
        let left = RestBlock.spoken(left(at: date), locale: locale)
        return String(localized: "\(left) left")
    }

    private func left(at date: Date) -> Double {
        min(length, max(0, pausedLeft ?? ends.timeIntervalSince(date)))
    }

    /// Whether the fill stands still: paused, or over.
    var holds: Bool {
        pausedLeft != nil || isOver
    }

    /// The run on to full as a count ends early: as quick as half a key's swap, easing out.
    static let runOn = Animation.easeOut(duration: PrimaryKeyButtonStyle.swapHalf)
}

/// A key face's fill from its leading edge, redrawn each frame while it runs, in `color`: the
/// done purple, held in it while paused, as the key swaps to Continue. As a mask, the part of
/// the label over it.
struct FillingFace: View {
    let filling: KeyFill
    var color: ColorToken?

    var body: some View {
        // At most 60 a second: on ProMotion, 120 moved a long rest's fill under a point a frame.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: filling.holds)) { context in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.pp(color ?? .done))
                    .frame(width: geometry.size.width * filling.share(at: context.date))
                    .animation(KeyFill.runOn, value: filling.isOver)
            }
        }
    }
}
