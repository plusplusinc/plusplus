import DesignSystem
import Session
import SwiftUI

/// How the app looks, a sheet at full height only, opened from the drawer's Settings button over
/// the drawer, with an inline title and the system's Close leading and the drag indicator, as the
/// exercise sheet has. One group under its label in the headings' style: Appearance
/// (`AppearanceChoice`): Light and Dark, Automatic, and Void. A choice takes at once, with no
/// Save:
/// the sheet and the app behind it recolor under the finger.
struct SettingsSheet: View {
    let health: HealthSaving
    @Environment(Look.self) private var look
    @Environment(\.dismiss) private var dismiss
    /// The phone's own light or dark, once read.
    @State private var phone: ColorScheme?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("Appearance")
                    AppearanceChoice(look: look, phone: phone)
                    if health.access != .unavailable {
                        GroupLabel("Apple Health")
                            .padding(.top, Spacing.lg)
                        HealthChoice(health: health)
                    }
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
        // window. Nor does a sheet drop a scheme it was given when given nil, so with Automatic on
        // it is held to the phone's own: given nil, Dark then Automatic on a light phone stayed
        // dark.
        // Before the phone is read, nil, as the sheet opens following it.
        .preferredColorScheme(look.colorScheme ?? phone)
        .phoneScheme($phone)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetGround()
    }
}

/// Appearance as iOS's Display & Brightness lays out its own: one card, the two looks' pictures
/// side by side (`AppearancePicture`), then the system's switches, Automatic and Void, split by
/// the separator. With Automatic on, the chosen picture is the look in effect now, and tapping
/// one holds it and turns Automatic off; turned off, the look in effect stays. Void draws the
/// dark picture in its colors. Void's row shows only where it can do something
/// (`Look.offersVoid`): with Light held it goes, the card's height closing on `.snappy` as the
/// row fades in place, nothing else moving; with Reduce Motion, a crossfade.
struct AppearanceChoice: View {
    let look: Look
    /// The phone's own light or dark, once read.
    let phone: ColorScheme?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shown = look.shown(phone: phone)
        let shape = RoundedRectangle(cornerRadius: Spacing.sm + Radius.key, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Appearance.allCases, id: \.self) { appearance in
                    AppearancePicture(
                        appearance,
                        isChosen: shown == appearance,
                        isVoid: look.isVoid,
                    ) {
                        look.choose(appearance)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Spacing.md)
            .sensoryFeedback(.selection, trigger: shown)
            separator
            SwitchRow(
                "Automatic",
                hint: "Follows your phone's light or dark",
                isOn: Binding { look.isAutomatic } set: { look.setAutomatic($0, phone: phone) },
            )
            if look.offersVoid {
                VStack(spacing: 0) {
                    separator
                    SwitchRow(
                        "Void",
                        hint: "True black whenever the app is dark",
                        isOn: Binding { look.isVoid } set: { look.isVoid = $0 },
                    )
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.md)
        .background(shape.fill(.pp(.surface)))
        .clipShape(shape)
        .animation(reduceMotion ? Self.crossfade : .snappy, value: look.offersVoid)
    }

    /// A Settings group's divider, as the exercise sheet's are (`ValueRow`): two pixels thick.
    private var separator: some View {
        Rectangle()
            .fill(.pp(.separator))
            .frame(height: 2 / displayScale)
    }

    /// Void's row coming and going with Reduce Motion: a fade, as the search field's is.
    private static let crossfade = Animation.easeInOut(duration: 0.2)
}

/// Apple Health as one card with one row, "Save workouts", reading On or Off from the system's
/// permission. It is not a switch: Apple asks apps to leave Health sharing to the system's
/// privacy settings. Never asked, a tap brings up Apple's sheet; once answered, the row only
/// shows the answer.
struct HealthChoice: View {
    let health: HealthSaving
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.sm + Radius.key, style: .continuous)
        // Answered, the row is no button: disabled, a button dimmed the answer it shows.
        Group {
            if health.access == .notAsked {
                Button {
                    Task { await health.ask() }
                } label: {
                    row
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
        // Combined, so the button's action and trait stay while asking.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Save workouts")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(health
            .access == .notAsked ? "Asks to save workouts to Apple Health" : "")
        .padding(.horizontal, Spacing.md)
        .background(shape.fill(.pp(.surface)))
        .clipShape(shape)
    }

    private var isOn: Bool {
        health.access == .on
    }

    @ViewBuilder private var row: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        layout {
            Text("Save workouts")
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            // One text whose words change, so On and Off swap in place.
            Text(isOn ? "On" : "Off")
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm + Spacing.xs)
    }
}

/// A switch on the Appearance card: its name at a row title's size, the system's switch
/// trailing; at accessibility sizes, the switch under the name. What it does is its hint.
private struct SwitchRow: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    @Binding var isOn: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: LocalizedStringKey, hint: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        self.hint = hint
        _isOn = isOn
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The switch under the name, which takes the card's whole width: beside it, at
                // AX5 on a 375-point phone, "Automatic" broke mid-word.
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    name
                        .accessibilityHidden(true)
                    Toggle(isOn: $isOn) { name }
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Toggle(isOn: $isOn) { name }
            }
        }
        .accessibilityHint(hint)
        .padding(.vertical, Spacing.sm + Spacing.xs)
    }

    private var name: some View {
        Text(title)
            .font(.ppRowTitle)
            .foregroundStyle(.pp(.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
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
    SettingsSheet(health: HealthSaving(client: .unavailable))
        .environment(Look(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}

#Preview("375 points") {
    ScrollView {
        AppearanceChoice(
            look: Look(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            phone: .dark,
        )
        .padding(.horizontal, Spacing.md)
    }
    .frame(width: 375)
    .background(Color.pp(.background))
}
