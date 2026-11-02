# The PR check

Every pull request to `main` runs one required GitHub Actions check, "PR check"
(`.github/workflows/pr-check.yml`), on each push; the `main` ruleset requires only it. Its logic is
`scripts/pr-check.sh`, which runs the same way on a Mac:

- **A PR that changes no app code**, one whose changed files all match `.github/no-code-paths`
  (docs, `.claude/`, the PR template, the rulesets, the root Markdown files, the scripts no build runs), gets
  `scripts/lint.sh` on its changed files and passes, in a minute or two. Xcode Cloud starts no
  run for it, since its PR workflow skips the same list.
- **Any other PR** waits for Xcode Cloud's commit status, "PlusPlus Workout Tracker | PR", on the
  PR's head commit, polling once a minute, and passes or fails with it, naming the run and its
  actions' results. A run Xcode Cloud cancels before any action starts fails the check with a
  message saying the month's Xcode Cloud hours are likely spent, since Xcode Cloud does that when
  they are. Once the hours are back, start the run again (`asc xcode-cloud run`, or push) and
  re-run the check.

Either way, "PR check" first fails a PR whose diff undoes a recent commit on `main`
(`scripts/pr-check.sh reverts <base> <head>`): for each of the merge base's last 30 commits, it
looks at the files the PR's diff also changes, and fails when, in one of them, every line that
commit changed is undone (a line it added gone, a line it removed back) or a binary file is back
to its copy before it. It names each commit and file. A squash onto a newer `main`,
`git reset --soft origin/main`, does that: the commit keeps the branch's stale copies of what
`main` changed meanwhile, which is how #136 undid #134 with every other check green, its
snapshots reverted along with the code. A revert that is meant is made with `git revert`, whose
"This reverts commit <sha>" line, a short sha too, exempts that commit. The guard reads history,
so this job checks out the whole of it; `scripts/pr-check-test.py`, which `scripts/test.sh`
runs, replays #136's case in a temporary repository.

It also fails a PR whose body lacks the Card, Verified, and Friction lines the nightly retro reads
(`scripts/pr-check.sh body`, the body on stdin), each as `Name:` or a `## Name` heading; the
check runs again when the body is edited, so `gh pr edit` that adds them clears it.

A first job, "Route", reads which of the two a PR is; "PR check" then lints or waits. Both run
on `ubuntu-24.04`, free on a public repository, and when Route fails, "PR check" fails too,
pointing to Route's log. The docs-only lint needs no Swift tools: `scripts/lint.sh` given paths
with no Swift file runs only the US English check, and Swift, `.swiftformat`, and
`.swiftlint.yml` all count as app code, which Xcode Cloud lints whole in
`ci_scripts/ci_post_clone.sh`. The jobs read and nothing more (`contents`, `pull-requests`,
`statuses`, `checks`), the token reaches only the steps that run the base's script, their one
action is pinned to a commit, a new push or an edit cancels the run it supersedes, and the check's time
limit, 45 minutes, sits above Xcode Cloud's longest PR run so far (about 20 minutes, queue
included) and above the script's 40-minute wait.

## The no-code list

`.github/no-code-paths` is the one list. The check reads it, and runs `scripts/pr-check.sh`,
from the PR's base commit, never the PR, so a PR cannot widen the list it is checked against;
locally both default to `origin/main` (`PR_CHECK_BASE` names another). Anything not on it counts as app
code, so a path nobody thought of gets tested. Its entries mean what Xcode Cloud's Files and
Folders matchers mean: `folder/` is everything in that folder at any depth, a bare `name` is a
file of that name in any folder, and `folder/name` is that file in that folder. A new file or
folder no build or test reads goes on the list, rather than somewhere already on it;
`scripts/pr-check-test.py` fails when a script is neither on it nor named in its header as not
listed. Xcode Cloud
holds a copy, in the PR workflow's pull-request start condition ("don't start if all files
match"), which only the App Store Connect API or its UI changes. After editing the list, update
the copy, keeping the rest of the start condition as it is. Agents are denied the update
(`.claude/settings.json`), as they are every write below to the repository's settings, so the
maintainer runs it; an agent prints the rule and leaves the command for them:

```sh
PR_CHECK_BASE=HEAD scripts/pr-check.sh xcode-cloud   # the branch's list as Xcode Cloud's rule
asc xcode-cloud workflows view --id FE8B3BCC-1973-4533-BB66-4D047A8E3C22 --pretty
# put the rule under data.attributes.pullRequestStartCondition.filesAndFoldersRule, keep
# source, destination, and autoCancel, and send only that attribute:
asc xcode-cloud workflows update --id FE8B3BCC-1973-4533-BB66-4D047A8E3C22 --file <patch.json>
```

When the two disagree, a PR Xcode Cloud skips but the check treats as app code gets no status,
and after 10 minutes with none the check fails, naming that and the other cause, GitHub's event
never reaching Xcode Cloud (`/pr` says what to do).

The files that decide the check, the list, `scripts/pr-check.sh`, and `.github/workflows/`, are
never on it: the check counts a PR that changes them as app code whatever the list says, so it
waits for Xcode Cloud, which runs on it. The workflow file itself is still the PR's, since a
`pull_request` job runs the PR's own copy, so a PR could edit it to skip all of this; the diff,
read before the merge, shows that. Xcode Cloud runs `ci_scripts/`, the `Brewfile`, and `scripts/lint.sh`
with what it sources before it builds, so those are not on it.

## Running it locally

```sh
scripts/pr-check.sh files <pr> | scripts/pr-check.sh classify   # docs, or the first app path
scripts/pr-check.sh route <pr>              # docs or xcode-cloud, as Route decides
scripts/pr-check.sh lint <pr>               # the docs-only path
scripts/pr-check.sh wait <sha> [minutes]    # Xcode Cloud's result on a commit, as CI reads it
scripts/pr-check.sh reverts origin/main HEAD   # the revert guard on the branch
```

`gh pr checks <n> --watch --interval 60` waits on it from a PR.

## Rulesets

Two rulesets, kept as JSON in `.github/rulesets/`, hold the rules. Nobody bypasses either, admins
included.

- **`main`** (`main.json`): a pull request, merged by squash only; "PR check" passing with the
  branch up to date; linear history; no force push and no deletion. Renaming the job means
  updating the rule, since it names the check. Change the required check only once the workflow
  that runs it, under that name, is on `main`: until then only the PR that adds it produces it,
  so every other PR waits on that one.
- **`release tags`** (`release-tags.json`): a `v*` tag can be created but never moved or
  deleted, since each one is a TestFlight build. To remove a bad tag, set the ruleset's
  enforcement to `disabled`, delete the tag, and set it back to `active`.

Edit the JSON, then apply it by name (`POST repos/plusplusinc/plusplus/rulesets --input <file>`
creates one that does not exist yet). `gh ruleset check main` shows what applies to a branch.

```sh
id=$(gh api repos/plusplusinc/plusplus/rulesets --jq '.[] | select(.name=="main").id')
gh api -X PUT repos/plusplusinc/plusplus/rulesets/$id --input .github/rulesets/main.json
```

Repository settings outside the rulesets: squash merges only, the commit taken from the PR's
title and body, and branches deleted on merge.

```sh
gh repo edit plusplusinc/plusplus --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge
```
