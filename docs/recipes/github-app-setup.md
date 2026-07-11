# Registering the GitHub App for in-app sync (#23)

The app syncs your program and history to a repo in *your* GitHub account
(private or public, your choice) using a **GitHub App with device flow** — no
PlusPlus server, no client
secret in the binary. Everything on both sides is built and tested; the only
thing missing is the App itself, which only the owner can register. This is the
one-time setup.

## 1. Register the App (~5 minutes)

1. Go to **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**
   (direct: <https://github.com/settings/apps/new>).
2. Fill in:
   - **GitHub App name:** `PlusPlus Sync` (must be globally unique — add a
     suffix if taken).
   - **Homepage URL:** `https://plusplus.fit`
   - **Callback URL:** leave blank.
   - **Enable Device Flow:** ✅ **check this.** This is the whole auth model —
     without it the app can't sign anyone in.
   - **Webhook:** **uncheck Active.** Not needed initially.
3. **Permissions → Repository permissions:**
   - **Contents:** **Read and write.** This is the *only* permission the app
     needs (it reads and commits the interchange files).
   - Leave everything else at *No access*.
4. **Where can this App be installed?** → **Any account** (so users other than
   you can install it on their own repo later). For a private beta, *Only on
   this account* is fine.
5. Click **Create GitHub App.**

## 2. Wire the client ID into the build

On the App's page, copy the **Client ID** (looks like `Iv23liABCD..`). It is
**not a secret** — device flow needs no client secret, and the ID ships in the
binary by design — so it's safe to commit.

In `project.yml`, set it on the `PlusPlus` target:

```yaml
    settings:
      base:
        ...
        GITHUB_APP_CLIENT_ID: "Iv23liABCDyourid"   # was ""
```

That's the whole change. The app reads it from `Info.plist`
(`GitHubAppClientID`, wired to this build setting) via
`GitHubSyncSettings.clientID()`. While it's blank, the connect screen shows
"Sync isn't set up in this build yet" instead of calling GitHub with an empty
ID. Regenerate the project (`xcodegen`) / next CI build picks it up.

> No App ID entitlement or portal capability is needed here — this is a GitHub
> App, unrelated to Apple's App ID capabilities. It does **not** go through the
> TestFlight entitlements mechanism.

## 3. Validate end-to-end (Mac session, ~15 min)

This part needs a Mac + Simulator/device — it exercises the Keychain, the
device-flow UX, and a real repo, none of which a remote Linux session can do.

1. **Create a repo + install the App first.** The App has Contents-only
   permission, which can read/write a repo but **cannot create one** — so make
   a repo (any name, e.g. `plusplus-data`, private or public; tick "Add a README" so it
   has a default branch), then install PlusPlus Sync on it
   (`github.com/apps/plusplus-sync` → Install → Only select repositories → pick
   it). The app discovers whichever repo you installed it on — no fixed name.
2. Build & run the app with the client ID set.
3. **Today → ++ → Settings → SYNC → Connect GitHub.** A code appears (e.g.
   `WDJB-MJHT`). Tap **Open GitHub**, enter the code, approve.
4. Back in the app, the screen flips to **Connected** and shows the repo you
   installed it on (bootstrap *adopts* it at its real default branch). If you
   skipped step 1 you'll see "Install PlusPlus Sync on a repo, then reconnect"
   instead — do that and reconnect.
5. Tap **Sync now.** In the repo on github.com you should see commits appear:
   `Sync: …` for templates, your finished sessions under `history/YYYY/`.
6. **Round-trip:** edit a routine file on github.com (or from the CLI), reopen
   the app (foreground triggers a sync), and confirm the change lands in the
   app. Then edit a routine in the app, background/foreground, and confirm the
   commit shows up in the repo.
7. **Second device (the real test):** connect a second Simulator/device to the
   same account. Confirm its history pulls down and both devices converge.
   Edit *different* fields of the same routine on each side (rest on one, notes
   on the other) and confirm both edits survive — that's the field-level
   auto-merge. Then edit the *same* field on both offline and confirm the
   device you synced last... no: confirm **local-wins** (the device doing the
   sync keeps its value; the other's is still recoverable from git history).

## What's deliberately deferred (follow-ups, not blockers)

- **Commit-per-session at finish time.** Sessions today push as part of the
  foreground sync commit (append-only, idempotent). Wiring `pushSession` into
  the finish flow for the nice `Log: Push Day — 24 sets` per-session commit is a
  small follow-up best done on a Mac where the finish flow can be driven.
- **Multi-user install UX.** The bootstrap adopts-or-creates a repo named
  `workouts`; letting the user pick a different repo/name is easy to add.
