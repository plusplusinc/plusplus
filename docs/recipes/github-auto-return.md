# One-step GitHub connect: post-install auto-return

The connect flow is two GitHub trips by nature (install the App on a repo, then
authorize a user token — see docs/PLATFORM.md "Sync semantics" and the
2026-07-11 decision on why device flow can't merge them). Two polish moves make
it *feel* like one:

- **B1 (shipped, app-only):** the app opens GitHub's `verification_uri_complete`
  so the code is pre-filled — the user just taps **Authorize**, no typing.
- **B2 (this recipe):** after the user installs the App, GitHub bounces them
  straight back into the app, which auto-starts the authorize step. Removes the
  manual "switch back to the app and find the Connect button" gap.

B2's app side is wired (`RootTabView` deep-link handlers + a `GitHubSyncTray(startAtConnect:)`
sheet that opens on the authorize step and auto-starts the device flow). It needs
two owner-side pieces to function end to end.

> **In-app browser note:** the tray opens the authorize step (and the
> create-repo fallback) in an in-app `SFSafariViewController`, but the **Install
> step opens EXTERNALLY** (`UIApplication.open`, Safari or the GitHub app) on
> purpose. `SFSafariViewController` does NOT hand a universal link back to the
> app, so an in-app install would forfeit the AASA auto-return (step 3) and
> leave only the custom-scheme bounce (step 2). Opening install externally keeps
> BOTH return paths available. The device-flow authorize step has no such
> dependency (the app polls in the background), so it stays in-app.

## Owner step 1 — set the GitHub App's Setup URL

At `github.com/settings/apps/plusplus-sync` → **General** → *Post installation*:

- **Setup URL (optional):** `https://plusplus.fit/github/connected`
- Leave **Redirect on update** unchecked (we only need the post-*install*
  redirect). Save.

After anyone installs the App, GitHub now redirects them to that URL (with
`?installation_id=…&setup_action=install`, which the app ignores — bootstrap
rediscovers the installation).

## Owner step 2 — add the bounce page at `plusplus.fit/github/connected`

The app declares `applinks:plusplus.fit`, so if the site's AASA covers this
path the universal link opens the app directly and this page never renders. The
page is the fallback (and the reliable path if universal links don't fire): it
bounces into the app via the custom scheme, which the app always handles.

Serve this at `/github/connected` (a static file with a rewrite, or a framework
route — whatever the site uses):

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark light">
  <title>Return to PlusPlus</title>
  <style>
    body { font: -apple-system-body, system-ui, sans-serif; background: #201f1d;
           color: #f5f3f0; margin: 0; min-height: 100vh; display: grid;
           place-items: center; text-align: center; padding: 24px; }
    .mark { font: 700 56px ui-monospace, monospace; color: #34c759; }
    h1 { font-size: 20px; margin: 16px 0 8px; }
    p { color: #a8a29a; max-width: 30ch; margin: 0 auto 24px; }
    a.open { display: inline-block; background: #1668d2; color: #fff;
             text-decoration: none; font-weight: 700; padding: 14px 28px;
             border-radius: 12px; }
  </style>
</head>
<body>
  <div>
    <div class="mark">++</div>
    <h1>PlusPlus Sync installed</h1>
    <p>Return to the app to finish connecting your repo.</p>
    <a class="open" href="plusplus://github/connected">Open PlusPlus</a>
  </div>
  <script>
    // Safari blocks auto-navigation to a custom scheme without a user gesture
    // on first load, so the button above is the reliable trigger; this is a
    // best-effort nudge for browsers that allow it.
    setTimeout(function () { location.href = "plusplus://github/connected"; }, 400);
  </script>
</body>
</html>
```

## Owner step 3 (optional polish) — AASA path

For the universal link to open the app *without* showing the page at all, the
site's `/.well-known/apple-app-site-association` must list the app
(`TEAMID.com.davidcole.plusplus`) with a path that matches `/github/connected`
— either `*` or an entry like `/github/*`. If the current AASA already uses `*`,
nothing to do. If it enumerates paths (e.g. only `/r/*` for share links), add
`/github/*`. Without this, the bounce page (step 2) still works via the custom
scheme; you just see the page for a beat first.

## How it behaves once configured

Install the App → GitHub redirects to `plusplus.fit/github/connected` → app
opens (directly via universal link, or via the page's Open button) → the
connect sheet appears and auto-starts the device flow → GitHub's authorize page
opens with the code pre-filled (B1) → tap **Authorize** → return to the app →
connected. One tap to start, one tap to authorize, no code typing, no hunting
for a button.
