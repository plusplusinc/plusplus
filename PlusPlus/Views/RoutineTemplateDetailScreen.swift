import SwiftUI
import SwiftData
import PlusPlusKit

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
                .padding(.horizontal, 18)

            // Name the kit these toggles write to: the marks land in the
            // ACTIVE kit, so say which one (shared prose rule).
            Text("Marking what you have in \(EquipmentLibrary.activeNamePhrase(in: libraries, storedID: activeLibraryID)). It determines which exercises your routines can include.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 6)
                .padding(.horizontal, 18)

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
            .padding(.horizontal, 18)
            .padding(.top, 14)

            QuietKey(label: "Full equipment catalog", identifier: "gearCheckCatalogButton") {
                showingCatalog = true
            }
            .padding(.top, 10)
            .padding(.horizontal, 18)
            }

            Spacer(minLength: 0)
        }
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
