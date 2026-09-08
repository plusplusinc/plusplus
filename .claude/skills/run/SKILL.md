---
name: run
description: Build, install, launch, and drive the app on the iOS simulator. Use to run the app, take screenshots, switch dark mode or Dynamic Type, relaunch without rebuilding, or read the app's log, and to verify UI work visually before calling it done.
allowed-tools: Bash(scripts/run.sh:*), Bash(scripts/sim.sh:*), Bash(xcrun simctl:*), Read
---

Two scripts, run from the repo root. `scripts/run.sh` gets the app on screen; `scripts/sim.sh`
drives it once it is there. Neither needs Xcode open.

## Launch

```sh
scripts/run.sh [name]
```

Builds Debug, boots the default simulator (iPhone 17; override with
`PLUSPLUS_SIMULATOR="iPhone 17 Pro"`), installs and launches the app, waits two seconds for the
first frame, and writes `.build/screenshots/<name>.png`. The path is printed last; Read it.
About 15 seconds on a warm build from a shut-down simulator.

## Drive

```sh
scripts/sim.sh shots [name]             # <name>.light.png, .dark.png, .xxxl.png; about 4 s
scripts/sim.sh screenshot [name]        # one capture of whatever is on screen now
scripts/sim.sh appearance light|dark
scripts/sim.sh content-size <category>  # large is the default; accessibility-extra-extra-extra-large the top
scripts/sim.sh reset                    # light, large
scripts/sim.sh relaunch                 # terminate and launch the installed build; boots the simulator if needed
scripts/sim.sh log [minutes]            # the app's own log lines plus errors and faults; last 5 minutes by default
```

`shots` is the whole checklist in one command and leaves the device at the defaults. Every
`appearance` and `content-size` call waits a second before returning: UIKit animates the change
after `simctl ui` has already exited, and a capture taken straight after the raw command shows
the old state.

What to check in the light, dark, and XXXL images before declaring UI work done:
- Touch targets look at least 44pt, nothing important hidden under system bars.
- No placeholder text, no labels clipped or truncated at XXXL, no glass stacked on glass.

## Gotchas

- Appearance and content size are device settings, so they survive relaunches and reboots of
  the simulator. A session that ended in dark mode makes the next `run.sh` screenshot dark.
  Use `shots`, or `reset` when finished.
- The default content size is `large`, not `medium`.
- There is no tap layer. The app has no controls yet; when one lands, its automation belongs in
  an XCUITest target in the `sim` test tier (see `.claude/rules/testing.md`), not in `sim.sh`.
- `log` is empty today: the placeholder creates no store and logs nothing. Errors reading
  "Connection interrupted" timestamped at a simulator shutdown are the app losing its XPC
  connections, not a bug.
- Only the iOS app exists. watchOS is in the plan and the package platforms, but there is no
  watch target or scheme yet.
- The `xcode` MCP server serves tools only while Xcode has this project open; otherwise it
  fails at session start. Nothing here needs it.

## Troubleshooting

- `Timeout waiting for screen surfaces` from `screenshot` or `shots`: the simulator is shut
  down. `scripts/sim.sh relaunch` boots it and relaunches the app.
- `Process spawn via launchd failed because device is not booted` from `log`: same fix.
- `no built app at .../PlusPlus.app/Info.plist; run scripts/run.sh first`: `relaunch` reuses the
  Debug build in `.build/DerivedData`, and there is none yet.
- `Unknown apperance: blue` (Apple's spelling): `appearance` takes only `light` or `dark`.
