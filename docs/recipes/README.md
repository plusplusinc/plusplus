# Actions recipes for routine repos

Copy-paste workflows for a repo scaffolded by `plusplus init` (like
[mrdavidjcole/workouts](https://github.com/mrdavidjcole/workouts)). Drop them
in your routine repo's `.github/workflows/` and adjust the marked lines.

Both recipes build the `plusplus` CLI from source by checking out the
(public) PlusPlus repo — no token or secret needed. Once release binaries
exist ([plusplus#37](https://github.com/plusplusinc/plusplus/issues/37)),
the build steps collapse to a download.

| Recipe | Trigger | What it does |
|---|---|---|
| `lint.yml` | PRs touching `program/**` + pushes to main | Fails the run if the program doesn't validate against the interchange schema |
| `weekly-report.yml` | Mondays + manual | Opens an issue with your per-exercise training stats |
| `streak-badge.yml` | Pushes touching `history/**` + manual | Maintains a shields.io endpoint JSON so your README shows your week streak (same semantics as the app's Streak widget) |

These run on `ubuntu-latest` at 1x minutes — the CLI is Linux-native by
design.
