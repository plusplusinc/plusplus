import DesignSystem
import SwiftUI

/// How the app looks, a sheet at full height only, opened from the drawer's Settings button over
/// the drawer, with an inline title and the system's Close leading and the drag indicator, as the
/// exercise sheet has. One group under its label in the headings' style: Appearance
/// (`AppearanceChoice`), Light, Dark, Auto, and Black belt. A choice takes at once, with no Save:
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
                    AppearanceChoice(selection: $look.appearance)
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
        .preferredColorScheme(look.appearance.colorScheme ?? phone)
        .phoneScheme(Binding { phone ?? .dark } set: { phone = $0 })
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetGround()
    }
}

/// The four appearances, in order, as the system's segmented control, as Log's tabs are drawn.
struct AppearanceChoice: View {
    @Binding var selection: Appearance

    var body: some View {
        Picker("Appearance", selection: $selection) {
            ForEach(Appearance.allCases, id: \.self) { appearance in
                Text(appearance.name).tag(appearance)
            }
        }
        .pickerStyle(.segmented)
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
