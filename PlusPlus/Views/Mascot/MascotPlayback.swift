import SwiftUI
import PlusPlusKit

/// The demo's clock. RealityKit's per-frame update event feeds
/// `tick(deltaTime:)`; the pose/face samples go straight to the rig,
/// while observable state (active cues, rep index) is published only
/// when it CHANGES — a few times per cycle, never per frame.
///
/// `frozen` is the inertness contract: under Reduce Motion or
/// `--uitest-reset` the mascot never animates — it holds the move's
/// characteristic resting pose with open eyes (the demo sheet swaps the
/// loop for a discrete step-through). The uitest half exists because
/// the app-wide `UIView.setAnimationsEnabled(false)` kill does NOT
/// cover a RealityKit render loop, and XCUITest waits for quiescence
/// before every event.
@MainActor @Observable
final class MascotPlayback {
    let animation: ExerciseAnimation
    /// The uitest half of frozen never changes; the Reduce Motion half
    /// is kept live by MascotView from the environment, so flipping the
    /// setting mid-demo takes effect without recreating the view.
    private let uitest: Bool
    var reduceMotion: Bool
    var frozen: Bool { uitest || reduceMotion }
    var paused = false

    private(set) var activeCueIndices: [Int] = []
    /// Which rep the loop is in (nil during the tired beat).
    private(set) var repIndex: Int?
    /// The step-through cursor's set phase, driven by the demo sheet in
    /// frozen mode; MascotView re-applies the rig from it.
    private(set) var manualPhase: Double?

    private var elapsed: TimeInterval = 0

    init(animation: ExerciseAnimation) {
        self.animation = animation
        uitest = CommandLine.arguments.contains("--uitest-reset")
        reduceMotion = Theme.Anim.reduceMotion
    }

    /// Advances the clock; nil when nothing should move this frame.
    func tick(deltaTime: TimeInterval) -> (pose: MascotPose, face: MascotFace)? {
        guard !frozen, !paused else { return nil }
        elapsed += deltaTime
        let t = (elapsed / animation.cycleDuration).truncatingRemainder(dividingBy: 1)
        publishProgress(at: t)
        return (animation.pose(at: t), animation.face(at: t))
    }

    /// The frozen-mode stand-in: the authored resting pose, eyes open.
    var frozenSample: (pose: MascotPose, face: MascotFace) {
        let pose = manualPhase.map { animation.pose(at: $0) } ?? animation.restingPose
        return (pose, MascotFace(eyeOpenness: 1, tiredness: 0))
    }

    /// Step-through (frozen demo sheet): jump the cursor to a phase and
    /// light up that moment's cues.
    func step(toPhase phase: Double) {
        manualPhase = phase
        publishProgress(at: phase)
    }

    private func publishProgress(at t: Double) {
        let cues = animation.activeCueIndices(at: t)
        if cues != activeCueIndices {
            activeCueIndices = cues
        }
        let rep: Int?
        switch animation.segment(at: t) {
        case .rep(let index, _): rep = index
        case .rest: rep = nil
        }
        if rep != repIndex {
            repIndex = rep
        }
    }
}
