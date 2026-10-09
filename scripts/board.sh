#!/bin/bash
# The private project board, where briefs live. See the /brief skill.
#
#   scripts/board.sh list                              # every item, in board order: id, status, feature, title
#   scripts/board.sh show <item-id>                    # title, status, and body
#   scripts/board.sh add <title> [body-file]           # a draft item in Todo; prints its id
#   scripts/board.sh body <item-id> <body-file>        # replace a draft item's body
#   scripts/board.sh status <item-id> Todo|"In Progress"|Done
#   scripts/board.sh move <item-id> top|<after-item-id>  # place it in the queue /onward works through
#   scripts/board.sh feature <item-id> <name>|-        # group it under a feature's design; - for a standalone task
#   scripts/board.sh publish <item-id>                # convert the draft to a repo issue, in place
#
# Draft items keep the board private while the repo is public; `publish` converts one to an
# issue when the /brief skill says so, keeping its place and status on the board. Trim the
# body first: the issue is public. The Status field's option ids are looked up each run
# rather than committed, so the board can be reshaped without a code change. The board's own
# order (what dragging a card changes) is the queue: /onward takes the In Progress card, else
# the topmost Todo card, feature or not. Backlog is parked; nothing picks it up.
# `gh` needs the `project` scope: `gh auth refresh -s project`.
set -euo pipefail

OWNER="plusplusinc"
REPO="plusplus"
NUMBER=2

project_id() {
    gh project view "$NUMBER" --owner "$OWNER" --format json --jq .id
}

field() {
    gh project field-list "$NUMBER" --owner "$OWNER" --format json \
        --jq ".fields[] | select(.name == \"$1\")"
}

usage() {
    sed -n '2,/^[^#]/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

# gh edits a draft's title and body through the draft issue's own id (DI_...), not the project
# item's id (PVTI_...) that every other subcommand takes.
draft_id() {
    gh project item-list "$NUMBER" --owner "$OWNER" --format json \
        --jq ".items[] | select(.id == \"$1\") | .content.id"
}

command="${1:-}"
shift || true
case "$command" in
    list)
        gh project item-list "$NUMBER" --owner "$OWNER" --format json --limit 500 \
            --jq '.items[] | "\(.id)  \(.status // "-")\t\(.feature // "-")\t\(.title)"'
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
        gh project item-edit --id "$(draft_id "$1")" --body "$(cat "$2")" > /dev/null
        ;;
    status)
        [ $# -eq 2 ] || usage
        field=$(field Status)
        option=$(jq -r --arg name "$2" '.options[] | select(.name == $name) | .id' <<< "$field")
        if [ -z "$option" ]; then
            echo "no Status option named '$2'; options: $(jq -r '[.options[].name] | join(", ")' <<< "$field")" >&2
            exit 1
        fi
        gh project item-edit --project-id "$(project_id)" --id "$1" \
            --field-id "$(jq -r .id <<< "$field")" --single-select-option-id "$option" > /dev/null
        ;;
    move)
        [ $# -eq 2 ] || usage
        after=()
        [ "$2" = top ] || after=(-f after="$2")
        gh api graphql -f query='
            mutation($project: ID!, $item: ID!, $after: ID) {
                updateProjectV2ItemPosition(input: {projectId: $project, itemId: $item, afterId: $after}) {
                    clientMutationId
                }
            }' \
            -f project="$(project_id)" -f item="$1" "${after[@]+"${after[@]}"}" > /dev/null
        ;;
    feature)
        [ $# -eq 2 ] || usage
        field=$(field Feature)
        if [ "$2" = - ]; then
            args=(--clear)
        else
            option=$(jq -r --arg name "$2" '.options[] | select(.name == $name) | .id' <<< "$field")
            if [ -z "$option" ]; then
                echo "no Feature named '$2'; features: $(jq -r '[.options[].name] | join(", ")' <<< "$field")" >&2
                exit 1
            fi
            args=(--single-select-option-id "$option")
        fi
        gh project item-edit --project-id "$(project_id)" --id "$1" \
            --field-id "$(jq -r .id <<< "$field")" "${args[@]}" > /dev/null
        ;;
    publish)
        [ $# -eq 1 ] || usage
        gh api graphql -f query='
            mutation($item: ID!, $repo: ID!) {
                convertProjectV2DraftIssueItemToIssue(input: {itemId: $item, repositoryId: $repo}) {
                    item { content { ... on Issue { url } } }
                }
            }' \
            -f item="$1" \
            -f repo="$(gh repo view "$OWNER/$REPO" --json id --jq .id)" \
            --jq .data.convertProjectV2DraftIssueItemToIssue.item.content.url
        ;;
    *) usage ;;
esac
