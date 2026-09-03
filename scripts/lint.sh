#!/bin/bash
# Formatting, lint, and spelling, the same way CI runs them.
#
#   scripts/lint.sh                  # whole tree, check only; non-zero on any finding
#   scripts/lint.sh --fix            # apply SwiftFormat and SwiftLint autocorrections first
#   scripts/lint.sh --fix <paths>    # only these files; what the edit hook runs
#
# Scope lives in the tools' own configs (.swiftformat, .swiftlint.yml), not here.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT"

for tool in swiftformat swiftlint; do
    command -v "$tool" > /dev/null || { echo "$tool is not installed: run 'brew bundle'" >&2; exit 1; }
done

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
    targets=("${swift_files[@]+"${swift_files[@]}"}")
    if $fix; then
        swiftformat --quiet ${targets[@]+"${targets[@]}"} $($whole_tree && echo .)
        swiftlint lint --fix --quiet --force-exclude ${targets[@]+"${targets[@]}"} > /dev/null || true
    fi
    swiftformat --lint --quiet ${targets[@]+"${targets[@]}"} $($whole_tree && echo .) || status=1
    swiftlint lint --strict --quiet --force-exclude ${targets[@]+"${targets[@]}"} || status=1
fi

scripts/check-us-english.sh "$@" || status=1

if $whole_tree; then
    # The project file is meant to stay tiny: App/ is a buildable folder and every build
    # setting lives in Config/*.xcconfig. Growth here means someone bypassed both.
    pbxproj="PlusPlus.xcodeproj/project.pbxproj"
    if [ "$(wc -l < "$pbxproj")" -gt 60 ] || grep -q 'buildSettings = {[^}]' "$pbxproj"; then
        echo "$pbxproj: build settings or file lists belong in xcconfig or buildable folders" >&2
        status=1
    fi
fi

[ "$status" -eq 0 ] && echo "lint ok"
exit "$status"
