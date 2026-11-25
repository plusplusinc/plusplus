import DesignSystem
import SwiftUI

/// How the app looks, a sheet at full height only, opened from the drawer's Settings button over
/// the drawer, with an inline title and the system's Close leading and the drag indicator, as the
/// exercise sheet has. Two groups, each under its label in the headings' style: Appearance, the
/// system's segmented control as Log's tabs are drawn, Light, Dark, and Auto; and Theme, the
/// theme in use as its card (`ThemeCard`) with a chevron, which only opens the themes
/// (`ThemeScreen`), pushed on the sheet's own stack. A choice takes at once, with no Save: the
/// sheet and the app behind it recolor under the finger.
struct SettingsSheet: View {
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    @State private var isThemesPushed = false

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
                        ThemeCard(theme: look.theme, mark: .opens)
                    }
                    .buttonStyle(.card)
                    .accessibilityHint("Shows the themes")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(isPresented: $isThemesPushed) {
                ThemeScreen()
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
        // over a light window.
        .preferredColorScheme(look.colorScheme)
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

/// Every theme as its card, PlusPlus first, then by name, the one in use checked. A tap picks
/// one and does nothing else: the screen and the app recolor at once, the check moving to it.
struct ThemeScreen: View {
    @Environment(Look.self) private var look

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(Theme.all) { theme in
                    Button {
                        // No animation: the colors change at once. The check crossfades on its
                        // own (`ThemeCard`).
                        look.theme = theme
                    } label: {
                        ThemeCard(theme: theme, mark: .checked(theme == look.theme))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background { Color.pp(.background).ignoresSafeArea() }
        .sensoryFeedback(.selection, trigger: look.theme)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsSheet()
        .environment(Look(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
