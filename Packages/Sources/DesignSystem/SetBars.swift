import SwiftUI

/// How far an exercise is through its sets: done of total, the bars it shows, and the same in
/// words for VoiceOver, "2 of 3 sets done". For an exercise done one side at a time,
/// `sidesDone` is how many sides of the set after those done are in, 0 or 1; nil for any other.
public struct SetProgress: Equatable {
    public var done: Int
    public var total: Int
    public var sidesDone: Int?
    public var spoken: String

    public init(done: Int, total: Int, sidesDone: Int? = nil, spoken: String) {
        self.done = done
        self.total = total
        self.sidesDone = sidesDone
        self.spoken = spoken
    }

    /// Whether the side at `side`, 0 the left and 1 the right, of the set at `index` is done.
    func isDone(set index: Int, side: Int) -> Bool {
        index < done || index == done && side < sidesDone ?? 0
    }
}

/// One short bar per set, side by side, at a row's detail line: the sets done filled `done`
/// purple, the rest `toDo` gray. A set done one side at a time is a pair of half bars, left
/// then right, a hair apart in the room of one bar, each purple once its side is done. Sized
/// with the detail line's text.
public struct SetBars: View {
    private let progress: SetProgress

    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 9
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 5
    @ScaledMetric(relativeTo: .subheadline) private var gap: CGFloat = 3
    @ScaledMetric(relativeTo: .subheadline) private var pairGap: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var corner: CGFloat = 1.5

    public init(_ progress: SetProgress) {
        self.progress = progress
    }

    public var body: some View {
        HStack(spacing: gap) {
            ForEach(0 ..< max(progress.total, 0), id: \.self) { index in
                if progress.sidesDone == nil {
                    bar(isDone: index < progress.done, width: width)
                } else {
                    HStack(spacing: pairGap) {
                        ForEach(0 ..< 2, id: \.self) { side in
                            bar(
                                isDone: progress.isDone(set: index, side: side),
                                width: (width - pairGap) / 2,
                            )
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(isDone: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(.pp(isDone ? .done : .toDo))
            .frame(width: width, height: height)
    }
}

/// The current exercise's sets as a bar of segments across its text column, one per set, of
/// equal widths, `gap` apart: the sets done `done` purple, the set it is on green, as its node
/// is, while `isOnSet`, and the sets to come the quiet track gray a rest's bar runs on
/// (`borderStrong`). Resting between sets, no segment is green: the set just done has turned
/// purple and the next is still to come. One view per segment, so a segment changing color
/// changes its fill in place, on the change's animation. With many sets the segments narrow,
/// the gaps kept.
///
/// A set done one side at a time is a pair of segments, left then right, a hair apart, with
/// the pairs further apart than plain sets are: the side it is on green, a side done purple.
struct SetSegments: View {
    let progress: SetProgress
    let isOnSet: Bool

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 4

    /// Between the two sides of a set, and between two sets done a side at a time.
    private static let pairGap: CGFloat = 1.5
    private static let pairsGap: CGFloat = 6

    var body: some View {
        let isPerSide = progress.sidesDone != nil
        HStack(spacing: isPerSide ? Self.pairsGap : Spacing.xs) {
            ForEach(0 ..< max(progress.total, 0), id: \.self) { index in
                if isPerSide {
                    HStack(spacing: Self.pairGap) {
                        ForEach(0 ..< 2, id: \.self) { side in
                            segment(color(index, side: side))
                        }
                    }
                } else {
                    segment(color(index, side: 0))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func segment(_ color: ColorToken) -> some View {
        Capsule()
            .fill(.pp(color))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private func color(_ index: Int, side: Int) -> ColorToken {
        if progress.isDone(set: index, side: side) {
            return .done
        }
        let isCurrent = index == progress.done && side == progress.sidesDone ?? 0
        return isOnSet && isCurrent ? .accent : .borderStrong
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        SetBars(SetProgress(done: 2, total: 3, spoken: ""))
        SetBars(SetProgress(done: 5, total: 8, spoken: ""))
        SetBars(SetProgress(done: 4, total: 6, sidesDone: 1, spoken: ""))
        SetSegments(progress: SetProgress(done: 1, total: 3, spoken: ""), isOnSet: true)
        SetSegments(progress: SetProgress(done: 1, total: 3, spoken: ""), isOnSet: false)
        SetSegments(progress: SetProgress(done: 4, total: 12, spoken: ""), isOnSet: true)
        SetSegments(
            progress: SetProgress(done: 0, total: 3, sidesDone: 1, spoken: ""),
            isOnSet: true,
        )
        SetSegments(
            progress: SetProgress(done: 1, total: 3, sidesDone: 0, spoken: ""),
            isOnSet: false,
        )
    }
    .padding()
    .background(Color.pp(.background))
}
