---
name: onward
description: Lead the next card on the board, a feature slice or a standalone task, from a fresh context to a merged PR. Use when the maintainer says /onward, "next slice", "what's next", or "pick up where we left off".
---

The main session runs this as the lead described in `CLAUDE.md` ("Building features"). The
maintainer clears the context between slices, so everything needed to continue lives on the
project board; agents' technical working files live in `.slices/`.

## Start

1. Read the board's README (`scripts/board.sh readme`): the settled design per feature and the
   standing setup. Telling the maintainer a settled rule, use its words there; a paraphrase
   drifts.
2. Find the card: the In Progress card, otherwise the topmost Todo card (`scripts/board.sh
   list` prints the board's order, then `scripts/board.sh show <id>`). The board's order is
   one queue: a card with a Feature is a slice of that feature, one without is a standalone
   task (tooling, a bug, process), and a Backlog card is parked, never picked. Once it's
   chosen, retitle the session for it, never leaving it "Onward": `set_session_title` needs
   this session's `session_id`, which `get_session` with no arguments returns.
   Its body holds the scope, the acceptance criteria, and a State section with the worktree,
   branch, PR, phase, next step, and the leading session's id. An In Progress card can still
   belong to another running session, its wrap-up after the merge included: before acting on
   one, check that session (`get_session` with that id) and its worktree's processes, and
   when it is active, leave the card to it and say so.
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

- Starting a slice: create its worktree as `CLAUDE.md`'s Branching says (the main checkout
  stays on `main`), move its card to In Progress, sharpen its acceptance criteria in the card
  itself (`scripts/board.sh body`), then run the planner, the builder, the verifier, and a
  builder again for what the verifier found, as `.claude/agents/` describes. Give each subagent
  the card id; it reads the criteria with `scripts/board.sh show`. Every file path you give a
  subagent is under `.slices/`. Size the team to the card: a small task with no UI can go
  straight to a builder with the card's Plan as its plan.
- A slice with something to see on the phone runs as a loop with the maintainer (see the
  builder's "Rounds"). Install each round from the slice worktree with `scripts/device.sh`; a
  fresh checkout is a cold build. It builds the worktree as it is, so uncommitted edits are fine
  for a first look, but say so. Tell the maintainer in a line what changed, that the build is
  unverified, and what to try: what to do and what they should see, never a check's name or what
  it looks for. Then give their feedback to a fresh builder named for that round, which starts
  from the slice's handoff note and brings it up to date before it reports; resume a builder
  only to finish its own round. Wi-Fi first, link second: when no iPhone is in reach the script
  makes an install link instead, printing why each paired iPhone was out of reach (say that,
  not a guess), and when the phone is locked the build installs but doesn't
  open, so tell them to open PlusPlus. Send them the link it prints. The work goes on while they
  are away. The loop ends when they say it's right; then the builder runs its full pass and the
  verifier runs once. Their being away doesn't end it: work done while they are away is a round
  for them to try when they're back, and the full pass still waits for their word.
- When you or the maintainer settle something while a builder works, send it to that builder
  at once (SendMessage) and add it to the slice's handoff note, so the next builder has it too.
  A change the maintainer proposes and you agree with is settled: build it, never ask again.
- While the maintainer is still weighing a rule (asking whether it holds together, or offering
  another), send no builder any of the candidates: show them side by side as a table of the
  cases where they differ, and send the one they pick.
- A problem found outside the card, by the verifier or anyone, gets checked on `main` before
  the merge (its code, or a worktree of `main`), and becomes a card when `main` has it too,
  the slice's to fix when it doesn't; never leave it as a question for the maintainer.
- A screen with no design gets options drawn before it is built. The first is the platform's
  own control for the job (principle 4, "Native bones"), and each other option says what it
  does that the system one can't. An API offered as an option is one whose Apple doc (sosumi)
  says it works on iPhone.
- No time estimates. While a phase runs, tell the maintainer in a line now and then what it is
  doing and why that still serves the card, without being asked. Before each new attempt or
  extra run, by you or a subagent, check that it is still worth doing for the card's goal; ask
  for the proof the change needs and leave repeat runs to Xcode Cloud.
- A test that fails on a PR's CI is diagnosed, never just rerun. A flake that is on `main` too
  gets fixed, as its own card ahead of the PR, before the PR merges.
- Before saying what state anything is in, read it at that moment, even mid-summary: an agent
  running (its transcript's last entry and when it happened), a PR open or merged
  (`gh pr view`), a run passed. What you read earlier in the turn may have changed. An interrupt of your turn can stop background agents: after one,
  check each, and restart a stopped one from its commits and handoff without waiting to be asked.
- When a subagent runs long, have it write `.slices/sliceN-handoff.md` and continue with a
  fresh one in the same worktree.
- Rewrite the card's State section (`scripts/board.sh state <id> <<'STATE'`, quoted so
  backticks stay text) whenever a phase ends, so a cleared context can resume mid-slice. It
  names this session's id, so another session can tell whether the card is still led.

## Finish

1. Look at the verifier's screenshots yourself. If the maintainer has not had the final build in
   hand (the full pass changed what they see, or there was no round), install it with
   `scripts/device.sh` (a link when the phone is out of reach) and tell them what to try, as for
   a round.
2. After the maintainer's go-ahead: merge once checks pass (a wait for that also ends when
   `gh pr view --json mergeable` reads `CONFLICTING`, since auto-merge waits on a conflict
   without a word; after any merge to `main`, check every PR that waits), move the card to Done, run
   `scripts/tidy.sh` (it removes the merged worktree and branch; it also runs at every session
   start), and delete the slice's `.slices/sliceN-*` files.
3. Record decisions made during the slice in the board README (read it with `scripts/board.sh
   readme`, then write the whole new text back with `scripts/board.sh readme <<'README'`), and
   re-plan the later cards if they changed.
4. Tell the maintainer the slice is merged and that it's a good moment to `/clear` and run
   `/onward` again.
