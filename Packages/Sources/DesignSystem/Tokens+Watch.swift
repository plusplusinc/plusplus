#if os(watchOS)
import SwiftUI
import UIKit

/// The Watch's type, sized to its boards (2x pictures of a 211 by 257 pt screen) and scaled with
/// the wrist's text size from there: each is a point size read relative to a text style, so a
/// larger text size on the Watch grows them all.
public enum WatchType: CaseIterable, Sendable {
    /// The "++" over the idle and finished pages.
    case mark
    /// A page's title: the exercise's name, the workout's, "No workout running".
    case title
    /// A line of plain words under a title.
    case body
    /// The caption under the name, "Set 2 of 3": SF Mono.
    case caption
    /// The large figures and a count: bold SF Mono.
    case figure
    /// What a figure counts, under it: "reps", "lb".
    case unit
    /// A label over a count, "Rest", "Start in".
    case label
    /// A key's word, alone on its row.
    case key
    /// A key's word, two keys side by side, "Skip" and "+15".
    case pairKey
    /// A button drawn as words, "Discard workout".
    case textButton
    /// A row in the list page: its name, and its detail under it.
    case rowName
    case rowDetail
    /// The workout's time on the time page.
    case time

    var size: CGFloat {
        switch self {
        case .mark: 36
        case .title: 15
        case .body: 12
        case .caption: 10
        case .figure: 48
        case .unit: 11
        case .label: 11
        case .key: 17
        case .pairKey: 14
        case .textButton: 13
        case .rowName: 14
        case .rowDetail: 11
        // The largest "00:00" fits on one line across the SE's 40 mm screen.
        case .time: 40
        }
    }

    var weight: Font.Weight {
        switch self {
        case .mark, .figure, .time: .bold
        case .title, .key, .pairKey, .textButton, .rowName: .semibold
        case .caption: .medium
        case .body, .unit, .label, .rowDetail: .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .mark, .caption, .figure, .time: .monospaced
        default: .default
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .mark, .figure, .time: .largeTitle
        case .title, .key, .rowName: .headline
        case .pairKey, .textButton: .body
        case .body, .unit, .label, .rowDetail, .caption: .footnote
        }
    }
}

extension View {
    /// `Text("Rest").ppWatchFont(.label)`: the Watch's type, never a size at the call site. A
    /// `scale` under 1 shrinks it to fit, as figures too wide for the screen do, all by the same.
    public func ppWatchFont(_ type: WatchType, scale: CGFloat = 1) -> some View {
        modifier(WatchFont(type: type, scale: scale))
    }
}

private struct WatchFont: ViewModifier {
    let type: WatchType
    let scale: CGFloat
    @ScaledMetric private var size: CGFloat

    init(type: WatchType, scale: CGFloat) {
        self.type = type
        self.scale = scale
        _size = ScaledMetric(wrappedValue: type.size, relativeTo: type.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: type.weight, design: type.design))
    }
}

extension View {
    /// Digits in the Watch's type with the room above their tops and under their baseline cut
    /// away, so the frame is the digits' own height: figures centered between two edges look
    /// centered, with no line's leading above them. For one line of digits, which have no
    /// descenders: the figures and counts.
    public func ppWatchDigits(_ type: WatchType, scale: CGFloat = 1) -> some View {
        modifier(WatchDigits(type: type, scale: scale))
    }
}

private struct WatchDigits: ViewModifier {
    let type: WatchType
    let scale: CGFloat
    @ScaledMetric private var size: CGFloat

    init(type: WatchType, scale: CGFloat) {
        self.type = type
        self.scale = scale
        _size = ScaledMetric(wrappedValue: type.size, relativeTo: type.textStyle)
    }

    func body(content: Content) -> some View {
        DigitsOnly(capHeight: capHeight) {
            content.font(.system(size: size * scale, weight: type.weight, design: type.design))
        }
    }

    /// The height of the digits' tops over their baseline, the font's cap height.
    private var capHeight: CGFloat {
        let weight: UIFont.Weight = type.weight == .bold ? .bold : .regular
        let font = type.design == .monospaced
            ? UIFont.monospacedSystemFont(ofSize: size * scale, weight: weight)
            : UIFont.systemFont(ofSize: size * scale, weight: weight)
        return font.capHeight
    }
}

/// Its one line of text as tall as `capHeight`, from its first baseline up.
private struct DigitsOnly: Layout {
    let capHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let width = text.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).width
        return CGSize(width: width, height: capHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard let text = subviews.first else { return }
        let free = ProposedViewSize(width: proposal.width, height: nil)
        let above = text.dimensions(in: free)[.firstTextBaseline] - capHeight
        text.place(at: CGPoint(x: bounds.minX, y: bounds.minY - above), proposal: free)
    }
}
#endif
