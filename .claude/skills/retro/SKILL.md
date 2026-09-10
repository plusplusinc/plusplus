---
name: retro
description: After a merge, find what slowed the work or went wrong, check that the brief was useful, and delete or fix anything in the rules, skills, and docs that no longer describes the code. Applies fixes at the lowest altitude, in a PR the maintainer reviews. Use after each merge to main, or on request over a range of merges.
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(scripts/xcode-cloud.py:*), Bash(scripts/board.sh:*), Read, Glob, Grep
---

Step 6 of `docs/process.md`. Input: a merged PR number, or a range for a catch-up. Output: a
short report, and when there is something to fix, one PR.

## Stopping rules, read first

- **A PR that came out of a retro does not get a retro.** Its body says "Retro of #N". The
  loop ends there.
- **Nothing found means nothing written.** A one-line report, no PR, no memory note.
- **One fix per recurring finding.** If the previous retro already fixed it, the fix did not
  work; say that instead of fixing it again.
- **One mistake is noise.** A mistake that happened once is reported, not fixed, unless the
  fix is a deletion. Twice, it gets a check that makes it impossible. The record of past
  findings is the bodies of earlier retro PRs: `gh pr list --search "Retro of in:title"`.
- **One retro per merge.** Before starting, check that no retro PR, open or merged, already
  names the PR number. The cloud routine and a local session can both run this.

## 1. Collect

For each PR: `gh pr view` for commits, review threads, and how long it took from open to
merge; `gh api repos/{owner}/{repo}/pulls/N/comments` for inline review; the diff; the Xcode
Cloud runs it caused (`gh pr checks`, and `scripts/xcode-cloud.py builds` when the App Store
Connect key is available) and why any failed; the board card, if there was one; the Friction
line in the PR body, which is where the session that did the work recorded what was retried,
what the maintainer corrected, and what took longer than it should have.

## 2. Ask three questions

1. **What slowed this down or went wrong?** Failed CI runs, review rounds, a wrong first
   attempt, a rule the agent needed and did not have, a tool that misbehaved.
2. **Was the brief useful?** Did the problem statement hold, did the criterion get checked,
   did the scope hold. A PR with no card is itself a finding once cards exist.
3. **Does everything still describe the code?** Sweep `CLAUDE.md`, `.claude/rules/`,
   `.claude/skills/`, and `docs/` for statements the merge made false, or that a decision
   recorded in memory has overtaken. Delete before rewriting.

## 3. Route each finding

The lowest altitude that can hold the fix:

```
script > hook > rule > skill > agent memory > CLAUDE.md
```

A script makes a mistake impossible; a hook catches it on every edit; a rule tells the agent
when it reads the file; a skill tells it when it does the task; memory records what is about
the maintainer or the project rather than the code; `CLAUDE.md` is for what every session
must know and is the last resort. Anything about how the maintainer prefers to work goes to
memory, not the repo (see the repo-may-become-public rule).

## 4. Land it

One branch, one PR titled "Retro of #N: <the main change>", body listing each finding and
where its fix went, with the fixes the retro decided not to make and why. Repo changes go
through `/pr` like any other; the body is the record the next retro reads, so list findings
one per line. Anything about how the maintainer prefers to work goes to agent memory instead
and is mentioned in the body without its content. Then report to the maintainer: findings,
fixes, and anything that needs their decision.

## How it runs

A cloud routine runs this skill on every pull request event (GitHub webhook) and once nightly
as a fallback, exiting at once unless a merge to `main` is waiting for its retro; see
`docs/agent-tooling.md`. That session never saw the work: it has only what the PR carries,
which is why the template asks for Verified, Friction, and Card lines. It has no local state,
no App Store Connect key, and cannot run the Mac lint, so its PR relies on CI for that. A
local session may run the skill too, for a merge it made, and the one-retro-per-merge rule
keeps the two from colliding.
