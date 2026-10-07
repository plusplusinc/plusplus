---
name: slice
description: Lead the next feature slice from a fresh context, from where the last session stopped to a merged PR. Use when the maintainer says /slice, "next slice", or "pick up where we left off" on feature work.
---

The main session runs this as the lead described in `CLAUDE.md` ("Building features"). The
maintainer clears the context between slices, so everything needed to continue lives in files.

## Start

1. Read `.build/slices/roadmap.md`. It holds the settled design, the slice list, the current
   slice and its files, and what was deferred. If it is missing, ask the maintainer where the
   work stands; don't reconstruct it from git.
2. Read the current slice's files it names: the spec, then the newest handoff or verify report.
   Read summaries, not code; subagents read code.
3. Say in two or three lines where the slice stands and what happens next, then do it. Ask only
   for product calls.

## Run the slice

- A new slice: write `.build/slices/sliceN-spec.md` (scope, out of scope, acceptance criteria,
  design boards) from the roadmap, then the planner, the builder, the verifier, and a builder
  again for what the verifier found, as `.claude/agents/` describes. Every file path you give
  a subagent is under `.build/slices/`.
- When a subagent runs long, have it write `.build/slices/sliceN-handoff.md` and continue with a
  fresh one in the same worktree.
- Keep `roadmap.md`'s "Current slice" section true as phases finish, so a cleared context can
  resume mid-slice.

## Finish

1. Look at the verifier's screenshots yourself, then install the build on the maintainer's
   simulator (`scripts/run.sh`, default simulator) and tell them what to try.
2. After the maintainer's go-ahead: merge once checks pass, move the card to Done, remove the
   slice's worktree.
3. Update `roadmap.md`: mark the slice done, note decisions made during it, re-plan the next
   slices if they changed, and set "Current slice" to the next one.
4. Tell the maintainer the slice is merged and that it's a good moment to `/clear` and run
   `/slice` again.
