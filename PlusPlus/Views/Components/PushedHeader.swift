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

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // ⚠️ The app supplies the BACK button rather than inheriting the
            // system's, and that is not a style preference. Two of these
            // screens are sheet ROOTS in some hosts (the presented catalog is
            // pushed by Today but sheeted by the drawer and by template
            // detail), and a stack root has no system back button at all — so
            // inheriting it would leave those hosts with nothing but the
            // sheet's swipe-down. One leading item works in both shapes, and
            // it keeps `onBack` running, which several of these screens use to
            // commit a rename and drop focus.
            //
            // The COST, accepted: a fully native pushed screen shows a back
            // button carrying the PREVIOUS screen's title. This shows a bare
            // chevron. Revisit if these screens ever stop being sheet roots.
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("backButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // A single item holding the group: the call sites pass
                    // one or two keys, and the toolbar spaces its own.
                    HStack(spacing: 2) { trailing }
                }
            }
            .modifier(PushedSubtitle(subtitle: subtitle))
            .modifier(PushedSearch(config: search))
            // NOT part of the header — a gesture, and it works whether or not
            // the bar is visible (#198 drives the navigation controller
            // directly). Routine detail has carried both together since
            // 2026-07-29, so the pairing is proven.
            .fullWidthSwipeBack()
    }
}

/// iOS 26's second title line, where a screen has one. Split out because the
/// modifier is unavailable below 26 and returns a different concrete type.
private struct PushedSubtitle: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        if let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

/// The presented catalog's field, now the SYSTEM's — the same `.searchable`
/// the tab roots take, so every search surface in the app is one mechanism.
/// ⚠️ `.searchToolbarBehavior(.minimize)` is deliberately NOT applied here:
/// these screens have no tab bar under them, so the field belongs in the
/// navigation bar where it lands by default.
///
/// ⚠️ `config.identifier` is DROPPED on this path — `.searchable` names its own
/// element and takes no identifier. The field is reachable as
/// `app.searchFields.firstMatch`, which is what the smoke tests already use;
/// the identifier still matters to `SearchFieldBody`'s remaining mount.
private struct PushedSearch: ViewModifier {
    let config: HeaderSearchConfig?

    func body(content: Content) -> some View {
        if let config {
            content.searchable(text: config.text, prompt: config.prompt)
        } else {
            content
        }
    }
}

/// The in-header search slot: binding + prompt + the field's
/// accessibility identifier (the collapsed key gets "\(id)Toggle").
struct HeaderSearchConfig {
    let text: Binding<String>
    let prompt: String
    let identifier: String
}

/// The search-field BODY — the app's own field anatomy (surface fill,
/// borderStrong stroke, r11, mono text, magnifier lead) with its in-field
/// CLEAR key and focus plumbing.
///
/// ⚠️ ONE consumer left (spike, 2026-08-02): the PICKER sheet, whose field
/// sits at the bottom within thumb reach. Every other search surface is the
/// system's `.searchable` now — the tab roots, and the pushed catalog via
/// `pushedScreenChrome`. `HeaderSearchField`, the magnifier that expanded into
/// this, is deleted with them. The one-shot
/// focus intent (#233) rides a binding: hosts arm it before the field
/// exists (consumed in onAppear) OR while it is on screen (consumed in
/// onChange — the "type a name first" refocus).
struct SearchFieldBody: View {
    let config: HeaderSearchConfig
    @Binding var wantsFocus: Bool
    @FocusState private var focused: Bool

    /// ⚠️ ONE anatomy again (spike, 2026-08-02): the floating key is the
    /// SYSTEM's `.searchable` field now, so this body serves only app-drawn
    /// chrome — pushed catalogs, pickers and sheets — and the mono-is-DATA law
    /// binds all of them without exception. The glass/native variant that used
    /// to be selected by a `glass:` pairing went with the hand-built dock.
    private let height: CGFloat = 44
    private let textFont: Font = .system(.footnote, design: .monospaced)
    private let glyphFont: Font = .system(.footnote)
    private let leadingInset: CGFloat = 13
    private let trailingInset: CGFloat = 13

    var body: some View {
        let hasText = !config.text.wrappedValue.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(glyphFont)
                .foregroundStyle(Theme.textFaint)
                .accessibilityHidden(true)
            TextField(config.prompt, text: config.text)
                .font(textFont)
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityIdentifier(config.identifier)
                // No Return action anywhere (Dave, 2026-07-26): submitting a
                // search puts the keyboard away, it doesn't choose a result.
                .onAppear {
                    if wantsFocus {
                        wantsFocus = false
                        focused = true
                    }
                }
                .onChange(of: wantsFocus) { _, wants in
                    guard wants else { return }
                    wantsFocus = false
                    focused = true
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
                        .font(glyphFont)
                        .foregroundStyle(Theme.textFaint)
                        // A full-height tap target (HIG floor); the glyph sits
                        // at its trailing edge so it still reads near the
                        // field border, the tap area extending back over the
                        // text tail.
                        //
                        // ⚠️ `.contentShape` is what makes the transparent part
                        // of this frame tappable AT ALL — a `.frame()` around an
                        // `Image` is layout space, not content, and SwiftUI hit
                        // tests the content. The dock's ✕ shipped without it on
                        // build 171 and its tappable area was the glyph's own
                        // strokes; taps around it fell through to the list, or
                        // landed on THIS key and read as "the ✕ does nothing".
                        .frame(width: height, height: height, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear text")
                .accessibilityIdentifier("clearSearchButton")
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, hasText ? trailingInset : leadingInset)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
    }
}


/// A trailing header key wrapping a Menu — `.menuStyle(.button)` routes the
/// label through the button style so menus press like every other key.
struct HeaderMenuKey<Items: View>: View {
    let systemImage: String
    /// Spoken VoiceOver name for the menu (required).
    let accessibilityLabel: String
    var identifier: String?
    var chrome: HeaderKeyChrome = .raised
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            if chrome == .toolbar {
                Image(systemName: systemImage)
            } else {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
            }
        }
        .modifier(RaisedMenuUnlessToolbar(chrome: chrome))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? systemImage)
    }
}

private struct RaisedMenuUnlessToolbar: ViewModifier {
    let chrome: HeaderKeyChrome

    func body(content: Content) -> some View {
        if chrome == .toolbar {
            content
        } else {
            content.menuStyle(.button).buttonStyle(.raisedKey())
        }
    }
}

extension View {
    /// One call per pushed screen: the SYSTEM navigation bar with an inline
    /// title, an app-supplied back item (see `PushedScreenChrome` for why),
    /// native trailing keys, optional `.searchable`, and the whole-surface
    /// swipe-back.
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
