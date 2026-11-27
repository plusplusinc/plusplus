import SwiftUI

/// A setting the system owns, alone on a Settings card: its name at a row title's size and, on
/// the right, its value, quieter, or a small green button that starts it (`button`); at
/// accessibility sizes, these under the name. Not a switch: the value is the system's answer,
/// which the app only reads, drawn at full strength rather than dimmed. A `note`, when there is
/// one, sits under a hairline inside the same card, in the secondary text color. VoiceOver reads
/// the name and the value as one element.
public struct SettingRow: View {
    private let title: String
    private let value: String
    private let note: String?
    private let button: (title: String, action: () -> Void)?
    /// When set, the whole card is a button that leaves for where the setting lives, and an
    /// arrow after the value says so.
    private let opens: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// The button's height at the default text size, a step under a tap target's, as it sits
    /// inside a row that is one.
    private static let buttonHeight: CGFloat = 36

    public init(
        _ title: String,
        value: String,
        note: String? = nil,
        opens: (() -> Void)? = nil,
    ) {
        self.title = title
        self.value = value
        self.note = note
        self.opens = opens
        button = nil
    }

    public init(_ title: String, button: String, action: @escaping () -> Void) {
        self.title = title
        value = ""
        note = nil
        opens = nil
        self.button = (button, action)
    }

    public var body: some View {
        Group {
            if let opens {
                Button(action: opens) { card.contentShape(.rect) }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        .settingsCard()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if let note {
                Rectangle()
                    .fill(.pp(.separator))
                    .frame(height: 1 / displayScale)
                Text(note)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.sm + Spacing.xs)
                    .padding(.bottom, Spacing.md)
            }
        }
    }

    @ViewBuilder private var row: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        layout {
            Text(title)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            if let button {
                Button(button.title, action: button.action)
                    .buttonStyle(.greenPill(height: Self.buttonHeight))
                    .padding(.trailing, -Spacing.sm)
            } else {
                // One text whose words change, so a new value swaps in place.
                Text(value)
                    .font(.ppRowTitle)
                    .foregroundStyle(.pp(.textSecondary))
                if opens != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.ppRowDetail.weight(.semibold))
                        .foregroundStyle(.pp(.textSecondary))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, button == nil ? Spacing.sm + Spacing.xs : Spacing.sm)
        .accessibilityElement(children: button == nil ? .combine : .contain)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        SettingRow("Sync workouts", button: "Turn on") { }
        SettingRow("Sync workouts", value: "On")
        SettingRow(
            "Sync workouts",
            value: "Off",
            note: "To turn it on, open the Health app, tap your picture, then Privacy, Apps, "
                + "PlusPlus.",
        )
    }
    .padding(Spacing.md)
    .frame(maxHeight: .infinity)
    .sheetGround()
}
