import SwiftUI

/// A bordered settings row that shows the current value and pushes a selection
/// screen to change it (a real navigation push, so it needs a `NavigationStack`
/// ancestor). Used for multi-word mode selectors that would crowd or truncate a
/// segmented control — the options get their own screen instead of fighting for
/// width in a row. Matches the tray's "configure" row look (surface fill,
/// border, r11) so it reads as a tappable control.
///
/// `.pickerStyle(.navigationLink)` is deliberately NOT used: it only renders as
/// a push row inside a `List`/`Form`, and these trays are plain `VStack`s.
struct NavigationSelectRow<Value: Hashable>: View {
    /// Names the pushed screen (its nav-bar title). The row itself shows the
    /// current value, not this title, so it never repeats the section label.
    let title: String
    @Binding var selection: Value
    let options: [Option]
    var identifier: String? = nil

    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        NavigationLink {
            NavigationSelectList(title: title, selection: $selection, options: options)
        } label: {
            HStack(spacing: 12) {
                Text(currentLabel)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            // surfaceRaised (not surface) so the row reads as a raised control
            // whether the tray background is surface (Settings) or background
            // (Schedule).
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityID(identifier)
    }
}

private struct NavigationSelectList<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [NavigationSelectRow<Value>.Option]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        selection = option.value
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(.body))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if option.value == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.selected)
                            }
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 48)
                        .padding(.horizontal, 18)
                    }
                    .buttonStyle(.plain)
                    if option.id != options.last?.id {
                        Divider().overlay(Theme.border).padding(.leading, 18)
                    }
                }
            }
            .padding(.top, 8)
        }
        // No explicit background: inherit the host sheet's presentation
        // background (Theme.surface for Settings, Theme.background for
        // Schedule) so the pushed screen matches its tray.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    @ViewBuilder func accessibilityID(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
