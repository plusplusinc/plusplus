#!/bin/bash
# Formatting, lint, and spelling, the same way CI runs them.
#
#   scripts/lint.sh                  # whole tree, and each agent's model, check only; non-zero on any finding
#   scripts/lint.sh --fix            # apply SwiftFormat and SwiftLint autocorrections first
#   scripts/lint.sh --fix <paths>    # only these files; what the edit hook runs
#
# Scope lives in the tools' own configs (.swiftformat, .swiftlint.yml), not here.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT"

fix=false
if [ "${1:-}" = "--fix" ]; then
    fix=true
    shift
fi

swift_files=()
for path in "$@"; do
    case "$path" in *.swift) [ -f "$path" ] && swift_files+=("$path") ;; esac
done
whole_tree=$([ "$#" -eq 0 ] && echo true || echo false)

status=0
if $whole_tree || [ "${#swift_files[@]}" -gt 0 ]; then
    # Required only for Swift. A docs-only path list gets only the US English check.
    # The pinned versions (scripts/lint-tools.sh), never whatever is on PATH, so a new release
    # changes nothing here or on Xcode Cloud until a PR raises the pin.
    swiftformat=$(scripts/lint-tools.sh path swiftformat) || exit 1
    swiftlint=$(scripts/lint-tools.sh path swiftlint) || exit 1
    targets=("${swift_files[@]+"${swift_files[@]}"}")
    if $fix; then
        "$swiftformat" --quiet ${targets[@]+"${targets[@]}"} $($whole_tree && echo .)
        "$swiftlint" lint --fix --quiet --force-exclude ${targets[@]+"${targets[@]}"} > /dev/null || true
    fi
    # Not --quiet: it drops the lines that say which file and rule, leaving only "did not pass".
    if ! format=$("$swiftformat" --lint ${targets[@]+"${targets[@]}"} $($whole_tree && echo .) 2>&1); then
        grep -E ': (error|warning): ' <<< "$format" >&2 || printf '%s\n' "$format" >&2
        echo "SwiftFormat: scripts/lint.sh --fix formats these." >&2
        status=1
    fi
    "$swiftlint" lint --strict --quiet --force-exclude ${targets[@]+"${targets[@]}"} || status=1
fi

scripts/check-us-english.sh "$@" || status=1

if $whole_tree; then
    # Every build setting lives in Config/*.xcconfig; the project file carries none. Xcode's
    # wizards sometimes write one in (the Xcode Cloud setup wrote PRODUCT_NAME); move it out.
    pbxproj="PlusPlus.xcodeproj/project.pbxproj"
    if grep -qE '^\s*[A-Z_]+ = .*;$' "$pbxproj"; then
        echo "$pbxproj: build settings belong in Config/*.xcconfig" >&2
        grep -nE '^\s*[A-Z_]+ = .*;$' "$pbxproj" >&2
        status=1
    fi
fi

# Each agent's model matches docs/agent-tooling.md's "Models by task": on the whole tree, and on a
# path list holding what sets a model, as a docs-only PR's lint is.
models=$whole_tree
for path in "$@"; do
    case "$path" in docs/agent-tooling.md | .claude/agents/* | scripts/nightly-*) models=true ;; esac
done
if $models; then
    python3 -I scripts/models.py check || status=1
fi

# The agent docs' word budget: what every session reads (CLAUDE.md) and what agents load with
# their work. Adherence falls as instructions grow, so adding a line means cutting one. Lower a
# number when a cut leaves room; raise one only in a PR that says what the added words earn.
CLAUDE_MD_WORDS=1700
AGENT_DOCS_WORDS=27670
budget=$whole_tree
for path in "$@"; do
    case "$path" in */CLAUDE.md | CLAUDE.md | *.claude/agents/* | *.claude/skills/* | *.claude/rules/* | *docs/agent-tooling.md) budget=true ;; esac
done
if $budget; then
    claude_md=$(wc -w < CLAUDE.md)
    agent_docs=$(cat CLAUDE.md .claude/agents/*.md .claude/skills/*/SKILL.md .claude/rules/*.md docs/agent-tooling.md | wc -w)
    if [ "$claude_md" -gt "$CLAUDE_MD_WORDS" ]; then
        echo "CLAUDE.md: $((claude_md)) words, over its budget of $CLAUDE_MD_WORDS. Cut as many as were added, or move them to the rules file or skill that needs them." >&2
        status=1
    fi
    if [ "$agent_docs" -gt "$AGENT_DOCS_WORDS" ]; then
        echo "agent docs (CLAUDE.md, .claude/agents, skills, rules, docs/agent-tooling.md): $((agent_docs)) words, over their budget of $AGENT_DOCS_WORDS. Cut as many as were added: a rule a script or check now holds, one said in another file, or one the ledger shows unused." >&2
        status=1
    fi
fi

[ "$status" -eq 0 ] && echo "lint ok"
exit "$status"
