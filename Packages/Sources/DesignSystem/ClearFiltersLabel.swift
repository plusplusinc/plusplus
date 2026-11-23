#if os(iOS)
import SwiftUI

/// Clear's look, at the leading end of the filter buttons while one is on: a bare × in a round
/// capsule the filter buttons' height, off, so it reads as one of them. The × is the + of the
/// offer buttons turned 45 degrees, not `xmark`, whose arms are longer and lighter, so the two
/// marks match. VoiceOver reads it as "Clear filters".
public struct ClearFiltersLabel: View {
    public init() { }

    public var body: some View {
        // A hidden letter gives the capsule the filter buttons' line height at every size.
        Text(verbatim: "M")
            .hidden()
            .overlay {
                Image(systemName: "plus")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .rotationEffect(.degrees(45))
            }
            .font(.ppRowDetail)
            .foregroundStyle(Color.pp(.textPrimary))
            .padding(Spacing.sm)
            .squared()
            .background(Color.pp(.surfaceRaised), in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clear filters")
    }
}

extension View {
    /// Lays the view out at least as wide as it is tall, so a capsule round it is a circle.
    fileprivate func squared() -> some View {
        SquareLayout { self }
    }
}

private struct SquareLayout: Layout {
    func sizeThatFits(
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: max(size.width, size.height), height: size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        subviews.first?.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: .unspecified,
        )
    }
}

#Preview {
    HStack(spacing: Spacing.sm) {
        ClearFiltersLabel()
        FilterLabel("Back", isOn: true)
        FilterLabel("Kind", isOn: false)
    }
    .padding()
    .background(Color.pp(.background))
}
#endif
