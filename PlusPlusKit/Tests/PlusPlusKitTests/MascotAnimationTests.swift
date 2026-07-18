import Testing
@testable import PlusPlusKit
import Foundation

@Suite struct MascotAnimationTests {
    /// A minimal synthetic animation: 2 reps of a 1-second nod between
    /// pose A and pose B, then a 1-second rest beat that stays on A.
    private static func makeNod() -> ExerciseAnimation {
        let a = MascotPose(joints: [.neck: .zero], effort: 0.2)
        let b = MascotPose(joints: [.neck: .deg(pitch: 30)], effort: 0.8)
        return ExerciseAnimation(
            exerciseName: "Test Nod",
            style: .reps(repDuration: 1),
            repsPerDemoSet: 2,
            repKeyframes: [
                MascotKeyframe(t: 0, pose: a, easing: .linear),
                MascotKeyframe(t: 0.5, pose: b, easing: .linear),
                MascotKeyframe(t: 1, pose: a),
            ],
            restBeat: ExerciseAnimation.RestBeat(duration: 1, keyframes: [
                MascotKeyframe(t: 0, pose: a, easing: .linear),
                MascotKeyframe(t: 1, pose: a),
            ]),
            cues: [MascotCue("Nod down", window: 0.1...0.5)],
            blinkPhases: [0.95],
            restingPhase: 0.5
        )
    }

    @Test func timelineDurations() {
        let nod = Self.makeNod()
        #expect(nod.repDuration == 1)
        #expect(nod.workDuration == 2)
        #expect(nod.cycleDuration == 3)
    }

    @Test func segmentMapping() {
        let nod = Self.makeNod()
        // Cycle: rep 0 spans 0..<1/3, rep 1 spans 1/3..<2/3, rest 2/3..<1.
        guard case .rep(let i0, let p0) = nod.segment(at: 0.1) else {
            Issue.record("expected rep segment"); return
        }
        #expect(i0 == 0)
        #expect(abs(p0 - 0.3) < 1e-9)

        guard case .rep(let i1, let p1) = nod.segment(at: 0.5) else {
            Issue.record("expected rep segment"); return
        }
        #expect(i1 == 1)
        #expect(abs(p1 - 0.5) < 1e-9)

        guard case .rest(let pr) = nod.segment(at: 5.0 / 6.0) else {
            Issue.record("expected rest segment"); return
        }
        #expect(abs(pr - 0.5) < 1e-9)

        // Wrapping: t just past 1 lands back in rep 0.
        guard case .rep(let iw, _) = nod.segment(at: 1.01) else {
            Issue.record("expected rep segment after wrap"); return
        }
        #expect(iw == 0)
    }

    @Test func poseInterpolatesAndWraps() {
        let nod = Self.makeNod()
        // Mid-descent of rep 0: halfway between A and B.
        let quarter = nod.pose(at: 0.25 / 3)
        #expect(abs(quarter.angles(.neck).pitch - 15 * .pi / 180) < 1e-9)
        #expect(abs(quarter.effort - 0.5) < 1e-9)
        // The loop seam: t = 1 equals t = 0.
        let start = nod.pose(at: 0)
        let end = nod.pose(at: 1)
        #expect(start == end)
    }

    @Test func easingShapesInterpolation() {
        let a = MascotPose(effort: 0)
        let b = MascotPose(effort: 1)
        let eased = [
            MascotKeyframe(t: 0, pose: a, easing: .easeIn),
            MascotKeyframe(t: 1, pose: b),
        ]
        // easeIn at u=0.5 is 0.25.
        #expect(abs(ExerciseAnimation.sample(eased, at: 0.5).effort - 0.25) < 1e-9)
        let held = [
            MascotKeyframe(t: 0, pose: a, easing: .hold),
            MascotKeyframe(t: 1, pose: b),
        ]
        #expect(ExerciseAnimation.sample(held, at: 0.99).effort == 0)
        #expect(ExerciseAnimation.sample(held, at: 1).effort == 1)
    }

    @Test func faceIsDeterministic() {
        let nod = Self.makeNod()
        for t in [0.0, 0.13, 0.5, 0.72, 0.85, 0.999] {
            #expect(nod.face(at: t) == nod.face(at: t))
        }
    }

    @Test func effortSquintsTheEyes() {
        let nod = Self.makeNod()
        // Peak effort (0.8) mid-nod squints; low effort (0.2) does not.
        // Rep 0 peak is at set phase 0.5/3.
        let squinting = nod.face(at: 0.5 / 3)
        let relaxed = nod.face(at: 0.01)
        #expect(squinting.eyeOpenness < 0.8)
        #expect(relaxed.eyeOpenness > 0.95)
    }

    @Test func blinkDipsAndRecovers() {
        let nod = Self.makeNod()
        let atCenter = nod.face(at: 0.95)
        #expect(atCenter.eyeOpenness <= 0.15)
        // Far from the bump (late eccentric, low effort, no tiredness)
        // the eye is essentially open.
        let outside = nod.face(at: 0.6)
        #expect(outside.eyeOpenness > 0.9)
    }

    @Test func tirednessRisesOnlyInTheRestBeat() {
        let nod = Self.makeNod()
        #expect(nod.tiredness(at: 0.2) == 0)
        // Middle of the rest beat: fully tired, eyes drooped to half.
        let restMid = 2.0 / 3.0 + 0.5 / 3.0
        #expect(nod.tiredness(at: restMid) == 1)
        let face = nod.face(at: restMid)
        #expect(abs(face.eyeOpenness - 0.5) < 1e-9)
        // The seam back into the next set is continuous: tiredness has
        // fully released by the end of the beat.
        #expect(nod.tiredness(at: 0.9999) < 0.01)
    }

    @Test func cuesActivateInsideTheirWindowOnEveryRep() {
        let nod = Self.makeNod()
        // Window 0.1...0.5 rep-relative: active at rep phase 0.3 in BOTH reps.
        #expect(nod.activeCueIndices(at: 0.3 / 3) == [0])
        #expect(nod.activeCueIndices(at: (1 + 0.3) / 3) == [0])
        // Inactive outside the window and during the rest beat.
        #expect(nod.activeCueIndices(at: 0.8 / 3).isEmpty)
        #expect(nod.activeCueIndices(at: 0.9).isEmpty)
    }

    @Test func restingPoseAndStepPhases() {
        let nod = Self.makeNod()
        // restingPhase 0.5 samples pose B.
        #expect(abs(nod.restingPose.angles(.neck).pitch - 30 * .pi / 180) < 1e-9)
        // Step phases: the rep keyframes' set-relative ts, final dropped.
        let expected = [0.0, 0.5 / 3.0]
        #expect(nod.stepPhases.count == expected.count)
        for (got, want) in zip(nod.stepPhases, expected) {
            #expect(abs(got - want) < 1e-9)
        }
    }
}
