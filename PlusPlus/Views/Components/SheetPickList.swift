import SwiftUI
import PlusPlusKit

/// A searchable MULTI-SELECT list, pushed from inside a sheet (Dave,
/// 2026-07-28). The multi-select sibling of `NavigationSelectRow`, and it
/// works the same way: the host wraps itself in a self-contained
/// `NavigationStack` with the root nav bar hidden, so its own `SheetHeader`
/// stays the header and only the pushed list wears a system bar.
///
/// ⚠️ **Drilling in inside a sheet is a `NavigationStack`, never a
/// hand-rolled stage slide.** The ZStack + `.move` transition idiom
/// (`ScheduleRoutineTray`, and `SwapInSheet` before its deletion) reads
/// janky and the reasons are
/// structural, not tunable: there is no interactive back-swipe, both stages
/// exist mid-transition so the sheet's height resolves to the taller one
/// and settles, the header sits outside the ZStack so the title hard-swaps
/// while the content slides, and VoiceOver gets a bare chevron instead of a
/// system Back carrying the origin's title. `NavigationStack` gives all of
/// that away for free, plus Reduce Motion and RTL.
///
/// What it replaces on the way in: a SwiftUI `Menu` over the equipment
/// catalog. Three things go wrong with a menu and all of them get worse the
/// longer the list is — it can't be searched, it closes on every pick (so
/// adding four pieces of equipment meant opening it four times), and it
/// shows no selection state, so it could only ever ADD and removal had to
/// live somewhere else entirely.
struct SheetPickList: View {
    struct Option: Identifiable, Equatable {
        let id: String
        let name: String

        init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        init(_ name: String) {
            self.init(id: name, name: name)
        }
    }

    /// A titled run. A list short enough to take in at a glance (the muscle
    /// groups) reads better grouped; a long one (the equipment catalog) is
    /// one flat alphabetical run you search, which is the presented-catalog
    /// law (2026-07-25).
    struct Section: Identifiable {
        let id: String
        let title: String?
        let options: [Option]

        init(title: String?, options: [Option]) {
            self.id = title ?? ""
            self.title = title
            self.options = options
        }
    }

    /// The pushed screen's nav-bar title.
    let title: String
    let sections: [Section]
    let selected: Set<String>
    /// nil means NO field: a list you can see all of has nothing to search,
    /// and an empty field over eleven rows is a keyboard waiting to cover
    /// them.
    var searchPrompt: String?
    var searchIdentifier = "sheetPickSearchField"
    /// Ids that can't be turned off right now — the last muscle group. They
    /// render disabled rather than swallowing the tap: a control that looks
    /// live and does nothing is the dead-tap class (build 76).
    var locked: Set<String> = []
    /// One line under the list, for the rule a locked row can't state.
    var note: String?
    let onToggle: (String) -> Void

    @State private var query = ""
    @State private var wantsFocus = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Searching collapses the sections into ONE ranked run: with a query
    /// the best match belongs at the top and section order would fight it,
    /// the same reason the catalogs drop their tiers while ranking.
    private var results: [Section] {
        guard !trimmedQuery.isEmpty else { return sections }
        let all = sections.flatMap(\.options)
        return [Section(title: nil, options: FuzzySearch.ranked(all, query: trimmedQuery) { $0.name })]
    }

    private var isEmpty: Bool {
        results.allSatisfy { $0.options.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let searchPrompt {
                SearchFieldBody(
                    config: HeaderSearchConfig(text: $query, prompt: searchPrompt, identifier: searchIdentifier),
                    wantsFocus: $wantsFocus
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isEmpty {
                        Text("Nothing matches.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                    }
                    ForEach(results) { section in
                        if let sectionTitle = section.title, !section.options.isEmpty {
                            SheetSectionLabel(sectionTitle)
                                .padding(.horizontal, 18)
                                .padding(.top, 18)
                                .padding(.bottom, 4)
                        }
                        ForEach(section.options) { option in
                            row(option)
                        }
                    }
                    if let note {
                        Text(note)
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            // The field is a keyboard magnet on a sheet; a scroll puts it
            // away, as under every search field in the app.
            .scrollDismissesKeyboard(.immediately)
        }
        // No explicit background: inherit the host sheet's presentation
        // background, exactly as `NavigationSelectRow`'s pushed list does.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ option: Option) -> some View {
        let isOn = selected.contains(option.id)
        let isLocked = locked.contains(option.id)
        return Button {
            onToggle(option.id)
        } label: {
            HStack(spacing: 10) {
                Text(option.name)
                    .font(.system(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The in-kit glyph (2026-07-17): membership reads as an
                // accent checkmark on the trailing edge, everywhere.
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.body))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked ? 0.5 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("pick-\(option.id)")
    }
}
