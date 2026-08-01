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
    var cornerRadius: CGFloat = Theme.keyRadius
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
            .animation(Theme.Anim.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RaisedKeyStyle {
    /// Secondary key: `Theme.background`/`surface` cap + 1 pt
    /// borderStrong border, role-colored content.
    static func raisedKey(cornerRadius: CGFloat = Theme.keyRadius) -> RaisedKeyStyle {
        RaisedKeyStyle(plate: Theme.border, cornerRadius: cornerRadius)
    }

    /// Primary key: `Theme.primaryFill` cap on the stronger plate.
    static func raisedPrimaryKey(cornerRadius: CGFloat = Theme.keyRadius) -> RaisedKeyStyle {
        RaisedKeyStyle(plate: Theme.borderStrong, cornerRadius: cornerRadius)
    }

    /// Quiet key: the escape-hatch variant — lower cap, shorter travel.
    static var quietKey: RaisedKeyStyle {
        RaisedKeyStyle(plate: Theme.border, cornerRadius: 10, travel: 3)
    }
}

/// Escape hatches as quiet keys ("N more need equipment you don't have ·
/// show", "Equipment check…", "build as you go"): `Theme.selected` is
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

/// The app's ONE create-affordance row (2026-07-19, promoted from the
/// catalog-detail cross-ref blocks): green "+ <label>" content on a
/// bordered raised key, so every "New …" / "Add …" / "Create …" row reads
/// as a pressable button rather than floating text in a list. Full-width,
/// left-aligned; callers add the list-row insets/background.
struct CreateRow: View {
    let label: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(.caption, weight: .semibold))
                Text(label)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            // Green content on a raised key (Quiet Arcade): creation
            // stays in the data-green voice, the key anatomy carries
            // "this commits".
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(Theme.borderStrong)
            )
        }
        .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
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
    /// Which of the three chevrons is lit as the highlight marches
    /// left→right once the key ignites.
    @State private var chevronActive = 0
    @State private var marchTask: Task<Void, Never>?
    /// Reduce Motion keeps the single static chevron — the emerge is
    /// positional (WCAG 2.3.3). The green wipe and the label morph stay.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !flashing else { return }
            guard Self.flashes else {
                action()
                return
            }
            flashing = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            startMarch()
            pendingFire = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.85))
                guard !Task.isCancelled else { return }
                flashing = false
                action()
            }
        } label: {
            HStack(spacing: 8) {
                // The longer label reserves the width, so swapping in
                // "let's go" can't move the chevrons: a hidden placeholder
                // fixes the box and the live label rides inside it
                // trailing-aligned, exactly as the welcome key does.
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .hidden()
                    .overlay(alignment: .trailing) {
                        Text(flashing ? "let's go" : label)
                            .contentTransition(.opacity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                chevronRun
            }
            .font(.system(.subheadline, weight: .bold))
            // onPrimary doubles as on-accent here by design: white
            // in light, 0x161616 in dark — the handoff's flash spec.
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(flashing ? Theme.accent : Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
            .animation(Theme.Anim.standard, value: flashing)
        }
        .buttonStyle(.raisedPrimaryKey())
        .accessibilityIdentifier(identifier ?? label)
        .onDisappear {
            pendingFire?.cancel()
            marchTask?.cancel()
            flashing = false
            chevronActive = 0
        }
    }

    /// At rest the key carries ONE chevron. On ignition two more slide out
    /// from behind it and a lit highlight marches left→right across the trio
    /// (the others dimmed, not gone), so the tap reads as forward momentum.
    ///
    /// Lifted out of the welcome key (2026-07-29) so the app has ONE start
    /// gesture: this button is Today's Start and routine detail's Start
    /// workout, and both now play what the first-run key plays.
    private var chevronRun: some View {
        HStack(spacing: 3) {
            Image(systemName: "chevron.right")
                .opacity(chevronOpacity(0))
            if flashing && !reduceMotion {
                ForEach(1..<3, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .opacity(chevronOpacity(index))
                        // Emerge from behind the resting chevron so they read
                        // as coming out of it rightward.
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
    }

    /// The lit chevron is full; its neighbours rest dim so the two that
    /// emerged stay visible as a track the highlight travels.
    private func chevronOpacity(_ index: Int) -> Double {
        guard flashing && !reduceMotion else { return index == 0 ? 1 : 0 }
        return chevronActive == index ? 1 : 0.25
    }

    /// The march, sized to the 0.85 s the key already waits before firing:
    /// a beat for the extra chevrons to emerge, then four 0.15 s hops.
    private func startMarch() {
        guard !reduceMotion else { return }
        marchTask?.cancel()
        chevronActive = 0
        marchTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            for hop in 0..<4 {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    chevronActive = hop % 3
                }
                try? await Task.sleep(for: .seconds(0.15))
            }
        }
    }
}

/// One block's state when a `BlockBar` carries the app's state grammar
/// rather than plain progress: `done` landed (purple), `live` in motion
/// (green), `upcoming` inert (2026-07-28, the live set bar).
enum BlockState: Equatable {
    case done, live, upcoming
}

/// Block-style progress (Quiet Arcade): one flexible block per unit,
/// filled left-to-right. Purple for the week bar (sessions landed),
/// accent green for live set progress. Pass `states` instead to colour
/// each block by where it stands.
struct BlockBar: View {
    let total: Int
    let filled: Int
    var fill: Color = Theme.done
    /// Per-block states. When nil the bar is plain progress and colours by
    /// `filled`; when set, each block wears its own status colour. Short
    /// arrays fall back to `upcoming`, so it can never index out of range.
    var states: [BlockState]? = nil
    /// Breathes the LIVE block — the live workout drives this from a
    /// running rest countdown, so the bar shows what you are about to do
    /// while you wait for it. The CALLER honours Reduce Motion (this view
    /// animates whenever it's true).
    var breathing: Bool = false

    /// Tapping a DONE block offers a correction (#504, Q8-B): the handler
    /// receives the block's index and the CALLER presents the set's
    /// values with an explicit confirm — a segment tap must never move
    /// the cursor by itself. nil (every mount but the live set bar)
    /// leaves the bar inert, exactly as before. ⚠️ VoiceOver keeps the
    /// bar as one summary element (children stay ignored below); the
    /// overview sheet's Redo is the accessible correction route.
    var onCorrect: ((Int) -> Void)? = nil

    /// Toggled under a `repeatForever` animation, exactly as the overview
    /// sheet's up-next pulse does (#421) — a deliberate flourish, and a
    /// named exception to the Anim-token rule: a countdown is a waiting
    /// state, and the slow breathe is the information.
    @State private var breathIn = false

    /// ⚠️ A status bar states done/live/upcoming in HUE, and purple against
    /// green measures 1.25:1 in light mode — a luminance near-tie, so the
    /// three states are separable by colour alone (WCAG 1.4.1). With
    /// Differentiate Without Color on, shape carries it instead: done stays
    /// solid, upcoming becomes a hollow outline (the overview sheet's pip
    /// treatment), and live grows taller than both. Same escape the session
    /// pips already take.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// This block's state, or nil when the bar is plain progress.
    private func blockState(at index: Int) -> BlockState? {
        guard let states else { return nil }
        return states.indices.contains(index) ? states[index] : .upcoming
    }

    private func color(at index: Int) -> Color {
        guard let state = blockState(at: index) else {
            return index < filled ? fill : Theme.surfaceRaised
        }
        switch state {
        case .done: return Theme.done
        case .live: return Theme.accent
        case .upcoming: return Theme.surfaceRaised
        }
    }

    private func isLive(at index: Int) -> Bool {
        guard let state = blockState(at: index) else { return false }
        return state == .live
    }

    /// Hollow only for a not-yet-done block, and only while the shape cue is
    /// asked for — a plain progress bar keeps its solid/inert pairing.
    private func isHollow(at index: Int) -> Bool {
        differentiateWithoutColor && blockState(at: index) == .upcoming
    }

    private func height(at index: Int) -> CGFloat {
        differentiateWithoutColor && isLive(at: index) ? 13 : 9
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                // ONE identity per block whatever its state (review): a
                // branch between Button and bare shape remounts the
                // segment when it crosses into `.done`, turning the
                // green→purple roll into a crossfade. The Button is
                // layout-neutral; hit testing is the only thing gated.
                Button {
                    onCorrect?(index)
                } label: {
                    segment(at: index)
                        .contentShape(BlockHitInflation())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(onCorrect != nil && blockState(at: index) == .done)
            }
        }
        .animation(Theme.Anim.standard, value: filled)
        // A jump moves the live block without changing the completed
        // count, so the colours need their own trigger.
        .animation(Theme.Anim.standard, value: states)
        .onChange(of: breathing, initial: true) { _, on in
            if on {
                breathIn = false
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    breathIn = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { breathIn = false }
            }
        }
        // Shape-only progress; VoiceOver hears the count, not the blocks
        // (#164, WCAG 1.1.1). Consumers either set a label naming the
        // subject ("Sets") or hide the bar when a sibling caption
        // already states the fact — a bare "2 of 4" with no subject is
        // the a11y bug this comment used to merely hope against
        // (2026-07-23). Correction taps (#504) deliberately stay out of
        // the tree too: the overview's Redo is the accessible route.
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(filled) of \(total)")
    }

    private func segment(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isHollow(at: index) ? Color.clear : color(at: index))
            .overlay {
                if isHollow(at: index) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Theme.borderStrong, lineWidth: 1)
                }
            }
            .frame(height: height(at: index))
            .frame(maxWidth: .infinity)
            .opacity(breathing && isLive(at: index) ? (breathIn ? 1.0 : 0.35) : 1.0)
    }
}

/// A 9 pt block sits far under the 44 pt hit floor, so the hit shape
/// inflates past the bounds without moving layout (MetricStepperRow's
/// negative-inset precedent) — but ASYMMETRICALLY (review): a uniform
/// −17 overlapped neighbors by 31 pt horizontally (later siblings
/// hit-test first, so the right ~third of every done block routed to
/// its NEIGHBOR's dialog), and reached 17 pt up into the header band.
/// Sides take half the bar's 3 pt spacing; vertically the reach is
/// 12 pt up (inside the bar's own top padding) and 24 pt down (the
/// stage's non-interactive kicker zone), for a 45 pt hit height.
private struct BlockHitInflation: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX - 1.5,
            y: rect.minY - 12,
            width: rect.width + 3,
            height: rect.height + 36
        ))
    }
}
