#if os(watchOS)
import SwiftUI

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
        case .time: 34
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
    /// `Text("Rest").ppWatchFont(.label)`: the Watch's type, never a size at the call site.
    public func ppWatchFont(_ type: WatchType) -> some View {
        modifier(WatchFont(type: type))
    }
}

private struct WatchFont: ViewModifier {
    let type: WatchType
    @ScaledMetric private var size: CGFloat

    init(type: WatchType) {
        self.type = type
        _size = ScaledMetric(wrappedValue: type.size, relativeTo: type.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: type.weight, design: type.design))
    }
}
#endif
