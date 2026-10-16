import SwiftUI

/// Short labels on capsules, left to right, wrapping onto as many lines as they need.
public struct Capsules: View {
    private let labels: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(_ labels: [String]) {
        self.labels = labels
    }

    private var entrance: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
    }

    public var body: some View {
        FlowLayout(spacing: Spacing.sm) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.ppRowDetail)
                    .foregroundStyle(Color.pp(.textPrimary))
                    .padding(.horizontal, Spacing.md - Spacing.xs)
                    .padding(.vertical, Spacing.xs + Spacing.xxs)
                    .background(Color.pp(.surface), in: .capsule)
                    .transition(entrance)
            }
        }
        // A new piece pops in, and the ones after it slide over to make room.
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.4, extraBounce: 0.15),
            value: labels,
        )
        .accessibilityElement(children: .combine)
        .hotReloadable()
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        Capsules(["Dumbbells", "Bench"])
        Capsules(["Dumbbells", "Kettlebell", "Barbell", "Bench", "Band", "Pull-up bar", "Rings"])
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.pp(.background))
}

/// Lays its subviews out in rows, starting a new row when the next one won't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size),
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            size.width = min(size.width, width)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
