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

/// One short bar per set, side by side: the sets done filled `done` purple, the rest `toDo`
/// gray. On the current exercise, `isCurrent`, the bar of the set it is on is green, pulsing with
/// its node. Sized with the detail line's text.
public struct SetBars: View {
    private let progress: SetProgress
    private let isCurrent: Bool

    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 9
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 5
    @ScaledMetric(relativeTo: .subheadline) private var gap: CGFloat = 3
    @ScaledMetric(relativeTo: .subheadline) private var corner: CGFloat = 1.5
    @ObserveHotReload private var hotReload

    public init(_ progress: SetProgress, isCurrent: Bool = false) {
        self.progress = progress
        self.isCurrent = isCurrent
    }

    public var body: some View {
        HStack(spacing: gap) {
            ForEach(0 ..< max(progress.total, 0), id: \.self) { index in
                bar(index)
            }
        }
        .accessibilityHidden(true)
        .hotReloadable()
    }

    /// One view per bar whatever it shows, so a bar turning green or purple changes its fill in
    /// place: as two views, one went out and the other came in, sliding apart.
    private func bar(_ index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        let isOn = isCurrent && index == progress.done
        return shape
            .fill(.pp(isOn ? .accent : index < progress.done ? .done : .toDo))
            .overlay {
                if isOn {
                    Color.clear.currentPulse(in: shape)
                }
            }
            .frame(width: width, height: height)
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        SetBars(SetProgress(done: 2, total: 3, spoken: ""))
        SetBars(SetProgress(done: 1, total: 4, spoken: ""), isCurrent: true)
        SetBars(SetProgress(done: 5, total: 8, spoken: ""))
    }
    .padding()
    .background(Color.pp(.background))
}
