#if canImport(Session)
import DesignSystem
import SwiftUI
import WorkoutStore

/// What every page of the Watch app shares.
enum WatchPage {
    /// The room between the screen's sides and a page's text, as the boards draw it.
    static let sideInset: CGFloat = 18
}

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
            WatchBars(bars: face.bars)
                .padding(.top, 8)
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
            Spacer(minLength: 6)
            WatchMiddle(middle: face.middle, isQuiet: face.isQuiet)
            Spacer(minLength: 6)
            WatchKeys(key: face.key, tap: tap)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, WatchPage.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// The big middle: the set's numbers over what they count, or a count with its label.
struct WatchMiddle: View {
    let middle: WatchFace.Middle
    var isQuiet = false
    @Environment(\.isLuminanceReduced) private var isWristDown
    @Environment(\.forcesDim) private var forcesDim

    private var isDimmed: Bool {
        isWristDown || forcesDim
    }

    var body: some View {
        Group {
            switch middle {
            case let .figures(figures):
                HStack(alignment: .top, spacing: 14) {
                    ForEach(figures, id: \.self) { figure in
                        VStack(alignment: .leading, spacing: 0) {
                            big(figure.number)
                            small(figure.unit)
                        }
                    }
                }
            case let .count(label, time):
                VStack(alignment: .leading, spacing: 0) {
                    small(label)
                    big(time)
                }
            case let .timed(time, of):
                VStack(alignment: .leading, spacing: 0) {
                    big(time)
                    small(of)
                }
            case let .allLogged(count, detail):
                VStack(alignment: .leading, spacing: 0) {
                    big(count)
                    small(detail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func big(_ text: String) -> some View {
        Text(text)
            .ppWatchFont(.figure)
            .foregroundStyle(Color.pp(isQuiet || isDimmed ? .textSecondary : .textPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .ppWatchFont(.unit)
            .foregroundStyle(Color.pp(.textSecondary))
    }
}

/// The key, or Skip and +15 through a rest; nothing, its room kept, through "Start in".
struct WatchKeys: View {
    let key: WatchFace.Key?
    let tap: (SetPageTap) -> Void

    var body: some View {
        Group {
            switch key {
            case let .log(text): WatchKey("\(text)", isPrimary: true) { tap(.log) }
            case .finish: WatchKey("Finish", isPrimary: true) { tap(.finish) }
            case .resume: WatchKey("Continue", isPrimary: true) { tap(.resume) }
            case let .logEarly(fill): WatchKey("Log early", fill: fill) { tap(.logEarly) }
            case let .rest(fill):
                GeometryReader { proxy in
                    HStack(spacing: 6) {
                        WatchKey("Skip", fill: fill, isSmall: true) { tap(.skipRest) }
                        WatchKey("+15", isSmall: true) { tap(.extendRest) }
                            .frame(width: (proxy.size.width - 6) * 0.45)
                    }
                }
            case nil: Color.clear
            }
        }
        .frame(height: WatchKey.height)
    }
}

/// A key: a pill, cream for the one primary key, dark otherwise, with the share of a count run
/// filling it purple from its leading edge.
struct WatchKey: View {
    static let height: CGFloat = 52

    let title: LocalizedStringKey
    var fill: Double?
    var isPrimary = false
    var isSmall = false
    let action: () -> Void
    @Environment(\.isLuminanceReduced) private var isWristDown
    @Environment(\.forcesDim) private var forcesDim

    private var isDimmed: Bool {
        isWristDown || forcesDim
    }

    init(
        _ title: LocalizedStringKey,
        fill: Double? = nil,
        isPrimary: Bool = false,
        isSmall: Bool = false,
        action: @escaping () -> Void,
    ) {
        self.title = title
        self.fill = fill
        self.isPrimary = isPrimary
        self.isSmall = isSmall
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .ppWatchFont(isSmall ? .pairKey : .key)
                .foregroundStyle(Color.pp(textColor))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isDimmed {
                        // Wrist down: an outline, with no fill and no purple.
                        Capsule().strokeBorder(Color.pp(.borderStrong), lineWidth: 1.5)
                    } else {
                        Capsule().fill(Color.pp(isPrimary ? .primaryKey : .surface))
                    }
                    if let fill, !isDimmed {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(Color.pp(.done))
                                .frame(width: proxy.size.width * fill)
                                .animation(.linear(duration: 1), value: fill)
                        }
                        .clipShape(Capsule())
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var textColor: ColorToken {
        if isDimmed {
            return .textSecondary
        }
        return isPrimary ? .onPrimaryKey : .textPrimary
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
