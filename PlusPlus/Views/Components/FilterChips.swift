import SwiftUI

/// The one filter-row vocabulary (#237): filters and sort share a
/// horizontally-scrollable row; every control is a 36 pt chip inside
/// a 44 pt hit target (Quiet Arcade — box-consistent, so filled and
/// outlined chips are identical height). Chips stay FLAT: they're
/// state togglers, and the state flip is the feedback. Three kinds
/// compose it:
/// - `FacetChip` — single-select, anchored Menu; the ACTIVE VALUE
///   becomes the label in solid selection blue (#223's grammar).
/// - `TrayFilterChip` — multi-select facets that open a tray; active
///   state is the facet name + a count pill (values don't fit, the
///   count says how much filtering is on).
/// - `ClearAllChip` — the leading ✕ that appears when anything is
///   active and resets the row in one tap.
/// Sort rides the same row but stays visually NEUTRAL with its
/// up/down glyph — ordering is not filter state, and users conflate
/// the two when they look alike.

/// Filter-row controls are rounded rectangles, not capsules (Dave,
/// 2026-07-20): every interactive key in the app is a rounded rect (the
/// r11 raised keys, the header icon squares), so the chips join that family
/// — and shape now carries role, rounded-rect = control vs the capsule
/// `CardTagCapsule` = inert data tag. One radius, matching the keys they
/// sit beside.
enum FilterChipShape {
    static let cornerRadius: CGFloat = 11
}

/// One facet, single-select. Tapping anchors a native Menu with a
/// checkmark on the current value and "Any" to clear — never
/// value-cycling, which is undiscoverable and punishes overshoot.
struct FacetChip<Value: Hashable>: View {
    let facet: String
    @Binding var selection: Value?
    let options: [(Value, String)]
    /// Optional footer rows in the menu for fixing the filter's BASIS in
    /// place (#260: "Edit my equipment…" on GEAR; "Switch library…" once
    /// equipment libraries exist) — the no-dead-ends law applied to
    /// availability.
    var footers: [(label: String, action: () -> Void)] = []
    /// A meaningful SF Symbol shown leading the label when the facet is
    /// active (Dave, 2026-07-20). `valueSymbols` maps a selected value to a
    /// symbol particular to it; `attributeSymbol` is the fallback for the
    /// facet as a whole.
    var attributeSymbol: String? = nil
    var valueSymbols: [Value: String] = [:]

    private var activeSymbol: String? {
        guard let selection else { return nil }
        return valueSymbols[selection] ?? attributeSymbol
    }

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
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    if selection == value {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
            if !footers.isEmpty {
                Divider()
                ForEach(footers.indices, id: \.self) { index in
                    Button(footers[index].label, action: footers[index].action)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let activeSymbol {
                    Image(systemName: activeSymbol)
                        .font(.system(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(activeLabel)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(selection == nil ? Theme.textSecondary : Theme.onSelected)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(
                selection == nil ? Theme.surface : Theme.selected,
                in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
            )
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(selection == nil ? Theme.border : Color.clear))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .animation(Theme.Anim.selection, value: selection == nil)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("facet\(facet.capitalized)")
    }

    // Sentence case, not all-caps: all-caps is reserved for section labels
    // (Dave, 2026-07-18); chips are rounded-rect controls (2026-07-20).
    private var activeLabel: String {
        guard let selection, let match = options.first(where: { $0.0 == selection }) else {
            return facet
        }
        return match.1
    }
}

/// A multi-select facet in an anchored menu: UNION within the facet
/// (each item carries exactly one value, so intersection would always
/// be empty), AND across facets — standard faceted search (#260). The
/// label SPEAKS the union so the semantics read at a glance: "PUSH",
/// "PUSH OR PULL", "PUSH +2". Menu items toggle with checkmarks;
/// "Any" clears the facet.
struct MultiFacetChip<Value: Hashable>: View {
    let facet: String
    @Binding var selection: Set<Value>
    let options: [(Value, String)]
    /// A meaningful SF Symbol when active (Dave, 2026-07-20): the selected
    /// value's own symbol when exactly one is picked, else the facet's
    /// `attributeSymbol` (a union has no single value to speak for).
    var attributeSymbol: String? = nil
    var valueSymbols: [Value: String] = [:]

    private var activeSymbol: String? {
        guard !selection.isEmpty else { return nil }
        if selection.count == 1, let only = selection.first, let symbol = valueSymbols[only] {
            return symbol
        }
        return attributeSymbol
    }

    var body: some View {
        Menu {
            Button {
                selection = []
            } label: {
                if selection.isEmpty {
                    Label("Any", systemImage: "checkmark")
                } else {
                    Text("Any")
                }
            }
            ForEach(options, id: \.0) { value, label in
                Button {
                    if selection.contains(value) {
                        selection.remove(value)
                    } else {
                        selection.insert(value)
                    }
                } label: {
                    if selection.contains(value) {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let activeSymbol {
                    Image(systemName: activeSymbol)
                        .font(.system(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(activeLabel)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(selection.isEmpty ? Theme.textSecondary : Theme.onSelected)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(
                selection.isEmpty ? Theme.surface : Theme.selected,
                in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
            )
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
                .strokeBorder(selection.isEmpty ? Theme.border : Color.clear))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .animation(Theme.Anim.selection, value: selection.isEmpty)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("facet\(facet.capitalized)")
    }

    /// Picked values in option order (stable, not Set order). Sentence
    /// case, not all-caps (Dave, 2026-07-18).
    private var activeLabel: String {
        let picked = options.filter { selection.contains($0.0) }.map(\.1)
        switch picked.count {
        case 0: return facet
        case 1: return picked[0]
        case 2: return "\(picked[0]) or \(picked[1])"
        default: return "\(picked[0]) +\(picked.count - 1)"
        }
    }
}

/// A multi-select facet whose values live in a tray: the chip opens
/// it, and the active state is the facet name plus a count pill —
/// "MUSCLE ②" says how much narrowing is on without listing values
/// (Dave's #237 ask).
struct TrayFilterChip: View {
    let facet: String
    let count: Int
    /// A meaningful SF Symbol shown leading the facet name when active
    /// (Dave, 2026-07-20). A tray's values don't fit the chip, so this is
    /// the facet's attribute symbol, not a per-value one.
    var activeSymbol: String? = nil
    let action: () -> Void

    private var active: Bool { count > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if active, let activeSymbol {
                    Image(systemName: activeSymbol)
                        .font(.system(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(facet)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if active {
                    Text("\(count)")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(Theme.selected)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.onSelected, in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(active ? Theme.onSelected : Theme.textSecondary)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(active ? Theme.selected : Theme.surface, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius).strokeBorder(active ? Color.clear : Theme.border))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.selection, value: active)
        .sensoryFeedback(.selection, trigger: count)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("facet\(facet.capitalized)")
    }
}

/// The leading ✕: appears when any facet is active, clears the row.
struct ClearAllChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius).strokeBorder(Theme.border))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear filters")
        .accessibilityIdentifier("clearFilters")
        .transition(.opacity)
    }
}

/// Sort as a chip in the same row, visually neutral always: ordering
/// is not filter state. The current order is the label.
struct SortChip<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            Picker("Sort", selection: $selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
                Text(currentLabel)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sort")
            .accessibilityValue(currentLabel)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius).strokeBorder(Theme.border))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("catalogSortMenu")
    }

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }
}

/// A filter chip that opens a SHEET rather than an anchored menu — the
/// routine catalog's Kit filter (Dave, 2026-07-20), which combines kit
/// switching with the fit mode and doesn't fit a menu. Its icon and label
/// speak the current mode; it reads active (blue) while narrowing to a kit
/// or to bodyweight, neutral while showing all routines.
struct KitFilterChip: View {
    let symbol: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isActive ? Theme.onSelected : Theme.textSecondary)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(isActive ? Theme.selected : Theme.surface, in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius).strokeBorder(isActive ? Color.clear : Theme.border))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.selection, value: isActive)
        .accessibilityLabel("Kit filter")
        .accessibilityValue(label)
        .accessibilityIdentifier("facetKit")
    }
}
