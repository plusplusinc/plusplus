---
name: lint
description: Run SwiftFormat, SwiftLint, and the US English check exactly as CI does. Use before committing.
allowed-tools: Bash(scripts/lint.sh:*)
---

`scripts/lint.sh --fix` applies SwiftFormat and SwiftLint autocorrections, then re-checks.
`scripts/lint.sh` checks only and exits non-zero on any finding; that is what Xcode Cloud runs
in `ci_scripts/ci_post_clone.sh`.

The edit hook already formats each Swift file you touch, so this is mostly a whole-tree sweep.
Fix remaining findings by hand; do not disable a rule inline without a comment saying why.
