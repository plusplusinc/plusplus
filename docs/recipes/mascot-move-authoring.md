# Authoring a mascot move

The loop that has authored every move so far, written down so the ~250-move
scale-out doesn't re-derive it. Everything runs on Linux: `swift test` in
`PlusPlusKit/` is the whole verification story.

## The loop

1. **Pick the archetype.** Squat pattern, hinge, standing arm work, floor work,
   heel raise — find the closest existing move in
   `PlusPlusKit/Sources/PlusPlusKit/Mascot/Moves/` and start from its shape.
2. **Author intent, not numbers.** Poses come from `MascotPoseBuilder`
   fragments (`torso`; `symmetricArms` with its clavicle channel;
   `symmetricLegs` with its toe channel) merged with `merge`. Eyeball the key angles first;
   they only need to be in the neighborhood.
3. **Scan for the numbers that matter.** For any pose with real constraints
   (a grip on a bar, a depth target, a balance requirement), write a THROWAWAY
   scratch test (`ScratchFooTests.swift`, deleted before commit) that grids or
   coordinate-descends over the free angles and prints the constraint values
   per candidate: palm position, grip alignment (`MascotCollision.
   worstGripMisalignment`), equipment graze (`maxEquipmentPenetration`),
   center of mass vs `MascotBalance.supportPolygon`, sole depths. Pick a
   candidate with margin on every bound, round to one decimal, re-measure the
   ROUNDED values (rounding once cost 7 mm of graze).
4. **Solve, don't hand-place.** Roots and paths go through solvers:
   - `plantingFeet` — standing moves; pins the ankle mean to rest.
   - `anchored` — floor/pivot moves; pins named joints to world targets
     (push-up wrists, the calf raise's ball-of-foot).
   - `solvingToes` — pointed/tucked feet; plants the sole's lowest corner.
     The sole-height curve is non-monotone: the pose's AUTHORED ankle pitch
     picks the branch, the solver only refines. Author your intent.
   - `coordinating` — the path servo: center of mass over the feet, bar over
     the midfoot, equipment clearing the legs, at EVERY baked sample. A lerp
     between two legal poses is not itself legal.
5. **Bake transitions.** `repCycle` for descend-pause-drive-settle moves
   (its defaults encode the slower eccentric); raw `span`s for anything else.
   Every span takes the SAME solve closure as the endpoints, and endpoints go
   through it too — pause keyframes must be EXACT pose copies or the spline's
   stillness detection loses the ease-into-pause. Dense baking (`steps: 24`)
   when a servo fights the lerp hard (the deadlift's bar-around-the-shins).
6. **Run the sweep, read the numbers.** `swift test --filter Mascot`. Every
   failure message carries the offending t, joint, pair, or depth — tune the
   authored angles toward the numbers, never the invariant toward the pose.
   (Widening a bound is allowed only when the HUMAN range was wrong — cite
   anatomy in the comment, like hip adduction and wrist pronation.)
7. **Register + name-match.** Add to `MascotMoves.all`; the exercise name must
   EXACTLY match a `SeedData` built-in (app-side `MascotTests` enforces it).
   Update `catalogIntegrity`'s count. Asymmetric moves get the exemption in
   `symmetricMovesAreExactlySymmetric`; new loaded moves join the
   `effortPeaksWhileTheLoadRises` / `theEccentricIsControlled` argument lists.

## Sign conventions (the ones that bite)

- Y up, mascot faces +Z, LEFT = +X. R = Ry(yaw)·Rx(pitch)·Rz(roll), intrinsic.
- Positive pitch tips up-bones forward (+Z) and hanging bones backward (−Z);
  a +Z bone (the toe cap) tips DOWN with positive pitch.
- Elbow flexion NEGATIVE; knee flexion POSITIVE; ankle plantarflexion
  POSITIVE (the calf raise's first cut had this inverted and drove the heel
  into the floor); toe-cap extension at the ball NEGATIVE.
- Hip: negative pitch = flexion (leg forward). With a foot ANCHORED, hip
  extension (+) sways the BODY forward over it — weight shifts are authored
  at the hip, not by teleporting the root.
- Right-side twins negate yaw and roll (`mirroredAngles`); `symmetric*`
  builders do it for you; `mirrored(_:)` flips a whole pose for alternating
  reps.
- Wrist yaw IS forearm pronation/supination (the forearm axis is the wrist
  frame's local Y). Clavicle: +roll shrugs up, +yaw retracts.

## The physical contracts (shared Kit↔renderer, never duplicated)

- `MascotGrip` — palm/pad offsets, every prop dimension.
- `MascotBalance` — segment masses, center of mass, support polygon.
- `MascotCollision` — body capsules mirroring the meshes. **A body part
  exists in BOTH the renderer and the collision model, or in neither.**
- `MascotSkeleton` sole landmarks — heel/ball corners (ankle frame), cap
  front corner (toe frame). Floor = y 0; rest soles sit exactly ON it.

## What the invariants will demand (so author for them up front)

Full ROM for the movement's teaching point (depth below parallel, pulls from
the floor, full arcs) · anatomical joint ranges · grip axis within 20° of the
bar · equipment ≤ 8 mm graze, never through floor or body · soles/pads may
touch the floor, nothing else may · center of mass inside the CONTACT-derived
support polygon (strict at held phases) · slower eccentric · effort peaks on
the concentric, blinks at low effort · 1–2 synced cues with ≥30%-of-rep
windows plus ≥1 static · seam continuity and exact pause stillness · declared
airborne windows must free-fall at 9.81 m/s².

## Dynamics extension points

`MascotDynamics` on the animation: `airborneWindows` (ballistic invariant
takes over), `handsBearWeight` (flat fingers + pads at the floor). Swung
inertia, band elasticity, and machine rails join HERE as declared properties
with paired invariants when their first moves land — never as per-move hacks.
