import SwiftUI

/// Shared building blocks for v2 sheets: the title bar and the small
/// typographic/control pieces every sheet composes. One place to change
/// the sheet language (#91).

// MARK: - How tall a tray opens
//
// The detent vocabulary (audited 2026-07-28, Dave: "we should only vary
// for good reason"). A tray picks ONE of these five by what it IS; a new
// magic `.fraction` is the thing to avoid, because a number nobody can
// justify is a number the next tray copies slightly wrong.
//
// 1. `[.medium, .large]` — THE DEFAULT, and already what 14 trays use.
//    Something you browse or edit: it opens at half and grows if you want
//    more. Reach for this unless one of the others clearly applies.
// 2. `[.appTall]` (below) — a tray over live context, non-resizable.
// 3. `[.large]` — a whole task that would be unusable at half: the
//    equipment-resolve flows, the exercise picker, the mascot demo.
// 4. `[.height(n)]` — content of an exactly known size (the metric, rep
//    and increment pickers). ⚠️ Do NOT pair a `.height` with `.medium`:
//    medium is a FRACTION of the screen, so on a small phone it lands
//    BELOW the fixed height and "expanding" the sheet shrinks it. The
//    increment tray had exactly that pairing.
// 5. `[.medium]` alone — a short fixed tray that shouldn't resize (the
//    Health primer, the Data tray). The drag indicator is hidden on a
//    primer, since there is nothing to drag to.

extension PresentationDetent {
    /// A tray that covers the screen but deliberately keeps a sliver of
    /// what it came from visible behind it — the exercise/session
    /// configuration family, which you open ON a routine or ON a live
    /// workout and where losing sight of that context makes the sheet read
    /// as a screen you navigated to.
    ///
    /// It exists because those four trays had FOUR different numbers
    /// (0.84, 0.85, 0.88, 0.70) that nobody can tell apart on a device and
    /// no comment explained. One value, one name, one place to tune it.
    static let appTall = Self.fraction(0.85)
}

// MARK: - Sheet chrome

/// One action in a sheet's navigation bar.
///
/// `isEnabled` exists for the commit key alone (a form that cannot be saved
/// yet); a cancel is never disabled, because the way out of a sheet must
/// always work.
struct SheetAction {
    let label: String
    var identifier: String?
    var isEnabled: Bool = true
    let action: () -> Void

    init(_ label: String, identifier: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// The sheet chrome, native edition (Dave, 2026-08-02: "also sheets", after
/// the toolbar keys and the pushed headers). A sheet wears the SYSTEM
/// navigation bar — inline title, optional `.navigationSubtitle`, a leading
/// `.cancellationAction` and a trailing `.confirmationAction` — exactly as a
/// pushed screen does, so there is one header mechanism left in the app.
///
/// ⚠️ **The HOST supplies the `NavigationStack`, not this modifier**, and that
/// is `ui-interaction.md`'s law, not a convenience: several of these sheets
/// already bring one to push a destination, and a stack nested inside a stack
/// is exactly the bug that law was written for. A sheet with no push of its
/// own still needs one — a `.navigationTitle` with no bar to land in renders
/// nothing at all, silently.
///
/// ⚠️ **Presentation modifiers go OUTSIDE that stack** (detents,
/// `.presentationBackground`, `.interactiveDismissDisabled`). Inside, they
/// address the stack's root screen instead of the sheet.
///
/// What changed from the hand-drawn `SheetHeader` it replaces (deleted with
/// `SheetDismissKey` in the same pass), all of it deliberate: Cancel moves to
/// the LEFT — it used to sit beside the commit on the right — and the commit
/// loses its green `primaryFill` capsule for the bar's own text button. The
/// capsule said "committing a form is an ACTION"; true, and the system says it
/// with position and weight instead. What the app KEEPS is the law underneath:
/// a sheet dismisses with a WORD, never a ✕, which is why ✕ can still mean
/// only "collapse the search".
///
/// ⚠️ One loss worth naming rather than discovering: a `SheetHeader` was the
/// app's own view, so `ExerciseEditorView` could hang a `.keyboardGround` on
/// it and make ~90 pt of blank space above a text field answer a tap. A system
/// bar cannot carry one. `.scrollDismissesKeyboard` is load-bearing in any
/// sheet that holds a field (ui-interaction.md).
private struct SheetChrome: ViewModifier {
    let title: String
    var subtitle: String?
    var confirm: SheetAction?
    var cancel: SheetAction?

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let cancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancel.label, action: cancel.action)
                            // Escape is NOT wired automatically on iOS; the
                            // hand-drawn key declared it and so does this.
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier(cancel.identifier ?? "")
                    }
                }
                if let confirm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirm.label, action: confirm.action)
                            .disabled(!confirm.isEnabled)
                            // Return commits the sheet, as it always has.
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier(confirm.identifier ?? "")
                    }
                }
            }
            .modifier(SheetSubtitle(subtitle: subtitle))
    }
}

/// iOS 26's second title line. Split out because the modifier returns a
/// different concrete type, so it cannot be applied inline behind an `if`.
private struct SheetSubtitle: ViewModifier {
    let subtitle: String?

    func body(content: Content) -> some View {
        if let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

extension View {
    /// One call per sheet: the system navigation bar with an inline title, an
    /// optional subtitle, and up to two actions. See `SheetChrome` for the two
    /// things the CALL SITE still owns — the `NavigationStack`, and keeping
    /// presentation modifiers outside it.
    func sheetChrome(
        title: String,
        subtitle: String? = nil,
        confirm: SheetAction? = nil,
        cancel: SheetAction? = nil
    ) -> some View {
        modifier(SheetChrome(title: title, subtitle: subtitle, confirm: confirm, cancel: cancel))
    }

    /// A view-only sheet: a title and one word to leave by.
    func sheetChrome(title: String, subtitle: String? = nil, done: SheetAction) -> some View {
        modifier(SheetChrome(title: title, subtitle: subtitle, confirm: done, cancel: nil))
    }
}


/// Mono section caption used inside v2 sheets.
struct SheetSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .kerning(0.7)
            .padding(.bottom, 6)
            // The rows under a section carry bare metric names ("Distance",
            // "1 mi"), so the section is the only thing saying which side of
            // target/actual they are. As a heading it becomes navigable
            // rather than a caption VoiceOver may sweep past (#164).
            .accessibilityAddTraits(.isHeader)
    }
}

/// Bordered full-width action button used in v2 sheets.
struct SheetActionButton: View {
    let title: String
    var systemImage: String?
    var destructive = false
    var dimmed = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, destructive: Bool = false, dimmed: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.destructive = destructive
        self.dimmed = dimmed
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.caption, weight: .semibold))
                }
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
            }
            .foregroundStyle(destructive ? Theme.destructive : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(destructive ? Theme.destructive.opacity(0.4) : Theme.borderStrong)
            )
        }
        .opacity(dimmed ? 0.35 : 1)
        .disabled(dimmed)
    }
}

/// The ±pair's exact footprint, drawn as nothing. Built from the same
/// pieces at the same widths as the real pad below rather than one magic
/// number, so the two cannot drift apart.
private struct StepperPadFootprint: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44, height: 36)
            Divider().frame(height: 36).hidden()
            Color.clear.frame(width: 44, height: 36)
        }
        .accessibilityHidden(true)
    }
}

/// The third of distance · duration · pace: shown, never stored.
///
/// Sits in the same 52 pt row as `MetricStepperRow` and deliberately
/// carries none of its input chrome — no field border, no ± pair, ink a
/// step back — because it is an ANSWER, not a control. Five miles at 9:00
/// is forty-five minutes; the sheet says so instead of offering a fourth
/// number you could contradict.
///
/// It stays tappable, because deriving is not deciding: tapping promotes
/// the metric to something you set, and `CardioTargets.evicted` picks
/// which of the other two steps back to make room.
struct DerivedMetricRow: View {
    let label: String
    let value: String
    let identifier: String
    let onPromote: () -> Void

    var body: some View {
        Button(action: onPromote) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                // Lowercase, because ALL-CAPS mono is the section-label
                // treatment and this is a caption on one value.
                Text("derived")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.textFaint)
                Text(value)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: value)
                    // The stepper value's box, without its border.
                    .padding(.horizontal, 12)
                    .frame(minWidth: 60, minHeight: 36)
                // ⚠️ The ±pair's FOOTPRINT, reserved. Without it this row's
                // number sits ~89 pt right of every stepper value in the
                // same card, and a column of three cardio metrics reads
                // ragged — the derived one juts out exactly as far as the
                // keys it doesn't have.
                StepperPadFootprint()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
        }
        .accessibilityLabel(label)
        .accessibilityValue("\(value), derived")
        .accessibilityHint("Set it yourself instead")
        .accessibilityIdentifier("\(identifier)Derived")
    }
}

/// The triad's rule, said out loud (#508, b26) — the caption AND its
/// chrome, so the two sheets that mount it can't drift apart (the same
/// argument this round makes for `RoutineExercise.targets`).
///
/// Distance, duration and pace are three views of one effort: set two and
/// the third follows. Before this, that rule lived only in a source
/// comment — `DerivedMetricRow`'s `accessibilityHint` says "Set it
/// yourself instead", which describes the TAP and never the eviction — so
/// every user, sighted or not, met the rule by suffering it: set a pace,
/// watch the duration you entered become the derived one.
///
/// ⚠️ It is gated on the PROFILE, not on `derivedMetric != nil` (review).
/// Gating on the derived value hid the caption in the one state where the
/// surprise actually fires: a legacy entry with all three stored has no
/// derived metric yet, so the card said nothing, and the next edit evicted
/// one. The rule is a property of the card, not of today's values.
///
/// ⚠️ ONE per card, under the triad it governs and ABOVE the heart-rate
/// row — placed after the ForEach it read as annotating heart rate, which
/// is not part of the triad.
struct DerivedMetricCaption: View {
    var body: some View {
        Text(DerivedMetricPhrasing.caption)
            .font(.system(.caption))
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

enum DerivedMetricPhrasing {
    static let caption = "Set any two and the third is derived. Tap the derived one to set it instead, and another steps back to make room."
}

/// Metric row in the v2 sheet style: label, tappable mono value, and a
/// bordered −/+ pair. Increment/decrement identifiers are derived from
/// `identifier` ("weightIncrement" etc.) for the UI tests.
struct MetricStepperRow: View {
    let label: String
    let value: String
    let identifier: String
    var onTapValue: (() -> Void)?
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    /// A tap-editable value (it opens a wheel or the duration tape).
    /// Those read as an outlined text input so the picker behind them is
    /// discoverable — the value was ALWAYS tappable, but as bare mono
    /// text it looked like a readout, so the picker (and the whole tape
    /// scrubber) went unfound even by Dave. A non-tappable value (Sets,
    /// nudged only by the ± pair) stays a plain readout.
    private var isValueTappable: Bool { onTapValue != nil }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(.footnote))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                onTapValue?()
            } label: {
                Text(value)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Rolling digits on step (#216).
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: value)
                    // Field chrome only when tappable: same 36 pt height
                    // and radius as the ± control beside it, so the two
                    // read as a matched pair of inputs (Dave, 2026-07-16).
                    .padding(.horizontal, isValueTappable ? 12 : 7)
                    .padding(.vertical, isValueTappable ? 0 : 3)
                    .frame(minWidth: isValueTappable ? 60 : nil, minHeight: isValueTappable ? 36 : nil)
                    .overlay {
                        if isValueTappable {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border)
                        }
                    }
            }
            .disabled(onTapValue == nil)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(onTapValue == nil ? "" : "Opens a picker")
            .accessibilityIdentifier("\(identifier)Value")

            // 44-wide targets with the hit carried to 44 pt tall by the
            // row (§H: 44×36 visual, 44×44 hit, 52 pt row).
            HStack(spacing: 0) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .accessibilityLabel("Decrease \(label)")
                .accessibilityIdentifier("\(identifier)Decrement")
                Divider().frame(height: 36).overlay(Theme.border)
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .accessibilityLabel("Increase \(label)")
                .accessibilityIdentifier("\(identifier)Increment")
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }
}
