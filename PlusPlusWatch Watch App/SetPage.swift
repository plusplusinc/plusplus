#if canImport(Session)
import DesignSystem
import SwiftUI
import WorkoutStore

/// What a key on the set page asks for. The page only reports it; the app turns it into an
/// action on the workout.
enum SetPageTap: Equatable {
    case log
    case skipRest
    case extendRest
    case logEarly
    case finish
    case resume
}

/// The Watch's center page: the exercise up, its set bars and caption, the big middle (its
/// numbers, or a count), and one key, or Skip and +15 through a rest (`WatchFace`).
struct SetPage: View {
    let face: WatchFace
    /// The phone is out of reach: a small mark before the caption.
    var isPhoneAway = false
    let tap: (SetPageTap) -> Void

    var body: some View {
        WatchScreen {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                    Text(face.name)
                        .ppWatchFont(.title)
                        .foregroundStyle(Color.pp(.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .clearOfClock()
                WatchBars(bars: face.bars)
                    .padding(.top, 7)
                HStack(spacing: 3) {
                    if isPhoneAway {
                        Image(systemName: "iphone.slash")
                            .accessibilityLabel("iPhone out of reach")
                    }
                    Text(face.caption)
                }
                .ppWatchFont(.caption)
                .foregroundStyle(Color.pp(.textSecondary))
                .padding(.top, 5)
            }
        } middle: {
            WatchMiddle(middle: face.middle, isQuiet: face.isQuiet)
        } keys: {
            WatchKeys(key: face.key, tap: tap)
        }
    }

    private var dotColor: Color {
        switch face.dot {
        case .active: .pp(.accent)
        case .done: .pp(.done)
        case .quiet: .pp(.toDo)
        }
    }
}

/// The exercise's set bars, full width: one a set, or a pair for a set done a side at a time.
struct WatchBars: View {
    let bars: [[WatchFace.Bar]]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(bars.indices, id: \.self) { set in
                HStack(spacing: 2) {
                    ForEach(bars[set].indices, id: \.self) { side in
                        Capsule()
                            .fill(color(of: bars[set][side]))
                            .frame(height: 3)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(of bar: WatchFace.Bar) -> Color {
        switch bar {
        case .done: .pp(.done)
        case .current: .pp(.accent)
        case .toDo: .pp(.toDo)
        }
    }
}

/// The big middle: the set's numbers over what they count, or a count with its label, at the
/// figure's full size where it fits and shrunk together to fit where it does not
/// (`ShrunkToFit`), a number never cut short.
struct WatchMiddle: View {
    let middle: WatchFace.Middle
    var isQuiet = false
    @Environment(\.isLuminanceReduced) private var isWristDown
    @Environment(\.forcesDim) private var forcesDim

    /// Between two figures side by side.
    private static let figureGap: CGFloat = 28
    /// Between the digits, cut to their own height (`ppWatchDigits`), and the words over or
    /// under them.
    private static let wordGap: CGFloat = 7

    private var isDimmed: Bool {
        isWristDown || forcesDim
    }

    var body: some View {
        ShrunkToFit { scale in
            switch middle {
            case let .figures(figures):
                HStack(alignment: .top, spacing: Self.figureGap * scale) {
                    ForEach(figures, id: \.self) { figure in
                        VStack(alignment: .leading, spacing: Self.wordGap) {
                            big(figure.number, scale: scale)
                            small(figure.unit)
                        }
                    }
                }
            case let .count(label, time):
                VStack(alignment: .leading, spacing: Self.wordGap) {
                    small(label)
                    big(time, scale: scale)
                }
            case let .timed(time, of):
                VStack(alignment: .leading, spacing: Self.wordGap) {
                    big(time, scale: scale)
                    small(of)
                }
            case let .allLogged(count, detail):
                VStack(alignment: .leading, spacing: Self.wordGap) {
                    big(count, scale: scale)
                    small(detail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func big(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .ppWatchDigits(.figure, scale: scale)
            .foregroundStyle(Color.pp(isQuiet || isDimmed ? .textSecondary : .textPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .ppWatchFont(.unit)
            .foregroundStyle(Color.pp(.textSecondary))
            .lineLimit(1)
    }
}

/// `content` drawn at the largest of a few steps down from its full size that fits the width it
/// is given, so figures side by side shrink by the same; past the last step, each text shrinks
/// on its own (`minimumScaleFactor`) rather than be cut short.
struct ShrunkToFit<Content: View>: View {
    private static var steps: [CGFloat] {
        [1, 0.92, 0.84, 0.76, 0.68, 0.6]
    }

    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.steps, id: \.self) { scale in
                content(scale)
            }
        }
    }
}

/// The key, or Skip and +15 through a rest; nothing, its room kept, through "Start in".
struct WatchKeys: View {
    let key: WatchFace.Key?
    let tap: (SetPageTap) -> Void
    @Environment(\.watchKeyHeight) private var height

    var body: some View {
        switch key {
        case let .log(text): WatchKey("\(text)", isPrimary: true) { tap(.log) }
        case .finish: WatchKey("Finish", isPrimary: true) { tap(.finish) }
        case .resume: WatchKey("Continue", isPrimary: true) { tap(.resume) }
        case let .logEarly(fill): WatchKey("Log early", fill: fill) { tap(.logEarly) }
        case let .rest(fill):
            GeometryReader { proxy in
                HStack(spacing: 5) {
                    WatchKey("Skip", fill: fill, isSmall: true) { tap(.skipRest) }
                    WatchKey("+15", isSmall: true) { tap(.extendRest) }
                        .frame(width: (proxy.size.width - 5) * 0.45)
                }
            }
            .frame(height: height)
        case nil: Color.clear.frame(height: height)
        }
    }
}

#Preview("Set") {
    let (live, now) = WatchFixture.set.live
    if let face = live.watchFace(at: now) {
        SetPage(face: face) { _ in }
            .preferredColorScheme(.dark)
    }
}
#endif
