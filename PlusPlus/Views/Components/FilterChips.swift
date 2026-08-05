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

/// The chip anatomy, in ONE place — all three chips wore a copy of it, and
/// the copies are why this is a modifier now rather than three edits (Dave,
/// 2026-08-05: make the filter triggers match the search field and the scope
/// bar).
///
/// **It is LIQUID GLASS, not app-drawn chrome.** The chips sit directly under
/// two system glass controls (the search field, the scope bar) and were the
/// only thing in that stack wearing a hairline stroke over a transparent
/// ground, which read as a different material rather than a different
/// control. `.glassEffect` is the system's own answer and it brings the
/// specular edge, the adaptive legibility and the dark/light behaviour that a
/// stroke was standing in for.
///
/// What is DELIBERATELY unchanged, because each is a law rather than a detail
/// (design-grammar.md):
/// - **The r11 ROUNDED RECT survives.** Filter controls sit at
///   `FilterChipShape.cornerRadius`, data tags at r6, and shape carries role
///   by radius. The field and the scope bar above are capsules; matching
///   THAT would reverse the 2026-07-20 rounded-rects-not-capsules law, which
///   is Dave's to reverse, not this change's.
/// - **One selection look.** Active still reads as a tinted ground plus a
///   brighter label. The tint is now `Glass.tint` rather than a drawn
///   `selectedTint` fill — the same intent (a wash, never a solid blue) via
///   the material's own knob. ⚠️ The RING is dropped: glass draws its own
///   edge, and a stroke on top of it is the box-in-a-box that killed the
///   bottom accessory.
/// - **`.interactive()`**, so a press responds the way the scope bar's
///   segments do. That is the one animation this chip gets; `Theme.Anim`
///   still owns the active-state cross-fade.
///
/// ⚠️ CONTRAST IS UNVERIFIED. `Theme.selectedInk` was measured against a
/// drawn 12% wash over `surface` (2026-07-28, the 4.07:1 finding); glass
/// composites differently and over live content. The law that produced that
/// finding — a hue proven on one ground has not been shown to read on
/// another — applies to this change too, and it needs eyes on device.
private struct FilterChipChrome: ViewModifier {
    let isActive: Bool
    var horizontalPadding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .font(.system(.footnote, weight: .semibold))
            .padding(.horizontal, horizontalPadding)
            .frame(height: 36)
            .foregroundStyle(isActive ? Theme.selectedInk : Theme.textPrimary)
            .glassEffect(
                isActive
                    ? .regular.tint(Theme.selected).interactive()
                    : .regular.interactive(),
                in: RoundedRectangle(cornerRadius: FilterChipShape.cornerRadius)
            )
            // 36 pt chip inside a 44 pt hit target, growing VERTICALLY ONLY
            // (the SelectableChip alignment lesson, 2026-07-24).
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

extension View {
    /// One filter chip's chrome. See `FilterChipChrome`.
    func filterChipChrome(isActive: Bool, horizontalPadding: CGFloat = 14) -> some View {
        modifier(FilterChipChrome(isActive: isActive, horizontalPadding: horizontalPadding))
    }
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
            .filterChipChrome(isActive: isActive)
        }
        .animation(Theme.Anim.selection, value: isActive)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier(identifier ?? "facet\(name)")
        .accessibilityLabel("\(name) filter")
        .accessibilityValue(selection.map(display) ?? "Any")
    }
}

/// A MULTI-select facet (#498): the chip opens a tray holding the
/// app's standard `SheetPickList`, because a multi-select is a list,
/// not a `Menu` (ui-interaction.md — a Menu can't be searched, closes
/// on every pick, and shows no selection state). Binary facets keep
/// `FacetChip` above: "both" and "neither" mean the same thing there,
/// so a two-option list would be ceremony around a toggle.
///
/// The chip states its own selection the way the row's summary chip
/// states the row's: the value when there is one, a count when there
/// are several.
struct FacetTrayChip<Value>: View where Value: Hashable & RawRepresentable, Value.RawValue == String {
    let name: String
    let options: [Value]
    let display: (Value) -> String
    @Binding var selection: Set<Value>
    var identifier: String?
    /// A list you can take in at a glance has nothing to search, and an
    /// empty field over five rows is a keyboard waiting to cover them
    /// (the SheetPickList rule).
    var searchPrompt: String?

    @State private var showingTray = false

    private var isActive: Bool { !selection.isEmpty }

    private var label: String {
        guard let only = selection.first, selection.count == 1 else {
            return isActive ? "\(name) · \(selection.count)" : name
        }
        return display(only)
    }

    var body: some View {
        Button {
            showingTray = true
        } label: {
            HStack(spacing: 5) {
                Text(label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .filterChipChrome(isActive: isActive)
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.selection, value: isActive)
        .accessibilityIdentifier(identifier ?? "facet\(name)")
        .accessibilityLabel("\(name) filter")
        .accessibilityValue(selection.isEmpty ? "Any" : selection.map(display).sorted().joined(separator: ", "))
        .sheet(isPresented: $showingTray) {
            // The HOST owns the stack (ui-interaction.md), and the
            // presentation modifiers sit outside it.
            NavigationStack {
                VStack(spacing: 0) {
                    SheetHeader(title: name, actionLabel: "Done") { showingTray = false }
                        .padding(18)
                    SheetPickList(
                        title: name,
                        sections: [SheetPickList.Section(title: nil, options: options.map {
                            SheetPickList.Option(id: $0.rawValue, name: display($0))
                        })],
                        selected: Set(selection.map(\.rawValue)),
                        searchPrompt: searchPrompt,
                        searchIdentifier: "facetPickSearchField"
                    ) { rawValue in
                        guard let value = options.first(where: { $0.rawValue == rawValue }) else { return }
                        if selection.contains(value) {
                            selection.remove(value)
                        } else {
                            selection.insert(value)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.background)
        }
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
            // Always active by construction — it only exists while something
            // is filtering — so it always wears the tinted glass.
            .filterChipChrome(isActive: true, horizontalPadding: 12)
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
