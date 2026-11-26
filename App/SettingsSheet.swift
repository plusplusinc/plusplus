import DesignSystem
import SwiftUI

/// How the app looks, a sheet at full height only, opened from the drawer's Settings button over
/// the drawer, with an inline title and the system's Close leading and the drag indicator, as the
/// exercise sheet has. One group under its label in the headings' style: Appearance
/// (`AppearanceChoice`): Light and Dark, Automatic, and Black belt. A choice takes at once, with no
/// Save:
/// the sheet and the app behind it recolor under the finger.
struct SettingsSheet: View {
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    /// The phone's own light or dark, once read.
    @State private var phone: ColorScheme?

    var body: some View {
        @Bindable var look = look
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("Appearance")
                    AppearanceChoice(look: look, phone: phone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // A sheet is a presentation of its own: the window's held scheme reached it as it
        // opened but not as it changed, and a choice of Light left the sheet dark over a light
        // window. Nor does a sheet drop a scheme it was given when given nil, so on Auto it is
        // held to the phone's own: given nil, Dark then Auto on a light phone stayed dark.
        // Before the phone is read, nil, as the sheet opens following it.
        .preferredColorScheme(look.colorScheme ?? phone)
        .phoneScheme($phone)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetGround()
    }
}

/// Appearance as iOS's Display & Brightness lays out its own: one card, the two looks' pictures
/// side by side (`AppearancePicture`), then the system's switches, Automatic ("Follows your
/// phone") and Black belt ("True black when dark"), split by the separator. With Automatic on,
/// the chosen picture is the look in effect now, and tapping one holds it and turns Automatic
/// off; turned off, the look in effect stays. Black belt draws the dark picture in its colors.
struct AppearanceChoice: View {
    let look: Look
    /// The phone's own light or dark, once read.
    let phone: ColorScheme?

    var body: some View {
        let shown = look.shown(phone: phone)
        let shape = RoundedRectangle(cornerRadius: Spacing.sm + Radius.key, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Appearance.allCases, id: \.self) { appearance in
                    AppearancePicture(
                        appearance,
                        isChosen: shown == appearance,
                        isBlackBelt: look.isBlackBelt,
                    ) {
                        look.choose(appearance)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Spacing.md)
            .sensoryFeedback(.selection, trigger: shown)
            Divider().overlay(Color.pp(.separator))
            SwitchRow(
                "Automatic",
                line: "Follows your phone",
                isOn: Binding { look.isAutomatic } set: { look.setAutomatic($0, phone: phone) },
            )
            Divider().overlay(Color.pp(.separator))
            SwitchRow(
                "Black belt",
                line: "True black when dark",
                isOn: Binding { look.isBlackBelt } set: { look.isBlackBelt = $0 },
            )
        }
        .padding(.horizontal, Spacing.md)
        .background(shape.fill(.pp(.surface)))
    }
}

/// A switch on the Appearance card: its name at a row title's size and a line under it in the
/// secondary text color, the system's switch trailing.
private struct SwitchRow: View {
    let title: LocalizedStringKey
    let line: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, line: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        self.line = line
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.ppRowTitle)
                    .foregroundStyle(.pp(.textPrimary))
                Text(line)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
            }
        }
        .padding(.vertical, Spacing.sm + Spacing.xs)
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

#Preview {
    SettingsSheet()
        .environment(Look(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
