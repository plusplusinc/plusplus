#if canImport(Session)
import SwiftUI

/// What every page of the Watch app shares: how far its words and its key stand from the
/// screen's edges, as the boards draw them, fitted to the screen's corners.
enum WatchPage {
    /// From the screen's sides to a page's words.
    static let sideInset: CGFloat = 20
    /// From the screen's top to a page's first line.
    static let topInset: CGFloat = 30
    /// Under a scrolled list's last row, so it scrolls clear of the page dots.
    static let listFoot: CGFloat = 30
    /// A key's height: the boards' 56 where the screen's corners leave room, never under a tap
    /// target's 44.
    static let keyHeights: ClosedRange<CGFloat> = 44 ... 56
    /// The least room around a key, above the page dots.
    static let leastKeyInset: CGFloat = 8

    /// A key's height, and its inset from the screen's sides and bottom, on a screen whose
    /// corners have `cornerRadius`: the inset is the radius less half the height, so the key's
    /// round ends share their centers with the screen's corner arcs. Where that would leave
    /// under `leastKeyInset`, the key comes down toward 44 points tall to keep it, and at 44
    /// takes the least inset, as near concentric as the screen allows.
    static func key(cornerRadius: CGFloat) -> (height: CGFloat, inset: CGFloat) {
        let height = min(
            max(2 * (cornerRadius - leastKeyInset), keyHeights.lowerBound),
            keyHeights.upperBound,
        )
        return (height, max(leastKeyInset, cornerRadius - height / 2))
    }

    /// The room a page's first line leaves at its end for the clock, on a screen whose corners
    /// have `cornerRadius`. Round corners as wide as the 49 mm Ultra's (57 points) set the clock
    /// low enough to meet a line `topInset` down, so the line stops short of the clock's left
    /// edge, 162 points across its 211; on the 40 mm SE (28 points) the clock sits above it.
    static func clockRoom(cornerRadius: CGFloat) -> CGFloat {
        cornerRadius >= 40 ? 33 : 0
    }
}

extension EnvironmentValues {
    /// The height a page gives its keys (`WatchPage.key(cornerRadius:)`).
    @Entry var watchKeyHeight = WatchPage.keyHeights.upperBound
    /// The room a page's first line leaves for the clock (`WatchPage.clockRoom(cornerRadius:)`).
    @Entry var watchClockRoom: CGFloat = 0
}

extension View {
    /// A page's first line, ending short of the clock where the clock comes down to it.
    func clearOfClock() -> some View {
        modifier(ClearOfClock())
    }
}

private struct ClearOfClock: ViewModifier {
    @Environment(\.watchClockRoom) private var room

    func body(content: Content) -> some View {
        content.padding(.trailing, room)
    }
}

/// The whole screen, edge to edge, with what its corners give a page: its keys' height and its
/// first line's room for the clock. The corner radius is the one the system gives the page's
/// container (`GeometryProxy.containerCornerInsets`): 57 points on the 49 mm Ultra, 28 on the
/// 40 mm SE.
struct WholeScreen<Content: View>: View {
    @ViewBuilder let content: (_ size: CGSize, _ keyInset: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let radius = proxy.containerCornerInsets.bottomLeading.height
            let key = WatchPage.key(cornerRadius: radius)
            content(proxy.size, key.inset)
                .environment(\.watchKeyHeight, key.height)
                .environment(\.watchClockRoom, WatchPage.clockRoom(cornerRadius: radius))
        }
        .ignoresSafeArea()
    }
}

/// A page laid out on the whole screen: its top group `WatchPage.topInset` down, its key (or
/// keys) at the foot, as far from the screen's bottom as from its sides
/// (`WatchPage.key(cornerRadius:)`), and its middle centered between them.
struct WatchScreen<Top: View, Middle: View, Keys: View>: View {
    @ViewBuilder let top: Top
    @ViewBuilder let middle: Middle
    @ViewBuilder let keys: Keys

    var body: some View {
        WholeScreen { size, keyInset in
            VStack(alignment: .leading, spacing: 0) {
                top
                    .padding(.horizontal, WatchPage.sideInset)
                Spacer(minLength: 4)
                middle
                    .padding(.horizontal, WatchPage.sideInset)
                Spacer(minLength: 4)
                keys
                    .padding(.horizontal, keyInset)
                    .padding(.bottom, keyInset)
            }
            .padding(.top, WatchPage.topInset)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

extension WatchScreen where Middle == EmptyView {
    init(@ViewBuilder top: () -> Top, @ViewBuilder keys: () -> Keys) {
        self.init(top: top, middle: { EmptyView() }, keys: keys)
    }
}
#endif
