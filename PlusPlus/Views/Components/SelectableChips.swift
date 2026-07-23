import SwiftUI

/// Shared chip + wrapping-layout pair, promoted out of ExercisePickerView
/// (2026-07-17) when the equipment catalog's type facet became their
/// second consumer — shared controls live in Components once they appear
/// in a second view.

/// A rounded-rect toggle chip: solid selected blue (#210) — one prominent
/// toggled-on look everywhere; ink fills stay reserved for actions.
struct SelectableChip: View {
    let label: String
    let isSelected: Bool
    var identifier: String? = nil
    /// Optional leading type glyph (the Find-or-create scope chips carry
    /// their result type). Rides the label's color, so it flips to
    /// `onSelected` white with the fill.
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(label)
            }
                .font(.system(.footnote, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? Theme.selected : Color.clear)
                .foregroundStyle(isSelected ? Theme.onSelected : Theme.textPrimary)
                // Rounded rect, matching the filter-row control shape (Dave,
                // 2026-07-20) — see FilterChipShape.
                .clipShape(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                    .strokeBorder(isSelected ? Color.clear : Theme.borderStrong, lineWidth: 1))
                .padding(4)
                .contentShape(Rectangle())
        }
        .animation(Theme.Anim.selection, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// Left-aligned wrapping layout for chip grids.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
