# The PR check

Every pull request to `main` runs one GitHub Actions job, "PR check"
(`.github/workflows/pr-check.yml`), on each push, and branch protection requires it. Its logic is
`scripts/pr-check.sh`, which runs the same way on a Mac:

- **A PR that changes no app code**, one whose changed files all match `.github/no-code-paths`
  (docs, `.claude/`, `.github/`, the root Markdown files, the scripts no build runs), gets
  `scripts/lint.sh` on its changed files and passes, in a minute or two. Xcode Cloud starts no
  run for it, since its PR workflow skips the same list.
- **Any other PR** waits for Xcode Cloud's commit status, "PlusPlus Workout Tracker | PR", on the
  PR's head commit, polling once a minute, and passes or fails with it, naming the run and its
  actions' results. A run Xcode Cloud cancels before any action starts fails the check with a
  message saying the month's Xcode Cloud hours are likely spent: Xcode Cloud does that when they
  are, and the free runner is no fallback (22 to 28 minutes a run, with UI test timeouts). Once
  the hours are back, start the run again (`asc xcode-cloud run`, or push) and re-run the check.

It runs on `ubuntu-24.04`, free on a public repository. The docs-only lint needs no Swift tools:
`scripts/lint.sh` given paths with no Swift file runs only the US English check, and Swift,
`.swiftformat`, and `.swiftlint.yml` all count as app code, which Xcode Cloud lints whole in
`ci_scripts/ci_post_clone.sh`. The job reads and nothing more (`contents`, `pull-requests`,
`statuses`, `checks`), its one action is pinned to a commit, a new push cancels the run it
supersedes, and its time limit, 45 minutes, sits above Xcode Cloud's longest PR run so far
(about 20 minutes, queue included).

## The no-code list

`.github/no-code-paths` is the one list, read by the check. Anything not on it counts as app
code, so a path nobody thought of gets tested. Its entries mean what Xcode Cloud's Files and
Folders matchers mean: `folder/` is everything in that folder at any depth, a bare `name` is a
file of that name in any folder, and `folder/name` is that file in that folder. Xcode Cloud
holds a copy, in the PR workflow's pull-request start condition ("don't start if all files
match"), which only the App Store Connect API or its UI changes. After editing the list, update
the copy, keeping the rest of the start condition as it is:

```sh
scripts/pr-check.sh xcode-cloud    # the list as Xcode Cloud's filesAndFoldersRule
asc xcode-cloud workflows view --id FE8B3BCC-1973-4533-BB66-4D047A8E3C22 --pretty
# put the rule under data.attributes.pullRequestStartCondition.filesAndFoldersRule, keep
# source, destination, and autoCancel, and send only that attribute:
asc xcode-cloud workflows update --id FE8B3BCC-1973-4533-BB66-4D047A8E3C22 --file <patch.json>
```

When the two disagree, a PR Xcode Cloud skips but the check treats as app code waits for a status
that never comes, and the check fails at its time limit saying to compare them.

`.github/` is on the list: no build or test reads it, and a change to the check itself is run by
the check on its own PR. Xcode Cloud runs `ci_scripts/`, the `Brewfile`, and `scripts/lint.sh`
with what it sources before it builds, so those are not on it.

## Running it locally

```sh
scripts/pr-check.sh files <pr> | scripts/pr-check.sh classify   # docs, or the first app path
scripts/pr-check.sh wait <sha> [minutes]    # Xcode Cloud's result on a commit, as CI reads it
scripts/pr-check.sh run <pr> <sha>          # the whole check
```

`gh pr checks <n> --watch --interval 60` waits on it from a PR.

## Branch protection

On `main`: require a pull request, require "PR check" with the branch up to date, squash merges
only, delete branches on merge. Renaming the job means updating the rule, since it names the
check:

```sh
gh api -X PATCH repos/plusplusinc/plusplus/branches/main/protection/required_status_checks \
  -F strict=true -f 'contexts[]=PR check'
gh repo edit plusplusinc/plusplus --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge
```
