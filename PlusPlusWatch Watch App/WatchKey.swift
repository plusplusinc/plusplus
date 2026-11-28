#if canImport(Session)
import DesignSystem
import SwiftUI

/// A key: a pill, cream for the one primary key, dark otherwise, with the share of a count run
/// filling it purple from its leading edge. Over the fill its word turns the cream key's dark,
/// switching where the fill's edge crosses it, as the phone's count key does
/// (`PrimaryKeyButtonStyle.countKey`).
struct WatchKey: View {
    let title: LocalizedStringKey
    var fill: Double?
    var isPrimary = false
    var isSmall = false
    let action: () -> Void
    @Environment(\.isLuminanceReduced) private var isWristDown
    @Environment(\.forcesDim) private var forcesDim
    /// As the page sets it from the screen's corners (`WatchPage.key(cornerRadius:)`).
    @Environment(\.watchKeyHeight) private var height

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
            word(in: textColor)
                .overlay {
                    if let fill, !isDimmed {
                        word(in: .onPrimaryKey)
                            .mask(alignment: .leading) { filled(fill) }
                            .accessibilityHidden(true)
                    }
                }
                .background {
                    if isDimmed {
                        // Wrist down: an outline, with no fill and no purple.
                        Capsule().strokeBorder(Color.pp(.borderStrong), lineWidth: 1.5)
                    } else {
                        Capsule().fill(Color.pp(isPrimary ? .primaryKey : .surface))
                    }
                    if let fill, !isDimmed {
                        filled(fill)
                            .foregroundStyle(Color.pp(.done))
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(height: height)
    }

    private func word(in color: ColorToken) -> some View {
        Text(title)
            .ppWatchFont(isSmall ? .pairKey : .key)
            .foregroundStyle(Color.pp(color))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The share `fill` of the key, from its leading edge.
    private func filled(_ fill: Double) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(width: proxy.size.width * fill)
                .animation(.linear(duration: 1), value: fill)
        }
    }

    private var textColor: ColorToken {
        if isDimmed {
            return .textSecondary
        }
        return isPrimary ? .onPrimaryKey : .textPrimary
    }
}
#endif
