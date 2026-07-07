---
name: deload-check
description: Analyze training history for progression stalls and recommend a deload or target adjustment. Use when the user feels stuck, asks whether to deload, or wants a plateau check on an exercise.
---

# Deload check

Read-only analysis: find where progression has stalled and say what you'd
change. Applying any change goes through `/tweak-program` (branch + lint),
never directly from here.

## Detecting a stall

Use `stats` for the per-exercise shape and `get_history` for the set-level
detail (or read `history/YYYY/` files directly without MCP). For each exercise
with enough data, look at the last 3–5 appearances:

- **Stalled**: same top weight AND same-or-fewer reps across 3+ sessions.
- **Grinding**: weight held but actual reps sliding below target, or logged
  sets shrinking session over session.
- **Progressing**: weight or reps moved anywhere in the window — not a
  candidate, say so and move on.

Fewer than 3 appearances is "not enough signal", not a stall.

## What to recommend

- A classic deload: cut the working weight ~10% (round to the equipment's
  step — 5 lb plates, 2.5 for microplate gear) and rebuild over 2–3 sessions.
- Or a volume cut (one fewer set) when reps are grinding but weight is moving.
- Or a target adjustment: if the rep range is never reached at the current
  weight, propose the range the last month actually supports.
- Name the exercise, the evidence (dates + numbers), and the single change
  you'd make. Offer to hand it to `/tweak-program` as a proposal.

## Framing rules (non-negotiable)

- Anti-shame: a deload is a strategy, not a setback. Never "you failed to
  progress" — the data says "this weight is fully adapted; drop to reload."
- Don't pathologize normal variance: one flat session is noise. Three is a
  pattern.
- If nothing is stalled, say so plainly and celebrate what's moving.
