#!/bin/bash

. ~/fuzzy-jira/.jiraconfig

function jira() {
    [[ ! -d ${JIRA_CACHE_DIR} ]] && mkdir ${JIRA_CACHE_DIR}
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

function jira_fetch() {
    local url="${JIRA_DOMAIN}/rest/api/2/search?jql=project=${PROJECT}&fields=summary&maxResults=1000"
    local auth="${JIRA_USERNAME}:${JIRA_PASSWORD}"
    echo "Fetching issues for $PROJECT..."
    echo "From ${url}"
    [[ ! -f "$PROJECT" ]] && touch "${CACHE}"
    local result=$(curl -s -u "${auth}" -X GET -H 'Content-type: application/json' "${url}" |
        jq -r '.issues[] | .key + " " + .fields.summary' |
        join -v 1 <(sort --version-sort -) <(sort --version-sort "${CACHE}") |
        tee -a "${CACHE}" |
        wc -l |
        tr -d ' ')
    local total=$(< "${CACHE}" wc -l | tr -d ' ')
    echo "Success: $result issues added to cache (${total} total)"
}

function search_issues() {
    local issue=$(< "${CACHE}" fzf --tac | cut -d ' ' -f 1 | cat)
    [[ -n "$issue" ]] && open_issue "$issue"
}

function open_issue() {
    echo "Opening issue ${1}"
    open "${JIRA_DOMAIN}/browse/${1}"
}

function parse_ticket_key() {
    local key=$(git describe --contains --all | grep -e '[A-Z]\+-[0-9]\+' -o)
    if [[ -n "$key" ]]; then
        open_issue "$key"
    else
        echo "Could not parse ticket key"
    fi
}

jira "$1" "$2"

