import SwiftUI

/// The Quiet Arcade press grammar (2026-07-10 handoff): every button
/// that commits or navigates is a raised key — an opaque cap sitting
/// proud of a fixed base plate, visible as a strip under the bottom
/// edge. Pressing sinks the cap onto the plate (the plate NEVER
/// moves), 0.06 s ease-out, reversing on release. Flat controls —
/// filter chips, toggles, checkboxes, segmented tabs, the tab bar,
/// list rows and cards — stay flat: their state flip is the feedback.
///
/// Travel is 4 pt standard / 3 pt quiet — a point over the mock's
/// 3/2 (Dave, build-42 feedback: "a bit more travel").
///
/// The style owns only the mechanics (plate, travel, press motion);
/// the label is the cap and the caller styles it. Caps MUST be
/// opaque (`Theme.background` / `Theme.surface` / `Theme.primaryFill`
/// fills) or the plate shows through them at rest.
struct RaisedKeyStyle: ButtonStyle {
    /// `Theme.border` under secondary/quiet keys, `Theme.borderStrong`
    /// under primary (filled) ones.
    var plate: Color = Theme.border
    /// Must match the cap's corner radius so the plate reads as the
    /// same key's underside.
    var cornerRadius: CGFloat = 11
    /// 4 pt standard, 3 pt quiet.
    var travel: CGFloat = 4

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && isEnabled ? travel : 0)
            .padding(.bottom, travel)
            .background {
                // Disabled keys lie flat (no plate, border only, dim
                // content — the caller dims its own cap).
                if isEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(plate)
                        .padding(.top, travel)
                }
            }
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RaisedKeyStyle {
    /// Secondary key: `Theme.background`/`surface` cap + 1 pt
    /// borderStrong border, role-colored content.
    static func raisedKey(cornerRadius: CGFloat = 11) -> RaisedKeyStyle {
        RaisedKeyStyle(plate: Theme.border, cornerRadius: cornerRadius)
    }

    /// Primary key: `Theme.primaryFill` cap on the stronger plate.
    static func raisedPrimaryKey(cornerRadius: CGFloat = 11) -> RaisedKeyStyle {
        RaisedKeyStyle(plate: Theme.borderStrong, cornerRadius: cornerRadius)
    }

    /// Quiet key: the escape-hatch variant — lower cap, shorter travel.
    static var quietKey: RaisedKeyStyle {
        RaisedKeyStyle(plate: Theme.border, cornerRadius: 10, travel: 3)
    }
}

/// Escape hatches as quiet keys ("N more need gear you don't own —
/// show", "Gear check…", "build as you go"): `Theme.selected` is
/// retired as a text/link color — a low-travel key reads as pressable
/// without borrowing the selection hue or an underline. An optional
/// `systemImage` rides at the leading edge in the same quiet ink.
struct QuietKey: View {
    let label: String
    var systemImage: String?
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.caption, weight: .semibold))
                }
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(minHeight: 42)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
        .buttonStyle(.quietKey)
        .accessibilityIdentifier(identifier ?? label)
    }
}

/// A primary key whose tap plays the commit flourish — the cap
/// flashes `accent` green with "let's go ▸" for ~0.85 s — before the
/// action runs (Start is the app's biggest commit; this is its
/// one-shot beat). The flash is skipped under UI test, where the
/// delay would slow every start-tapping flow for no observable gain.
///
/// ⚠️ The deferred fire is CANCELLED if this button disappears
/// mid-flash (a swipe-back popping routine detail must not start a
/// session against a dead screen), and callers must still re-check
/// their own preconditions in `action` — 0.85 s is long enough for a
/// second Start to flash or a sheet to present (swift-reviewer catch
/// on this component's first cut).
struct StartFlashButton: View {
    let label: String
    var height: CGFloat = 48
    var identifier: String?
    let action: () -> Void

    private static let flashes = !CommandLine.arguments.contains("--uitest-reset")

    @State private var flashing = false
    @State private var pendingFire: Task<Void, Never>?

    var body: some View {
        Button {
            guard !flashing else { return }
            guard Self.flashes else {
                action()
                return
            }
            flashing = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            pendingFire = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.85))
                guard !Task.isCancelled else { return }
                flashing = false
                action()
            }
        } label: {
            Text(flashing ? "let's go ▸" : label)
                .font(.system(.subheadline, weight: .bold))
                // onPrimary doubles as on-accent here by design: white
                // in light, 0x161616 in dark — the handoff's flash spec.
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(flashing ? Theme.accent : Theme.primaryFill, in: RoundedRectangle(cornerRadius: 11))
                .animation(.easeOut(duration: 0.15), value: flashing)
        }
        .buttonStyle(.raisedPrimaryKey())
        .accessibilityIdentifier(identifier ?? label)
        .onDisappear {
            pendingFire?.cancel()
            flashing = false
        }
    }
}

/// Block-style progress (Quiet Arcade): one flexible block per unit,
/// filled left-to-right. Purple for the week bar (sessions landed),
/// accent green for live set progress.
struct BlockBar: View {
    let total: Int
    let filled: Int
    var fill: Color = Theme.done

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filled ? fill : Theme.surfaceRaised)
                    .frame(height: 9)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: filled)
    }
}
