import SwiftUI
import PlusPlusKit

/// The FORM section's inline preview: the mascot already performing the
/// exercise in a small fixed-camera card, tap to expand into the full
/// demo sheet. The whole card is one plain button (the viewport ignores
/// hits), so scroll and tap never fight the 3D view. Owns its demo
/// sheet so both detail surfaces integrate with a single line.
struct MascotFormCard: View {
    let exerciseName: String
    let animation: ExerciseAnimation

    @State private var playback: MascotPlayback
    @State private var showingDemo = false
    @State private var visible = true
    @Environment(\.scenePhase) private var scenePhase

    init(exerciseName: String, animation: ExerciseAnimation) {
        self.exerciseName = exerciseName
        self.animation = animation
        _playback = State(initialValue: MascotPlayback(animation: animation))
    }

    var body: some View {
        Button {
            showingDemo = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                MascotView(playback: playback, mode: .preview)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(.caption2, weight: .semibold))
                    Text("WATCH THE FORM")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                }
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mascotPreviewCard")
        .accessibilityLabel("Form demo. The mascot performs \(exerciseName).")
        .accessibilityHint("Expands into the full demo with form cues.")
        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
            visible = isVisible
            reconcilePause()
        }
        .onChange(of: scenePhase) { reconcilePause() }
        .onChange(of: showingDemo) { reconcilePause() }
        .sheet(isPresented: $showingDemo) {
            MascotDemoSheet(exerciseName: exerciseName, animation: animation)
                .presentationDetents([.large])
                .presentationBackground(Theme.surface)
                .presentationDragIndicator(.hidden)
        }
    }

    /// The preview runs only while it is actually watchable. Pausing
    /// under the open sheet also dodges a simulator limitation where a
    /// second live RealityView can render black.
    private func reconcilePause() {
        playback.paused = !visible || showingDemo || scenePhase != .active
    }
}
