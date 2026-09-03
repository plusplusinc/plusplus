# CI and releases: Xcode Cloud

Xcode Cloud builds and tests every pull request and ships `main` to TestFlight. Workflow
definitions live in App Store Connect, not in the repo; the repo contributes only
`ci_scripts/ci_post_clone.sh`, which installs SwiftFormat and SwiftLint and runs
`scripts/lint.sh` before any build action.

## One-time setup

1. Install the [Xcode Cloud GitHub app](https://github.com/apps/xcode-cloud) on the
   `plusplusinc` organization and grant it this repository.
2. In Xcode, with `PlusPlus.xcodeproj` open: Product ▸ Xcode Cloud ▸ Create Workflow. Xcode
   registers the app record and bundle ID in App Store Connect if they do not exist.
3. Signing is managed by Xcode Cloud; nothing about the team lives in the repo. Locally, put
   `DEVELOPMENT_TEAM = XXXXXXXXXX` in `Config/Local.xcconfig` (gitignored).

## Workflows

**PR**: start on pull request to `main`. Actions: Build and Test, scheme `PlusPlus`, iOS
simulator iPhone 17. The scheme's test action includes the package test targets, so this covers
storage, snapshot, and UI tests in one run. Post-actions: none.

**Main**: start on push to `main`. Actions: Archive, iOS, TestFlight (Internal Testing). Adds a
build to the internal group on every merge.

**Release**: start on tag `v*`. Archive with TestFlight and App Store distribution, submitted
manually.

Bump `MARKETING_VERSION` in `Config/Base.xcconfig` for a release; `CURRENT_PROJECT_VERSION` is
overridden by Xcode Cloud's build number.

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
