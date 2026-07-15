import SwiftUI
import PlusPlusKit

/// The full form demo: the mascot looping a set in an orbitable
/// viewport, with the move's cues below lighting up (notes amber — the
/// form-cue color) at the exact moment in the motion they apply to.
/// Under Reduce Motion or UI test the loop is replaced by a discrete
/// step-through, so the whole demo remains available without motion.
struct MascotDemoSheet: View {
    let exerciseName: String
    let animation: ExerciseAnimation

    @State private var playback: MascotPlayback
    @State private var stepIndex = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(exerciseName: String, animation: ExerciseAnimation) {
        self.exerciseName = exerciseName
        self.animation = animation
        _playback = State(initialValue: MascotPlayback(animation: animation))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: exerciseName,
                subtitle: "form demo",
                actionIdentifier: "closeMascotDemoSheet",
                closeOnly: true
            ) {
                dismiss()
            }
            .padding(.horizontal, 20)

            MascotView(playback: playback, mode: .demo)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .padding(.top, 8)

            viewportCaption
                .padding(.top, 6)

            cueList
                .padding(.horizontal, 20)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .background(Theme.surface)
        // A downward orbit drag must never be claimed by the sheet's
        // dismiss gesture; the ✕ key and Escape both close.
        .interactiveDismissDisabled()
        .onAppear {
            // Frozen mode opens ON step 1 (pose, cues, and label agree
            // from the first frame, not after a wrap-around).
            if playback.frozen {
                stepBy(0)
            }
        }
        .onChange(of: scenePhase) {
            playback.paused = scenePhase != .active
        }
    }

    /// Under the viewport: the orbit hint plus a live rep counter, or
    /// the step-through keys when motion is off.
    @ViewBuilder
    private var viewportCaption: some View {
        if playback.frozen {
            HStack(spacing: 10) {
                QuietKey(label: "back", systemImage: "chevron.left", identifier: "mascotStepBack") {
                    stepBy(-1)
                }
                Text("STEP \(stepIndex + 1) OF \(animation.stepPhases.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                QuietKey(label: "next", systemImage: "chevron.right", identifier: "mascotStepForward") {
                    stepBy(1)
                }
            }
        } else {
            HStack(spacing: 12) {
                Text(repCaption)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.standard, value: playback.repIndex)
                Text("drag to look around")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
        }
    }

    private var repCaption: String {
        if let rep = playback.repIndex {
            if case .hold = animation.style {
                return "HOLD"
            }
            return "REP \(rep + 1) OF \(animation.repsPerDemoSet)"
        }
        return "REST"
    }

    private var cueList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(animation.cues.enumerated()), id: \.offset) { index, cue in
                    let active = playback.activeCueIndices.contains(index)
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(active ? Theme.notes : Theme.border)
                            .frame(width: 3)
                        Text(cue.text)
                            .font(.system(.subheadline, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Theme.notes : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityValue(active ? "current step" : "")
                    }
                    .animation(Theme.Anim.standard, value: active)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func stepBy(_ delta: Int) {
        let phases = animation.stepPhases
        guard !phases.isEmpty else { return }
        stepIndex = (stepIndex + delta + phases.count) % phases.count
        playback.step(toPhase: phases[stepIndex])
    }
}
