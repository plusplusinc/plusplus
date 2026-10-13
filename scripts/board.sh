#!/bin/bash
# The private project board, where briefs live. See the /brief skill.
#
#   scripts/board.sh list                              # every item, in board order: id, status, feature, title
#   scripts/board.sh show <item-id>...                 # title, status, and body of each, in one request
#   scripts/board.sh readme                            # the board's README: the design per feature
#   scripts/board.sh readme <<'README'                 # replace the README with stdin
#   scripts/board.sh add <title> <<'CARD'              # a draft item in Todo; prints its id
#   scripts/board.sh body <item-id> <<'CARD'           # replace a draft item's body
#   scripts/board.sh title <item-id> <title>           # rename a draft item
#   scripts/board.sh state <item-id> <<'STATE'         # replace or append its ## State section
#   scripts/board.sh status <item-id> Backlog|Todo|"In Progress"|Done
#   scripts/board.sh move <item-id> top|<after-item-id>  # place it in the queue /onward works through
#   scripts/board.sh feature <item-id> <name>|-        # group it under a feature's design; - for a standalone task
#   scripts/board.sh publish <item-id>                # convert the draft to a repo issue, in place
#
# `add`, `body`, and `state` read from stdin, usually a quoted heredoc (quoted, so backticks stay
# text), so no draft file exists to drift from the card or go missing. `add` with no body makes
# an empty-bodied card; `body` and `state` refuse empty input rather than blank the card. `state`
# takes the section's content without its heading and replaces everything from `## State` to
# the end of the body, State being the last section, or appends the section when there is none.
# `readme` writes the README when stdin has text and reads it otherwise.
#
# Draft items keep the board private while the repo is public; `publish` converts one to an
# issue when the /brief skill says so, keeping its place and status on the board. Trim the
# body first: the issue is public. The Status field's option ids are looked up each run
# rather than committed, so the board can be reshaped without a code change. The board's own
# order (what dragging a card changes) is the queue: /onward takes the In Progress card, else
# the topmost Todo card, feature or not. Backlog is parked; nothing picks it up.
#
# Each command makes one or two GraphQL requests against the hourly quota every session on the
# account shares; "Quotas" in docs/agent-tooling.md has what each costs. When the quota is
# spent, a command says when it resets and exits rather than retrying. `gh` needs the `project`
# scope: `gh auth refresh -s project`.
set -euo pipefail

OWNER="plusplusinc"
REPO="plusplus"
NUMBER=2

# One GraphQL request; prints the response's JSON. Every call goes through here, so a spent
# quota stops the script with its reset time wherever it happens. With --missing-ok, ids that
# resolve to nothing come back as nulls for the caller to report, rather than as an error.
# Called inside $(...), where set -e does not apply, so callers exit on its failure themselves.
gql() {
    local missing_ok=false response status=0 err stderr body errors reset
    if [ "$1" = --missing-ok ]; then
        missing_ok=true
        shift
    fi
    err=$(mktemp)
    response=$(gh api graphql --include "$@" 2> "$err") || status=$?
    stderr=$(cat "$err")
    rm -f "$err"
    body=$(sed $'1,/^\r*$/d' <<< "$response")
    if [ "$status" -eq 0 ]; then
        echo "$body"
        return
    fi
    # The messages in the response, else what gh said, as when the request never reached GitHub.
    errors=$(jq -r '.errors[]?.message, .message? // empty' <<< "$body" 2> /dev/null || true)
    [ -n "$errors" ] || errors=$stderr
    if grep -qi 'rate limit' <<< "$errors"; then
        reset=$(sed $'/^\r*$/q' <<< "$response" | grep -i '^x-ratelimit-reset:' | tr -dc 0-9 || true)
        if [ -n "$reset" ]; then
            reset=$(date -r "$reset" '+%H:%M %Z' 2> /dev/null || date -d "@$reset" '+%H:%M %Z')
            echo "GitHub's API quota is spent until $reset. Every session on this account shares it:" \
                "wait for the reset rather than retrying, which spends whatever comes back." >&2
        else
            echo "GitHub's API quota is spent. Every session on this account shares it: check when" \
                "it resets with gh api graphql -f query='{rateLimit{resetAt}}' and wait, not retry." >&2
        fi
        exit 1
    fi
    if $missing_ok && jq -e '.data and all(.errors[]; .type == "NOT_FOUND")' <<< "$body" > /dev/null 2>&1; then
        echo "$body"
        return
    fi
    echo "${errors:-gh api graphql failed}" >&2
    exit 1
}

# The fields `list` and `show` read from an item, so the two cannot drift: id, status, feature,
# and content (title, the body when $bodies is true, and the draft issue's own id).
ITEM='
    fragment Item on ProjectV2Item {
        id
        status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
        feature: fieldValueByName(name: "Feature") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
        content {
            ... on DraftIssue { id title body @include(if: $bodies) }
            ... on Issue { title body @include(if: $bodies) }
            ... on PullRequest { title body @include(if: $bodies) }
        }
    }'

# The project's id. Looked up each run rather than committed, like the fields' option ids.
project_id() {
    local response
    response=$(gql -f query='
        query($owner: String!, $number: Int!) { organization(login: $owner) { projectV2(number: $number) { id } } }' \
        -f owner="$OWNER" -F number="$NUMBER") || exit
    jq -r '.data.organization.projectV2.id' <<< "$response"
}

# The body on stdin, from a heredoc, a pipe, or a file. A terminal, or the socket an agent's
# shell holds open, gives nothing rather than waiting for input that never ends.
stdin_body() {
    if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then cat; fi
}

usage() {
    sed -n '2,/^[^#]/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

no_item() {
    echo "no item $1 on the board; a new card takes a few seconds to appear" >&2
    exit 1
}

# The items with these ids, as a JSON array in the same order, each with its body. One request
# for up to 100 ids, GitHub's limit for nodes(ids:), so reading every card costs what reading
# one does.
cards() {
    local ids=("$@") args=() id response missing
    for id in "$@"; do
        args+=(-f "ids[]=$id")
    done
    response=$(gql --missing-ok -f query='
        query($ids: [ID!]!, $bodies: Boolean!) { nodes(ids: $ids) { ...Item } }'"$ITEM" \
        -F bodies=true "${args[@]}") || exit
    # An id that names nothing comes back null, and one that names something else, empty.
    missing=$(jq '.data.nodes | map(.id == null) | index(true) // empty' <<< "$response")
    [ -z "$missing" ] || no_item "${ids[missing]}"
    jq '.data.nodes' <<< "$response"
}

# Sets $card to the item's JSON and $draft to its draft issue's own id (DI_...), which
# updateProjectV2DraftIssue takes in place of the item id (PVTI_...) every subcommand takes.
# Called directly, not inside $(...), so its exit ends the script.
draft_card() {
    card=$(cards "$1") || exit
    draft=$(jq -r '.[0].content.id // empty' <<< "$card")
    if [ -z "$draft" ]; then
        echo "$1 is not a draft; edit its issue with gh issue edit" >&2
        exit 1
    fi
}

edit_draft() {
    gql -f query='
        mutation($draft: ID!, $title: String, $body: String) {
            updateProjectV2DraftIssue(input: {draftIssueId: $draft, title: $title, body: $body}) {
                clientMutationId
            }
        }' -f draft="$1" "${@:2}" > /dev/null
}

# Sets a single-select field (Status, Feature) to the option named, or clears it for "-". The
# field and its option ids are looked up each run, so a reshaped board needs no code change.
set_field() {
    local item=$1 name=$2 value=$3 response field ids option
    response=$(gql -f query='
        query($owner: String!, $number: Int!, $name: String!) {
            organization(login: $owner) {
                projectV2(number: $number) {
                    id
                    field(name: $name) { ... on ProjectV2SingleSelectField { id options { id name } } }
                }
            }
        }' -f owner="$OWNER" -F number="$NUMBER" -f name="$name") || exit
    field=$(jq '.data.organization.projectV2.field // empty' <<< "$response")
    if [ -z "$field" ]; then
        echo "no single-select field named '$name' on the board" >&2
        exit 1
    fi
    ids=(-f project="$(jq -r '.data.organization.projectV2.id' <<< "$response")" -f item="$item"
        -f field="$(jq -r .id <<< "$field")")
    if [ "$value" = - ]; then
        gql -f query='
            mutation($project: ID!, $item: ID!, $field: ID!) {
                clearProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field}) {
                    clientMutationId
                }
            }' "${ids[@]}" > /dev/null
        return
    fi
    option=$(jq -r --arg name "$value" '.options[] | select(.name == $name) | .id' <<< "$field")
    if [ -z "$option" ]; then
        echo "no $name option named '$value'; options: $(jq -r '[.options[].name] | join(", ")' <<< "$field")" >&2
        exit 1
    fi
    gql -f query='
        mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
            updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field,
                                                  value: {singleSelectOptionId: $option}}) {
                clientMutationId
            }
        }' "${ids[@]}" -f option="$option" > /dev/null
}

command="${1:-}"
shift || true
case "$command" in
    list)
        [ $# -eq 0 ] || usage
        cursor=null
        while :; do
            page=$(gql -f query='
                query($owner: String!, $number: Int!, $cursor: String, $bodies: Boolean!) {
                    organization(login: $owner) {
                        projectV2(number: $number) {
                            items(first: 100, after: $cursor) {
                                pageInfo { hasNextPage endCursor }
                                nodes { ...Item }
                            }
                        }
                    }
                }'"$ITEM" -f owner="$OWNER" -F number="$NUMBER" -F bodies=false -F cursor="$cursor") || exit
            items=$(jq '.data.organization.projectV2.items' <<< "$page")
            jq -r '.nodes[] | "\(.id)  \(.status.name // "-")\t\(.feature.name // "-")\t\(.content.title // "")"' <<< "$items"
            cursor=$(jq -r '.pageInfo | select(.hasNextPage) | .endCursor' <<< "$items")
            [ -n "$cursor" ] || break
        done
        ;;
    show)
        [ $# -ge 1 ] || usage
        found=$(cards "$@") || exit
        # One card prints bare; several each get a header line naming the id.
        jq -r '(length > 1) as $many
            | [.[] | (if $many then "==> \(.id) <==\n" else "" end)
                + "\(.content.title)\n[\(.status.name // "-")]\n\n\(.content.body // "")"] | join("\n\n")' <<< "$found"
        ;;
    readme)
        [ $# -eq 0 ] || usage
        readme=$(stdin_body)
        if [[ $readme =~ [^[:space:]] ]]; then
            project=$(project_id) || exit
            gql -f query='
                mutation($project: ID!, $readme: String!) {
                    updateProjectV2(input: {projectId: $project, readme: $readme}) { clientMutationId }
                }' -f project="$project" -f readme="$readme" > /dev/null
        else
            response=$(gql -f query='
                query($owner: String!, $number: Int!) {
                    organization(login: $owner) { projectV2(number: $number) { readme } }
                }' -f owner="$OWNER" -F number="$NUMBER") || exit
            jq -r '.data.organization.projectV2.readme // ""' <<< "$response"
        fi
        ;;
    add)
        [ $# -eq 1 ] || usage
        body=$(stdin_body)
        project=$(project_id) || exit
        response=$(gql -f query='
            mutation($project: ID!, $title: String!, $body: String) {
                addProjectV2DraftIssue(input: {projectId: $project, title: $title, body: $body}) {
                    projectItem { id }
                }
            }' -f project="$project" -f title="$1" -f body="$body") || exit
        jq -r '.data.addProjectV2DraftIssue.projectItem.id' <<< "$response"
        ;;
    body)
        [ $# -eq 1 ] || usage
        body=$(stdin_body)
        if [[ ! $body =~ [^[:space:]] ]]; then
            echo "no body on stdin; $1 left unchanged" >&2
            exit 1
        fi
        draft_card "$1"
        edit_draft "$draft" -f body="$body"
        ;;
    title)
        [ $# -eq 2 ] || usage
        draft_card "$1"
        edit_draft "$draft" -f title="$2"
        ;;
    state)
        [ $# -eq 1 ] || usage
        state=$(stdin_body)
        if [[ ! $state =~ [^[:space:]] ]]; then
            echo "no State on stdin; $1 left unchanged" >&2
            exit 1
        fi
        draft_card "$1"
        # The body above its State heading: the whole body when there is none.
        above=$(jq -r '.[0].content.body // "" | sub("(\\A|\n)## State[ \t]*(\n[\\s\\S]*)?\\z"; "")' <<< "$card")
        body="## State"$'\n'"$state"
        [ -z "$above" ] || body="$above"$'\n\n'"$body"
        edit_draft "$draft" -f body="$body"
        ;;
    status)
        [ $# -eq 2 ] || usage
        [ "$2" != - ] || usage
        set_field "$1" Status "$2"
        ;;
    move)
        [ $# -eq 2 ] || usage
        after=null
        [ "$2" = top ] || after=$2
        project=$(project_id) || exit
        gql -f query='
            mutation($project: ID!, $item: ID!, $after: ID) {
                updateProjectV2ItemPosition(input: {projectId: $project, itemId: $item, afterId: $after}) {
                    clientMutationId
                }
            }' \
            -f project="$project" -f item="$1" -F after="$after" > /dev/null
        ;;
    feature)
        [ $# -eq 2 ] || usage
        set_field "$1" Feature "$2"
        ;;
    publish)
        [ $# -eq 1 ] || usage
        response=$(gql -f query='
            query($owner: String!, $repo: String!) { repository(owner: $owner, name: $repo) { id } }' \
            -f owner="$OWNER" -f repo="$REPO") || exit
        response=$(gql -f query='
            mutation($item: ID!, $repo: ID!) {
                convertProjectV2DraftIssueItemToIssue(input: {itemId: $item, repositoryId: $repo}) {
                    item { content { ... on Issue { url } } }
                }
            }' \
            -f item="$1" -f repo="$(jq -r .data.repository.id <<< "$response")") || exit
        jq -r '.data.convertProjectV2DraftIssueItemToIssue.item.content.url' <<< "$response"
        ;;
    *) usage ;;
esac
