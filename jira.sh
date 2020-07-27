#!/bin/bash

. ~/fuzzy-jira/.jiraconfig

jira() {
    if [[ $1 == "fetch" ]]; then
        if [[ -n "$2" ]]; then
            PROJECT=$(tr a-z A-Z <<< "$2")
        else
            PROJECT=$JIRA_DEFAULT_PROJECT
        fi
        CACHE="${JIRA_CACHE_DIR}/${PROJECT}"
        jira_fetch "$PROJECT"
    elif [[ $1 == "." ]]; then
        parse_ticket_key
    elif [[ -n $(echo "$1" | grep -e '[A-Z]\+-[0-9]\+' -o) ]]; then
        open_issue "$1"
    else
        if [[ -n "$1" ]]; then
            PROJECT=$(tr a-z A-Z <<< "$1")
        else
            PROJECT=$JIRA_DEFAULT_PROJECT
        fi
        CACHE="${JIRA_CACHE_DIR}/${PROJECT}"
        [[ ! -f "${CACHE}" ]] && jira_fetch "$PROJECT"
        search_issues "$PROJECT"
    fi
}

jira_fetch() {
    local url="${JIRA_DOMAIN}/rest/api/2/search?jql=project=${PROJECT}&fields=summary&maxResults=1000"
    echo "Fetching issues for $PROJECT..."
    echo "From ${url}"
    [[ ! -f "$PROJECT" ]] && touch "${CACHE}"
    local curl_args=(
        --silent
        --fail
        --user "${JIRA_USERNAME}:${JIRA_PASSWORD}" 
        --header 'Content-type: application/json'
        --request GET "${url}"
    )
    local result=$(curl "${curl_args[@]}" \
        | jq -r '.issues[] | .key + " " + .fields.summary' \
        | join -v 1 <(sort --version-sort -) <(sort --version-sort "${CACHE}") \
        | tee -a "${CACHE}" \
        | wc -l \
        | tr -d ' ')
    local total=$(< "${CACHE}" wc -l | tr -d ' ')
    echo "Success: $result issues added to cache (${total} total)"
}

search_issues() {
    local issue=$(< "${CACHE}" fzf --tac | cut -d ' ' -f 1 | cat)
    [[ -n "$issue" ]] && open_issue "$issue"
}

open_issue() {
    echo "Opening issue ${1}"
    open "${JIRA_DOMAIN}/browse/${1}"
}

parse_ticket_key() {
    local key=$(git describe --contains --all | grep -e '[A-Z]\+-[0-9]\+' -o)
    if [[ -n "$key" ]]; then
        open_issue "$key"
    else
        echo "Could not parse ticket key"
    fi
}

jira "$1" "$2"

