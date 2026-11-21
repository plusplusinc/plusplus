---
name: onward
description: Lead the next card on the board, a feature slice or a standalone task, from a fresh context to a merged PR. Use when the maintainer says /onward, "next slice", "what's next", or "pick up where we left off".
---

The main session runs this as the lead described in `CLAUDE.md` ("Building features"). The
maintainer clears the context between slices, so everything needed to continue lives on the
project board. The steps under Start and Finish are a procedure; everything between is how to
judge, with the reason for each, since the cases it meets are never quite the ones written down.

## Start

1. Find the card: the In Progress card, otherwise the topmost Todo card (`scripts/board.sh
   list` prints the queue in order, then `scripts/board.sh show <id>`). A card with a Feature is
   a slice of that feature, one without is a standalone task, and a Backlog card is never
   picked. Its State section names the worktree, branch, PR, phase, next step, and the leading
   session's id. An In Progress card led by another session that is still active
   (`get_session` with that id, and its worktree's processes) is left to it, and you take the
   next Todo card; one naming this session's own id is yours.
2. Retitle the session for the card (`set_session_title`, with the `session_id` that
   `get_session` with no arguments returns), so the maintainer can find it later.
3. An open nightly retro PR (`gh pr list --search "Retro of in:title"`) comes first: update it
   from `main`, check each hunk against `main`, then trim, merge, or close it, and say in a line
   what it changed. So does a night card's PR left for you (`scripts/nightly-retro.sh show`):
   merge it or say why not.
4. Read the feature's settled design, `scripts/board.sh readme <feature>` (never the whole
   README, which is hundreds of lines), and the `.slices/` files State names. Quote a settled
   rule in the README's words; a paraphrase drifts.
5. A card that is yours alone (`CLAUDE.md`: tooling, CI, tests, process, a bug whose right
   behavior is settled) you align against the code yourself and run with a builder in its own
   worktree, never as the topic of the maintainer's turn: with them engaged, lead the next
   product card beside it.
6. A product card not yet started is aligned with the maintainer first, as `/brief`'s "Align"
   says. Restate it as what they will see and do, reading what the app does today from
   `main`'s code. Check it against the README, what merged since it was written, its neighbors
   on the board, and the options already drawn for its feature. Count the settings it puts on
   one row or sheet and check each against principle 3 ("Adding is cheap, removing is not"),
   even one aligned before. Bring what is open,
   contradicted, or missing, each with a recommendation; record the answers in the card; make
   cards for what falls out of scope; start on their yes.
7. Otherwise say in two or three lines where the slice stands and what happens next, then do it.

## The maintainer's attention

Their time is the scarce thing, and it is for the product.

- **Ask only for product calls**: what they would see or feel using the app by hand. A choice
  only a scripted build can reach, a safety default, a technical call, or a tooling design is
  yours: make it and say so in a line. A tooling design that ends in a step for them (run a
  command, paste a setting, allow a tool) is redone until it needs none; bring the ask only
  when no such design exists, saying what was ruled out.
- **Show, then ask.** Anything they can see goes on their phone the moment it builds
  (`scripts/device.sh` from the slice's worktree, which installs directly, else prints a link
  and why), before tests, cleanup, or review, and never as a step inside a longer job. A
  choice of look or behavior is drawn before it is asked or built: options as phone-size
  frames on a Design canvas (Artifact `quickstart`, intent "design"), the platform's own
  control first (principle 4), each other option saying what it does that the system one
  can't, options that differ in motion drawn moving. What a system control can do
  is read from its Apple doc then, never from memory. One small canvas per open question,
  since a link to a page of a larger canvas doesn't reliably open on that page, numbered and
  lettered so they answer in a line, linked from the board README. Check for the Artifact tool
  with ToolSearch before anyone draws; without it, publish as agent memory describes. A file
  on the Mac never reaches their phone.
- **Guess their call first.** Before an ask or a round reaches them, put your guess and why in
  agent memory's prediction log; after they reply, their call and, on a miss, what you
  misjudged. Agent memory holds what misses taught.
- **Every message reads on its own, on a phone.** Plain words about the app, not the work:
  name a part of the screen by what they see and where, a card by its title, an option by what
  it shows, never an item id, a canvas label, or a platform term. One question to a message,
  the next after their reply; each carries its link and says what a yes does, again when it is
  repeated hours later. With a build: what changed, that
  it is unverified, and what to do and what they should see. No time estimates; during a long
  phase, a line now and then on what is happening and why it still serves the card. Text
  before a tool call reaches them as a message, so write none that tells them nothing.
- **What they decided stays decided.** A choice they made stays in every brief and every later
  round; a clearly better alternative goes beside it, with the reason, never in its place. An
  option they turned down returns only with something new. What you infer from their words (a
  cause for something they felt, a consequence of a rule) goes back as a question before any
  builder gets it. A change they propose and you agree with is settled: build it, unless the
  code or the board records it as tried and dropped, in which case say why first.
- **Be sure what a reply means.** A short "yes" answers one yes-or-no question. When several
  questions were open, when the reply arrived within seconds of your message (it may answer
  the one before), when it states something instead of answering, or when it could read as its
  opposite, restate the reading you will build and confirm it. Praise with a
  question about a detail is a round, not the go-ahead. While they are still weighing a rule,
  show the candidates as a table of the cases where they differ, and build only the one they
  pick.
- **A note on how something feels is a design question.** Spacing is yours to settle as an iOS
  designer would: a note on one gap gets the whole surface set on the tokens' one rhythm, and
  you say what you chose. For a motion or its speed, say why it reads that way, set it against
  the named constants the app already uses for that kind of move (`.claude/rules/swiftui.md`
  maps them), and bring options before tuning a number. A request that names a size or direction is worked out against today's
  values first; when the words and the numbers disagree, ask. A round that can do what they
  asked only by adding something they didn't comes back as options, not as a cost to judge.
- **The card is the scope.** Feedback that reaches past its criteria becomes a card through
  `/brief`, and you recommend that; the card grows only when they choose so. A problem found
  outside the card is checked on `main`: the slice's to fix when only the branch has it, a card
  when `main` has it too, never a question left with them.

## What you say is checked

- Read a state when you report or build on it (a run's result, a frame, how the code stores a
  thing), never from an earlier look. After an interrupt, check each background agent and
  restart a stopped one from its commits and handoff.
- Reporting a phase done, say where it went less deep than the card asked. A fix to how
  something reaches them is tried the way they will meet it, or called untried; keep sending
  the proven way until the new one has worked for them.
- Before each new attempt or extra run, yours or a subagent's, check it still serves the card.
  A flake's fix is proved from its cause (a log showing the failing order handled, or a test
  that forces it), never by a count of clean runs; without either, say so in the PR. A test
  that fails on CI is diagnosed, never just rerun, and a flake `main` has too is fixed as its
  own card before the PR merges.

## The agents

- **Where they work.** A session in a worktree of its own (`git rev-parse --show-toplevel`
  is under `.claude/worktrees/`) builds the slice there, on its branch: Claude Code refuses a
  builder's edits in a worktree its session doesn't sit in (`docs/agent-tooling.md`). Only a session in the main checkout adds one
  (`CLAUDE.md`, Branching). Every path you give a planner or builder is absolute, under your worktree's
  `.slices/`; a prompt asking it to save a report asks its hand-back to say what it saved where.
- Start each verifier with the Agent tool's `isolation: "worktree"`, and say so in its prompt,
  naming the builder's worktree and the branch, so it works in a worktree of its own. Its
  evidence comes back in its scratchpad directory; copy what you keep into your `.slices/`.
- **The phases.** Move the card to In Progress, sharpen its criteria in the card
  (`scripts/board.sh body`), then planner, builder, verifier, and a builder for what the
  verifier found, each given the card id. Size the team to the card: a small task with no UI
  goes straight to a builder with the card's Plan. With something to see, rounds come first
  (the builder's "Rounds"); a round's brief asks for the change, and for a recording, frame
  grid, measurement, or cleanup only with the question it answers. A value they name a change to
  (a duration, a spacing) you change, commit, and install with `scripts/device.sh` in the
  slice's worktree while no builder runs there, with a line in the handoff note; the full
  pass reviews it. Before a builder round's install, check what they asked for in the
  round's screenshots on content like theirs, and that nothing they corrected earlier moved.
  The loop ends on their word that it's right; then the builder's full pass and the verifier run once,
  while the next card starts (below). Work done while they are away is a round for them to
  try, not the end of the loop.
- **Fresh and focused.** Each builder round or job gets a new agent named for it, starting from the
  slice's handoff note (`.slices/sliceN-handoff.md`) and bringing it up to date; resume one
  only to finish its own job, and wait for its hand-back before acting on its work. A decision
  made while a builder works goes to it at once (SendMessage) and into the handoff. A one-off
  task starts its kind's agent (`lookup`, `repro`, `edit`, `reviewer`); pass no model, since
  each definition sets its own.
- **Your context is for decisions.** Never read whole the board README, a dump of cards, a
  transcript, or a large diff: send it to a subagent that returns what the question needs.
- **After each agent hands back**, run `scripts/sim.sh shutdown` in the slice worktree and in
  any worktree of `main` it added (only those simulators, never another's), in case it skipped
  its own, and add its line to the PR's agent record with `scripts/agent-record.py line` and
  `post` (`docs/agent-tooling.md`, "Agent records"); lines from before the PR exists go with
  the first post.
- **While one runs**, it says nothing until it ends, so every 15 minutes read where it
  is and send the maintainer that line. Past 15 minutes, a round they wait on is told
  (SendMessage) to commit what builds and hand back, and that line says where it is. A wake you
  set says what was true then: cancel it when you stop what it watches, and a check that has
  finished is a result whatever a watch says. A turn with no text is sent back for one, so a
  notice that brings nothing new still gets a few words, never a second summary.
- Rewrite the card's State section (`scripts/board.sh state <id> <<'STATE'`) whenever a phase
  ends, with this session's id, so a cleared context or another session can pick it up.

## The next card starts at the go-ahead

Their word that a round is right ends their part, but the full pass, verifier, and CI take an
hour or more, so their next card starts then:

1. Record the slice's decisions in the board README (Finish 4) and the card's State.
2. Start the full-pass builder, and in the same turn propose a fresh session running `/onward`
   in its own worktree (`start_session`). It aligns, draws, plans, and runs rounds while this
   one finishes, one simulator agent each.
3. Finish here without them, bringing only what Finish says is theirs, naming this card.

Its planner reads this PR's diff where they share files, and its first round after this merge
merges `origin/main` in.

## Pushes and CI

Each push to a PR that changes the app spends a full Xcode Cloud run, so push only when CI's
answer is needed: when the PR opens, after a round of fixes, and before the merge. Commit
locally in between. Bring a pushed branch up to date by merging `origin/main`, never a rebase,
whose push agents are denied.

After every push, watch "PR check" to the end yourself (`/pr`): `gh pr checks <n> --watch
--interval 60` in the background, stopping an earlier watch first (`TaskStop`). A subagent's "still queued"
is not a result. A failed run goes to a builder before anything reaches the maintainer, unless
the check says the month's Xcode Cloud hours are likely spent, which is theirs. The go-ahead
you ask for names the commit CI is green at.

## Finish

1. Look at the verifier's screenshots yourself. Their saying a round looks right is the
   go-ahead: once the full pass, the verifier, and CI pass, merge and tell them in a line. Ask
   again only when the full pass changed something they would see, or there was no round,
   with that build on their phone first and what to try. A card that is yours alone needs
   only the verifier and CI. A wait for
   checks also ends when `gh pr view --json mergeable` reads `CONFLICTING`; after any merge to
   `main`, check every PR that waits.
3. Move the card to Done, run `scripts/tidy.sh`, and delete the slice's `.slices/` files.
4. Record the slice's decisions in the feature's section of the board README
   (`scripts/board.sh readme > .slices/readme.md`, edit that section, write the whole file
   back, delete it), and re-plan later cards they changed. Done at the go-ahead, unless the
   full pass changed them.
5. Tell the maintainer it is merged; with no next session running, that it's a good moment to
   `/clear` and run `/onward`.
