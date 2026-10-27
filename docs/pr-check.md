# The PR check

Every pull request to `main` runs one required GitHub Actions check, "PR check"
(`.github/workflows/pr-check.yml`), on each push; branch protection requires only it. Its logic is
`scripts/pr-check.sh`, which runs the same way on a Mac:

- **A PR that changes no app code**, one whose changed files all match `.github/no-code-paths`
  (docs, `.claude/`, the PR template, the root Markdown files, the scripts no build runs), gets
  `scripts/lint.sh` on its changed files and passes, in a minute or two. Xcode Cloud starts no
  run for it, since its PR workflow skips the same list.
- **Any other PR** waits for Xcode Cloud's commit status, "PlusPlus Workout Tracker | PR", on the
  PR's head commit, polling once a minute, and passes or fails with it, naming the run and its
  actions' results. A run Xcode Cloud cancels before any action starts fails the check with a
  message saying the month's Xcode Cloud hours are likely spent, since Xcode Cloud does that when
  they are. Once the hours are back, start the run again (`asc xcode-cloud run`, or push) and
  re-run the check.

A first job, "Route", reads which of the two a PR is; "PR check" then lints or waits. Both run
on `ubuntu-24.04`, free on a public repository, and when Route fails, "PR check" fails too,
pointing to Route's log. The docs-only lint needs no Swift tools: `scripts/lint.sh` given paths
with no Swift file runs only the US English check, and Swift, `.swiftformat`, and
`.swiftlint.yml` all count as app code, which Xcode Cloud lints whole in
`ci_scripts/ci_post_clone.sh`. The jobs read and nothing more (`contents`, `pull-requests`,
`statuses`, `checks`), the token reaches only the steps that run the base's script, their one
action is pinned to a commit, a new push cancels the run it supersedes, and the check's time
limit, 45 minutes, sits above Xcode Cloud's longest PR run so far (about 20 minutes, queue
included) and above the script's 40-minute wait.

## The no-code list

`.github/no-code-paths` is the one list. The check reads it, and runs `scripts/pr-check.sh`,
from the PR's base commit, never the PR, so a PR cannot widen the list it is checked against;
locally both default to `origin/main` (`PR_CHECK_BASE` names another). Anything not on it counts as app
code, so a path nobody thought of gets tested. Its entries mean what Xcode Cloud's Files and
Folders matchers mean: `folder/` is everything in that folder at any depth, a bare `name` is a
file of that name in any folder, and `folder/name` is that file in that folder. Xcode Cloud
holds a copy, in the PR workflow's pull-request start condition ("don't start if all files
match"), which only the App Store Connect API or its UI changes. After editing the list, update
the copy, keeping the rest of the start condition as it is:

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
```

`gh pr checks <n> --watch --interval 60` waits on it from a PR.

## Branch protection

On `main`: require a pull request, require "PR check" with the branch up to date, squash merges
only, delete branches on merge. Renaming the job means updating the rule, since it names the
check. Change the required check only once the workflow that runs it, under that name, is on
`main`: until then only the PR that adds it produces it, so every other PR waits on that one.
Set once with the first command; the second changes only the required check:

```sh
gh api -X PUT repos/plusplusinc/plusplus/branches/main/protection \
  -f required_status_checks[strict]=true \
  -f 'required_status_checks[contexts][]=PR check' \
  -F enforce_admins=true \
  -f required_pull_request_reviews[required_approving_review_count]=0 \
  -F restrictions=null
gh api -X PATCH repos/plusplusinc/plusplus/branches/main/protection/required_status_checks \
  -F strict=true -f 'contexts[]=PR check'
gh repo edit plusplusinc/plusplus --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge
```
