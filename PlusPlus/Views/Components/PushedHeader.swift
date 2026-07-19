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

    /// Owned here so the title can hide while the shared `HeaderSearchField`
    /// (which carries its own focus state) is expanded.
    @State private var searchExpanded = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .fullWidthSwipeBack()
            .onAppear {
                // A pre-seeded query (owned-tab "Add <query>" threading)
                // arrives with the field already open, so the active search
                // is visible instead of hidden behind the magnifier.
                if let search, !search.text.wrappedValue.isEmpty {
                    searchExpanded = true
                }
            }
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
                if let search {
                    // `HeaderSearchField` stays a SINGLE stable instance —
                    // its Spacer + trailing keys are conditionalized around
                    // it, NOT placed in a rival if/else arm. Splitting it
                    // across two arms gave the collapsed and expanded copies
                    // different identities, so the one-shot focus intent was
                    // dropped on expand and the keyboard never rose (#233,
                    // swift-reviewer catch 2026-07-18).
                    if !searchExpanded { Spacer(minLength: 0) }
                    HeaderSearchField(config: search, isExpanded: $searchExpanded)
                    if !searchExpanded { trailing }
                } else {
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}

/// The in-header search slot: binding + prompt + the field's
/// accessibility identifier (the collapsed key gets "\(id)Toggle").
struct HeaderSearchConfig {
    let text: Binding<String>
    let prompt: String
    let identifier: String
}

/// The one expanding in-header search affordance (2026-07-18), factored
/// out of `pushedScreenChrome` so pushed screens, tab roots, and sheets
/// all share it. Collapsed it is the magnifier toggle key; expanded it is
/// a field — magnifier + mono text + an in-field CLEAR key (`delete.left`,
/// a backspace glyph deliberately NOT an ✕ so it never duplicates the
/// collapse key) that empties the query and keeps you typing — plus a
/// separate `xmark` COLLAPSE key. `isExpanded` is a binding so the host
/// can hide its own title while the field is open; the one-shot focus
/// intent (#233) and the keyboard state (#213) live here.
///
/// ✕ here means "collapse the search", never "close the surface": a
/// sheet/tray dismisses with a text key, so the two never read alike.
struct HeaderSearchField: View {
    let config: HeaderSearchConfig
    @Binding var isExpanded: Bool

    /// One-shot focus intent, consumed by the field's onAppear — a focus
    /// request made before the view exists is silently dropped, and an
    /// unconditional onAppear re-summons the keyboard on pop-back (#233).
    @State private var wantsFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        if isExpanded {
            HStack(spacing: 10) {
                field
                // Closing the search is its own key, outside the field —
                // separate from the in-field clear, so emptying the query
                // and collapsing back to the icon are two distinct acts.
                HeaderIconButton(systemImage: "xmark", accessibilityLabel: "Close search", identifier: "dismissSearchButton") {
                    config.text.wrappedValue = ""
                    focused = false
                    withAnimation(Theme.Anim.standard) { isExpanded = false }
                }
            }
        } else {
            HeaderIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search", identifier: "\(config.identifier)Toggle") {
                wantsFocus = true
                withAnimation(Theme.Anim.standard) { isExpanded = true }
            }
        }
    }

    private var field: some View {
        let hasText = !config.text.wrappedValue.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(.footnote))
                .foregroundStyle(Theme.textFaint)
                .accessibilityHidden(true)
            TextField(config.prompt, text: config.text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityIdentifier(config.identifier)
                .onAppear {
                    if wantsFocus {
                        wantsFocus = false
                        focused = true
                    }
                }
                // A push while focused must not strand the keyboard (#213).
                .onDisappear { focused = false }
            if hasText {
                Button {
                    config.text.wrappedValue = ""
                    // Clearing is a within-field refinement, not an exit —
                    // keep focus so the keyboard stays up and typing resumes.
                    focused = true
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
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
    }
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
