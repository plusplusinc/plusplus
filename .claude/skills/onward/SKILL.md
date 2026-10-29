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
   it yourself, and tell the maintainer in a line what it changed.
   A standalone card that changes nothing the maintainer sees in the app (tooling, CI, tests,
   process) is yours alone, as `CLAUDE.md` says: align it against the code yourself, run it,
   merge it green, and say in a line what landed. Run one alongside a product slice (a builder
   in its own worktree) rather than spending the maintainer's turn on it; with them engaged,
   lead the next product card.
3. Read the `.slices/` files that State names: the newest handoff or verify report. Read
   summaries, not code; subagents read code.
4. A card not yet started gets an alignment check before anything else (see the /brief
   skill's "Align"). Restate it as what the maintainer will see and do, reading each thing the
   app does today from `main`'s code before you say it, then check its Aligned list against the
   README, what merged since it was written, its neighbors on the board, and the pages of every
   design board and canvas drawn for its feature, for options drawn earlier and never picked
   (one card's alignment missed a control drawn for it a week before). Bring anything open,
   contradicted, or missing (an undesigned screen, content nobody chose, a gap no card covers),
   each with a recommendation. Record the answers in the card, make cards for what lands out of
   scope, and start a product card only on the maintainer's yes.
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
  it looks for.
  Before installing, check each thing they asked for in the round's screenshots, on content like
  theirs (as many exercises, equipment, long names). Then give their feedback to a fresh builder
  named for that round, which starts from the slice's handoff note and brings it up to date before
  it reports; resume a builder only to finish its own round. Wi-Fi first, link second: when no
  iPhone is in reach the script makes an install link instead, printing why each paired iPhone was
  out of reach (say that, not a guess), and when the phone is locked the build installs but
  doesn't open, so tell them to open PlusPlus. Send them the link it prints. The work goes on
  while they are away. The loop ends when they say it's right; then the builder runs its full pass
  and the verifier runs once. Their being away doesn't end it: work done while they are away is a
  round for them to try when they're back, and the full pass still waits for their word.
- When you or the maintainer settle something while a builder works, send it to that builder
  at once (SendMessage) and add it to the slice's handoff note, so the next builder has it too.
  A change the maintainer proposes and you agree with is settled: build it, never ask again.
  What you add to it is not: a cause you infer for something they felt, or a consequence you
  derive (a new shape, a new timing), goes to them as a question before any builder gets it.
- While the maintainer is still weighing a rule (asking whether it holds together, or offering
  another), send no builder any of the candidates: show them side by side as a table of the
  cases where they differ, and send the one they pick.
- A short reply ("yes", "go") answers only a yes-or-no question. When more than one question is
  open, when the last one asks which of several, or when the reply arrived within seconds of
  your message, ask which it answers before acting on it.
- A number a recommendation or a card turns on (a price, a quota, a machine's speed) is read
  from its source or measured, the cheapest way, before you recommend it or anything is built
  on it: a card whose go or no-go rests on one measures it as its first step.
- Reporting a phase as done, say where it went less deep than the card asked (what was compared
  only by name, sampled, or left out) before the maintainer has to ask. A fix to how something
  reaches them (a link, an install) is tried the way they will meet it before you call it fixed,
  or called untried, with what would show it works: #120 and #121 were each called fixed, and
  each design link still opened on the wrong question for them.
- A round that does what they asked only by adding something they didn't (a clip at an edge, an
  uneven gap) is not installed as a cost for them to judge: bring the ways to do it as a table,
  and build the one they pick. Read a request that names a size or a direction (smaller, to
  match, faster) against today's values in the code before you restate it; when the words and
  the numbers disagree, ask.
- Name a part of the screen by what the maintainer sees and where it is, not the platform's term
  for it (home indicator, safe area, popover), and before asking about something in their build,
  say where it is and what it does.
- A problem found outside the card, by the verifier or anyone, gets checked on `main` before
  the merge (its code, or a worktree of `main`), and becomes a card when `main` has it too,
  the slice's to fix when it doesn't; never leave it as a question for the maintainer.
- A screen with no design gets options drawn before it is built. The first is the platform's
  own control for the job (principle 4, "Native bones"), and each other option says what it does
  that the system one can't. An API offered as an option is one whose Apple doc (sosumi) says it
  works on iPhone. Draw them as phone-size frames on a Design canvas, a claude.ai artifact made
  from the Design type (Artifact `quickstart` with intent "design"), each decision numbered and
  each option lettered so the maintainer answers in one line ("1A, 2B"), options that differ
  only in how they move drawn moving (two stills that look alike read as one option), link it
  from the feature's section of the board README, and send its link: the maintainer chooses on
  the phone, where a file on the Mac never reaches them and `SendUserFile` fails in a session
  with no project thread. The link opens on exactly what is being asked: each open question has
  a page of its own holding only its frames, and the link sent is the canvas's with `#page-<page
  id>` after it and a tag of its own after a dot each time it is sent
  (`…/artifact/<id>#page-d5.r1029a`): the canvas opens on that page, but ignores a hash it has
  already seen, and reads only what comes before the first dot. The canvas's `launch`
  page alone doesn't do it, since the app reopens the page a returning viewer last saw. Since
  2026-10-28 a session started from the phone, and the subagents it starts, have the Artifact
  tool; check with ToolSearch before anyone draws, and without it publish through an interactive
  `claude` on the Mac, as agent memory describes.
- No time estimates. While a phase runs, tell the maintainer in a line now and then what it is
  doing, for which card, and why that still serves the card, without being asked. Every line of
  text you write reaches them, the text before a tool call included, which arrives as a message
  of its own: plan in your head, and write nothing before a tool call but what tells them
  something ("The canvas file hasn't changed, so my edit still applies" told them nothing). When
  a subagent's notice brings only what you already told them, send nothing for it: a second
  summary, or an ask repeated minutes after the first, is noise. A subagent or
  a CI watch in the background says nothing until it ends, and a watch can outlive its run, so
  while one runs, wake yourself about every 15 minutes (a background wait that notifies you) to
  read where it is at that moment (a subagent's transcript's last entry, the PR's `gh pr
  checks`) and send that line; a check that has finished is a result, whatever the watch says.
  A wake's message is what was true when you set it: cancel it when you stop what it watches,
  and when one fires, read your own steps since before taking anything it finds for someone
  else's. Before each new attempt or extra run, by you or a subagent, check that it is still
  worth doing for the card's goal. A flake's fix is proved from its cause (a log showing the
  failing order now handled, or a test that forces it), never by a count of clean runs: at a
  1-in-15 failure rate, a fix that did nothing still passes 30 runs about one time in eight.
  Without either, say so in the PR.
- Push only when CI's answer is needed: when the PR opens, after a round of fixes, and before
  the merge (the rebase "require up to date" asks for included). You and every subagent commit
  locally in between: rounds reach the phone by `scripts/device.sh`, not CI, and each push to a
  PR that changes the app spends a full Xcode Cloud run.
- After every push to the PR, yours or a subagent's, watch its "PR check" to the end yourself
  (see `/pr`): `gh pr checks <n> --watch --interval 60` with `run_in_background: true`, which
  notifies you when it exits. Stop a watch still running from an earlier push first
  (`TaskStop`), so each push brings one result. For a PR that changes the app it lasts as long as the Xcode Cloud
  run it waits for. A subagent's "still queued" is not a result. A failed run goes to a builder
  before anything else reaches the maintainer, unless "PR check" says the month's Xcode Cloud
  hours are likely spent, which goes to the maintainer; the go-ahead you ask for names the
  commit CI is green at.
- A test that fails on a PR's CI is diagnosed, never just rerun. A flake that is on `main` too
  gets fixed, as its own card ahead of the PR, before the PR merges.
- A round builds what the card's criteria cover. Feedback that reaches past them (a new look, a
  rename, a new rule) gets its own card through `/brief`, and you recommend that; the card grows
  only when the maintainer picks that over a card, and then you say how far past its starting
  criteria it now reaches.
- Telling the maintainer what a round or a change will do before it's built, keep today and the
  change apart ("Today …; with this round, …"); in the plain present it reads as how the app
  works now.
- Before saying what state anything is in, read it at that moment, even mid-summary: an agent
  running (its transcript's last entry and when it happened), a PR open or merged
  (`gh pr view`), a run passed. What you read earlier in the turn may have changed. An interrupt of your turn can stop background agents: after one,
  check each, and restart a stopped one from its commits and handoff without waiting to be asked.
- An ask still open when you repeat it in a later update says again, in a line, what it is and
  what a yes does, so it reads on its own: a bare "still open: merge #N?" hours after the
  explanation sends the maintainer back to ask what #N was.
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
2. After the maintainer's go-ahead (for a card that is yours alone, once the verifier and CI
   pass): merge once checks pass (a wait for that also ends when
   `gh pr view --json mergeable` reads `CONFLICTING`, since auto-merge waits on a conflict
   without a word; after any merge to `main`, check every PR that waits), move the card to Done, run
   `scripts/tidy.sh` (it removes the merged worktree and branch; it also runs at every session
   start), and delete the slice's `.slices/sliceN-*` files.
3. Record decisions made during the slice in the board README (read it with `scripts/board.sh
   readme`, then write the whole new text back with `scripts/board.sh readme <<'README'`), and
   re-plan the later cards if they changed.
4. Tell the maintainer the slice is merged and that it's a good moment to `/clear` and run
   `/onward` again.
