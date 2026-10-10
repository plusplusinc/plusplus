# CI and releases: Xcode Cloud

Xcode Cloud builds and tests every pull request and ships each `v*` tag to TestFlight. Workflow
definitions live in App Store Connect, not in the repo. Two files here belong to it:
`ci_scripts/ci_post_clone.sh`, which installs the `Brewfile` tools and runs `scripts/lint.sh`
before any build action, and `PlusPlus.xcodeproj/xcshareddata/xcodecloud/manifest.json`, which
records the Xcode Cloud product the project belongs to. Xcode writes the manifest back whenever
a workflow is edited, so it is committed rather than deleted; it holds a product id and target
name, nothing secret, and nothing in the build reads it.

## One-time setup

1. Install the [Xcode Cloud GitHub app](https://github.com/apps/xcode-cloud) on the
   `plusplusinc` organization and grant it this repository.
2. In Xcode, with `PlusPlus.xcodeproj` open: Product ▸ Xcode Cloud ▸ Create Workflow. Xcode
   registers the app record and bundle ID in App Store Connect if they do not exist.
3. Signing is managed by Xcode Cloud using the `DEVELOPMENT_TEAM` in `Config/Base.xcconfig`.
4. Both workflows below exist in App Store Connect. The `Release` distribution audience and the
   `Internal` beta group were set through the API, which `asc` reaches (see below).

## Workflows

**PR**: start on pull request to `main`. Actions: Build and Test, scheme `PlusPlus`, iOS
simulator iPhone 17, using the scheme's settings. The scheme's test plan, `PlusPlus.xctestplan`,
includes the package test targets, so this covers storage, snapshot, and UI tests in one run.
Post-actions: none.

**Release**: start on a tag beginning with `v`. Actions: Archive, iOS, with distribution to
TestFlight internal testing. Post-actions: TestFlight Internal Testing, group `Internal`. The post-action is
what puts each build in the group: the group's "access to all builds" does not pull in Xcode
Cloud uploads, and without it a build uploads and waits unassigned. The API does not expose
post-actions; edit them in Xcode or in App Store Connect ▸ Xcode Cloud ▸ Workflows. Members of
`Internal` are added in App Store Connect (TestFlight ▸ Internal Testing), since the API does
not let a team member be added to an internal group. Internal builds skip Beta App
Review, and `ITSAppUsesNonExemptEncryption` in `Config/Base.xcconfig` answers the export
compliance question so the build is available as soon as processing finishes.

Merges to `main` do not build; the PR run already tested that code, since branch protection
requires a branch to be up to date before it merges. Builds reach TestFlight only when a release
is cut, one build per tag.

## Cutting a release

Tag `main` and push the tag: `git tag v0.2.0 origin/main && git push origin v0.2.0`.

There is no App Store workflow yet. `CURRENT_PROJECT_VERSION` is overridden by Xcode Cloud's
build number; `MARKETING_VERSION` in `Config/Base.xcconfig` is bumped by hand.

## From the command line

[`asc`](https://asccli.sh) (in the `Brewfile`) talks to the App Store Connect API. The commands
used here:

```sh
asc xcode-cloud workflows list --app 6808082840            # workflow ids
asc xcode-cloud build-runs --workflow-id <id> --sort -number --limit 10 --output table
asc xcode-cloud status --run-id <id> --wait               # block until a run finishes
asc xcode-cloud doctor --run-id <id> --save-logs .build/asc/<n>   # status, issues, logs
asc xcode-cloud artifacts download --id <artifact-id> --path .build/asc/<file>.zip
asc xcode-cloud run --workflow-id <id> --branch <name>     # start a run
asc builds add-groups --app 6808082840 --latest --group Internal     # attach a TestFlight build
```

It needs an API key with the Developer role, registered once per machine with `asc auth login
--bypass-keychain --name plusplus --key-id <id> --issuer-id <id> --private-key <path to .p8>`.
That writes `~/.asc/config.json`, which points at the `.p8` rather than copying it; the keychain
is bypassed because its access is tied to the binary and a Homebrew upgrade would prompt again.
The `.p8` lives in `~/.appstoreconnect/private_keys/`. Nothing of that is in the repo.

## Agents

An agent uses the least access that answers its question. Pass or fail comes from GitHub, where
Xcode Cloud reports every run as a check (`gh pr checks`, or the GitHub MCP tools in the cloud
session, whose `gh` is not logged in); that needs no key and is all a cloud agent such as the
retro gets. Local agents that operate CI use `asc` rather than ad hoc API calls. Reading runs
and starting one are allowed without a prompt (`.claude/settings.json`); anything else that
changes App Store Connect asks first. The API cannot cancel a running build or edit a
workflow's post-actions, so those two go through App Store Connect in the browser. The Xcode
MCP server has no Xcode Cloud tools.

## Branch protection

On `main`: require a pull request, require the Xcode Cloud status check, squash merges only,
delete branches on merge. Set once with:

```sh
gh api -X PUT repos/plusplusinc/plusplus/branches/main/protection \
  -f required_status_checks[strict]=true \
  -f 'required_status_checks[contexts][]=Xcode Cloud' \
  -F enforce_admins=true \
  -f required_pull_request_reviews[required_approving_review_count]=0 \
  -F restrictions=null
gh repo edit plusplusinc/plusplus --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge
```

The check name is whatever Xcode Cloud reports on the first PR; adjust the context if it differs.

## If GitHub Actions is ever wanted

`macos-latest` runners default to the same Xcode as this project and are free for public
repositories. The same `scripts/lint.sh` and `scripts/test.sh` would be the job steps; cache
`~/.swiftpm/cache`, not DerivedData.
