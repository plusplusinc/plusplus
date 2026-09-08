# CI and releases: Xcode Cloud

Xcode Cloud builds and tests every pull request and ships `main` to TestFlight. Workflow
definitions live in App Store Connect, not in the repo; the repo contributes only
`ci_scripts/ci_post_clone.sh`, which installs the `Brewfile` tools and runs `scripts/lint.sh`
before any build action.

## One-time setup

1. Install the [Xcode Cloud GitHub app](https://github.com/apps/xcode-cloud) on the
   `plusplusinc` organization and grant it this repository.
2. In Xcode, with `PlusPlus.xcodeproj` open: Product ▸ Xcode Cloud ▸ Create Workflow. Xcode
   registers the app record and bundle ID in App Store Connect if they do not exist.
3. Signing is managed by Xcode Cloud using the `DEVELOPMENT_TEAM` in `Config/Base.xcconfig`.
4. Both workflows below exist in App Store Connect. `scripts/xcode-cloud.py` can read and change
   them through the API (the `Main` distribution audience was set that way), and it created the
   `Internal` beta group.

## Workflows

**PR**: start on pull request to `main`. Actions: Build and Test, scheme `PlusPlus`, iOS
simulator iPhone 17. The scheme's test action includes the package test targets, so this covers
storage, snapshot, and UI tests in one run. Post-actions: none.

**Main**: start on push to `main`. Actions: Archive, iOS, with distribution to TestFlight
internal testing. Every merge becomes a build for the `Internal` group, which has access to all
builds; its members are added in App Store Connect (TestFlight ▸ Internal Testing), since the
API does not let a team member be added to an internal group. Internal builds skip Beta App
Review, and `ITSAppUsesNonExemptEncryption` in `Config/Base.xcconfig` answers the export
compliance question so the build is available as soon as processing finishes.

There is no App Store workflow yet. `CURRENT_PROJECT_VERSION` is overridden by Xcode Cloud's
build number; `MARKETING_VERSION` in `Config/Base.xcconfig` is bumped by hand.

## From the command line

`scripts/xcode-cloud.py` talks to Xcode Cloud through the App Store Connect API: `builds` lists
recent runs, `artifacts <n>` and `download <n> [substring]` fetch a run's result bundles, logs,
and test products into `.build/xcode-cloud/`, and `start <workflow> pr <n>` starts a run. It
needs an API key with the Developer role: the `.p8` in `~/.appstoreconnect/private_keys/` and
`ASC_KEY_ID` and `ASC_ISSUER_ID` in `~/.appstoreconnect/plusplus.env`. Nothing of that is in the
repo.

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
