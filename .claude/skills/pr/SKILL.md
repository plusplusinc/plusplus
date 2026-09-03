---
name: pr
description: Open or update a pull request for the current branch the way this repo expects, with lint and tests green first.
allowed-tools: Bash(scripts/lint.sh:*), Bash(scripts/test.sh:*), Bash(git:*), Bash(gh pr:*)
---

`main` only moves through pull requests, and merges are squashed: the PR title and body become
the single commit on `main`. Write the body as a commit message, in US English.

Before pushing:
1. `scripts/lint.sh` is clean.
2. `scripts/test.sh all` passes. For a change touching only docs or config, `fast` is enough.
3. For UI changes, a screenshot from `/run` has been looked at.

Then:
```sh
git push -u origin <branch>
gh pr create --fill        # or gh pr edit to update the body
gh pr checks --watch       # Xcode Cloud reports back as a check
```

PR body structure: one paragraph on what and why; short sections only if the change has
distinct parts; a "Verified" line stating exactly what was run. Nothing about review order or
"as discussed"; that goes in a PR comment.
