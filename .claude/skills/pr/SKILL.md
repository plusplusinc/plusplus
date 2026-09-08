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
4. `scripts/test.sh sim` passes. For a change touching only docs or config, `scripts/test.sh`
   is enough.
5. For UI changes, a screenshot from `/run` has been looked at.

Steps 1 and 2 are skipped for a diff with no Swift in it.

Then:
```sh
git push -u origin <branch>
gh pr create --fill        # or gh pr edit to update the body
gh pr checks --watch       # Xcode Cloud reports back as a check
```

PR body: one paragraph on what and why; short sections only if the change has distinct parts;
a "Verified" line stating exactly what was run.
