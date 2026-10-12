---
name: onward
description: Lead the next card on the board, a feature slice or a standalone task, from a fresh context to a merged PR. Use when the maintainer says /onward, "next slice", "what's next", or "pick up where we left off".
---

The main session runs this as the lead described in `CLAUDE.md` ("Building features"). The
maintainer clears the context between slices, so everything needed to continue lives on the
project board; agents' technical working files live in `.slices/`.

## Start

1. Read the board's README (`scripts/board.sh readme`): the settled design per feature and the
   standing setup.
2. Find the card: the In Progress card, otherwise the topmost Todo card (`scripts/board.sh
   list` prints the board's order, then `scripts/board.sh show <id>`). The board's order is
   one queue: a card with a Feature is a slice of that feature, one without is a standalone
   task (tooling, a bug, process), and a Backlog card is parked, never picked.
   Its body holds the scope, the acceptance criteria, and a State section with the worktree,
   branch, PR, phase, and next step.
   An open nightly retro PR (title "Retro of", `gh pr list --search "Retro of in:title"`)
   comes before the card: rebase it, check each hunk against main, then trim, merge, or close
   it with the maintainer's go-ahead.
3. Read the `.slices/` files that State names: the newest handoff or verify report. Read
   summaries, not code; subagents read code.
4. A card not yet started gets an alignment check before anything else (see the /brief skill's
   "Align"). Restate it as what the maintainer will see and do, then check its Aligned list
   against the README, what merged since it was written, and its neighbors on the board. Bring
   anything open, contradicted, or missing (an undesigned screen, content nobody chose, a gap
   no card covers), each with a recommendation. Record the answers in the card, make cards for
   what lands out of scope, and start only on the maintainer's yes.
5. Otherwise say in two or three lines where the slice stands and what happens next, then do
   it. Ask only for product calls.

## Run the slice

- Starting a slice: move its card to In Progress, sharpen its acceptance criteria in the card
  itself (`scripts/board.sh body`), then run the planner, the builder, the verifier, and a
  builder again for what the verifier found, as `.claude/agents/` describes. Give each subagent
  the card id; it reads the criteria with `scripts/board.sh show`. Every file path you give a
  subagent is under `.slices/`. Size the team to the card: a small task with no UI can go
  straight to a builder with the card's Plan as its plan, and a task with nothing to see on the
  phone skips the loop.
- A slice with something to see runs as a loop with the maintainer (see the builder's
  "Rounds"). Install each round from the slice worktree with `scripts/device.sh`; a fresh
  checkout is a cold build. It builds the worktree as it is, so uncommitted edits are fine for a
  first look, but say so. Tell the maintainer in a line what changed and that the build is
  unverified, then pass their feedback to the same builder. When `scripts/device.sh` finds no
  iPhone, the phone is locked, away, or off the Mac's Wi-Fi: ask them to unlock it. If they are
  away, the work goes on and the build waits. The loop ends when they say it's right; then the
  builder runs its full pass and the verifier runs once.
- When a subagent runs long, have it write `.slices/sliceN-handoff.md` and continue with a
  fresh one in the same worktree.
- Rewrite the card's State section (`scripts/board.sh state <id> <<'STATE'`, quoted so
  backticks stay text) whenever a phase ends, so a cleared context can resume mid-slice.

## Finish

1. Look at the verifier's screenshots yourself. If the full pass changed anything the
   maintainer would see since their last round, install it again with `scripts/device.sh` and
   tell them what changed.
2. After the maintainer's go-ahead: merge once checks pass, move the card to Done, run
   `scripts/tidy.sh` (it removes the merged worktree and branch; it also runs at every session
   start), and delete the slice's `.slices/sliceN-*` files.
3. Record decisions made during the slice in the board README (read it with `scripts/board.sh
   readme`, then write the whole new text back with `scripts/board.sh readme <<'README'`), and
   re-plan the later cards if they changed.
4. Tell the maintainer the slice is merged and that it's a good moment to `/clear` and run
   `/onward` again.
