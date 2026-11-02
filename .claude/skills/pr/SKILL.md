---
name: pr
description: Open or update a pull request for the current branch the way this repo expects, with lint and tests green first.
allowed-tools: Bash(scripts/lint.sh:*), Bash(scripts/test.sh:*), Bash(scripts/ci-times.py:*), Bash(git:*), Bash(gh pr:*), Bash(scripts/pr-media.sh:*), Bash(ffmpeg:*)
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
   (`scripts/test.sh sim <Target/Class>`). The full simulator suite runs on Xcode Cloud for a
   PR that changes the app, and "PR check" reports its result; a PR merges only when that check
   is green. For docs or config alone, `scripts/test.sh` is enough. Each run prints its tiers'
   times against their budgets; name any test over budget in the body, with its time.
5. For UI changes, a screenshot from `/run` has been looked at.

Steps 1 and 2 are skipped for a diff with no Swift in it. Give both the same target, filled in:
`<branch> against origin/main, checked out at <worktree>; say which branch and HEAD you
reviewed`. They, and every agent they start, begin in the session's own checkout, not in a
worktree you `cd` into, and with no target they review whatever is checked out there: on `main`,
its last squash merge, a pull request that already merged. Before acting on findings, check that
the branch and HEAD they name are the worktree's; if not, run again with the target named.

Push only when CI's answer is needed: when opening the PR, after a round of fixes, and before
the merge (bringing it up to date with `main` included: merge `origin/main` into a pushed
branch, never rebase it locally, since its push would need a force push agents are denied). Commit locally between them; each push to a PR that
changes the app spends a full Xcode Cloud run of the month's hours. Then:
```sh
git push -u origin <branch>
gh pr create --title "<title>" --body-file - <<'BODY'   # or gh pr edit to update the body
<body>
BODY
gh pr checks --watch --interval 60                     # "PR check" is the one that decides
scripts/ci-times.py <branch>                           # the run's times against the budgets
```

Merge a branch's PR from its own worktree with no number (`gh pr merge --squash --auto` takes
the branch's): a number written before `gh pr create` prints it is a guess, and one merged the
night's retro (#123) in place of the PR just opened.

Once Xcode Cloud's run finishes, put `scripts/ci-times.py`'s lines for it in the body's Verified
line with `gh pr edit`.

The body goes in on stdin, as above, for `gh pr edit` too, never from a file: the scratchpad is
shared by the lead and every subagent, and a body read back from a file there that another
session had overwritten put a private card's text in a public PR's body (#118).

"PR check" (`docs/pr-check.md`) lints a PR whose changed files are all in
`.github/no-code-paths` and passes in a minute or two; Xcode Cloud starts no run for it. For any
other PR it waits for Xcode Cloud's "PlusPlus Workout Tracker | PR" on the same commit and passes
or fails with it, naming the run. When it fails saying the month's Xcode Cloud hours are likely
spent, tell the lead or the maintainer; no rerun helps until they are back.

If a PR that changes the app still lists no "PlusPlus Workout Tracker | PR" check a minute after
it opens or after a push to it, an update from `main` included, GitHub's event never reached Xcode Cloud,
which happens intermittently and leaves no log on our side. Push an empty commit
(`git commit --allow-empty -m "Start Xcode Cloud" && git push`); the push sends a fresh event.
If a minute later there is still no check, run `gh pr close <n> && gh pr reopen <n>`. Each has
started a missed run, and closing and reopening has also once started nothing.

The body follows `.github/pull_request_template.md`, and #138 is its model. Write it to be read
in a minute by someone who wasn't there, the maintainer first:
- **Open with one or two plain sentences**: what someone using the app notices, or what changes
  for the agents, and why. No code names, file names, or numbers there.
- **Card**, on the line right under them: the board card linked by its title, `[title](url)`
  with the link `scripts/board.sh show` prints after its status, never its `PVTI_` id; or
  "Closes #N" when the card was published as an issue, so the merge closes it.
- **What changes**: short bullets, or a table of today against this PR when values change
  (timings, sizes). One fact per bullet, in plain words. Say what stays the same if a reader
  would wonder.
- **Before and after**, for a change someone can see (below).
- **How**, for a reviewer: a few bullets with the code names, the tests and what each pins, and
  any decision the diff doesn't explain. Leave out what the diff already says.
- **Verified, Friction**, each as a few short bullets. Verified gives what was run and the
  times against their budgets; Friction says what was retried, what was corrected and who found
  it (the maintainer, an agent review, the verifier, CI), and what took longer than it should
  have, written from the session, not from the diff. The template
  says why the retro needs these.

Bullets and short paragraphs over long ones: a paragraph past four lines is two, or a list.
Frame-by-frame measurements and long test lists go in a PR comment (the verifier's record comment
is one), not the body. `--fill` skips the template.

A change someone can see carries its before and after in the body itself, never as a path to a
local file, which no reader of the PR can open: screenshots of `main` and the branch at the same
moment, and a recording of each where the change is motion. `scripts/pr-media.sh <pr> <file>...`
pushes them to the `pr-media` branch and prints the Markdown image lines; a recording becomes a
looping GIF. Say in a line above each image what it shows and which side is which. The PR's
number exists only once `gh pr create` prints it, so open the PR, then add the images with
`gh pr edit`. To put two recordings side by side, trimmed to the moment, make the GIF first and
pass that:
```sh
ffmpeg -v error -ss <before start s> -t <seconds> -i before.mov -ss <after start s> -t <seconds> -i after.mov \
  -filter_complex "[0:v]fps=20,scale=300:-2[a];[1:v]fps=20,scale=300:-2[b];[a][b]hstack,split[x][y];[x]palettegen=max_colors=96[p];[y][p]paletteuse=dither=bayer:bayer_scale=4" \
  -loop 0 before-after.gif
```

Write the body as the commit message it becomes, true before the merge too: today and the
change kept apart, as CLAUDE.md's "Tense tells the truth" says. The title is already the
commit's subject, so
do not repeat it in the body's first line, and leave each paragraph on a single line: GitHub
re-wraps the body when it squashes, so prose hard-wrapped to this repo's width arrives on `main`
with a short ragged line after every long one.
