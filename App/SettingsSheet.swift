import DesignSystem
import SwiftUI

/// How the app looks, a sheet at full height only, opened from the drawer's Settings button over
/// the drawer, with an inline title and the system's Close leading and the drag indicator, as the
/// exercise sheet has. Two groups, each under its label in the headings' style: Appearance, the
/// system's segmented control as Log's tabs are drawn, Light, Dark, and Auto; and Theme, the
/// theme in use as its card (`ThemeCard`) with a chevron, which only opens the themes
/// (`ThemeScreen`), pushed on the sheet's own stack, which comes back here once one is picked. A
/// choice takes at once, with no Save: the sheet and the app behind it recolor under the finger.
struct SettingsSheet: View {
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isThemesPushed = false
    /// The phone's own light or dark, once read.
    @State private var phone: ColorScheme?

    var body: some View {
        @Bindable var look = look
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("Appearance")
                    Picker("Appearance", selection: $look.appearance) {
                        ForEach(Appearance.allCases, id: \.self) { appearance in
                            Text(appearance.name).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, Spacing.lg)
                    GroupLabel("Theme")
                    Button {
                        isThemesPushed = true
                    } label: {
                        // The theme in use, in the look the sheet itself is in.
                        ThemeCard(theme: look.theme, scheme: colorScheme, mark: .opens)
                    }
                    .buttonStyle(.card)
                    // What it sets, then the theme in use, as a settings row reads: "Theme,
                    // PlusPlus". Its looks are the Theme screen's to say.
                    .accessibilityLabel("Theme")
                    .accessibilityValue(look.theme.name)
                    .accessibilityHint("Shows the themes")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(isPresented: $isThemesPushed) {
                ThemeScreen(showing: look.theme)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // A sheet is a presentation of its own: the window's held scheme reached it as it
        // opened but not as it changed, and under PlusPlus a choice of Light left the sheet dark
        // over a light window. Nor does a sheet drop a scheme it was given when given nil, so on
        // Auto it is held to the phone's own: given nil, Dark then Auto on a light phone stayed
        // dark. Before the phone is read, nil, as the sheet opens following it.
        .preferredColorScheme(look.colorScheme ?? phone)
        .phoneScheme(Binding { phone ?? .dark } set: { phone = $0 })
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.background))
    }
}

/// A group's label on Settings: the headings' style, as "Also needs" is (`NeedsHeader`), a step
/// above its control.
private struct GroupLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.ppRowDetail)
            .fontWeight(.semibold)
            .foregroundStyle(.pp(.textSecondary))
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, Spacing.sm)
    }
}

/// Every theme as its card, PlusPlus first, then by name, the one in use outlined and checked.
/// It opens on the theme in use, its card scrolled to the middle (or as near as the list's ends
/// allow) before the first frame, so nothing scrolls as it arrives: the list's first position is
/// that card's id with a center anchor, which holds at any width and text size, not an offset.
///
/// A tap works as a picker that closes on its choice: the screen and the app recolor at once and
/// the outline and check move to the card, then, `pickedBeat` later, the screen goes back to
/// Settings, whose card shows the new theme. A tap on the theme in use goes back too; the back
/// button leaves with nothing changed. A second tap within the beat picks again and starts the
/// beat over. Each card shows the look Appearance calls for, the phone's on Auto, even under a
/// dark-only theme that holds the screen dark.
struct ThemeScreen: View {
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ColorScheme.dark
    @State private var position: ScrollPosition
    @State private var leaving: Task<Void, Never>?

    /// How long the picked card shows checked before the screen goes back: the check's
    /// crossfade (`tapChange`, 0.25 s) and a tenth of a second at rest, so the mark is seen to
    /// land and the app to recolor before the pop. Shorter, the pop began with the check still
    /// fading in; longer reads as a wait.
    static let pickedBeat: Duration = .milliseconds(350)

    init(showing current: Theme) {
        _position = State(initialValue: ScrollPosition(id: current.id, anchor: .center))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(Theme.all) { theme in
                    Button {
                        pick(theme)
                    } label: {
                        ThemeCard(
                            theme: theme,
                            scheme: theme.shownScheme(for: look.appearance, phone: phone),
                            mark: .checked(theme == look.theme),
                        )
                    }
                    .buttonStyle(.card)
                    .accessibilityHint("Uses this theme and goes back to Settings")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollPosition($position, anchor: .center)
        .background { Color.pp(.background).ignoresSafeArea() }
        .phoneScheme($phone)
        .sensoryFeedback(.selection, trigger: look.theme)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        // Left by the back button mid-beat: the pop is done, and a dismiss now would close the
        // sheet.
        .onDisappear { leaving?.cancel() }
    }

    private func pick(_ theme: Theme) {
        // No animation: the colors change at once. The check crossfades on its own
        // (`ThemeCard`).
        look.theme = theme
        leaving?.cancel()
        leaving = Task {
            guard await (try? Task.sleep(for: Self.pickedBeat, tolerance: .zero)) != nil else {
                return
            }
            dismiss()
        }
    }
}

#Preview {
    SettingsSheet()
        .environment(Look(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
