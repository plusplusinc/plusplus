---
name: weekly-review
description: Summarize the last week of training from a PlusPlus workout repo — sessions, per-exercise increments, and streak. Use when the user asks how their training week went, wants a weekly review, or asks what changed since last week.
---

# Weekly review

Summarize the last ~7 days of training from this repo's history, in PlusPlus's
quiet-terminal voice: lowercase monospace for data, sentence case for prose.

## Getting the data

Prefer the MCP tools if the `plusplus` server is connected: `get_history`
(newest first; every set carries targets and actuals) and `stats` (per-exercise
aggregates). Without MCP, read the files directly: sessions live under
`history/YYYY/` as one JSON file per finished session (append-only), routine
templates under `program/routines/`.

## What to report

1. **Sessions this week** — one line each: `date · routine · sets · duration`.
2. **Increments (++)** — per exercise, compare this week's best completed set
   against the previous appearance of that exercise in history. Weight up
   beats reps up when both moved. Format deltas like the app: `+5 lb`,
   `+2 reps`, `new` for a first appearance, `=` for holding steady.
3. **Streak** — consecutive weeks (ending this week) with at least one
   session. One number with context: `4 weeks running`.
4. **The week ahead** — if routines under `program/` imply a cadence the
   user mentioned, note what's likely next. Skip this if you'd be guessing.

## Framing rules (non-negotiable)

- Anti-shame is a design invariant. Celebrate increments and presence.
  Regressions and missed days are reported as neutral data or not at all —
  never with failure language ("only", "just", "you missed", "fell short").
- Holding a weight steady IS a result. `=` is not a problem to fix.
- Never invent numbers. If history is empty or thin, say what's there and
  stop. A one-session week gets the same respect as a five-session week.
