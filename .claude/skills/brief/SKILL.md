---
name: brief
description: Turn a kernel (a sentence, a screenshot, a design prototype, a memo) into a brief on the project board, argued and scoped, ready for the maintainer to approve. Use whenever the user throws out an idea, a bug, or a hunch, before any code.
allowed-tools: Bash(scripts/board.sh:*), Bash(git log:*), Bash(gh pr list:*), Bash(gh pr view:*), Read, Glob, Grep
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

Write the body to a file under `.build/` and `scripts/board.sh add "<title>" <file>`. If it
belongs to a feature in the board README, `scripts/board.sh feature <id> "<name>"`; anything
else (tooling, a bug, process) stays a standalone task. Draft
items are private; the repo is not. A bug any user of a shipped build could hit is published
at once (`scripts/board.sh publish`); everything else stays a draft until a PR is about to
implement it, so the PR can close it and the reasoning ships with the code. Before publishing,
delete from the body what must not be public: strategy and why-now reasoning, personal or
health data, unreleased design work, anything about other apps. If that leaves nothing useful,
the card stays private and the PR names it by title.

## 4. Queue it

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

## 5. Hand off

Reply with the card id, the classification, where it landed in the queue and why, and the one
thing in the brief the maintainer is most likely to disagree with. The maintainer approves by
leaving it there and vetoes by reordering or parking it; do not move it to In Progress
yourself.
