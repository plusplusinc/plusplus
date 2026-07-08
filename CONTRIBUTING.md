# Contributing to PlusPlus

Thanks for looking. This project is small, opinionated, and moves fast —
this page tells you how to land a change without friction.

## Before you write code

- **Bugs**: open an issue with reproduction steps (device/simulator, iOS
  version, what you expected). Small fixes are welcome directly as PRs.
- **Features**: open an issue first. PlusPlus follows a deliberate design
  language (quiet-terminal, green-is-data, no obligation vocabulary) and a
  short v1 path — a feature PR that fights either will stall. The issue is
  where scope gets agreed.
- Check `CLAUDE.md` — the decisions log is the project's memory. If your
  change re-litigates something recorded there, the PR needs to say why.

## Building

The Xcode project is generated, not checked in:

```sh
xcodegen generate        # needs XcodeGen; Xcode 26+
open PlusPlus.xcodeproj
```

The platform-pure layers build anywhere Swift 6 does — no Mac required:

```sh
swift test --package-path PlusPlusKit
swift test --package-path PlusPlusCLI
```

## Landing a change

- PRs target `main`. The ruleset requires the `test`, `kit-test`, and
  `cli-test` checks to pass; squash is the only merge method. Fork PRs get
  the same checks via the `pull_request` trigger.
- Tests ride the change that motivates them. New test containers use
  the throwaway on-disk store pattern in `CLAUDE.md` → Patterns — not
  in-memory configurations.
- If your change touches the interchange format, the CLI surface, targets,
  or CI, update the doc that describes it (`docs/PLATFORM.md`,
  `docs/AGENTS.md`, `README.md`) in the same PR. PLATFORM.md's JSON
  examples are executable — CI decodes them, so a schema change without a
  doc change fails honestly.
- Keep commits explanatory: what changed and *why*, not a play-by-play.

## Licensing

The app (repo as a whole) is **AGPL-3.0**; `PlusPlusKit/` and
`PlusPlusCLI/` are **MIT**. By contributing you agree your contribution is
licensed under the license of the directory it lands in. The interchange
format is meant to be adopted — if you're building your own tool on it,
the MIT-licensed Kit and conformance fixtures are the contract.
