import SwiftUI
import SwiftData
import PlusPlusKit

/// A piece of equipment a routine needs that isn't in the active kit, wrapped
/// for `.sheet(item:)`. Identity is the name.
struct ResolveTarget: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

/// Pure resolution logic for a missing-equipment gap: which routes exist and
/// how each fares. Built from primitives (no `@Model`) so it's unit-testable.
struct EquipmentResolution {
    struct KitOption: Equatable { var name: String; var members: Set<String> }
    struct ExerciseNeed: Equatable { var name: String; var needs: Set<String> }
    struct Trade: Equatable { var kit: String; var lack: String; var exercise: String }

    /// The missing piece.
    var item: String
    /// Every piece the routine needs.
    var required: Set<String>
    /// The active kit's name (for prose).
    var activeKit: String
    /// The routine's exercises with the equipment each needs.
    var exercises: [ExerciseNeed]
    /// The user's OTHER kits (active excluded), in switch order.
    var otherKits: [KitOption]

    /// Routine exercises that use the missing item (unique, in routine order).
    var affected: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for entry in exercises where entry.needs.contains(item) {
            if seen.insert(entry.name).inserted { out.append(entry.name) }
        }
        return out
    }

    private func covers(_ kit: KitOption) -> Bool { required.isSubset(of: kit.members) }

    /// The cleanest switch: a kit that has the item AND covers everything else
    /// the routine needs. The hero action when it exists.
    var bestKit: String? {
        otherKits.first { $0.members.contains(item) && covers($0) }?.name
    }

    /// Kits that have the item but trade one gap for another — each named with
    /// the piece it lacks and an exercise that would then be short.
    var trades: [Trade] {
        otherKits.compactMap { kit in
            guard kit.members.contains(item), !covers(kit) else { return nil }
            let lacks = required.subtracting(kit.members).sorted()
            guard let lack = lacks.first else { return nil }
            let exercise = exercises.first { $0.needs.contains(lack) }?.name ?? ""
            return Trade(kit: kit.name, lack: lack, exercise: exercise)
        }
    }
}

/// The equipment-resolve sheet, "lead with the best fix" (2026-07-22): a hero
/// route up top (switch to a kit that covers everything, or add the piece),
/// then the other ways below — add to kit, switch to a kit that trades the
/// gap, or swap the moves for ones your kit can do. Opens from an amber
/// (not-in-kit) gear chip in the routine detail header.
struct EquipmentResolveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var routine: Routine
    let equipmentName: String

    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var showingSwap = false

    private var activeKit: EquipmentLibrary? {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)
    }
    private var activeKitName: String {
        activeKit?.name ?? EquipmentLibrary.defaultName
    }
    private var activeMembers: Set<String> { activeKit?.memberNames ?? [] }

    /// The routine slots that use the missing piece.
    private var affectedEntries: [RoutineExercise] {
        routine.sortedGroups.flatMap(\.sortedExercises).filter { entry in
            (entry.exercise?.equipment ?? []).contains { !$0.isDeleted && $0.name == equipmentName }
        }
    }

    private var resolution: EquipmentResolution {
        let needs: [EquipmentResolution.ExerciseNeed] = routine.sortedGroups
            .flatMap(\.sortedExercises)
            .compactMap { entry in
                guard let exercise = entry.exercise else { return nil }
                let names = exercise.equipment.filter { !$0.isDeleted }.map(\.name)
                return EquipmentResolution.ExerciseNeed(name: exercise.name, needs: Set(names))
            }
        let others = libraries
            .filter { $0 !== activeKit }
            .map { EquipmentResolution.KitOption(name: $0.name, members: $0.memberNames) }
        return EquipmentResolution(
            item: equipmentName,
            required: Set(routine.equipmentNames),
            activeKit: activeKitName,
            exercises: needs,
            otherKits: others
        )
    }

    var body: some View {
        let res = resolution
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Equipment", closeOnly: true) { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.notes)
                        .frame(width: 44, height: 44)
                        .background(Theme.notes.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)

                    Text("\(equipmentName) isn't in your kit")
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    Text(subtitle(res))
                        .font(.system(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)

                    hero(res).padding(.top, 18)

                    let more = moreWaysRows(res)
                    if !more.isEmpty {
                        SheetSectionLabel("MORE WAYS TO FIX THIS")
                            .padding(.top, 26)
                        moreWays(more).padding(.top, 8)
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
        .presentationDetents([.large])
        .sheet(isPresented: $showingSwap) {
            SwapMovesSheet(
                routine: routine,
                item: equipmentName,
                kitNames: activeMembers,
                catalog: allExercises,
                onApplied: { dismiss() }
            )
        }
    }

    // MARK: - Routes

    /// The active kit can gain a piece unless it's the immutable bodyweight
    /// (`null`) kit, whose membership writes no-op — offering "add" there
    /// would be a silent dead tap.
    private var canAddToActiveKit: Bool {
        !(activeKit?.isBodyweight ?? true)
    }

    /// When no kit covers the routine and the active kit can't take the piece
    /// (bodyweight), swapping the moves is the lead route.
    private func heroIsSwap(_ res: EquipmentResolution) -> Bool {
        res.bestKit == nil && !canAddToActiveKit && !affectedEntries.isEmpty
    }

    // MARK: - Hero (the cleanest fix)

    private func hero(_ res: EquipmentResolution) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CLEANEST FIX")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.notes)
                if let best = res.bestKit {
                    Text("Switch to the \(best) kit")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("It has \(equipmentName.lowercased()) and covers every other exercise in this routine too.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                } else if canAddToActiveKit {
                    Text("Add \(equipmentName.lowercased()) to \(activeKitName)")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Keep this routine exactly as it is.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Swap the \(affectedEntries.count) \(equipmentName.lowercased()) move\(affectedEntries.count == 1 ? "" : "s")")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your kit has no equipment, so replace these with moves you can do without it.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.notes.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.notes.opacity(0.4)))

            if let best = res.bestKit {
                primaryButton(title: "Switch to \(best)", systemImage: "arrow.left.arrow.right", tint: Theme.selected) {
                    switchKit(named: best)
                }
            } else if canAddToActiveKit {
                primaryButton(title: "Add \(equipmentName.lowercased()) to \(activeKitName)", systemImage: "plus", tint: Theme.accent) {
                    addToKit()
                }
            } else {
                primaryButton(title: "Swap the moves", systemImage: "arrow.triangle.2.circlepath", tint: Theme.selected) {
                    showingSwap = true
                }
            }
        }
    }

    // MARK: - More ways

    /// One "more ways" row, kept as data so dividers land only between rows.
    private struct RouteRow {
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
        let subtitleTint: Color
        let action: () -> Void
    }

    private func moreWaysRows(_ res: EquipmentResolution) -> [RouteRow] {
        var rows: [RouteRow] = []
        // Add-to-kit, unless it's the hero (bestKit == nil) or the kit can't take it.
        if canAddToActiveKit, res.bestKit != nil {
            rows.append(RouteRow(icon: "plus", tint: Theme.accent,
                                 title: "Add \(equipmentName.lowercased()) to \(activeKitName)",
                                 subtitle: "Keep this kit, add the piece",
                                 subtitleTint: Theme.textSecondary,
                                 action: { addToKit() }))
        }
        // Swap, unless it's the hero.
        if !affectedEntries.isEmpty, !heroIsSwap(res) {
            let count = affectedEntries.count
            rows.append(RouteRow(icon: "arrow.triangle.2.circlepath", tint: Theme.textSecondary,
                                 title: "Swap the \(count) \(equipmentName.lowercased()) move\(count == 1 ? "" : "s")",
                                 subtitle: "Pick replacements, or remove them",
                                 subtitleTint: Theme.textSecondary,
                                 action: { showingSwap = true }))
        }
        // Kits that have the piece but trade one gap for another.
        for trade in res.trades {
            let sub = trade.exercise.isEmpty
                ? "Adds \(equipmentName.lowercased()), but misses \(trade.lack.lowercased())"
                : "No \(trade.lack.lowercased()) for \(trade.exercise)"
            rows.append(RouteRow(icon: "arrow.left.arrow.right", tint: Theme.notes,
                                 title: "\(trade.kit) kit",
                                 subtitle: sub,
                                 subtitleTint: Theme.notes,
                                 action: { switchKit(named: trade.kit) }))
        }
        return rows
    }

    private func moreWays(_ rows: [RouteRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { divider }
                resolveRow(icon: row.icon, tint: row.tint, title: row.title,
                           subtitle: row.subtitle, subtitleTint: row.subtitleTint, action: row.action)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 56)
    }

    private func resolveRow(icon: String, tint: Color, title: String, subtitle: String, subtitleTint: Color = Theme.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.system(.caption))
                        .foregroundStyle(subtitleTint)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title).font(.system(.body, weight: .semibold))
            }
            .foregroundStyle(Theme.onSelected)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    // MARK: - Prose + actions

    private func subtitle(_ res: EquipmentResolution) -> String {
        let names = res.affected
        let verb = names.count == 1 ? "uses" : "use"
        return "\(listPhrase(names)) \(verb) it."
    }

    /// "Squat", "Squat and Deadlift", "Squat, Deadlift and Bench Press".
    private func listPhrase(_ names: [String]) -> String {
        switch names.count {
        case 0: return "This routine"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.dropLast().joined(separator: ", ")) and \(names.last ?? "")"
        }
    }

    private func switchKit(named name: String) {
        guard let target = libraries.first(where: { $0.name == name }) else { return }
        activeLibraryID = target.uuid.uuidString
        dismiss()
    }

    private func addToKit() {
        guard let piece = allEquipment.first(where: { $0.name == equipmentName }) else { return }
        activeKit?.setMembership(piece, true)
        dismiss()
    }
}

// MARK: - Swap step

/// The "swap the moves" step: for each routine slot using the missing piece,
/// pick a replacement that hits the same muscle group and your kit can do,
/// remove the slot, or keep it as is. Commits on Apply.
struct SwapMovesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var routine: Routine
    let item: String
    let kitNames: Set<String>
    let catalog: [Exercise]
    var onApplied: () -> Void

    /// Per slot: replace with a named exercise, remove, or keep.
    enum Choice: Equatable { case replace(String), remove, keep }

    @State private var choices: [PersistentIdentifier: Choice] = [:]

    private var affectedEntries: [RoutineExercise] {
        routine.sortedGroups.flatMap(\.sortedExercises).filter { entry in
            (entry.exercise?.equipment ?? []).contains { !$0.isDeleted && $0.name == item }
        }
    }

    private func alternatives(for entry: RoutineExercise) -> [Exercise] {
        guard let exercise = entry.exercise else { return [] }
        return ExerciseFilterState.kitDoableAlternatives(for: exercise, in: catalog, kit: kitNames)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Swap moves", closeOnly: true) { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pick a replacement for each move that needs \(item.lowercased()). These keep the same muscles with your kit.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    ForEach(affectedEntries, id: \.persistentModelID) { entry in
                        swapCard(entry)
                            .padding(.top, 18)
                    }
                }
                .padding(.bottom, 24)
            }

            Button {
                apply()
            } label: {
                Text("Apply changes")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.onSelected)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.selected, in: RoundedRectangle(cornerRadius: 13))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 18)
        .presentationBackground(Theme.background)
        .presentationDetents([.large])
        .onAppear(perform: seedDefaults)
    }

    @ViewBuilder
    private func swapCard(_ entry: RoutineExercise) -> some View {
        let alts = alternatives(for: entry)
        let name = entry.exercise?.name ?? "Exercise"
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("REPLACING")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                Text(name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(alts, id: \.persistentModelID) { alt in
                    optionRow(entry: entry, choice: .replace(alt.name), title: alt.name, subtitle: gearLine(alt), muscles: alt.muscleGroup.displayName)
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
                }
                optionRow(entry: entry, choice: .remove, title: "Remove from routine", subtitle: "Take \(name) out entirely", muscles: nil, destructive: true)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
                optionRow(entry: entry, choice: .keep, title: "Keep it anyway", subtitle: "Leave \(name) in, still needs \(item.lowercased())", muscles: nil)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func optionRow(entry: RoutineExercise, choice: Choice, title: String, subtitle: String, muscles: String?, destructive: Bool = false) -> some View {
        let selected = choices[entry.persistentModelID] == choice
        return Button {
            choices[entry.persistentModelID] = choice
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(destructive ? Theme.notes : Theme.textPrimary)
                    if let muscles {
                        HStack(spacing: 5) {
                            Text(muscles.lowercased())
                                .font(.system(.caption2))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                            Text(subtitle)
                                .font(.system(.caption2))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text(subtitle)
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(.body))
                    .foregroundStyle(selected ? Theme.selected : Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A one-word availability tag for an alternative: "bodyweight" or the
    /// piece(s) it needs (all in the kit by construction).
    private func gearLine(_ exercise: Exercise) -> String {
        let names = exercise.equipment.filter { !$0.isDeleted }.map(\.name)
        return names.isEmpty ? "bodyweight" : names.map { $0.lowercased() }.joined(separator: " · ")
    }

    private func seedDefaults() {
        for entry in affectedEntries where choices[entry.persistentModelID] == nil {
            if let first = alternatives(for: entry).first {
                choices[entry.persistentModelID] = .replace(first.name)
            } else {
                choices[entry.persistentModelID] = .keep
            }
        }
    }

    private func apply() {
        for entry in affectedEntries {
            switch choices[entry.persistentModelID] ?? .keep {
            case .keep:
                continue
            case .remove:
                routine.removeExercise(entry, context: modelContext)
            case .replace(let name):
                if let alt = catalog.first(where: { $0.name == name && !$0.isDeleted }) {
                    routine.replaceExercise(entry, with: alt)
                }
            }
        }
        onApplied()
    }
}
