---
name: run
description: Build, install, and launch the app on the simulator and capture a screenshot to look at. Use to verify UI work visually before calling it done.
allowed-tools: Bash(scripts/run.sh:*), Bash(xcrun simctl:*), Read
---

`scripts/run.sh [name]` builds Debug, boots the default simulator (override with
`PLUSPLUS_SIMULATOR="iPhone 17 Pro"`), installs and launches the app, waits two seconds, and
writes `.build/screenshots/<name>.png`. It prints the path last; Read that file to see it.

What to check in a screenshot before declaring UI work done:
- Layout at the default size, then with `xcrun simctl ui booted content_size extra-extra-extra-large`
  set for Dynamic Type, then with `xcrun simctl ui booted appearance dark`.
- Touch targets look at least 44pt, nothing important hidden under system bars.
- No placeholder text, no clipped labels, no glass stacked on glass.

Restore `content_size medium` and `appearance light` when finished.
