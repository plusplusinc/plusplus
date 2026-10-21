---
name: brief
description: Turn a kernel (a sentence, a screenshot, a design prototype, a memo) into a brief on the project board, argued and scoped, ready for the maintainer to approve. Use whenever the user throws out an idea, a bug, or a hunch, before any code.
allowed-tools: Bash(scripts/board.sh:*), Bash(git log:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh issue edit:*), Read, Glob, Grep
---

This skill produces the brief and nothing after it. No branch, no code, no spike until the
card is in In Progress.

## 1. Classify

- **Feature**: something the user cannot do today. Argue the problem first, from
  `docs/principles.md`: say what is hard or missing, for whom, and why now. If the kernel looks
  like a solution ("add a timer"), find the problem behind it ("rest between sets is guessed")
  and check it is the right one to solve before the one after it. Push back in the brief itself, with an alternative, when it is not.
- **Bug**: something does not do what it already promises. Reproduce it first (`/run`, tests,
  the log), write the reproduction into the brief, skip the argument.
- **Hunch**: a question that needs evidence. The brief proposes a spike and its shape:
  throwaway branch, promotable prototype, or shipped behind a flag. Say which and why.

## 2. Look before writing

`scripts/board.sh list` for an existing card on the same thing; `git log` and `gh pr list` for
prior work; the code for what exists; the memory for product context. A brief that ignores a
card already in Todo is a duplicate, not a brief.

## 3. Write the card

Title: what the user can do afterward, not the mechanism. Body, one screen, in this order,
every heading present even when its answer is one line:

```
## Problem
## Out of scope
## Success
## Plan
```

- **Success** is either "plain improvement, not measured" with the reason, or a criterion plus
  what gets measured, how, and when to check. A criterion the maintainer cannot judge from
  their phone or from the analytics is not a criterion.
- **Plan** lists the model change, the views, the tests, and the screenshots the PR will carry
  (before and after for any UI). For a hunch, the spike and what answer would end it.
- **Tense** follows CLAUDE.md: a card is read before the work, during it, and after it, and
  every sentence has to be true whenever it is read.
  - Problem describes today in the present tense: "Today a routine is a list of names." Any
    other present-tense sentence has to be just as true today.
  - Plan is instructions: "Save a routine once anything in it changes."
  - Anything else the card will change says "will".
  - Acceptance criteria and Success are checks to run once the work is done, written as
    what someone does and what they should see: "Launch and leave without changing
    anything: nothing is saved."
  - Decisions say they were decided: "Decided: time will be a measure alongside reps."

  "A routine autosaves to Routines only once something changed" reads as a fact about the app
  today. On a card that hasn't been built, it is false.

Pass the body on stdin, as a quoted heredoc: `scripts/board.sh add "<title>" <<'CARD'`. The card
is the only copy; there is no draft file. If it belongs to a feature in the board README,
`scripts/board.sh feature <id> "<name>"`; anything else (tooling, a bug, process) stays a
standalone task. Draft items are private; the repo is not. A bug any user of a shipped build could
hit is published at once (`scripts/board.sh publish`); everything else stays a draft until a PR is
about to implement it, so the PR can close it and the reasoning ships with the code. Before
publishing, delete from the body what must not be public: strategy and why-now reasoning, personal
or health data, unreleased design work, anything about other apps. If that leaves nothing useful,
the card stays private and the PR names it by title.

## 4. Align

Before handing off, make sure the maintainer and the card agree. Restate it as what they will see
and do. Settled points name where they were settled (the board README, a design board, a
decision). Open points are listed with a recommendation each: screens with no design, content
nobody has chosen (lists, copy, defaults), conflicts with earlier decisions, and gaps between this
card and its neighbors. Check the card is one step that merges on its own and leaves the app
working; one bundling pieces that could each merge gets the split proposed as an open point. A
limit it proposes (a control turned off, an edit locked) names what would break today without it;
one that guards a case a later card brings belongs to that card. An open point that is a choice
between rules is a table of the cases where they differ, not prose. Their answers go into the body
as an "Aligned with <maintainer> <date>" list, and out of every section that still lists them as
open or plans otherwise; read the card back (`scripts/board.sh show`) before saying they're
recorded.
Anything they push out of scope becomes its own card, named in Out of scope. An
open point that doesn't change what gets built can stay open; say so in the body. A card
published as an issue is public: edit it with `gh issue edit <n> --body-file -` from a heredoc,
and keep the "Aligned" list to what may be published (section 3).

## 5. Queue it

`/onward` works through one queue: the Todo cards in board order, top first, the order the
maintainer drags them into. A new card lands at the bottom; place it with
`scripts/board.sh move <id> top` or `scripts/board.sh move <id> <card-it-follows>`
(`scripts/board.sh list` shows the queue). Rank it yourself:
- A bug in shipped behavior, or anything that slows every later card (build time, flaky tests),
  goes next, after the card in progress.
- A slice goes where its feature's sequence needs it.
- Everything else goes after the current feature's remaining slices, unless the maintainer said
  when they want it.
- A hunch, or a card the maintainer said to park, goes to Backlog
  (`scripts/board.sh status <id> Backlog`), which nothing picks up.

## 6. Hand off

Reply with the card id, the classification, where it landed in the queue and why, the open
points still waiting on an answer with your recommendation for each, and the one thing in the
brief the maintainer is most likely to disagree with. The maintainer approves by
leaving it there and vetoes by reordering or parking it; do not move it to In Progress
yourself.
