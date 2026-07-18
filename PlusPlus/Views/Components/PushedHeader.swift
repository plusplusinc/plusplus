import SwiftUI

/// The pushed-screen chrome, Quiet Arcade edition (Dave's build-42
/// call: our own keys over Liquid Glass, for the toolbar and search
/// both). The system bar hides entirely; a custom header rides
/// `safeAreaInset` — a 44 pt raised back key, the title (+ optional
/// mono subtitle) truly centered, trailing raised keys, and on catalog
/// surfaces a search key that expands into a field replacing the title
/// (mock 06 — the expanded field carries an in-field clear, and
/// closing is a separate key beside it). Supersedes #198's glass chevron and #233's toolbar
/// search button; the full-width swipe-back is untouched — the #198
/// pan drives the navigation controller directly and never depended
/// on the bar being visible.
private struct PushedScreenChrome<Trailing: View>: ViewModifier {
    let title: String
    var subtitle: String?
    var search: HeaderSearchConfig?
    let onBack: () -> Void
    let trailing: Trailing

    @State private var searchExpanded = false
    /// One-shot focus intent, consumed by the field's onAppear — a
    /// focus request made before the view exists is silently dropped,
    /// and an unconditional onAppear re-summons the keyboard on
    /// pop-back (both #233 lessons, inherited).
    @State private var wantsFocus = false
    @FocusState private var searchFocused: Bool

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .fullWidthSwipeBack()
    }

    private var header: some View {
        ZStack {
            // The title centers on the SCREEN, not between whatever
            // keys happen to flank it. Side padding must clear the
            // WIDEST flanking group — two trailing keys are 98 pt —
            // or a long name truncates with its ellipsis hidden UNDER
            // a key cap (swift-reviewer math check).
            if !searchExpanded {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 100)
            }

            HStack(spacing: 10) {
                HeaderIconButton(systemImage: "chevron.left", accessibilityLabel: "Back", identifier: "backButton") {
                    onBack()
                }
                if searchExpanded, let search {
                    searchField(search)
                    // Closing the search is its own key, outside the field —
                    // separate from the in-field clear, so emptying the query
                    // and collapsing back to the icon are two distinct acts
                    // (2026-07-18, Apple's search pattern).
                    HeaderIconButton(systemImage: "xmark", accessibilityLabel: "Close search", identifier: "dismissSearchButton") {
                        search.text.wrappedValue = ""
                        searchFocused = false
                        withAnimation(Theme.Anim.standard) { searchExpanded = false }
                    }
                } else {
                    Spacer(minLength: 0)
                    if let search {
                        HeaderIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search", identifier: "\(search.identifier)Toggle") {
                            wantsFocus = true
                            withAnimation(Theme.Anim.standard) { searchExpanded = true }
                        }
                    }
                    trailing
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Theme.background)
    }

    /// Mock 06, clear/close split (2026-07-18): a 44 pt field where the
    /// title was — magnifier, mono text, and an in-field CLEAR key
    /// (`delete.left`, a backspace glyph read as "erase what I typed" —
    /// deliberately NOT an ✕, so it never reads as a duplicate of the
    /// close key beside it). It empties the query and keeps you typing;
    /// collapsing the search is the separate close key.
    private func searchField(_ search: HeaderSearchConfig) -> some View {
        let hasText = !search.text.wrappedValue.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
                .accessibilityHidden(true)
            TextField(search.prompt, text: search.text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .focused($searchFocused)
                .accessibilityIdentifier(search.identifier)
                .onAppear {
                    if wantsFocus {
                        wantsFocus = false
                        searchFocused = true
                    }
                }
                // A push while focused must not strand the keyboard
                // (the #213 lesson, inherited through two components).
                .onDisappear { searchFocused = false }
            if hasText {
                Button {
                    search.text.wrappedValue = ""
                    // Clearing is a within-field refinement, not an exit —
                    // keep focus so the keyboard stays up and typing resumes.
                    searchFocused = true
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textFaint)
                        // A full 44 pt tap target (HIG floor); the glyph sits
                        // at its trailing edge so it still reads near the
                        // field border, the tap area extending back over the
                        // text tail.
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear text")
                .accessibilityIdentifier("clearSearchButton")
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, hasText ? 10 : 13)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
    }
}

/// The in-header search slot: binding + prompt + the field's
/// accessibility identifier (the collapsed key gets "\(id)Toggle").
struct HeaderSearchConfig {
    let text: Binding<String>
    let prompt: String
    let identifier: String
}

/// A trailing header key wrapping a Menu — `.menuStyle(.button)` routes
/// the label through the raised-key ButtonStyle so menus press like
/// every other key.
struct HeaderMenuKey<Items: View>: View {
    let systemImage: String
    /// Spoken VoiceOver name for the menu (required).
    let accessibilityLabel: String
    var identifier: String?
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .menuStyle(.button)
        .buttonStyle(.raisedKey())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

extension View {
    /// One call per pushed screen: hidden system bar, the custom key
    /// header (back + centered title + optional search/trailing keys),
    /// whole-surface swipe-back.
    func pushedScreenChrome<Trailing: View>(
        title: String,
        subtitle: String? = nil,
        search: HeaderSearchConfig? = nil,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(PushedScreenChrome(
            title: title,
            subtitle: subtitle,
            search: search,
            onBack: onBack,
            trailing: trailing()
        ))
    }
}
