import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// How the app looks, reached from the drawer as Log is, with ++ leading and an inline title.
/// Two groups, each under its label in the headings' style: Appearance, the system's segmented
/// control as Log's tabs are drawn, Light, Dark, and Auto; and Theme, the theme in use as its
/// card (`ThemeCard`) with a chevron, which only opens the themes (`ThemeScreen`), pushed with the
/// system push. A choice takes at once, with no Save: the app recolors under the finger.
struct SettingsScreen: View {
    @Bindable var session: AppSession
    @Environment(Look.self) private var look

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
                        session.openThemes()
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
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(isPresented: isThemesPushed) {
                ThemeScreen()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MenuButton(session: session)
                }
            }
        }
    }

    /// The themes pushed, which the back button and the back swipe pop.
    private var isThemesPushed: Binding<Bool> {
        Binding {
            session.screen == .theme
        } set: { isPushed in
            if isPushed {
                session.openThemes()
            } else {
                session.popThemes()
            }
        }
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
    SettingsScreen(
        session: AppSession(
            workout: .init(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
    )
    .environment(Look(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
