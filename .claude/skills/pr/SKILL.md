---
name: pr
description: Open or update a pull request for the current branch the way this repo expects, with lint and tests green first.
allowed-tools: Bash(scripts/lint.sh:*), Bash(scripts/test.sh:*), Bash(git:*), Bash(gh pr:*)
---

Branching and merge rules are in CLAUDE.md. Before pushing, in this order, because the first
two change code and the rest verify it:
1. `/simplify` has run over the diff and its cleanups are applied.
2. `/code-review` has run over the diff and every confirmed finding is fixed or explained in
   the PR body.
3. `scripts/lint.sh` is clean.
4. `scripts/test.sh` passes, and so do the simulator tests the change touches
   (`scripts/test.sh sim <Target/Class>`). The full simulator suite is Xcode Cloud's check on
   the PR; a PR merges only when it is green. For docs or config alone, `scripts/test.sh` is
   enough.
5. For UI changes, a screenshot from `/run` has been looked at.

Steps 1 and 2 are skipped for a diff with no Swift in it.

Then:
```sh
git push -u origin <branch>
gh pr create --title "<title>" --body-file <file>   # or gh pr edit to update the body
gh pr checks --watch                                # Xcode Cloud reports back as a check
```

If `gh pr checks` still says "no checks reported" 30 seconds after the PR opens, GitHub's
pull request event never reached Xcode Cloud, which happens intermittently and leaves no log
on our side. Run `gh pr close <n> && gh pr reopen <n>`; the reopen sends a fresh event, and the
run starts within seconds.

The body follows `.github/pull_request_template.md`: one paragraph on what and why, short
sections only if the change has distinct parts, a "Verified" line stating exactly what was run,
a "Friction" line saying what was retried, what the maintainer corrected, and what took longer
than it should have, and a "Card" line naming the board card, written as "Closes #N" when the
card was published as an issue so the merge closes it. The retro runs in a cloud session
that never saw this work and reads only the PR, so write Friction from the session, not from
the diff, and put any decision the diff does not explain in the body. `--fill` skips the
template; write the body to a file under `.build/`.

Write the body as the commit message it becomes. The title is already the commit's subject, so
do not repeat it in the body's first line, and leave each paragraph on a single line: GitHub
re-wraps the body when it squashes, so prose hard-wrapped to this repo's width arrives on `main`
with a short ragged line after every long one.
