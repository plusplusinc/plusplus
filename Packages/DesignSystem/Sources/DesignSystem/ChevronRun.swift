import SwiftUI

/// The forward-momentum flourish on a key that starts something.
///
/// At rest it shows one chevron. Once running, two more emerge from behind it to the right and a
/// lit highlight marches left→right across the trio, the others dimmed rather than hidden.
///
/// **The resting chevron never moves, and the resting content still centres.** Only a single
/// chevron occupies layout width; the other two are drawn in an overlay that extends past the
/// trailing edge, so they cost nothing in layout and cannot shove anything. Laying all three out
/// normally would grow the run from one chevron wide to three as they appear, and because a key
/// centres its contents that growth drags the label and the resting chevron leftward at the exact
/// moment the eye is tracking them. Reserving all three up front fixes the drift but leaves the
/// resting label visibly off-centre. Overflowing gets both.
///
/// Reduce Motion keeps the single static chevron: the emerge is positional (WCAG 2.3.3).
public struct ChevronRun: View {
    /// How many chevrons the run marches across, and therefore how much width it reserves.
    public static let count = 3

    private let isRunning: Bool
    private let activeIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - isRunning: whether the key has ignited.
    ///   - activeIndex: which chevron is lit, as the caller drives the march.
    public init(isRunning: Bool, activeIndex: Int) {
        self.isRunning = isRunning
        self.activeIndex = activeIndex
    }

    /// The gap between chevrons. Tighter than ``Spacing/xs`` on purpose: these are one glyph
    /// repeated, not separate elements, and the run should read as a single arrow.
    private static let gap: CGFloat = 3

    public var body: some View {
        // The sizing element: exactly one chevron, so a key's contents centre on the resting state.
        Image(systemName: "chevron.right")
            .hidden()
            .overlay(alignment: .leading) { liveRun }
            // Decoration. The button's own label already says what it does.
            .accessibilityHidden(true)
    }

    private var liveRun: some View {
        HStack(spacing: Self.gap) {
            Image(systemName: "chevron.right")
                .opacity(opacity(of: 0))

            if marching {
                ForEach(1..<Self.count, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .opacity(opacity(of: index))
                        // Emerge from behind the resting chevron so they read as coming out of it
                        // rightward, into space that costs the layout nothing.
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        // Take the trio's ideal width rather than being squeezed to the single-chevron frame
        // this sits on; the excess spills past the trailing edge, which is the whole point.
        .fixedSize()
    }

    private var marching: Bool {
        isRunning && !reduceMotion
    }

    /// The lit chevron is full; its neighbours rest dim so the two that emerged stay visible as a
    /// track for the highlight to travel. At rest, only the first shows at all.
    private func opacity(of index: Int) -> Double {
        guard marching else { return index == 0 ? 1 : 0 }
        return activeIndex == index ? 1 : 0.25
    }
}

#Preview("Rest vs running") {
    VStack(alignment: .leading, spacing: Spacing.md) {
        ChevronRun(isRunning: false, activeIndex: 0)
        ChevronRun(isRunning: true, activeIndex: 0)
        ChevronRun(isRunning: true, activeIndex: 2)
    }
    .font(.ppButtonLabel)
    .foregroundStyle(Color.ppTextPrimary)
    .padding(Spacing.lg)
    .background(Color.ppBackground)
}
