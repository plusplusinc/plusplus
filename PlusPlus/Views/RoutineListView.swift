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
    @State private var showingCatalog = false
    @State private var openSwipeRow: PersistentIdentifier?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                List {
                ForEach(routines) { routine in
                    SwipeRevealRow(
                        id: routine.persistentModelID,
                        openRow: $openSwipeRow,
                        actionsWidth: 58,
                        onTap: { path.append(routine) }
                    ) {
                        RoutineCard(routine: routine)
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
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            // A plain push, no hero zoom (Dave, build 37): the #216 zoom
            // made list -> detail read as a custom cover rather than a
            // navigation push. Today's zooms (committed card -> record,
            // pending card -> workout cover) are unchanged.
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(routine: routine)
            }
            // Registered at the stack root, NOT inside RoutineCatalogScreen:
            // a value destination declared on a screen that is itself pushed
            // (the catalog rides navigationDestination(isPresented:)) failed
            // to resolve in production — template taps hit SwiftUI's
            // missing-destination placeholder (build 33).
            .navigationDestination(for: RoutineTemplate.self) { template in
                RoutineTemplateDetailScreen(template: template, path: $path)
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
            .navigationDestination(isPresented: $showingCatalog) {
                RoutineCatalogScreen(path: $path)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HeaderGlyph()
                Spacer()
                HeaderIconButton(systemImage: "plus", identifier: "newRoutineButton") {
                    showingCatalog = true
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
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

/// Plain content, deliberately NOT a Button: activation belongs to
/// SwipeRevealRow's onTap (see the component contract — a Button here
/// fired on reveal-drag release and closed the row it opened).
private struct RoutineCard: View {
    let routine: Routine

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
        // Three lines (#238 — the single row was cramped): identity,
        // what it hits, what it needs.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(routine.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(headerMeta)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .layoutPriority(-1)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
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
                    Text(pill)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .overlay(Capsule().strokeBorder(Theme.borderStrong))
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
    }
}
