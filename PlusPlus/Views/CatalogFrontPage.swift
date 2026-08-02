import SwiftUI
import PlusPlusKit

/// The catalog's front matter (2026-08-02): what a scope's list adds up to,
/// and the axis values you can enter it by, above the list itself.
///
/// The problem it answers: with no query and no facet on, a catalog tab
/// showed row 1 of 347, alphabetical, which on Exercises means 90/90 Hip
/// Switch. Search is excellent once you know a name and the facet row is
/// precise once you speak the taxonomy, so the one arrival that had nothing
/// built for it was the one where you know neither.
///
/// ⚠️ It PREPENDS, it never replaces. The whole grouped list still follows
/// (navigation.md's "an empty query shows the scope's WHOLE list" stands),
/// which is what keeps three things working that a replacement would have
/// broken: routines' drag reorder (tab-only, empty-query-only, MINE-tier
/// only, so it has nowhere else to live), the missing-equipment disclosure,
/// and the facet row's pinned-header seat. `kitHint` is the precedent for
/// empty-query-only content injected before the sections.
///
/// It is also SELF-DISMISSING: a chip writes a facet, the facet makes
/// `filters.isEmpty(for:)` false, and the front matter gives way to the
/// narrowed list it just asked for. Read the other direction, this row IS
/// the facet row spelled out, for the arrival where a chevron chip that
/// opens a tray of words you don't know yet is no help.

/// What a scope states about itself. Built from the ENGINE's own results
/// (`FindOrCreateEngine.outcome` at empty query and no filters), never from
/// a parallel count over the `@Query` arrays: the tier rules, the
/// added-template dedup and the kit-doability verdict all already live
/// there, and a second implementation of them is a second answer waiting to
/// disagree with the list two rows below.
enum CatalogFrontMatter: Equatable {
    case exercises(CatalogReach)
    case kit(inKit: Int, total: Int, types: [TypeBucket])
    case routines(doable: Int, total: Int, focuses: [FocusBucket])

    struct TypeBucket: Equatable, Identifiable {
        let category: SeedData.EquipmentCategory
        let total: Int
        var id: String { category.rawValue }
    }

    struct FocusBucket: Equatable, Identifiable {
        let focus: RoutineTemplate.Focus
        let total: Int
        var id: String { focus.rawValue }
    }

    /// Nothing to say about a list with nothing in it.
    var isEmpty: Bool {
        switch self {
        case .exercises(let reach): return reach.total == 0
        case .kit(_, let total, _): return total == 0
        case .routines(_, let total, _): return total == 0
        }
    }

    static func make(
        scope: FindScope,
        sections: [FindOrCreateEngine.Section],
        kitNames: Set<String>
    ) -> CatalogFrontMatter {
        let results = sections.flatMap(\.results)
        switch scope {
        case .exercises:
            let features: [ExerciseSimilarityFeatures] = results.compactMap { result in
                guard case .exercise(let exercise) = result.item else { return nil }
                return ExerciseFilterState.similarityFeatures(exercise)
            }
            return .exercises(CatalogReachCalculator.reach(features, kit: kitNames))

        case .kit:
            var counts: [SeedData.EquipmentCategory: Int] = [:]
            var inKit = 0
            for result in results {
                guard case .equipment = result.item else { continue }
                if result.mine { inKit += 1 }
                // A custom piece carries no category and simply doesn't
                // appear on the row, the way it drops out under the facet.
                if let category = SeedData.equipmentCategory(named: result.name) {
                    counts[category, default: 0] += 1
                }
            }
            let types = SeedData.EquipmentCategory.allCases.compactMap { category -> TypeBucket? in
                guard let total = counts[category], total > 0 else { return nil }
                return TypeBucket(category: category, total: total)
            }
            return .kit(inKit: inKit, total: results.count, types: types)

        case .routines:
            var counts: [RoutineTemplate.Focus: Int] = [:]
            var doable = 0
            for result in results {
                let focus: RoutineTemplate.Focus?
                switch result.item {
                case .routine(let routine): focus = CatalogFilterState.resolvedFocus(routine)
                case .template(let template): focus = template.focus
                default: focus = nil
                }
                guard let focus else { continue }
                counts[focus, default: 0] += 1
                if result.doable { doable += 1 }
            }
            let focuses = RoutineTemplate.Focus.allCases.compactMap { focus -> FocusBucket? in
                guard let total = counts[focus], total > 0 else { return nil }
                return FocusBucket(focus: focus, total: total)
            }
            return .routines(doable: doable, total: results.count, focuses: focuses)
        }
    }
}

/// The rendered front matter: one statement, then a wrapping chip run per
/// axis. One `List` row holding the block, not a row per line — it is front
/// matter, and the separators between its parts would read as list rows.
struct CatalogFrontPage: View {
    let matter: CatalogFrontMatter
    /// The active kit named for prose, per the one-rule naming law: the
    /// generic possessive until a second kit exists, the name after.
    let kitPhrase: String
    @Binding var filters: CatalogFilterState

    /// `EquipmentLibrary.activeNamePhrase`'s own generic. When the phrase IS
    /// the generic, the sentence ends in plain words; when it is a NAME, the
    /// name wears the data tag and has to come last (KitNamePhrase's law).
    private var kitIsNamed: Bool { kitPhrase != EquipmentLibrary.genericNamePhrase }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statement
            switch matter {
            case .exercises(let reach):
                axis("BY MUSCLE", reach.byMuscle.map { bucket in
                    Entry(id: bucket.value.rawValue, label: bucket.value.displayName, count: bucket.total) {
                        filters.muscles = [bucket.value]
                    }
                })
                axis("BY MOVEMENT", reach.byPattern.map { bucket in
                    Entry(id: bucket.value.rawValue, label: bucket.value.displayName, count: bucket.total) {
                        filters.patterns = [bucket.value]
                    }
                })
            case .kit(_, _, let types):
                axis("BY TYPE", types.map { bucket in
                    Entry(id: bucket.id, label: bucket.category.rawValue, count: bucket.total) {
                        filters.equipmentCategories = [bucket.category]
                    }
                })
            case .routines(_, _, let focuses):
                axis("BY FOCUS", focuses.map { bucket in
                    Entry(id: bucket.id, label: bucket.focus.rawValue, count: bucket.total) {
                        filters.focuses = [bucket.focus]
                    }
                })
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - The statement

    /// Consequence first: what this catalog and this kit come to. The
    /// numbers are stated side by side and nothing is called missing (the
    /// anti-shame law) — a kit that does 83 of 347 is a kit that does 83
    /// exercises, not a kit short of 264.
    @ViewBuilder
    private var statement: some View {
        switch matter {
        case .exercises(let reach):
            if reach.doable == reach.noEquipment {
                // Bodyweight-only, which is a real answer and reads as one.
                sentence("\(counted(reach.doable, of: reach.total, .exercises)) need no equipment", tagged: false)
            } else {
                sentence("\(counted(reach.doable, of: reach.total, .exercises)) fit", tagged: true)
                caption("\(reach.noEquipment) need no equipment")
            }
        case .kit(let inKit, let total, _):
            if inKit == 0 {
                sentence("\(total) \(FindScope.kit.searchNoun(for: total)) in the catalog", tagged: false)
            } else {
                sentence("\(counted(inKit, of: total, .kit)) are in", tagged: true)
            }
        case .routines(let doable, let total, _):
            if doable == 0 {
                // The same escape the other two scopes take, and the tab
                // that needs it most: a fresh install's kit is empty until
                // Today's setup step fills it, so "0 of 56 routines fit
                // your kit" would open the surface with a subtraction
                // against something nobody has been asked to build yet.
                sentence("\(total) \(FindScope.routines.searchNoun(for: total)) in the catalog", tagged: false)
            } else {
                sentence("\(counted(doable, of: total, .routines)) fit", tagged: true)
            }
        }
    }

    /// "129 of 347 exercises". The noun comes from `FindScope.searchNoun(
    /// for:)` rather than being spelled here, so the front matter cannot
    /// drift from the vocabulary the rest of the surface counts in — the kit
    /// scope's "pieces" in particular is a decided word (#507: "equipment"
    /// is a mass noun and cannot take a bare numeral). It pluralizes off the
    /// TOTAL, which is the noun's real subject.
    private func counted(_ some: Int, of total: Int, _ scope: FindScope) -> String {
        "\(some) of \(total) \(scope.searchNoun(for: total))"
    }

    /// `tagged` says the sentence ends on the kit: when the kit is NAMED the
    /// name wears `KitTag` and must terminate the phrase; when it is the
    /// generic, the words finish the sentence themselves.
    @ViewBuilder
    private func sentence(_ text: String, tagged: Bool) -> some View {
        if tagged, kitIsNamed {
            KitNamePhrase(prefix: text, kit: kitPhrase)
                .accessibilityIdentifier("frontPageStatement")
        } else {
            Text(tagged ? "\(text) \(kitPhrase)" : text)
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("frontPageStatement")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Theme.textFaint)
    }

    // MARK: - The axes

    /// One axis value, carrying the facet write it performs. The write rides
    /// the entry rather than an index into the source array: a `ForEach` over
    /// `enumerated()` needs a tuple parameter Swift closures cannot
    /// destructure, and an index is one refactor away from pointing at the
    /// wrong bucket.
    private struct Entry: Identifiable {
        let id: String
        let label: String
        let count: Int
        let apply: () -> Void
    }

    /// One axis: an all-caps section label over a wrapping chip run. Chips
    /// are `SelectableChip` — the app's existing selectable-chip anatomy, so
    /// the front matter introduces no third tag tier. They render unselected
    /// by construction: any selection hides this whole block.
    ///
    /// ⚠️ Wrapping (`FlowLayout`), never a horizontal scroller. A scroller
    /// hides options behind a gesture, which is the opposite of the job, and
    /// the overflow row is the one component that writes `@State` from a
    /// `GeometryReader` — forbidden this deep in the `TabView` subtree
    /// (navigation.md's morph law).
    ///
    /// The count is the axis value's CATALOG total, not its kit-doable
    /// subset. Two reasons: a doable count reshuffles nothing but reads
    /// "Carry · 0" for a kit that has no loadable gear, which is a chip that
    /// opens a group with a disclosure and nothing above it; and the
    /// statement above already carries the kit frame, so the chips are free
    /// to say what the catalog holds.
    @ViewBuilder
    private func axis(_ title: String, _ entries: [Entry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SheetSectionLabel(title)
                FlowLayout(horizontalSpacing: 7, verticalSpacing: 0) {
                    ForEach(entries) { entry in
                        SelectableChip(
                            label: "\(entry.label) · \(entry.count)",
                            isSelected: false,
                            identifier: "frontPageChip-\(entry.id)"
                        ) {
                            withAnimation(Theme.Anim.standard) { entry.apply() }
                        }
                    }
                }
                // ⚠️ `.plain`, never the default — the build-12 class
                // (`catalogRow` carries the same warning, and every other
                // control that is a row in THIS list declares a non-automatic
                // style). Inside a `List`, row taps route into default-styled
                // buttons anywhere in the row, and this row is a ~200 pt block
                // that is mostly NOT chips: the statement, the caption, the
                // section labels and the ragged end of every wrapped chip line.
                // A tap on any of them would write a facet nobody chose, and
                // since the block is self-dismissing the list would then narrow
                // with no visible cause. `SelectableChip` brings all its own
                // chrome, so plain looks identical. ⚠️ Here, not on the
                // component: its other two call sites are in `ScrollView`s and
                // rely on the automatic style's press fade.
                .buttonStyle(.plain)
            }
        }
    }
}
