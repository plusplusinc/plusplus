---
name: tweak-program
description: Propose a change to the training program (add/adjust exercises, sets, targets, routines) as a reviewable git branch — never a direct edit. Use when the user wants to modify their program, add an exercise, change weights/reps, or restructure a routine.
---

# Tweak the program

Program changes are proposals, not edits: they land on a fresh git branch,
gated by lint, and a human merges them. History is the record and is never
touched.

## How to apply a change

With the `plusplus` MCP server connected, use `propose_program_change`:

- `files`: full interchange-JSON content for each changed file, paths under
  `program/` only (`program/exercises/<slug>.json`, `program/routines/<slug>.json`).
- The tool commits to a NEW branch, runs lint, and rolls the whole thing back
  if lint fails. It never pushes — tell the user the branch name and let them
  review, push, and merge.
- The repo needs a clean work tree; if the tool refuses, say why instead of
  working around it.

Without MCP (e.g. claude.ai reading the repo, or a plain shell): make the same
change by hand on a new branch and run `plusplus lint` before committing.
Same rules — `program/` only, small reviewable diffs, the human merges.

## Change hygiene

- Read the current file first (`list_exercises` / `list_routines` or the file
  itself); write back the complete document, not a fragment. The codec is
  deterministic — don't fight its key order or whitespace by hand-editing.
- One concern per proposal: "bump bench and add a back-off set" is one
  proposal; "bump bench and also reorganize leg day" is two.
- Renaming an exercise creates a NEW identity — history and "last time" stay
  with the old name. Warn before doing it; prefer editing everything except
  the name.
- Respect rep-range semantics: `reps`/`repsUpper` express "15–20"; shift the
  whole range rather than collapsing it.
- Explain the why in the commit message: the reasoning is the review.

## Never

- Write under `history/` (append-only, owned by the app and CLI).
- Commit to the current branch or push anywhere.
- Delete an exercise that history references without flagging it — files may
  be adopted back by sync, and history that points at it keeps working, but
  the user should know.
