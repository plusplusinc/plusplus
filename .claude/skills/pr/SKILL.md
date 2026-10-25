---
name: pr
description: Open or update a pull request for the current branch the way this repo expects, with lint and tests green first.
allowed-tools: Bash(scripts/lint.sh:*), Bash(scripts/test.sh:*), Bash(git:*), Bash(gh pr:*)
---

Branching and merge rules are in CLAUDE.md. Every diff also leaves the repo's prose true: read
it against CLAUDE.md, `.claude/`, `docs/`, and the README and fix each statement it makes false,
the status lines in CLAUDE.md and the README included. For a diff with no Swift in it, which
steps 1 and 2 below skip, that read is its only review. Then, before pushing, in this order,
because the first two change code and the rest verify it:
1. `/simplify` has run over the diff and its cleanups are applied.
2. `/code-review` has run over the diff and every confirmed finding is fixed or explained in
   the PR body.
3. `scripts/lint.sh` is clean.
4. `scripts/test.sh` passes, and so do the simulator tests the change touches
   (`scripts/test.sh sim <Target/Class>`). The full simulator suite is the PR's GitHub Actions
   check, "Lint and test"; a PR merges only when it is green. For docs or config alone,
   `scripts/test.sh` is enough.
5. For UI changes, a screenshot from `/run` has been looked at.

Steps 1 and 2 are skipped for a diff with no Swift in it. Give both the same target, filled in:
`<branch> against origin/main, checked out at <worktree>; say which branch and HEAD you
reviewed`. They, and every agent they start, begin in the session's own checkout, not in a
worktree you `cd` into, and with no target they review whatever is checked out there: on `main`,
its last squash merge, a pull request that already merged. Before acting on findings, check that
the branch and HEAD they name are the worktree's; if not, run again with the target named.

Then:
```sh
git push -u origin <branch>
gh pr create --title "<title>" --body-file - <<'BODY'   # or gh pr edit to update the body
<body>
BODY
gh pr checks --watch --interval 60                     # GitHub Actions' "Lint and test"
```

A failed check's log is one command away: `gh run view <run-id> --log-failed`, with the run id
from `gh pr checks`' link. A failed test run also uploads its result bundle, `test-xcresult`,
which `gh run download <run-id> -n test-xcresult -D .build/ci` fetches for `xcrun xcresulttool`
(snapshot diffs are attachments in it). `docs/pr-check.md` has the rest.

The body follows `.github/pull_request_template.md`: one paragraph on what and why, short
sections only if the change has distinct parts, a "Verified" line stating exactly what was run,
a "Friction" line saying what was retried, what was corrected and who found it (the
maintainer, an agent review, the verifier, CI), and what took longer than it should have, and a
"Card" line naming the board card, written as "Closes #N" when the card was published as an
issue so the merge closes it. Write Friction from the session, not from the diff, and put any
decision the diff does not explain in the body; the template says why the retro needs them.
`--fill` skips the template.

Write the body as the commit message it becomes, true before the merge too: today and the
change kept apart, as CLAUDE.md's "Tense tells the truth" says. The title is already the
commit's subject, so
do not repeat it in the body's first line, and leave each paragraph on a single line: GitHub
re-wraps the body when it squashes, so prose hard-wrapped to this repo's width arrives on `main`
with a short ragged line after every long one.
