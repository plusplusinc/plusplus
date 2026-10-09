---
name: onward
description: Lead the next card on the board, a feature slice or a standalone task, from a fresh context to a merged PR. Use when the maintainer says /onward, "next slice", "what's next", or "pick up where we left off".
---

The main session runs this as the lead described in `CLAUDE.md` ("Building features"). The
maintainer clears the context between slices, so everything needed to continue lives on the
project board and in `.slices/`.

## Start

1. Read the board's README (`gh project view 2 --owner plusplusinc --format json --jq .readme`):
   the settled design per feature and the standing setup.
2. Find the card: the In Progress card, otherwise the topmost Todo card (`scripts/board.sh
   list` prints the board's order, then `scripts/board.sh show <id>`). The board's order is
   one queue: a card with a Feature is a slice of that feature, one without is a standalone
   task (tooling, a bug, process), and a Backlog card is parked, never picked.
   Its body holds the scope, the acceptance criteria, and a State section with the worktree,
   branch, PR, phase, and next step.
3. Read the `.slices/` files that State names: the newest handoff or verify report. Read
   summaries, not code; subagents read code.
4. Say in two or three lines where the slice stands and what happens next, then do it. Ask only
   for product calls.

## Run the slice

- Starting a slice: move its card to In Progress, sharpen its acceptance criteria into
  `.slices/sliceN-spec.md`, then run the planner, the builder, the verifier, and a builder
  again for what the verifier found, as `.claude/agents/` describes. Every file path you give a
  subagent is under `.slices/`. Size the team to the card: a small task with no UI can go
  straight to a builder with the spec as its plan, and a task the maintainer can't try on the
  phone skips the try-out.
- When a subagent runs long, have it write `.slices/sliceN-handoff.md` and continue with a
  fresh one in the same worktree.
- Rewrite the card's State section (`scripts/board.sh body`) whenever a phase ends, so a
  cleared context can resume mid-slice.

## Finish

1. Look at the verifier's screenshots yourself, then install the build on the maintainer's
   simulator (`scripts/run.sh`, default simulator) and tell them what to try.
2. After the maintainer's go-ahead: merge once checks pass, move the card to Done, run
   `scripts/tidy.sh` (it removes the merged worktree and branch; it also runs at every session
   start), and delete the slice's `.slices/sliceN-*` files.
3. Record decisions made during the slice in the board README, and re-plan the later cards if
   they changed.
4. Tell the maintainer the slice is merged and that it's a good moment to `/clear` and run
   `/onward` again.
