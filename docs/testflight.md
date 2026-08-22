# Shipping to TestFlight

The workflow in `.github/workflows/testflight.yml` is complete and correct, but **inert until the
six secrets below exist**. Everything here is manual, one-time setup on Apple's side.

## Prerequisites

1. **Apple Developer Program membership** ($99/yr). App Groups, iCloud/CloudKit, and HealthKit all
   require a paid team — a free personal team cannot provision them. Until this exists, debug
   builds fall back to a local-only SwiftData store (see `WorkoutStoreContainer`).
2. **An App Store Connect app record** for bundle ID `com.plusplusinc.plusplus`.
3. **Registered capabilities** on that App ID: App Groups (`group.com.plusplusinc.plusplus`),
   iCloud with CloudKit container `iCloud.com.plusplusinc.plusplus`, and HealthKit.
4. **An app icon.** App Store Connect rejects uploads without one. This is currently the only
   hard blocker that is not a credential.

## Repository secrets

Set these under Settings → Secrets and variables → Actions.

| Secret | Where it comes from |
| --- | --- |
| `DEVELOPMENT_TEAM` | Your 10-character Team ID, from the Apple Developer account page |
| `APPSTORE_ISSUER_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `APPSTORE_KEY_ID` | Same page, the key's ID |
| `APPSTORE_PRIVATE_KEY` | The `.p8` file contents, pasted whole. **Downloadable exactly once** |
| `CERTIFICATES_P12` | Base64 of your Apple Distribution certificate `.p12` (below) |
| `CERTIFICATES_P12_PASSWORD` | The password you set when exporting that `.p12` |

### Exporting the distribution certificate

In Keychain Access, find your **Apple Distribution** certificate, right-click → Export, choose
`.p12`, and set a password. Then:

```sh
base64 -i Certificates.p12 | pbcopy
```

Paste that as `CERTIFICATES_P12` and the password as `CERTIFICATES_P12_PASSWORD`.

## Running it

- **Manually:** Actions → TestFlight → Run workflow, with optional release notes.
- **By tag:** `git tag v0.1.0 && git push --tags`.

The build number is `github.run_number`, so it always increases and never collides. The marketing
version comes from `MARKETING_VERSION` in `Config/Base.xcconfig`.

## Why there is no fastlane and no stored provisioning profiles

The archive step passes `-allowProvisioningUpdates` together with the App Store Connect API key,
so Xcode creates and downloads whatever profiles the app needs at build time. This matters more
once the Watch app and widget extension land, because each target needs its own profile — storing
three profiles as secrets and rotating them by hand is exactly the chore this avoids.
