import SwiftUI
import SwiftData
import PlusPlusKit

/// Path marker for pushing the routine catalog. The catalog MUST ride
/// the value path, never navigationDestination(isPresented:): its
/// template taps and blank creation append to the same path, and a
/// value appended while a boolean-presented screen is on top replaces
/// it without a transition and double-pops on back (Dave, build 44).
/// Rule of thumb: a pushed screen that itself appends to the path must
/// itself be a path entry.
struct RoutineCatalogDestination: Hashable {
    /// Seeds the catalog's search (owned-tab "Add <query>" threads the
    /// Routines-tab query straight through, 2026-07-18); empty = fresh.
    var query: String = ""
}

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
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// The Routines tab's NavigationPath — Add pushes the freshly
    /// instantiated routine's detail on top of the catalog.
    @Binding var path: NavigationPath

    @State private var search = ""
    // FOCUS/EFFORT/TIME are multi-select — UNION within a facet, AND
    // across (#260, Dave's call; each template has one value per facet,
    // so intersection would always be empty). GEAR stays single-select:
    // its options are modes, not attributes ("My equipment" already
    // contains every bodyweight template).
    @State private var focusFilter: Set<RoutineTemplate.Focus> = []
    @State private var effortFilter: Set<RoutineTemplate.Effort> = []
    @State private var timeFilter: Set<TimeBand> = []
    /// Defaults to YOUR gear (#260): browsing opens on what you can
    /// actually do today — the lit chip, the ✕, and the escape line
    /// below the list all make the narrowing visible and reversible.
    @State private var gearFilter: GearFit? = .mine
    @State private var sort: CatalogSort = .featured
    @State private var showingLibraryTray = false
    @State private var showingNewRoutine = false
    @State private var newRoutineName = ""
    /// One-shot per appearance: path.append isn't idempotent the way
    /// the old isPresented boolean was, so a fast double-tap on a
    /// template row would stack two detail screens. Reset on pop-back
    /// via onAppear (fires on return — the #233 lesson proves it).
    @State private var pushedTemplate = false

    /// `initialQuery` seeds the search once at construction (owned-tab
    /// "Add <query>" threading); the pushed chrome auto-expands the field
    /// when it arrives non-empty, so the active query is visible.
    init(path: Binding<NavigationPath>, initialQuery: String = "") {
        self._path = path
        self._search = State(initialValue: initialQuery)
    }

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

    /// The routine catalog's kit lens: narrow to the active kit (`.mine`) or,
    /// as `nil`, drop the lens and show all routines. The bodyweight-only
    /// scope moved to the baked-in `null` kit (2026-07-21) — switch to it
    /// instead of a separate mode.
    enum GearFit: String, CaseIterable, Hashable {
        case mine = "My equipment"
    }

    enum CatalogSort: String, CaseIterable {
        case featured = "Featured"
        case name = "Name"
        case time = "Time"
    }

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    /// The active library's gear — what "my equipment" means everywhere.
    private var ownedEquipmentNames: Set<String> {
        activeLibrary?.memberNames ?? []
    }

    /// The switch strip names the kit the catalog judges routines against and
    /// switches it app-wide (2026-07-21 axes separation): switching lives here
    /// (the one shared tray), while the "Can do now" chip below is a pure local
    /// lens that never changes global scope.
    private var kitBar: some View {
        HStack(spacing: 8) {
            Text("Browsing")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
            LibrarySwitcherKey(
                name: activeLibrary?.name ?? EquipmentLibrary.defaultName,
                identifier: "routineKitSwitcher"
            ) {
                showingLibraryTray = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The ✕ appears only once the browse is narrowed past its default (your
    /// kit, no facets): a facet is set, or the kit lens is off-default.
    private var anyFilterActive: Bool {
        !focusFilter.isEmpty || !effortFilter.isEmpty || !timeFilter.isEmpty || gearFilter != .mine
    }

    private var filteredTemplates: [RoutineTemplate] {
        filtered(gearOverride: gearFilter)
    }

    /// How many templates ONLY the gear filter is hiding — the escape
    /// line's count (mirrors the exercise catalog's ownership hatch).
    private var hiddenByGear: Int {
        guard gearFilter != nil else { return 0 }
        return max(0, filtered(gearOverride: nil).count - filteredTemplates.count)
    }

    private func filtered(gearOverride: GearFit?) -> [RoutineTemplate] {
        let owned = ownedEquipmentNames
        // A template already in the library drops out of the catalog: the
        // detail's "Add" was only local view state, so an added routine
        // still read as addable (Dave, 2026-07-16). Matched by name — the
        // same key `instantiate`'s uniqueName dedups on; a routine renamed
        // away from its template frees the template to be added fresh again.
        let inLibrary = Set(routines.map { $0.name.lowercased() })
        var result = RoutineCatalog.all.filter { template in
            if inLibrary.contains(template.name.lowercased()) { return false }
            if !focusFilter.isEmpty, !focusFilter.contains(template.focus) { return false }
            if !effortFilter.isEmpty, !effortFilter.contains(template.effort) { return false }
            if !timeFilter.isEmpty, !timeFilter.contains(where: { $0.contains(template.estimatedSeconds) }) { return false }
            switch gearOverride {
            case .mine:
                if !template.equipmentNames.allSatisfy(owned.contains) { return false }
            case nil:
                break
            }
            return true
        }
        if !search.isEmpty {
            result = result.enumerated().compactMap { index, template in
                searchScore(template).map { (template: template, score: $0, index: index) }
            }
            // Relevance replaces FEATURED order while a search is live
            // (an explicit Name/Time sort still wins, below): a fuzzy
            // hit set is only trustworthy with its best matches on top.
            // Index tie-break because Swift doesn't promise sort stability.
            .sorted { a, b in a.score != b.score ? a.score > b.score : a.index < b.index }
            .map(\.template)
        }
        switch sort {
        case .featured: break
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .time: result.sort { $0.estimatedSeconds < $1.estimatedSeconds }
        }
        return result
    }

    /// The name is the headline: a hit anywhere else (summary, style,
    /// the exercise list) still shows the template, demoted below any
    /// name hit.
    private func searchScore(_ template: RoutineTemplate) -> Double? {
        let deep = "\(template.name) \(template.summary) \(template.style.rawValue) \(template.blocks.flatMap(\.entries).map(\.exercise).joined(separator: " "))"
        return [
            FuzzySearch.score(query: search, candidate: template.name),
            FuzzySearch.score(query: search, candidate: deep).map { $0 * 0.75 },
        ].compactMap { $0 }.max()
    }

    var body: some View {
        VStack(spacing: 0) {
            kitBar
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

                // Only under the MY-EQUIPMENT fit: "gear you don't
                // own" is false under No-equipment, where hiding gear-
                // users is the filter's whole job (swift-reviewer).
                // And only alongside visible rows — the empty state
                // below carries the count itself.
                if gearFilter == .mine, hiddenByGear > 0, !filteredTemplates.isEmpty {
                    // Quiet key (Quiet Arcade): the escape hatch reads
                    // as pressable without the retired link blue.
                    QuietKey(
                        label: "\(hiddenByGear) more need equipment you don't have · show",
                        identifier: "showUnavailableTemplates"
                    ) {
                        gearFilter = nil
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }

                if filteredTemplates.isEmpty {
                    VStack(spacing: 10) {
                        Text("Nothing matches.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textFaint)
                        if gearFilter == .mine, hiddenByGear > 0 {
                            QuietKey(
                                label: "\(hiddenByGear) match\(hiddenByGear == 1 ? "es" : "") need equipment you don't have · show",
                                identifier: "showUnavailableTemplatesEmpty"
                            ) {
                                gearFilter = nil
                            }
                        }
                        if anyFilterActive {
                            QuietKey(label: "Clear filters", identifier: "clearCatalogFilters") {
                                clearFilters()
                            }
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
        .onAppear { pushedTemplate = false }
        .pushedScreenChrome(
            title: "Routine catalog",
            search: HeaderSearchConfig(text: $search, prompt: "Search routines", identifier: "routineCatalogSearchField"),
            onBack: { dismiss() }
        )
        // ⚠️ No .navigationDestination(for: RoutineTemplate.self) here:
        // this screen is itself pushed (via RoutineCatalogDestination),
        // and a value destination declared on a pushed screen failed to
        // resolve in production (build 33: template taps hit SwiftUI's
        // missing-destination placeholder). The registration lives at each
        // owning stack's root — RoutineListView and TodayView.
        // Switching the active kit uses the one canonical tray (2026-07-21
        // axes separation), reached from the "Browsing" strip; the list
        // re-renders live behind it. The kit lens (the "Can do now" chip) is a
        // separate LOCAL filter that never switches.
        .sheet(isPresented: $showingLibraryTray) {
            EquipmentLibraryTray()
        }
        .alert("New routine", isPresented: $showingNewRoutine) {
            TextField("Name", text: $newRoutineName)
            Button("Cancel", role: .cancel) { newRoutineName = "" }
            Button("Create") { createBlankRoutine() }
        }
    }

    // MARK: - Facet chips

    private var chipRow: some View {
        HStack(spacing: 7) {
            if anyFilterActive {
                ClearAllChip { clearFilters() }
            }
            // A pure LOCAL availability lens (2026-07-21 axes separation):
            // narrow to routines you can do with the active kit, or clear it
            // to see all. Switching the kit itself is the strip above — a
            // filter never changes global scope.
            SelectableChip(label: "Can do now", isSelected: gearFilter == .mine) {
                gearFilter = gearFilter == .mine ? nil : .mine
            }
            MultiFacetChip(
                facet: "Focus",
                selection: $focusFilter,
                options: RoutineTemplate.Focus.allCases.map { ($0, $0.rawValue) },
                attributeSymbol: "target"
            )
            MultiFacetChip(
                facet: "Effort",
                selection: $effortFilter,
                options: RoutineTemplate.Effort.allCases.map { ($0, $0.rawValue) },
                attributeSymbol: "flame.fill",
                // A single-effort pick reads as an intensity ramp; a union
                // falls back to the flame.
                valueSymbols: [
                    .light: "thermometer.low",
                    .moderate: "thermometer.medium",
                    .intense: "thermometer.high",
                ]
            )
            MultiFacetChip(
                facet: "Time",
                selection: $timeFilter,
                options: TimeBand.allCases.map { ($0, $0.rawValue) },
                attributeSymbol: "clock"
            )
            // Sort rides the same row (#237) but stays neutral — see
            // FilterChips: ordering is not filter state.
            SortChip(selection: $sort, options: CatalogSort.allCases.map { ($0, $0.rawValue) })
            Spacer(minLength: 0)
        }
        .animation(Theme.Anim.standard, value: anyFilterActive)
    }

    /// Clearing returns to the DEFAULT browse (your kit, no facets), not to
    /// show-all: your kit is the resting scope.
    private func clearFilters() {
        focusFilter = []
        effortFilter = []
        timeFilter = []
        gearFilter = .mine
    }

    // MARK: - Rows

    /// Mirrors the exercise catalog's create key (#63): with a query
    /// live, the label telegraphs the prefilled name.
    private var createLabel: String {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return "Create \u{201C}\(trimmed.sentenceCasedFirst)\u{201D}" }
        return "New routine"
    }

    private var createRow: some View {
        // A searched-for routine that isn't in the catalog is probably the
        // one being created — the query seeds the name prompt (still fully
        // editable; Cancel clears it).
        CreateRow(label: createLabel, identifier: "createBlankRoutine") {
            newRoutineName = search.trimmingCharacters(in: .whitespacesAndNewlines)
            showingNewRoutine = true
        }
    }

    private func templateRow(_ template: RoutineTemplate) -> some View {
        Button {
            guard !pushedTemplate else { return }
            pushedTemplate = true
            path.append(template)
        } label: {
            // The shared routine-card body (2026-07-19): identity, prose,
            // then the capsule row (focus · effort · estimate · gear). No
            // schedule capsule — a template isn't scheduled, the one
            // necessary catalog↔library difference.
            RoutineCardContent(model: templateModel(template))
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }

    /// Gear reads exactly like the library card: each piece a soft tag,
    /// amber-washed when the active kit lacks it (no more "NEEDS X" verdict
    /// line). A gearless template shows one neutral "Bodyweight" tag.
    private func templateModel(_ template: RoutineTemplate) -> RoutineCardModel {
        let names = template.equipmentNames
        let gear: [(name: String, available: Bool)] = names.isEmpty
            ? [(name: "Bodyweight", available: true)]
            : names.map { (name: $0, available: ownedEquipmentNames.contains($0)) }
        return RoutineCardModel(
            title: template.name,
            prose: template.summary,
            schedule: nil,
            focus: template.focus.rawValue,
            effort: template.effort.rawValue,
            estimate: template.estimatedMinutesText,
            gear: gear
        )
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
        try? modelContext.save()
        // Blank creation still pushes into the new routine's detail (the
        // fluid-nav promise — an empty routine wants its exercises added
        // now), but REPLACE this catalog with the detail rather than
        // stacking on top of it: the detail then sits directly on the
        // library root, so its Back key — and a delete from its settings —
        // returns to the library, never to this catalog (Dave, 2026-07-15;
        // deleting a just-created routine used to strand the user on the
        // catalog level). Permanent id before the push (tray-flicker
        // class; swiftdata.md).
        guard let uuid = routine.uuid else { return }
        var collapsed = NavigationPath()
        collapsed.append(RoutineRef(uuid: uuid))
        path = collapsed
    }
}

// MARK: - Template detail

/// Full template view: the block list reads like the routine detail
/// rail's order map, equipment shows ownership honestly, and Add is
/// the single primary action — instantiate and join the library. Where
/// it lands afterwards is the host's call via `onAdded`: the Routines
/// library pops back to itself with the new card highlighted; Today
/// collapses to the new routine's detail on its own root. Absent an
/// `onAdded` the default is a plain push into the detail.
struct RoutineTemplateDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    let template: RoutineTemplate
    @Binding var path: NavigationPath
    /// How to navigate once the routine is instantiated. Absent this, the
    /// default is a plain push into the new routine's detail. Both hosts
    /// supply one: the Routines library pops back to itself and highlights
    /// the new card (a template arrives complete, so landing back in the
    /// library reads as "added" better than a fresh detail push); Today
    /// collapses the catalog/template out so the detail rests on its root
    /// (Dave, 2026-07-15).
    var onAdded: ((Routine) -> Void)? = nil
    /// Add fires exactly once: a fast double-tap could otherwise
    /// instantiate twice against a stale routines query and mint the
    /// duplicate-name state #189 forbids (reviewer catch).
    @State private var added = false
    @State private var showingGearCheck = false

    private var ownedEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    private var missingNames: [String] {
        template.equipmentNames.filter { !ownedEquipmentNames.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Name as a large, left-aligned wrapping body header
                    // (2026-07-18) — consistent with every other detail screen.
                    Text(template.name)
                        .font(.system(.title, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
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
                        Text("None · bodyweight only.")
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
                        // The unchecked circles are fixable HERE (#260):
                        // "turns out I do have a bench" is two taps,
                        // not a tab-switch expedition.
                        if !missingNames.isEmpty {
                            QuietKey(label: "Equipment check · mark what you have", identifier: "gearCheckButton") {
                                showingGearCheck = true
                            }
                            .padding(.top, 8)
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
            // Once added it lies flat (the disabled key spec: no plate,
            // border only, dimmed content).
            Button {
                guard !added else { return }
                added = true
                let routine = template.instantiate(in: modelContext, among: routines)
                // Permanent id before either navigation — see
                // createBlankRoutine (the tray-flicker class; swiftdata.md).
                try? modelContext.save()
                if let onAdded {
                    onAdded(routine)
                } else {
                    routine.uuid.map { path.append(RoutineRef(uuid: $0)) }
                }
            } label: {
                Text(added ? "Added" : "Add to routines")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(added ? Theme.textFaint : Theme.onPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(added ? Theme.surface : Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(added ? Theme.borderStrong : Color.clear))
            }
            .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
            .accessibilityIdentifier("addTemplateButton")
            .disabled(added)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background)
        .pushedScreenChrome(title: "", onBack: { dismiss() })
        .sheet(isPresented: $showingGearCheck) {
            GearCheckTray(names: missingNames)
        }
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
            // Same compact label the scrubber and detail rows speak —
            // a 90 s hold reads "1:30", not "90s".
            return "\(block.sets)×\(DurationTape.label(for: seconds))"
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

// MARK: - Gear check

/// A focused availability fix-up (#260): exactly the gear a template
/// needs and you don't have, as toggles — the direct path from "NEEDS
/// Bench" to having one here, without leaving the template. Toggling
/// writes membership in the ACTIVE equipment library, so the filter,
/// meta lines, and check circles all update live.
struct GearCheckTray: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    /// FROZEN at first presentation via @State's initialValue — a
    /// plain stored property re-derives when the presenting view
    /// invalidates (toggling membership does exactly that), and rows
    /// would vanish as they're toggled on: the #139 disappearing-act
    /// this tray exists to avoid (swift-reviewer catch).
    @State private var frozenNames: [String]

    @State private var showingCatalog = false

    init(names: [String]) {
        _frozenNames = State(initialValue: names)
    }

    private var activeLibrary: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Equipment check", closeOnly: true, action: { dismiss() })

            // Name the kit these toggles write to: the marks land in the
            // ACTIVE kit, so say which one (shared prose rule).
            Text("Marking what you have in \(EquipmentLibrary.activeNamePhrase(in: libraries, storedID: activeLibraryID)). It determines which exercises your routines can include.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)

            ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, equipment in
                    Toggle(isOn: Binding(
                        get: { activeLibrary?.contains(equipment) ?? false },
                        set: { activeLibrary?.setMembership(equipment, $0) }
                    )) {
                        Text(equipment.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.selected)
                    .accessibilityIdentifier("gearCheck-\(equipment.name)")
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    if index < rows.count - 1 {
                        Divider().overlay(Theme.border)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
            .padding(.top, 14)

            QuietKey(label: "Full equipment catalog", identifier: "gearCheckCatalogButton") {
                showingCatalog = true
            }
            .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingCatalog) {
            NavigationStack {
                EquipmentCatalogScreen()
            }
        }
    }

    private var rows: [Equipment] {
        frozenNames.compactMap { name in allEquipment.first { $0.name == name } }
    }
}
