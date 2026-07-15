import SwiftUI
import SwiftData
import PlusPlusKit

/// The Routines tab, v3 (#109): routine cards with equipment pills and
/// a contextual header + (new routine). Library/History/Settings left
/// this header with the nav restructure — Exercises and Equipment are
/// tabs, history lives on Today, settings opens from Today's header.
struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.order), SortDescriptor(\Routine.createdAt, order: .reverse)])
    private var routines: [Routine]

    @State private var path = NavigationPath()
    @State private var openSwipeRow: PersistentIdentifier?
    /// The routine just added from a template — scrolled into view and
    /// given an entrance flash when we land back on the library, then
    /// released (Dave, 2026-07-15). Permanent id (set post-save), so it is
    /// safe as list/scroll identity.
    @State private var newlyAdded: PersistentIdentifier?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    List {
                    ForEach(routines) { routine in
                        SwipeRevealRow(
                            id: routine.persistentModelID,
                            openRow: $openSwipeRow,
                            actionsWidth: 58,
                            onTap: { routine.uuid.map { path.append(RoutineRef(uuid: $0)) } },
                            accessibilityActions: [
                                SwipeRowAction(name: "Delete") {
                                    openSwipeRow = nil
                                    deleteRoutine(routine)
                                }
                            ]
                        ) {
                            RoutineCard(routine: routine, justAdded: routine.persistentModelID == newlyAdded)
                        } actions: {
                            SwipeActionButton(label: "DELETE", color: Theme.destructive) {
                                openSwipeRow = nil
                                deleteRoutine(routine)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                        .onMove(perform: moveRoutines)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // A template add pops back here and sets newlyAdded;
                    // let the pop settle, then scroll the new card into
                    // view (it lands at order 0 = top, but the list may
                    // have been scrolled) and release so the entrance
                    // flash can retrigger on the next add. Lifecycle-bound
                    // via .task(id:): leaving the tab or a rapid second add
                    // cancels this in flight, and the throwing sleeps bail
                    // in the catch WITHOUT clearing newlyAdded — so a
                    // superseding add keeps its own highlight (the repo's
                    // cancel-deferred-UI-on-disappear law, ui-interaction.md).
                    .task(id: newlyAdded) {
                        guard let id = newlyAdded else { return }
                        do {
                            try await Task.sleep(for: .milliseconds(350))
                            withAnimation(Theme.Anim.standard) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                            try await Task.sleep(for: .milliseconds(1500))
                        } catch {
                            return
                        }
                        newlyAdded = nil
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // A plain push, no hero zoom (Dave, build 37): the #216 zoom
            // made list -> detail read as a custom cover rather than a
            // navigation push. Today's zooms (committed card -> record,
            // pending card -> workout cover) are unchanged.
            .navigationDestination(for: RoutineRef.self) { ref in
                // Resolve the routine from its stable uuid (not by pushing
                // the @Model, whose persistentModelID can swap under the
                // push). A just-created routine resolves via a direct fetch.
                if let routine = modelContext.routine(uuid: ref.uuid) {
                    RoutineDetailView(routine: routine)
                }
            }
            // Registered at the stack root, NOT inside RoutineCatalogScreen:
            // a value destination declared on a screen that is itself pushed
            // (the catalog rides navigationDestination(isPresented:)) failed
            // to resolve in production — template taps hit SwiftUI's
            // missing-destination placeholder (build 33).
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $path) { routine in
                    // A template is complete on arrival, so return to the
                    // library with the new card highlighted rather than
                    // pushing into an empty-feeling detail (Dave,
                    // 2026-07-15). Popping the whole path also clears the
                    // catalog beneath, so Back is never stranded.
                    newlyAdded = routine.persistentModelID
                    path = NavigationPath()
                }
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No Routines",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Create your first routine to get started.")
                    )
                }
            }
            // The + pushes the routine catalog (#223) — the same
            // grammar as the library tabs: adding starts from a
            // browsable catalog, with blank creation as its first row.
            // A PATH entry, not isPresented (Dave, build 44): the
            // catalog appends templates/routines to this same path,
            // and a value appended beneath a boolean-presented screen
            // replaces it transition-less and double-pops on back.
            .navigationDestination(for: RoutineCatalogDestination.self) { _ in
                RoutineCatalogScreen(path: $path)
            }
        }
        .revealRoot(tab: "routines", atRoot: path.isEmpty)
        // Routine creates / deletes / reorders reach GitHub when you leave the
        // tab. Debounced + dirty-gated (see requestSync).
        .syncsProgramOnClose()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AppMenuKey()
                Spacer()
                HeaderIconButton(systemImage: "plus", accessibilityLabel: "New routine", identifier: "newRoutineButton") {
                    // Root-only affordance, so emptiness doubles as the
                    // double-tap guard (the addTemplateButton class): a
                    // second tap during the push must not stack a
                    // second catalog.
                    guard path.isEmpty else { return }
                    path.append(RoutineCatalogDestination())
                }
            }
            Text("Routines")
                .font(.system(.title, weight: .bold))
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        reindexRoutines()
    }

    private func moveRoutines(from source: IndexSet, to destination: Int) {
        var reordered = Array(routines)
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in reordered.enumerated() {
            routine.order = index
        }
    }

    private func reindexRoutines() {
        for (index, routine) in routines.enumerated() {
            routine.order = index
        }
    }
}

/// 44 pt square raised icon key used in tab headers (Quiet Arcade:
/// header icon buttons are neutral secondary keys — supersedes #202's
/// green header +; green's scope tightened to true data and in-list
/// creation rows).
struct HeaderIconButton: View {
    let systemImage: String
    /// Spoken VoiceOver name for the action (required — the glyph alone reads
    /// as its raw SF Symbol name, e.g. "slider horizontal 3").
    let accessibilityLabel: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

/// Plain content, deliberately NOT a Button: activation belongs to
/// SwipeRevealRow's onTap (see the component contract — a Button here
/// fired on reveal-drag release and closed the row it opened).
private struct RoutineCard: View {
    let routine: Routine
    /// True for the routine just added from a template — plays a one-shot
    /// entrance flash so the eye lands on it (Dave, 2026-07-15).
    var justAdded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 1 at the peak of the entrance flash, animating to 0 at rest.
    @State private var entrance: Double = 0
    @Query(sort: \EquipmentLibrary.order) private var libraries: [EquipmentLibrary]
    @AppStorage(EquipmentLibrary.activeIDKey) private var activeLibraryID = ""

    private var availableEquipmentNames: Set<String> {
        EquipmentLibrary.active(in: libraries, storedID: activeLibraryID)?.memberNames ?? []
    }

    private var estimateText: String {
        let minutes = max(5, Int((Double(routine.estimatedSeconds) / 300).rounded()) * 5)
        return "~\(minutes) min"
    }

    /// Up to three equipment pills plus a "+N" overflow — the taller
    /// card (#238) affords more than the old single row did.
    private var pills: [String] {
        let names = routine.equipmentNames
        guard !names.isEmpty else { return ["bodyweight"] }
        if names.count > 3 {
            return Array(names.prefix(3)) + ["+\(names.count - 3)"]
        }
        return names
    }

    /// A gear pill the active library doesn't have renders in notes
    /// amber (flag-don't-hide): the card still shows, but a glance says
    /// "not here". The synthetic "+N" and "bodyweight" pills are neutral.
    private func pillUnavailable(_ pill: String) -> Bool {
        guard pill != "bodyweight", !pill.hasPrefix("+") else { return false }
        return !availableEquipmentNames.contains(pill)
    }

    private var musclesLine: String {
        let present = Set(
            routine.sortedGroups.flatMap(\.sortedExercises).compactMap { $0.exercise?.muscleGroup }
        )
        let ordered = MuscleGroup.allCases.filter { present.contains($0) }
        guard !ordered.isEmpty else { return "no exercises yet" }
        return ordered.map { $0.displayName.lowercased() }.joined(separator: " · ")
    }

    /// Empty routines show nothing here — a "~5 min · 0 sets" claim
    /// above "no exercises yet" described a workout that doesn't exist.
    private var headerMeta: String {
        let exercises = routine.sortedGroups.flatMap(\.sortedExercises).count
        guard exercises > 0 else { return "" }
        let sets = routine.sortedGroups.reduce(0) { $0 + $1.sets * $1.sortedExercises.count }
        return "\(estimateText) · \(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) set\(sets == 1 ? "" : "s")"
    }

    var body: some View {
        // Up to four lines when populated (#238 gave the card room; the
        // workload facts then earned their own line to stop truncating):
        // identity, workload, what it hits, what it needs.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(routine.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            // Workload facts on their own full-width line. Sharing line
            // one with the name (even at layoutPriority(-1)) crushed
            // "~30 min · 5 exercises · 6 sets" to "~30 min · 5 e…"
            // whenever the name ran long — the same squeeze the detail
            // chrome hit in build-48, fixed the same way: give the facts
            // the full width instead of what's left beside the title.
            if !headerMeta.isEmpty {
                Text(headerMeta)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Text(musclesLine)
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            HStack(spacing: 5) {
                // Schedule pill first (#112): the cadence at a glance,
                // faint when the routine is unscheduled.
                Text(routine.schedule.shortLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(routine.schedule.normalized == .unscheduled ? Theme.textFaint : Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .overlay(Capsule().strokeBorder(Theme.border))
                    .lineLimit(1)
                ForEach(pills, id: \.self) { pill in
                    let unavailable = pillUnavailable(pill)
                    Text(pill)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(unavailable ? Theme.notes : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .overlay(Capsule().strokeBorder(unavailable ? Theme.notes.opacity(0.5) : Theme.borderStrong))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        // Entrance flash: a green (creation) ring plus a gentle pop that
        // settles to rest, so a template-added card announces itself. Green
        // is the creation hue (Theme.accent, the ++ grammar); no banner
        // needed. Set to full instantly, then eased to 0. The pop is
        // suppressed under Reduce Motion; the color fade is not vestibular.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(entrance)
        )
        .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * entrance)
        .onChange(of: justAdded, initial: true) { _, isNew in
            guard isNew else { return }
            entrance = 1
            withAnimation(.easeOut(duration: 0.9).delay(0.3)) { entrance = 0 }
        }
    }
}
