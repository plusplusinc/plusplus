#!/bin/bash
# The private project board, where briefs live. See docs/process.md.
#
#   scripts/board.sh list                              # every item: id, status, title
#   scripts/board.sh show <item-id>                    # title, status, and body
#   scripts/board.sh add <title> [body-file]           # a draft item in Todo; prints its id
#   scripts/board.sh body <item-id> <body-file>        # replace a draft item's body
#   scripts/board.sh status <item-id> Todo|"In Progress"|Done
#
# Draft items keep the board private while the repo may be public; convert one to an issue in
# the GitHub UI when the work can be discussed publicly. The Status field's option ids are
# looked up each run rather than committed, so the board can be reshaped without a code change.
# `gh` needs the `project` scope: `gh auth refresh -s project`.
set -euo pipefail

OWNER="plusplusinc"
NUMBER=2

project_id() {
    gh project view "$NUMBER" --owner "$OWNER" --format json --jq .id
}

status_field() {
    gh project field-list "$NUMBER" --owner "$OWNER" --format json \
        --jq '.fields[] | select(.name == "Status")'
}

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

command="${1:-}"
shift || true
case "$command" in
    list)
        gh project item-list "$NUMBER" --owner "$OWNER" --format json \
            --jq '.items[] | "\(.id)  \(.status // "-")\t\(.title)"'
        ;;
    show)
        [ $# -eq 1 ] || usage
        gh project item-list "$NUMBER" --owner "$OWNER" --format json \
            --jq ".items[] | select(.id == \"$1\") | \"\(.title)\n[\(.status // \"-\")]\n\n\(.content.body // \"\")\""
        ;;
    add)
        [ $# -ge 1 ] && [ $# -le 2 ] || usage
        body=""
        [ $# -eq 2 ] && body=$(cat "$2")
        gh project item-create "$NUMBER" --owner "$OWNER" --title "$1" --body "$body" \
            --format json --jq .id
        ;;
    body)
        [ $# -eq 2 ] || usage
        gh project item-edit --id "$1" --body "$(cat "$2")" > /dev/null
        ;;
    status)
        [ $# -eq 2 ] || usage
        field=$(status_field)
        option=$(jq -r --arg name "$2" '.options[] | select(.name == $name) | .id' <<< "$field")
        if [ -z "$option" ]; then
            echo "no Status option named '$2'; options: $(jq -r '[.options[].name] | join(", ")' <<< "$field")" >&2
            exit 1
        fi
        gh project item-edit --project-id "$(project_id)" --id "$1" \
            --field-id "$(jq -r .id <<< "$field")" --single-select-option-id "$option" > /dev/null
        ;;
    *) usage ;;
esac
