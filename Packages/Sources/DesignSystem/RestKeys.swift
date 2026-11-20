import SwiftUI

/// The keys at the bottom during a rest, in the key's place: −15 s and +15 s side by side in its
/// room, each half its width, its height and shape, in the quieter secondary look
/// (`secondaryKey`). They are another key to the bar, so the key and they swap as any two keys do
/// (`StagedKey`): the one showing goes down out of sight, then the other comes up, never the two
/// at once; with Reduce Motion, each fades. While the bar has them out in a swap, a tap does
/// nothing. The two keep the key's room, so the floating button above it never moves, and stand
/// on a plate of the screen's color in the one key's shape, so no row shows between them.
/// VoiceOver reads them as two buttons, "Minus 15 seconds" and "Plus 15 seconds".
public struct RestKeys: View {
    let isOut: Bool
    let onShorten: () -> Void
    let onExtend: () -> Void

    public init(
        isOut: Bool = false,
        onShorten: @escaping () -> Void,
        onExtend: @escaping () -> Void,
    ) {
        self.isOut = isOut
        self.onShorten = onShorten
        self.onExtend = onExtend
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                if !isOut {
                    onShorten()
                }
            } label: {
                Text(AttributedString.monoNumbers("−15 s", font: .ppPrimaryKeyNumber))
            }
            .accessibilityLabel("Minus 15 seconds")
            Button {
                if !isOut {
                    onExtend()
                }
            } label: {
                Text(AttributedString.monoNumbers("+15 s", font: .ppPrimaryKeyNumber))
            }
            .accessibilityLabel("Plus 15 seconds")
        }
        .buttonStyle(.secondaryKey)
        // On a plate of the screen's own color, the one key's footprint, so the rows running on
        // under the bar show no more between the two keys than around the one: through the gap,
        // a row's words were readable.
        .background(Capsule().fill(.pp(.background)))
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        Button("Log set") { }
            .buttonStyle(.primaryKey)
        RestKeys(onShorten: { }, onExtend: { })
    }
    .padding()
    .background(Color.pp(.background))
}
