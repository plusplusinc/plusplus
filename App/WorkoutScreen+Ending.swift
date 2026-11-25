import DesignSystem
import SwiftUI

/// The workout's finishes, each popping a "+" off the key on each of two beats: the first with
/// a medium impact, the second, `PrimaryKeyButtonStyle.finishBeat` later, with a heavy one
/// (`finishHaptics(_:)`).
struct FinishBeats {
    private(set) var first = 0
    /// When the first beat played, which the second counts from.
    private(set) var struck: ContinuousClock.Instant?

    /// The first beat, now.
    mutating func strike() {
        first += 1
        struck = .now
    }
}

extension WorkoutScreen {
    /// Finishes the workout, from the key with no dialog, or from End's Finish: two "+"s pop
    /// off the key a beat apart, each with an impact, and meet as "++" over a still screen; once
    /// they have gone the app goes to Log through the drawer, the screen holding still behind it
    /// until Log replaces it (`end(holdingStill:_:)`). Until the drawer opens, no touch reaches
    /// the app (`windowTouchesOff(_:)`). With VoiceOver, straight to Log, with no
    /// burst, the two impacts still playing a beat apart.
    func finish() {
        guard !voiceOver else {
            guard end({ session.finish() }) else { return }
            finishBeats.strike()
            session.showLog()
            return
        }
        let hold = PrimaryKeyButtonStyle.finishBurst + PrimaryKeyButtonStyle.finishRest
        guard end(holdingStill: true, { session.finish() }) else { return }
        // The burst draws its second "+" on the same constant as the second impact, from the
        // first's trigger.
        finishBeats.strike()
        session.showThroughDrawer(.log, after: .seconds(hold), reduceMotion: reduceMotion)
    }
}

extension View {
    /// End's dialog on `screen`.
    func finishing(_ screen: WorkoutScreen) -> some View {
        endWorkoutDialog(
            isPresented: screen.$isConfirmingEnd,
            session: screen.session,
            finish: screen.finish,
            discard: { _ = screen.end(screen.session.discard) },
        )
    }

    /// A finish's two impacts, the second `PrimaryKeyButtonStyle.finishBeat` after the first.
    /// Played above the screens, which a finish with VoiceOver takes away at once, so the second
    /// impact's wait outlives them.
    func finishHaptics(_ beats: Binding<FinishBeats>) -> some View {
        modifier(FinishHaptics(beats: beats))
    }
}

private struct FinishHaptics: ViewModifier {
    @Binding var beats: FinishBeats
    @State private var second = 0

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .medium), trigger: beats.first)
            .sensoryFeedback(.impact(weight: .heavy), trigger: second)
            .task(id: beats.first) {
                guard let struck = beats.struck else { return }
                let due = struck + .seconds(PrimaryKeyButtonStyle.finishBeat)
                guard await (try? beat(until: due)) != nil else { return }
                second += 1
            }
    }
}

/// End's motion, once `end(holdingStill:_:)` has set the phase to its ending.
extension WorkoutScreen {
    /// End's motion from the key leaving, with `change` on the curve the bar moves on.
    func playEnding(tookOver: Bool, _ change: () -> Void) {
        // The workout's key slides down as it fades, and Start stays away until the list has
        // landed: taken out with no animation, the key went on the frame.
        withAnimation(.easeOut(duration: Self.barFade)) {
            phase.keyLeaves()
        }
        guard !reduceMotion else {
            withAnimation(Self.crossfadeCurve) { change() }
            beginCrossfade(scrollingTo: 0)
            return sequence.run {
                let start = ContinuousClock.now
                try await laterTurn()
                try await crossfade {
                    phase.listLeaves()
                    // Any room Start or a move was keeping: there is no landing after End.
                    isMakingRoom = false
                    closingRoomTop = nil
                } meanwhile: {
                    try await beat(until: start + .seconds(Self.barFade))
                    fadeTime()
                }
                keyReturns { phase.rest() }
            }
        }
        if tookOver {
            withAnimation(Self.endCurve) { change() }
        } else {
            shrink(storing: change)
        }
        sequence.run {
            let start = ContinuousClock.now
            if tookOver {
                try await laterTurn()
                shrink()
            }
            // Once the time has faded out of its key, the key's glass goes, the bar fading it:
            // taken out with no animation, it went on the frame. A beat in the sequence by design.
            try await beat(until: start + .seconds(Self.barFade))
            fadeTime()
            // Start comes back as the list lands, a beat in the sequence by design: the
            // animation's completion came a few frames after the rows had stopped.
            try await beat(until: start + .seconds(Self.endBeat))
            if startDrop != 0 {
                // Ended as Start rode down: it comes back from out of sight.
                withTransaction(\.disablesAnimations, true) { startDrop = 0 }
                try await laterTurn()
            }
            // The + Start's ride took down comes back up with it.
            keyReturns {
                plusLeftWithStart = false
                return phase.rest()
            }
        }
    }

    /// End's one motion, with `change` when End took over nothing: the list leaving the workout,
    /// the current exercise shrinking, the rows
    /// below closing up, and the list scrolling to its top, on the rows' own animation: until it
    /// has ended, room under the list's end holds, so the shrinking content doesn't pull the
    /// scroll up, and a loop's heads ease to their new places, as at Start (`listResizes(_:)`).
    private func shrink(storing change: () -> Void = { }) {
        withAnimation(Self.endCurve) {
            change()
            phase.listLeaves()
            scrollPosition.scrollTo(edge: .top)
            resizes += 1
            // Any room a move to the next exercise or the last set's close left: the resize
            // holds the room from here.
            isMakingRoom = false
            closingRoomTop = nil
            growthLift = 0
        }
    }

    /// The time fades out of its key as the workout ends, and then the key's glass goes.
    private func fadeTime() {
        withAnimation(.easeOut(duration: Self.barFade)) { _ = phase.timeFades() }
    }
}
