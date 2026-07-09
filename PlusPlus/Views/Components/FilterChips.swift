import SwiftUI

/// The one filter-row vocabulary (#237): filters and sort share a
/// horizontally-scrollable row; every control is a 44 pt chip. Three
/// kinds compose it:
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

/// One facet, single-select. Tapping anchors a native Menu with a
/// checkmark on the current value and "Any" to clear — never
/// value-cycling, which is undiscoverable and punishes overshoot.
struct FacetChip<Value: Hashable>: View {
    let facet: String
    @Binding var selection: Value?
    let options: [(Value, String)]

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
        } label: {
            Text(activeLabel)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .kerning(0.5)
                .lineLimit(1)
                .foregroundStyle(selection == nil ? Theme.textSecondary : Theme.onSelected)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(
                    selection == nil ? Theme.surface : Theme.selected,
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(selection == nil ? Theme.border : Color.clear))
        }
        .animation(.easeOut(duration: 0.15), value: selection == nil)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("facet\(facet.capitalized)")
    }

    private var activeLabel: String {
        guard let selection, let match = options.first(where: { $0.0 == selection }) else {
            return facet
        }
        return match.1.uppercased()
    }
}

/// A multi-select facet whose values live in a tray: the chip opens
/// it, and the active state is the facet name plus a count pill —
/// "MUSCLE ②" says how much narrowing is on without listing values
/// (Dave's #237 ask).
struct TrayFilterChip: View {
    let facet: String
    let count: Int
    let action: () -> Void

    private var active: Bool { count > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(facet)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .kerning(0.5)
                    .lineLimit(1)
                if active {
                    Text("\(count)")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(Theme.selected)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.onSelected, in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
            }
            .foregroundStyle(active ? Theme.onSelected : Theme.textSecondary)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(active ? Theme.selected : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.clear : Theme.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: active)
        .sensoryFeedback(.selection, trigger: count)
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
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Text(currentLabel.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .kerning(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
        }
        .accessibilityIdentifier("catalogSortMenu")
    }

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }
}
