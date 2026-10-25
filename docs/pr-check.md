# The PR check: GitHub Actions

Every pull request to `main` runs one GitHub Actions job, "Lint and test", defined in
`.github/workflows/pr.yml`, on each push. It installs the `Brewfile` tools, runs
`scripts/lint.sh`, then `scripts/test.sh sim`: the scheme `PlusPlus` and its test plan,
`PlusPlus.xctestplan`, on an iPhone 17 simulator, so storage, snapshot, and UI tests run in one
pass. CI and a developer run the same scripts, so they cannot disagree about what passing means.
The checkout is a plain clone, not a linked worktree, so the scripts use the simulator named
"iPhone 17" that the runner image ships, and do not reset it.

It runs on `xcode-27`, a standard GitHub-hosted runner (Apple silicon, 3 CPUs, 7 GB), which is
free and has no hour limit on a public repository; `xcode-27-xlarge` is a larger, paid one. The
job reads the repository and nothing else: `permissions: contents: read`, no secrets, actions
pinned to a commit. A new push to the same PR cancels the run it supersedes.

SwiftFormat is pinned, in the workflow, to the release the code is formatted with, since the
image ships a newer one whose rules would fail code that is clean locally. Moving to a newer
release is its own change: bump the version and checksum there and reformat the tree with it.

## Reading a result

```sh
gh pr checks <n> --watch --interval 60          # wait; a run takes several minutes
gh run view <run-id> --log-failed               # the failing step's output
gh run download <run-id> -n test-xcresult -D .build/ci   # the result bundle, failed runs only
gh run view <run-id> --json startedAt,updatedAt,jobs     # each step's start and end
```

The run id is in the link `gh pr checks` prints. A failed test step uploads
`.build/results/test.xcresult` as the artifact `test-xcresult`, kept seven days; open it with
`xcrun xcresulttool`, or `python3 scripts/xcresult.py tests <bundle>` for the summary. Snapshot
diffs are attachments in it.

## Branch protection

On `main`: require a pull request, require the "Lint and test" check with the branch up to date,
squash merges only, delete branches on merge. Renaming the job means updating the rule, since it
names the check:

```sh
gh api -X PATCH repos/plusplusinc/plusplus/branches/main/protection/required_status_checks \
  -F strict=true -f 'contexts[]=Lint and test'
gh repo edit plusplusinc/plusplus --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge
```
