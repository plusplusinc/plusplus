# How work moves

The loop for features, bugs, and hunches. Keeping it short is the point; the mechanics are in
the scripts and skills it names.

## 1. Kernel

Work starts as anything: a sentence in chat, a screenshot of another app, a design prototype, a
memo. The agent turns it into a brief; the maintainer does not have to.

## 2. Brief

A brief is a draft item on the private project board. One screen, in this order:

- **Problem.** What is hard or missing today, for whom, and why it is the right problem to
  solve now. A feature gets this argued before anything else; a bug gets reproduced instead;
  a hunch gets a spike whose shape (throwaway, promotable, or shipped behind a flag) is decided
  per case.
- **Out of scope.** What the first version deliberately leaves out.
- **Success.** How we will know it worked. Some changes are plain improvements and say so; the
  rest name a criterion, what gets measured, and when to check.
- **Plan.** Model changes, views, tests, and the screenshots the PR will carry.

The maintainer approves by moving the card from Todo to In Progress. Discussion that changes
the brief goes on the card, not in chat.

## 3. Build

One branch per card, in its own worktree when more than one is in flight (see
`docs/agent-tooling.md`). `/pr` is the gate: simplify, review, lint, tests, and for UI a
screenshot that was looked at. A UI change carries before and after screenshots in the PR, and
a video when motion is the point.

## 4. Ship

Merge to `main`. Xcode Cloud archives it and TestFlight puts it on the maintainer's phone
(`docs/ci.md`). The card moves to Done.

## 5. Follow up

Only when the brief said to measure. At the agreed time the agent checks the data against the
criterion and posts the verdict on the card. A miss becomes a new card with a diagnosis;
nothing changes until that card is approved.

## 6. Retro

After every merge, look at what slowed the PR down or went wrong, whether the brief and its
criterion were useful, and whether any rule, skill, or doc no longer describes the code. Each
fix lands at the lowest altitude that can hold it, in a PR the maintainer reviews:

```
script > hook > rule > skill > agent memory > CLAUDE.md
```

One mistake is noise. The same mistake twice gets a check that makes it impossible.
Anything that no longer matches the code is deleted in the same retro.
