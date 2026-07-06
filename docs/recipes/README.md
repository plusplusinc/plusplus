# Actions recipes for workout repos

Copy-paste workflows for a repo scaffolded by `plusplus init` (like
[mrdavidjcole/workouts](https://github.com/mrdavidjcole/workouts)). Drop them
in your workout repo's `.github/workflows/` and adjust the marked lines.

Both recipes build the `plusplus` CLI from source, which means checking out
the PlusPlus repo. **While that repo is private**, create a fine-grained PAT
with read access to it and add it to your workout repo as the
`PLUSPLUS_REPO_TOKEN` secret. Once release binaries exist
([plusplus#37](https://github.com/mrdavidjcole/plusplus/issues/37)), the
build steps collapse to a download and the token goes away.

| Recipe | Trigger | What it does |
|---|---|---|
| `lint.yml` | PRs touching `program/**` | Fails the PR if the program doesn't validate against the interchange schema |
| `weekly-report.yml` | Mondays + manual | Opens an issue with your per-exercise training stats |

These run on `ubuntu-latest` at 1x minutes — the CLI is Linux-native by
design.
