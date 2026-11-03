#!/bin/bash
# The SwiftFormat and SwiftLint that scripts/lint.sh runs, here and on Xcode Cloud, at the
# versions named below and nowhere else. Each is a release binary from the tool's GitHub
# releases, checked against its SHA-256 and kept in the main checkout's .build/tools/, which every
# worktree of the clone shares. A new release changes nothing until a PR raises a version here.
#
#   scripts/lint-tools.sh path <tool>     # print the tool's binary, fetching it first if needed
#   scripts/lint-tools.sh outdated        # "<tool> <pinned> <latest>" for each with a newer release
#
# Dependabot can't read these pins, so the nightly run (scripts/nightly-tooling.py) runs
# `outdated` and makes a card, "Update <tool> to <latest>", for each tool it names.
#
# To raise a version: change it and its checksum below (the release page lists each asset's
# sha256), run scripts/lint.sh --fix, and fix or turn off in .swiftformat or .swiftlint.yml what
# the new rules find.
set -euo pipefail

#   <tool> <version> <sha256 of the asset> <release asset URL, {v} for the version>
TOOLS=(
    "swiftformat 0.64.5 ec017c91fdd46233e5a22dc43ff9564a3cc4b37023d3b4681b6c7d7b781de113 https://github.com/nicklockwood/SwiftFormat/releases/download/{v}/swiftformat.zip"
    "swiftlint 0.65.1 c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0 https://github.com/realm/SwiftLint/releases/download/{v}/portable_swiftlint.zip"
)

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# The main checkout, also from a linked worktree, so one download serves every worktree. Two
# steps, so a git failure stops the script rather than leaving dirname with "".
COMMON=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)
TOOLS_DIR="$(dirname "$COMMON")/.build/tools"

# Downloads a tool's asset and checks it, in a folder beside the tools so the last step is a
# rename on one volume: the tool appears whole or not at all. Fetches that race, from two
# worktrees, each finish; the first to land wins and none deletes another's.
#
#   fetch <tool> <version> <sha256> <url> <dir>
fetch() (
    # Each step exits on its own: set -e does nothing in a function called from `||`.
    name=$1 version=$2 sha=$3 url=$4 dir=$5
    echo "installing $name $version into $dir"
    mkdir -p "$TOOLS_DIR" || exit 1
    tmp=$(mktemp -d "$TOOLS_DIR/.fetch.XXXXXX") || exit 1
    trap 'rm -rf "$tmp"' EXIT
    curl --fail --silent --show-error --location --retry 2 --output "$tmp/asset.zip" "$url" ||
        exit 1
    actual=$(shasum -a 256 "$tmp/asset.zip" | cut -d' ' -f1)
    if [ "$actual" != "$sha" ]; then
        echo "$name $version: checksum $actual does not match the pinned $sha" >&2
        exit 1
    fi
    unzip -q "$tmp/asset.zip" -d "$tmp/unzipped" || exit 1
    [ -x "$tmp/unzipped/$name" ] || { echo "$name $version: no $name in $url" >&2; exit 1; }
    [ -x "$dir/$name" ] || mv "$tmp/unzipped" "$dir"
)

# Each tool's latest GitHub release against its pin, one REST request a tool. A tool whose
# release can't be read is named on stderr and fails the command, after the others are checked.
outdated() {
    local entry name version sha url repo latest status=0 found=0
    for entry in "${TOOLS[@]}"; do
        read -r name version sha url <<< "$entry"
        repo=$(sed -E 's#^https://github.com/([^/]+/[^/]+)/.*#\1#' <<< "$url")
        if ! latest=$(gh api "repos/$repo/releases/latest" --jq .tag_name); then
            echo "could not read $name's latest release from $repo: check gh auth status and the network" >&2
            status=1
            continue
        fi
        latest=${latest#v}
        if [ "$latest" != "$version" ] &&
            [ "$(printf '%s\n%s\n' "$version" "$latest" | sort -V | tail -1)" = "$latest" ]; then
            echo "$name $version $latest"
            found=1
        fi
    done
    [ "$status" -ne 0 ] || [ "$found" -eq 1 ] || echo "every pinned tool is at its latest release" >&2
    return "$status"
}

if [ "${1:-}" = outdated ] && [ "$#" -eq 1 ]; then
    outdated
    exit
fi
[ "${1:-}" = path ] && [ "$#" -eq 2 ] ||
    { echo "usage: scripts/lint-tools.sh path <swiftformat|swiftlint> | outdated" >&2; exit 64; }

for entry in "${TOOLS[@]}"; do
    read -r name version sha url <<< "$entry"
    [ "$name" = "$2" ] || continue
    dir="$TOOLS_DIR/$name-$version"
    if [ ! -x "$dir/$name" ]; then
        fetch "$name" "$version" "$sha" "${url//\{v\}/$version}" "$dir" >&2 || {
            echo "could not install $name $version into $dir; check the network and run scripts/lint.sh again" >&2
            exit 1
        }
    fi
    echo "$dir/$name"
    exit 0
done
echo "unknown tool: $2 (swiftformat or swiftlint)" >&2
exit 64
