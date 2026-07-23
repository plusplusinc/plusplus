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
   - `grippingTheBar` — the whole-hand barbell servo (the grip round, from
     device feedback: hands slid 99 mm along the bench bar into a plate, and
     the wrap read underhand): per baked sample it re-solves the WHOLE left
     arm (shoulder 3 + elbow pitch/yaw + wrist 3, damped Gauss-Newton) so the
     palm keeps ONE STATION on the bar, the wrap is OVERHAND (left thumb
     INWARD — thumb-out is supinated), and the metacarpals continue the
     forearm; optional `elbowUnderBar` adds the pressing stack, optional
     `palmTarget` is for endpoint authoring, and `armSeed` picks the basin.
     Mirrored right; requires bilateral symmetry. Hard-won rules:
     - The overhand flip is ~180° about the forearm and NO single joint owns
       it — anatomy splits it across shoulder internal rotation (~90°), the
       elbow's radioulnar share (~23°), and wrist pronation (~88°); at some
       configurations the chain tops out just short, and the leftover reads
       as the natural diagonal bar placement (the grip-angle invariant allows
       25° for exactly this).
     - The Gauss-Newton SEED picks the basin. Author endpoints in the target
       basin and let lerped samples seed themselves (the bench), or — when
       the authored arms serve another servo's conventions — pass `armSeed`,
       INTERPOLATED from the pose's own hinge so it tracks the body (the
       deadlift: a constant seed left the standing end so far from home the
       solver crossed basins and put the bar in the belly).
     - Servos COMPOSE in order: `coordinating` first (it speaks the simple
       pitch-only arm convention and owns the bar's path), `grippingTheBar`
       second (it rebuilds the arm on that path and owns the hand).
     - Per-sample greedy search is NOT a continuous map; a damped local
       root from a continuous seed is.
   - `plantingPalms` — the floor-hand arm servo (the hand round: the
     planted push-up hands read as curled-under puppy paws): re-solves
     the whole arm so the flat `MascotHand` palm plane faces the floor
     with fingers extended forward-inward, wrist pinned where the
     chain planted it, elbow stacked fore-aft (laterally free — deep
     reps flare the elbows). The fingers-forward twist is ~180° about
     the forearm and splits across humeral spin + pronation, exactly
     like the overhand wrap; seed the wrist in the extension basin and
     pass a `shoulderSpinSeed` for the humeral half. At the deep
     bottom the twist chain tops out — pair the servo with
     lowest-hand-point anchoring (the push-up's `settledPlanted`) so
     the hand rocks onto its planted fingers instead of piercing or
     hovering. Forearm-supported moves (the plank) should NOT fight
     this at all: their honest hand is the neutral `.fist` at wrist
     zero-plus-pronation, thumb up, pinky edge riding the floor.
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

- `MascotGrip` — the grip channel (`palmOffset` — barbell AND dumbbell
  handles rest there), the contact pad, every prop dimension.
- `MascotHand` — the hand itself: palm slab, finger, and thumb segments
  per state (gripped wrap around a radius, planted flat palm, neutral
  fist, idle), ONE segment list the renderer meshes and the invariant
  capsules are both built from. `state(for:)` is the per-move rule.
- `MascotSupport` — support-surface geometry (the flat bench: pad top height,
  half-extents, world placement) plus its collision rails. The renderer
  builds the bench from these numbers; the five-points-of-contact invariant
  proves the body lies on them.
- `MascotBalance` — segment masses, center of mass, support polygon.
- `MascotCollision` — body capsules mirroring the meshes. **A body part
  exists in BOTH the renderer and the collision model, or in neither.**
- `MascotSkeleton` sole landmarks — heel/ball corners (ankle frame), cap
  front corner (toe frame). Floor = y 0; rest soles sit exactly ON it.

## Supine (bench) moves — placement notes

- The body pitch lives in `rootRotation` (≈ −89°, like the push-up's +72°);
  `angles(.root)` stays inside its ±5° range.
- The torso capsules' radii differ (pelvis 0.075 / abdomen 0.08 / cowl
  0.085), so a LEVEL body cannot graze the pad everywhere — about a degree
  of head-up tilt balances all three inside the contact band. The helmet
  (r 0.115) out-bulges the back plane by 4 cm; ~7° of chin tuck rests it on
  the pad.
- Legs hang toward the floor through hip EXTENSION (~+21°, near the +25°
  anatomical stop); the ankle closes the chain to a flat sole:
  `ankle = −(rootPitch + hip + knee)`.
- The camera frames supine moves from the side (`rootRotation.pitch <
  −π/4` in `MascotView.framing`).
- The standing servo (`coordinating`) does not apply; the bench's servo is
  `grippingTheBar` (station + overhand wrap + `elbowUnderBar` for the
  pressing stack), and the contact/collision invariants police the rest.

## What the invariants will demand (so author for them up front)

Full ROM for the movement's teaching point (depth below parallel, pulls from
the floor, full arcs) · anatomical joint ranges · grip axis within 25° of the
bar (the pronation chain's honest shortfall — the diagonal-grip look) · hands
hold ONE STATION, wrap OVERHAND, and the `MascotHand` finger capsules never
pierce what they grip (tangent-wrap graze ≤ 6 mm) or a plate/head face ·
planted flat hands REST on the floor (never pierce, never hover; residual
deep-bottom tilt rocks onto the fingers) · equipment ≤ 8 mm graze, never
through floor or body · soles/pads may
touch the floor, nothing else may · center of mass inside the CONTACT-derived
support polygon (strict at held phases) · slower eccentric · effort peaks on
the concentric, blinks at low effort · 1–2 synced cues with ≥30%-of-rep
windows plus ≥1 static · seam continuity and exact pause stillness · declared
airborne windows must free-fall at 9.81 m/s².

## Archetypes (start from the nearest)

- **Squat pattern** — Squat, Goblet Squat, Jump Squat's crouch. `repCycle` + `coordinating`.
- **Hinge** — Deadlift, Barbell Row (held isometric), Kettlebell Swing (ballistic rhythm). `coordinating` + `grippingTheBar` where a bar rides.
- **Standing arm work, lift-first** — Dumbbell Curl, Lateral Raise, Overhead Press. `liftCycle` (bottom dwell, rise, squeeze, slow lower); the OHP adds an authored bar line.
- **Floor prone** — Push-Up, Plank. `anchored`/`plantingPalms`, toe-anchored straight line.
- **Floor supine** — Bench Press (pad), Glute Bridge, Sit-Up (floor). Flat soles via `ankle = -(rootPitch + hip + knee)`; back capsules rest within the graze; `supineTiredBeat` (the chin-up phew digs the helmet).
- **Hanging** — Pull-Up. `hangingFromTheBar` + `dynamics.hangsFromBar` (swaps the grounded law for the hang law: palms on the bar line, one station, feet clear).
- **Ballistic** — Jump Squat. Declared `airborneWindows`, dense linear parabola keys, rigid flight pose, zero-sum leg chain, one-sided sole clamps on launch/landing legs.
- **Asymmetric** — Single-Leg Calf Raise, Reverse Lunge. Build joint dicts per side; `anchored` on the stance ankle; join the symmetry exemption.

## Scale-out lessons (2026-07-23, the 7-to-17 round)

- **Scan configs with the servo's own objectives.** A config scanned with a
  soft hand-continues-forearm floor parks fine on its own — then the
  per-sample servo finishes that objective and drags the palm 10 mm off
  station. Put the servo's terms in the scan cost.
- **Multi-config paths need ONE basin family.** Bound shoulder roll in the
  scan and seed chained stations from the previous winner. An unbounded scan
  landed a rack at roll 100 (elbows sideways) and the unwind swung the
  mid-press wild.
- **Author the bar path as GEOMETRY when it matters.** An angle-space lerp
  arcs a pressed bar through the helmet; per-sample `palmTarget` on a
  piecewise-linear line pins it (54 mm in-head → 9.6 mm clear on the OHP).
- **Feedforward station compensation**: solve once, measure the equilibrium's
  offset, re-solve with the target shifted the other way. The servo's soft
  terms leave a locally-affine bias this cancels in one round.
- **Eased legs beat dense legs.** Velocity-zero at leg ends kills spline
  corner overshoot; densifying a lerp-seeded servo bake instead EXPOSES
  per-sample solver wobble (11 mm jitter, joint-speed spikes). Six eased
  steps per leg was the OHP's landing spot. Continuation seeding (each
  sample seeded from the previous solution) compounds lag and snaps at the
  seam — use interpolated seeds, never chained ones.
- **Bounded-authority pins.** The pull-up's station holds via a bisected
  symmetric shoulder-yaw + elbow-yaw delta with hard clamps inside the
  anatomical table: enough authority to hold the path on station, too
  little to fold the arms across the midline (the unbounded version drove
  them 45 mm into each other).
- **Never author AT an anatomical stop.** The Catmull spline overshoots
  ~1 degree past its keys: spine at its -10 stop or shoulder yaw at ±95
  fails the joint-range sweep on interpolated samples. Stay 1-2 degrees
  inside; clamp any pin's writes 2.5 degrees inside.
- **Zero-sum leg chains through ground transitions.** If both endpoint
  chains satisfy hip + knee + ankle = -rootPitch, every LERPED sample keeps
  the soles parallel to the floor — the Jump Squat's toe corner stopped
  digging the moment its flight pose summed to zero like its crouch.
- **The helmet is bigger than its orbit.** Chin-over-bar is geometrically
  impossible (the palm-to-helmet chain radius is shorter than the helmet
  radius + bar); the honest pull-up finish is the hard neck arch — look
  over the bar — which also happens to be textbook.
- **Flare waypoints move arms past the helmet.** A straight hang-to-top
  lerp sweeps the upper arms through the head; 6- and 12-degree shoulder
  roll waypoints (what elbows really do mid-pull) clear it.
- **The lateral-raise wrist law**: one fixed wrist yaw reads as a neutral
  grip at the hang AND palm-down at the top — shoulder roll carries the
  hand; don't animate the wrist to fake it.
- **Supine bridging pivots at the shoulder blades**: root pitch goes PAST
  -90 (the torso points downhill to the grounded shoulders), the ankles
  re-plant via `anchored`, and the chin tuck (+neck) keeps the helmet
  resting. Counter-flexing the spine flat is a different (smaller) bridge.

## Dynamics extension points

`MascotDynamics` on the animation: `airborneWindows` (ballistic invariant
takes over), `handsBearWeight` (flat fingers + pads at the floor). Swung
inertia, band elasticity, and machine rails join HERE as declared properties
with paired invariants when their first moves land — never as per-move hacks.
