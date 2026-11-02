#!/bin/bash
# The SwiftFormat and SwiftLint that scripts/lint.sh runs, here and on Xcode Cloud, at the
# versions named below and nowhere else. Each is a release binary from the tool's GitHub
# releases, checked against its SHA-256 and kept in the main checkout's .build/tools/, which every
# worktree of the clone shares. A new release changes nothing until a PR raises a version here.
#
#   scripts/lint-tools.sh path <tool>     # print the tool's binary, fetching it first if needed
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

# Downloads a tool's asset, checks it, and moves its unzipped folder into place whole, so an
# interrupted fetch never leaves a half-written binary.
#
#   fetch <tool> <version> <sha256> <url> <dir>
fetch() {
    local name=$1 version=$2 sha=$3 url=$4 dir=$5 tmp actual
    echo "installing $name $version into $dir"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lint-tools.XXXXXX")
    curl --fail --silent --show-error --location --retry 2 --output "$tmp/asset.zip" "$url" &&
        actual=$(shasum -a 256 "$tmp/asset.zip" | cut -d' ' -f1) &&
        { [ "$actual" = "$sha" ] ||
            { echo "$name $version: checksum $actual does not match the pinned $sha" >&2; false; }; } &&
        unzip -q "$tmp/asset.zip" -d "$tmp/unzipped" &&
        { [ -x "$tmp/unzipped/$name" ] || { echo "$name $version: no $name in $url" >&2; false; }; } &&
        mkdir -p "$TOOLS_DIR" && rm -rf "$dir" && mv "$tmp/unzipped" "$dir"
    local status=$?
    rm -rf "$tmp"
    return "$status"
}

[ "${1:-}" = path ] && [ "$#" -eq 2 ] ||
    { echo "usage: scripts/lint-tools.sh path <swiftformat|swiftlint>" >&2; exit 64; }

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
