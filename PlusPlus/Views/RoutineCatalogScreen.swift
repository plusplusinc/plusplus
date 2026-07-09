import SwiftUI
import SwiftData
import PlusPlusKit

/// The routine catalog (#223): a pushed browse surface off the
/// Routines tab, mirroring CatalogBrowseScreen's shape — top search,
/// then the facet chips, then the list. Filtering is four single-
/// select chips with anchored menus (no Filters sheet, no Apply —
/// a ~40-item in-memory list updates in a frame, and a batch sheet
/// is the Save button of filtering, see #219). An active chip shows
/// its VALUE in solid selection blue, so one glance reads the whole
/// filter state; facets AND together with the search text. Sort
/// lives in the toolbar, adjacent-but-distinct from narrowing.
struct RoutineCatalogScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    /// The Routines tab's NavigationPath — Add pushes the freshly
    /// instantiated routine's detail on top of the catalog.
    @Binding var path: NavigationPath

    @State private var search = ""
    @State private var focusFilter: RoutineTemplate.Focus?
    @State private var effortFilter: RoutineTemplate.Effort?
    @State private var timeFilter: TimeBand?
    @State private var gearFilter: GearFit?
    @State private var sort: CatalogSort = .featured
    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""

    enum TimeBand: String, CaseIterable, Hashable {
        case short = "Under 20 min"
        case medium = "20–40 min"
        case long = "40+ min"

        func contains(_ seconds: Int) -> Bool {
            switch self {
            case .short: seconds < 1200
            case .medium: (1200..<2400).contains(seconds)
            case .long: seconds >= 2400
            }
        }
    }

    // Not `case none`: inside a switch over GearFit?, `.none` resolves
    // to Optional.none and the compiler loses the case (CI catch).
    enum GearFit: String, CaseIterable, Hashable {
        case mine = "My equipment"
        case bodyweightOnly = "No equipment"
    }

    enum CatalogSort: String, CaseIterable {
        case featured = "Featured"
        case name = "Name"
        case time = "Time"
    }

    private var ownedEquipmentNames: Set<String> {
        Set(allEquipment.filter { $0.inLibrary || !$0.isBuiltIn }.map(\.name))
    }

    private var anyFilterActive: Bool {
        focusFilter != nil || effortFilter != nil || timeFilter != nil || gearFilter != nil
    }

    private var filteredTemplates: [RoutineTemplate] {
        let owned = ownedEquipmentNames
        var result = RoutineCatalog.all.filter { template in
            if let focusFilter, template.focus != focusFilter { return false }
            if let effortFilter, template.effort != effortFilter { return false }
            if let timeFilter, !timeFilter.contains(template.estimatedSeconds) { return false }
            switch gearFilter {
            case .mine:
                if !template.equipmentNames.allSatisfy(owned.contains) { return false }
            case .bodyweightOnly:
                if !template.equipmentNames.isEmpty { return false }
            case nil:
                break
            }
            if search.isEmpty { return true }
            let haystack = "\(template.name) \(template.summary) \(template.style.rawValue) \(template.blocks.flatMap(\.entries).map(\.exercise).joined(separator: " "))"
            return haystack.localizedCaseInsensitiveContains(search)
        }
        switch sort {
        case .featured: break
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .time: result.sort { $0.estimatedSeconds < $1.estimatedSeconds }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal scroll: four ACTIVE values plus the ✕ can
            // outgrow a compact row, and truncated values defeat the
            // whole glanceable-state point (reviewer catch).
            ScrollView(.horizontal, showsIndicators: false) {
                chipRow
                    .padding(.horizontal, 16)
            }
            .padding(.top, 6)

            List {
                createRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

                ForEach(filteredTemplates) { template in
                    templateRow(template)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if filteredTemplates.isEmpty {
                    VStack(spacing: 10) {
                        Text("Nothing matches.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textFaint)
                        if anyFilterActive {
                            Button("Clear filters") { clearFilters() }
                                .buttonStyle(.plain)
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.selected)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .padding(.top, 4)
        }
        .background(Theme.background)
        .navigationTitle("Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .pushedScreenChrome(onBack: { dismiss() })
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ExpandingSearchButton(prompt: "Search routines", text: $search, identifier: "routineCatalogSearchField")
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CatalogSort.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("catalogSortMenu")
            }
        }
        .navigationDestination(for: RoutineTemplate.self) { template in
            RoutineTemplateDetailScreen(template: template, path: $path)
        }
        .alert("New Routine", isPresented: $showingNewRoutine) {
            TextField("Name", text: $newRoutineName)
            Button("Cancel", role: .cancel) { newRoutineName = "" }
            Button("Create") { createBlankRoutine() }
        }
    }

    // MARK: - Facet chips

    private var chipRow: some View {
        HStack(spacing: 7) {
            if anyFilterActive {
                Button {
                    clearFilters()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("clearCatalogFilters")
                .transition(.opacity)
            }
            FacetChip(
                facet: "FOCUS",
                selection: $focusFilter,
                options: RoutineTemplate.Focus.allCases.map { ($0, $0.rawValue) }
            )
            FacetChip(
                facet: "EFFORT",
                selection: $effortFilter,
                options: RoutineTemplate.Effort.allCases.map { ($0, $0.rawValue) }
            )
            FacetChip(
                facet: "TIME",
                selection: $timeFilter,
                options: TimeBand.allCases.map { ($0, $0.rawValue) }
            )
            FacetChip(
                facet: "GEAR",
                selection: $gearFilter,
                options: GearFit.allCases.map { ($0, $0.rawValue) }
            )
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.15), value: anyFilterActive)
    }

    private func clearFilters() {
        focusFilter = nil
        effortFilter = nil
        timeFilter = nil
        gearFilter = nil
    }

    // MARK: - Rows

    private var createRow: some View {
        Button {
            showingNewRoutine = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(.caption, weight: .semibold))
                Text("New blank routine")
                    .font(.system(.footnote, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(Theme.borderStrong)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("createBlankRoutine")
    }

    private func templateRow(_ template: RoutineTemplate) -> some View {
        Button {
            path.append(template)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                Text(template.summary)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Text(metaLine(for: template))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func metaLine(for template: RoutineTemplate) -> String {
        var parts = [
            template.focus.rawValue.uppercased(),
            template.effort.rawValue.uppercased(),
            template.estimatedMinutesText.uppercased(),
        ]
        let gear = template.equipmentNames
        if gear.isEmpty {
            parts.append("NO GEAR")
        } else if gear.allSatisfy(ownedEquipmentNames.contains) {
            parts.append("YOUR GEAR ✓")
        } else {
            let missing = gear.filter { !ownedEquipmentNames.contains($0) }
            parts.append("NEEDS \(missing.prefix(2).joined(separator: ", ").uppercased())\(missing.count > 2 ? "…" : "")")
        }
        return parts.joined(separator: " · ")
    }

    private func createBlankRoutine() {
        let name = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRoutineName = ""
        guard !name.isEmpty else { return }
        let routine = Routine(name: Routine.uniqueName(name, among: routines), order: 0)
        modelContext.insert(routine)
        for existing in routines where existing !== routine {
            existing.order += 1
        }
        path.append(routine)
    }
}

/// One facet, single-select: at rest the chip shows its facet name in
/// quiet-terminal neutral; with a value picked it shows the VALUE in
/// solid selection blue (#210 — one glance reads the filter state).
/// Tapping anchors a native Menu with a checkmark on the current value
/// and "Any" to clear — never value-cycling, which is undiscoverable
/// and punishes overshoot.
private struct FacetChip<Value: Hashable>: View {
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
                // 44 pt, the #130 target standard — same height as the
                // picker's filter dropdowns doing the same job.
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

// MARK: - Template detail

/// Full template view: the block list reads like the routine detail
/// rail's order map, equipment shows ownership honestly, and Add is
/// the single primary action — instantiate, join the library, land in
/// the new routine (the fluid-nav promise).
struct RoutineTemplateDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    let template: RoutineTemplate
    @Binding var path: NavigationPath
    /// Add fires exactly once: a fast double-tap could otherwise
    /// instantiate twice against a stale routines query and mint the
    /// duplicate-name state #189 forbids (reviewer catch).
    @State private var added = false

    private var ownedEquipmentNames: Set<String> {
        Set(allEquipment.filter { $0.inLibrary || !$0.isBuiltIn }.map(\.name))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(template.focus.rawValue.lowercased()) · \(template.effort.rawValue.lowercased()) · \(template.style.rawValue.lowercased()) · \(template.estimatedMinutesText)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.bottom, 8)
                    Text(template.summary)
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)

                    SheetSectionLabel("EXERCISES (\(template.exerciseCount)) · \(template.totalSets) SETS")
                        .padding(.top, 24)
                    VStack(spacing: 0) {
                        ForEach(Array(template.blocks.enumerated()), id: \.offset) { index, block in
                            blockRow(block)
                            if index < template.blocks.count - 1 {
                                Divider().overlay(Theme.border)
                            }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                    SheetSectionLabel("EQUIPMENT")
                        .padding(.top, 24)
                    if template.equipmentNames.isEmpty {
                        Text("None — bodyweight only.")
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(template.equipmentNames, id: \.self) { name in
                                HStack(spacing: 7) {
                                    Image(systemName: ownedEquipmentNames.contains(name) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(.caption))
                                        .foregroundStyle(ownedEquipmentNames.contains(name) ? Theme.accent : Theme.textFaint)
                                    Text(name)
                                        .font(.system(.footnote))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                        }
                    }

                    SheetSectionLabel("MUSCLES")
                        .padding(.top, 24)
                    Text(template.muscleGroups.map(\.displayName).joined(separator: " · "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }

            // Add is the page's one action — bottom-docked like Start.
            Button {
                guard !added else { return }
                added = true
                let routine = template.instantiate(in: modelContext, among: routines)
                path.append(routine)
            } label: {
                Text(added ? "Added" : "Add to routines")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(added ? Theme.textFaint : Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(added ? Theme.surface : Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(added ? Theme.borderStrong : Color.clear))
            }
            .accessibilityIdentifier("addTemplateButton")
            .disabled(added)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .pushedScreenChrome(onBack: { dismiss() })
    }

    private func blockRow(_ block: RoutineTemplate.Block) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(block.entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(targetText(block: block, entry: entry))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 74, alignment: .leading)
                    Text(entry.exercise)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if block.entries.count > 1 {
                Text("SUPERSET")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .kerning(0.7)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func targetText(block: RoutineTemplate.Block, entry: RoutineTemplate.Entry) -> String {
        if let seconds = entry.durationSeconds {
            return "\(block.sets)×\(seconds)s"
        }
        if let reps = entry.reps {
            if let upper = entry.repsUpper {
                return "\(block.sets)×\(reps)–\(upper)"
            }
            return "\(block.sets)×\(reps)"
        }
        return "\(block.sets) sets"
    }
}
