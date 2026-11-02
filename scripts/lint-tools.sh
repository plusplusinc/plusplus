#!/bin/bash
# The SwiftFormat and SwiftLint that scripts/lint.sh runs, here and on Xcode Cloud, at the
# versions named below and nowhere else. Each is a release binary from the tool's GitHub
# releases, checked against its SHA-256 and kept in the main checkout's .build/tools/, which every
# worktree of the clone shares. A new release changes nothing until a PR raises a version here.
#
#   scripts/lint-tools.sh install         # fetch both, if not already there
#   scripts/lint-tools.sh path <tool>     # print the tool's binary, fetching it first if needed
#
# To raise a version: change it and its checksum below (the release page lists each asset's
# sha256), run scripts/lint.sh --fix, and fix or turn off in .swiftformat or .swiftlint.yml what
# the new rules find.
set -euo pipefail

#   <tool> <version> <release asset URL> <sha256 of the asset>
TOOLS=(
    "swiftformat 0.64.5 https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.5/swiftformat.zip ec017c91fdd46233e5a22dc43ff9564a3cc4b37023d3b4681b6c7d7b781de113"
    "swiftlint 0.65.1 https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
)

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# The main checkout, also from a linked worktree, so one download serves every worktree.
MAIN=$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)")
TOOLS_DIR="$MAIN/.build/tools"

usage() {
    sed -n '7,8p' "${BASH_SOURCE[0]}" | sed 's/^# *//' >&2
    exit 64
}

# Prints the binary of a tool, fetching it when it is missing.
#
#   tool_path <tool>
tool_path() {
    local entry name version url sha
    for entry in "${TOOLS[@]}"; do
        read -r name version url sha <<< "$entry"
        [ "$name" = "$1" ] || continue
        local dir="$TOOLS_DIR/$name-$version"
        if [ ! -x "$dir/$name" ]; then
            fetch "$name" "$version" "$url" "$sha" "$dir" >&2 || {
                echo "could not install $name $version into $dir; run scripts/lint-tools.sh install (needs the network)" >&2
                return 1
            }
        fi
        echo "$dir/$name"
        return 0
    done
    echo "unknown tool: $1 (swiftformat or swiftlint)" >&2
    return 64
}

fetch() {
    local name=$1 version=$2 url=$3 sha=$4 dir=$5
    echo "installing $name $version into $dir"
    local tmp status=0
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lint-tools.XXXXXX")
    unpack "$name" "$version" "$url" "$sha" "$tmp" || status=1
    # Moved into place whole, so an interrupted fetch never leaves a half-written binary.
    if [ "$status" -eq 0 ]; then
        mkdir -p "$TOOLS_DIR" && rm -rf "$dir" && mv "$tmp/unzipped" "$dir" || status=1
    fi
    rm -rf "$tmp"
    return "$status"
}

# Downloads the asset into <tmp>, checks it, and unzips it into <tmp>/unzipped.
unpack() {
    local name=$1 version=$2 url=$3 sha=$4 tmp=$5 actual
    curl --fail --silent --show-error --location --retry 2 --output "$tmp/asset.zip" "$url" ||
        return 1
    actual=$(shasum -a 256 "$tmp/asset.zip" | cut -d' ' -f1)
    if [ "$actual" != "$sha" ]; then
        echo "$name $version: checksum $actual does not match the pinned $sha" >&2
        return 1
    fi
    unzip -q "$tmp/asset.zip" -d "$tmp/unzipped" || return 1
    [ -x "$tmp/unzipped/$name" ] || { echo "$name $version: no $name in $url" >&2; return 1; }
}

case "${1:-}" in
    install)
        for entry in "${TOOLS[@]}"; do
            tool_path "${entry%% *}" > /dev/null
        done
        ;;
    path)
        [ "$#" -eq 2 ] || usage
        tool_path "$2"
        ;;
    *) usage ;;
esac
