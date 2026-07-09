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
    /// Hero zoom (#216): the card IS the detail screen, so opening one
    /// grows it in place instead of sliding a stranger in.
    @Namespace private var zoomNamespace

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                List {
                ForEach(routines) { routine in
                    RoutineCard(routine: routine) {
                        path.append(routine)
                    }
                    .matchedTransitionSource(id: routine.persistentModelID, in: zoomNamespace)
                    // Native swipe (#231); no full swipe — deleting a
                    // routine is a real decision, not a flick.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteRoutine(routine)
                        } label: {
                            Label("Delete", systemImage: "trash")
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
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(routine: routine)
                    .navigationTransition(.zoom(sourceID: routine.persistentModelID, in: zoomNamespace))
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
                HeaderIconButton(systemImage: "plus", identifier: "newRoutineButton", tint: Theme.accent) {
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

/// 44 pt round icon button used in tab headers (HIG minimum target).
struct HeaderIconButton: View {
    let systemImage: String
    var identifier: String?
    /// Glyph color — creation buttons pass the data green (#202).
    var tint: Color = Theme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

private struct RoutineCard: View {
    let routine: Routine
    let onOpen: () -> Void

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

    private var setsSummary: String {
        let exercises = routine.sortedGroups.flatMap(\.sortedExercises).count
        let sets = routine.sortedGroups.reduce(0) { $0 + $1.sets * $1.sortedExercises.count }
        return "\(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) sets"
    }

    var body: some View {
        Button(action: onOpen) {
            // Three lines (#238 — the single row was cramped): identity,
            // what it hits, what it needs.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routine.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(estimateText) · \(setsSummary)")
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
        .buttonStyle(.plain)
    }
}
