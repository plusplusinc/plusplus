#!/bin/bash
# Puts screenshots and recordings in a pull request's body. GitHub has no API for the
# drag-and-drop upload its web editor uses, so the files go on the `pr-media` branch, which
# shares no history with main, in a folder named for the PR. The body links them from
# raw.githubusercontent.com, and GitHub shows them inline because the repo is public. A recording
# (.mov or .mp4) becomes a looping GIF, 300 px wide at 20 fps, which plays inline where a video
# file would only be a link. A still wider than 1200 px is scaled down. Prints one Markdown image
# line per file for the body; replace each alt text with what the image shows.
#
# Trim a recording, or put a before and after side by side, with ffmpeg first; the pr skill
# shows how. Everything pushed here is public at once, so check each file shows nothing private.
#
#   scripts/pr-media.sh <pr> <file>...
set -euo pipefail

usage() {
    echo "usage: scripts/pr-media.sh <pr> <file>...  (a PR number, then .png, .jpg, .gif, .mov or .mp4 files)" >&2
    exit 64
}
[ $# -ge 2 ] || usage
PR=$1
shift
[[ $PR =~ ^[0-9]+$ ]] || usage

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Ready each file under the name it will have on the branch.
NAMES=()
for file in "$@"; do
    [ -f "$file" ] || { echo "no such file: $file" >&2; exit 66; }
    base=$(basename "$file")
    stem=${base%.*}
    case "$(echo "${base##*.}" | tr '[:upper:]' '[:lower:]')" in
        mov | mp4)
            name="$stem.gif"
            ffmpeg -v error -y -i "$file" -filter_complex \
                "fps=20,scale=300:-2,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
                -loop 0 "$WORK/$name"
            ;;
        png | jpg | jpeg)
            name=$base
            sips -Z 1200 "$file" --out "$WORK/$name" >/dev/null
            ;;
        gif)
            name=$base
            cp "$file" "$WORK/$name"
            ;;
        *)
            echo "can't put $base in a PR: use .png, .jpg, .gif, .mov or .mp4" >&2
            exit 65
            ;;
    esac
    NAMES+=("$name")
done

# Commit onto the branch through a scratch index, so no checkout changes. Another session may
# push in between: fetch and commit again.
export GIT_INDEX_FILE="$WORK/index"
for attempt in 1 2 3; do
    parent=()
    if git fetch -q origin pr-media 2>/dev/null; then
        git read-tree FETCH_HEAD
        parent=(-p FETCH_HEAD)
    else
        git read-tree --empty
    fi
    for name in "${NAMES[@]}"; do
        blob=$(git hash-object -w "$WORK/$name")
        git update-index --add --cacheinfo "100644,${blob},${PR}/${name}"
    done
    commit=$(git commit-tree "$(git write-tree)" "${parent[@]}" -m "Media for PR #$PR")
    if git push -q origin "${commit}:refs/heads/pr-media" 2>/dev/null; then
        for name in "${NAMES[@]}"; do
            echo "![${name%.*}](https://raw.githubusercontent.com/$REPO/pr-media/$PR/$name)"
        done
        exit 0
    fi
    [ "$attempt" -lt 3 ] && sleep $((attempt * 2))
done
echo "couldn't push to pr-media after 3 tries; check 'git push origin pr-media' by hand" >&2
exit 1
