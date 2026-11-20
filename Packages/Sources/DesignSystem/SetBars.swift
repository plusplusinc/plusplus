import SwiftUI

/// How far an exercise is through its sets: done of total, the bars it shows, and the same in
/// words for VoiceOver, "2 of 3 sets done".
public struct SetProgress: Equatable {
    public var done: Int
    public var total: Int
    public var spoken: String

    public init(done: Int, total: Int, spoken: String) {
        self.done = done
        self.total = total
        self.spoken = spoken
    }
}

/// One short bar per set, side by side, at a row's detail line: the sets done filled `done`
/// purple, the rest `toDo` gray. Sized with the detail line's text.
public struct SetBars: View {
    private let progress: SetProgress

    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 9
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 5
    @ScaledMetric(relativeTo: .subheadline) private var gap: CGFloat = 3
    @ScaledMetric(relativeTo: .subheadline) private var corner: CGFloat = 1.5

    public init(_ progress: SetProgress) {
        self.progress = progress
    }

    public var body: some View {
        HStack(spacing: gap) {
            ForEach(0 ..< max(progress.total, 0), id: \.self) { index in
                RoundedRectangle(cornerRadius: corner)
                    .fill(.pp(index < progress.done ? .done : .toDo))
                    .frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The current exercise's sets as a bar of segments across its text column, one per set, of
/// equal widths, `gap` apart: the sets done `done` purple, the set it is on green, as its node
/// is, while `isOnSet`, and the sets to come the quiet track gray a rest's bar runs on
/// (`borderStrong`). Resting between sets, no segment is green: the set just done has turned
/// purple and the next is still to come. One view per segment, so a segment changing color
/// changes its fill in place, on the change's animation. With many sets the segments narrow,
/// the gaps kept.
struct SetSegments: View {
    let progress: SetProgress
    let isOnSet: Bool

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 4

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0 ..< max(progress.total, 0), id: \.self) { index in
                Capsule()
                    .fill(.pp(color(index)))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ index: Int) -> ColorToken {
        if index < progress.done {
            return .done
        }
        return isOnSet && index == progress.done ? .accent : .borderStrong
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        SetBars(SetProgress(done: 2, total: 3, spoken: ""))
        SetBars(SetProgress(done: 5, total: 8, spoken: ""))
        SetSegments(progress: SetProgress(done: 1, total: 3, spoken: ""), isOnSet: true)
        SetSegments(progress: SetProgress(done: 1, total: 3, spoken: ""), isOnSet: false)
        SetSegments(progress: SetProgress(done: 4, total: 12, spoken: ""), isOnSet: true)
    }
    .padding()
    .background(Color.pp(.background))
}
