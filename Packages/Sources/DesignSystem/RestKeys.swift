import SwiftUI

/// The key at the bottom, which during a rest swaps in place for −15 s and +15 s: two keys side by
/// side in its room, each half its width, its height and shape, in the quieter secondary look
/// (`secondaryKey`). The swap is a crossfade in place, the one going shrinking a little as it
/// fades and the one coming growing back to its size, on the rest's swap curve
/// (`SetMotion.restSwap`) after `delay`: at the log from the tap, with everything else it changes;
/// at a rest's end with the figures coming back. With Reduce Motion, only the fade. Whichever is
/// not showing takes no taps and is hidden from VoiceOver. The two keys keep the key's room, so
/// the floating button above it never moves.
public struct RestKeys<Key: View>: View {
    let isResting: Bool
    let delay: Double
    let key: Key
    let onShorten: () -> Void
    let onExtend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isResting: Bool,
        delay: Double = 0,
        onShorten: @escaping () -> Void,
        onExtend: @escaping () -> Void,
        @ViewBuilder key: () -> Key,
    ) {
        self.isResting = isResting
        self.delay = delay
        self.onShorten = onShorten
        self.onExtend = onExtend
        self.key = key()
    }

    public var body: some View {
        ZStack {
            key
                .opacity(isResting ? 0 : 1)
                .scaleEffect(isResting && !reduceMotion ? Self.shrunk : 1)
                .allowsHitTesting(!isResting)
                .accessibilityHidden(isResting)
            HStack(spacing: Spacing.sm) {
                Button(action: onShorten) {
                    Text(AttributedString.monoNumbers("−15 s", font: .ppPrimaryKeyNumber))
                }
                .accessibilityLabel("Shorten rest by 15 seconds")
                Button(action: onExtend) {
                    Text(AttributedString.monoNumbers("+15 s", font: .ppPrimaryKeyNumber))
                }
                .accessibilityLabel("Extend rest by 15 seconds")
            }
            .buttonStyle(.secondaryKey)
            .opacity(isResting ? 1 : 0)
            .scaleEffect(isResting || reduceMotion ? 1 : Self.shrunk)
            .allowsHitTesting(isResting)
            .accessibilityHidden(!isResting)
        }
        .animation(SetMotion.restSwap.delay(delay), value: isResting)
    }

    /// The size the key going shrinks to as it fades, and the one coming grows from.
    static var shrunk: CGFloat {
        0.96
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        RestKeys(
            isResting: false,
            onShorten: { },
            onExtend: { },
            key: { Button("Log set") { } },
        )
        RestKeys(
            isResting: true,
            onShorten: { },
            onExtend: { },
            key: { Button("Log set") { } },
        )
    }
    .buttonStyle(.primaryKey)
    .padding()
    .background(Color.pp(.background))
}
