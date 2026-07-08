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

## After shipping

Update CLAUDE.md's Current State (build number + contents) and tell Dave
what to expect on-device, flagging anything that needs the #1 checklist.
