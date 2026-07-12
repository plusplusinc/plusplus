---
name: testflight
description: Ship a PlusPlus TestFlight build from CI — dispatch, entitlements mechanism, build numbering, and what each historical failure mode means.
---

# Shipping a TestFlight build

`.github/workflows/testflight.yml`, manual dispatch on any ref (GitHub MCP
`actions_run_trigger`, method `run_workflow`, `workflow_id: testflight.yml`,
`ref` = usually `main`). Build number = workflow run number. Upload lands in
TestFlight processing a few minutes after the run goes green.

## How signing works (do not "simplify" this)

1. Archive is UNSIGNED (`CODE_SIGNING_ALLOWED=NO`) — signing at archive
   time fails on runners (no registered devices / conflicting settings).
2. An unsigned archive carries NO entitlements (`.xcent`), so the export's
   cloud signing would request none. Therefore the workflow re-signs the
   three bundles inside the archive (watch app → widget appex → main app)
   with a THROWAWAY SELF-SIGNED identity, embedding each target's
   xcodegen-generated entitlements file. The p12 is created with legacy
   PKCS12 algorithms (`-macalg sha1 -keypbe/-certpbe PBE-SHA1-3DES`)
   because macOS's keychain importer can't read OpenSSL 3 defaults.
3. `xcodebuild -exportArchive` cloud-signs with the ASC API key (must be
   **Admin** role) and reads the embedded entitlements as its request; the
   App Store profiles satisfy it because Dave enabled the capabilities on
   the App IDs in the developer portal.

**Adding a capability** = Dave toggles it on the App ID in the portal +
an entitlements entry in project.yml. The workflow needs nothing new.

## Failure modes seen in the wild

- `Cloud signing permission error` → ASC key isn't Admin.
- Validation 90701 (missing entitlement) → a bundle demanded a capability
  (e.g. WKBackgroundModes → healthkit) that isn't in its embedded
  entitlements or isn't enabled on the App ID.
- `Ad Hoc code signing is not allowed with SDK` → someone tried ad-hoc
  (`CODE_SIGN_IDENTITY=-`) archive signing; iOS/watchOS SDKs refuse it.
- `SecKeychainItemImport: MAC verification failed` → p12 built with
  OpenSSL 3 defaults; use the legacy algorithm flags above.
- Empty `CFBundleVersion` in an extension makes simulators refuse the
  .appex; project.yml pins `CURRENT_PROJECT_VERSION: 1`, and TestFlight
  overrides with the run number.

## Recording the build (fold into the feature PR, not a follow-up)

The CLAUDE.md Current State update (build number + contents) rides in the
SAME PR as the change — never a separate bookkeeping PR after shipping
(Dave, 2026-07-12). The wrinkle: the build number IS the testflight run
number, which doesn't exist until dispatch, and dispatch is after merge. So
PREDICT it before merging — it's the latest testflight run number + 1
(`actions_list` on `testflight.yml`, take the top `run_number`, add 1). You
dispatch immediately after merging, so nothing slips in between and the
prediction holds. Write the Current State line with that number, commit it in
the feature PR, merge, then dispatch — the run number matches. If a stray
dispatch ever bumps the number, fix the one line in the next PR that touches
CLAUDE.md; don't open a PR just for the correction.

Then tell Dave what to expect on-device, flagging anything that needs the
#1 checklist.
