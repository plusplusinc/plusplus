import SwiftUI

/// The filter-row vocabulary. Retired 2026-07-25, returned 2026-07-31
/// (Dave's call) — REBUILT under the current selection law, not
/// restored from git: the deleted chips wore the retired solid-blue
/// fill, and these wear `SelectableChip`'s anatomy (tinted ground +
/// ring + bright ink, 36 pt chip in a 44 pt vertical-only hit frame,
/// r11). Single-select Menus only in v1 — a multi-select is a list,
/// not a Menu (ui-interaction.md); a facet that outgrows a Menu gets a
/// tray, not more Menu.
enum FilterChipShape {
    static let cornerRadius: CGFloat = Theme.keyRadius
}

/// One single-select facet: a Menu chip. The active value becomes the
/// chip's label; "Any" clears. Never value-cycling — the Menu shows a
/// checkmark on the current pick so state is visible before changing it.
struct FacetChip<Value: Hashable>: View {
    let name: String
    let options: [Value]
    let display: (Value) -> String
    @Binding var selection: Value?
    var identifier: String? = nil

    private var isActive: Bool { selection != nil }

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("Any", systemImage: "checkmark")
                } else {
                    Text("Any")
                }
            }
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if selection == option {
                        Label(display(option), systemImage: "checkmark")
                    } else {
                        Text(display(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection.map(display) ?? name)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.system(.footnote, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isActive ? Theme.selectedTint : Color.clear)
            .foregroundStyle(isActive ? Theme.selectedInk : Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(isActive ? Theme.selectedRing : Theme.borderStrong, lineWidth: 1))
            // 36 pt chip inside a 44 pt hit target, growing VERTICALLY ONLY
            // (the SelectableChip alignment lesson, 2026-07-24).
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .animation(Theme.Anim.selection, value: isActive)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier(identifier ?? "facet\(name)")
        .accessibilityLabel("\(name) filter")
        .accessibilityValue(selection.map(display) ?? "Any")
    }
}

/// The mandated active-state summary (design-grammar: "active filters
/// summarize, never insta-clear"): a selection-look count chip leading
/// the row, opening a popover that names each active facet's value,
/// says how far the list narrowed, and holds Clear all. `total` was a
/// CLOSURE while the unfiltered count meant a second ranking pass — the
/// engine now counts what the facets hid in the pass that built the
/// sections (#507), so shown + hidden is already in hand and there is
/// nothing left to defer.
struct FilterSummaryChip: View {
    let facets: [ActiveFacet]
    let shown: Int
    let total: Int
    let onClearAll: () -> Void

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
                Text("\(facets.count)")
            }
            .font(.system(.footnote, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Theme.selectedTint)
            .foregroundStyle(Theme.selectedInk)
            .clipShape(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(Theme.selectedRing, lineWidth: 1))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        // ⚠️ Plain, never the default: on tab roots the facet row is LIST
        // CONTENT now, and inside a `List` row taps route into default-styled
        // buttons anywhere in the row (the build-12 class) — a tap on the
        // row's dead band would pop this popover. The chip draws all its own
        // chrome, so plain is visually identical.
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterSummary")
        .accessibilityLabel("Active filters")
        .accessibilityValue("\(facets.count)")
        .popover(isPresented: $showingDetail, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(facets) { facet in
                    HStack(spacing: 6) {
                        Text(facet.name)
                            .foregroundStyle(Theme.textSecondary)
                        Text(facet.value)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .font(.system(.footnote))
                }
                Text("\(shown) of \(total) shown")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                QuietKey(label: "Clear all", identifier: "clearAllFilters") {
                    showingDetail = false
                    onClearAll()
                }
            }
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
    }
}
