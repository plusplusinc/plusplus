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
                // 36 pt chip inside a 44 pt hit target, growing VERTICALLY ONLY
                // — the same idiom as FacetChip/TrayFilterChip (FilterChips.swift).
                // A symmetric `.padding(4)` also inset the border horizontally,
                // which shoved the leading chip 4 pt in from the row edge (out of
                // line with the ++ key / create row / list rows) and widened the
                // gap after it — so a filter row led by this chip read misaligned
                // and unevenly spaced (2026-07-24).
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .animation(Theme.Anim.selection, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// Left-aligned wrapping layout for chip grids. Horizontal and vertical
/// gaps are separable: chips grow their hit target VERTICALLY (a 36 pt
/// chip in a 44 pt tap frame), so a chip's measured height carries 4 pt of
/// transparent inset top and bottom that a row-to-row gap inherits. Callers
/// that want visually EVEN gaps therefore pass a smaller `verticalSpacing`
/// (the inset makes up the difference); `FlowLayout(spacing:)` keeps a
/// single value for both when the subviews carry no such inset.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.horizontalSpacing = spacing
        self.verticalSpacing = spacing
    }

    init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            if index < rows.count - 1 { height += verticalSpacing }
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
                x += size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
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
            currentWidth += size.width + horizontalSpacing
        }
        return rows
    }
}
