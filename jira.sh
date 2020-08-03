#!/bin/bash
set -e

. ~/fuzzy-jira/.jiraconfig

jira() {
    if [[ -z "$1" ]]; then
        usage
        exit 0
    fi
    if [[ $1 == 'fetch' ]]; then
        if [[ -n "$2" ]]; then
            set_project $2
        else
            echo 'Please specify a project to fetch from'
            exit 1
        fi
        fetch_issues "$PROJECT"
    elif [[ $1 == '.' ]]; then
        parse_git_branch
    elif [[ -n $(echo "$1" | grep -e '[A-Za-z]\+-[0-9]\+' -o) ]]; then
        open_issue $(tr a-z A-Z <<< "$1")
    else
        set_project $1
        search_issues "$PROJECT"
    fi
}

set_project() {
    PROJECT=$(tr a-z A-Z <<< "$1")
    CACHE="${JIRA_CACHE_DIR}/${PROJECT}"
}

fetch_issues() {
    local url="${JIRA_DOMAIN}/rest/api/2/search?jql=project=${PROJECT}&fields=summary&maxResults=1000"
    echo "Fetching issues for $PROJECT..."
    echo "From ${url}"
    [[ ! -f "$PROJECT" ]] && touch "${CACHE}"
    local curl_args=(
        --silent
        --show-error
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
    [[ ! -f "${CACHE}" ]] && fetch_issues "$PROJECT"
    local issue=$(< "${CACHE}" fzf --tac | cut -d ' ' -f 1 | cat)
    [[ -n "$issue" ]] && open_issue "$issue"
}

open_issue() {
    echo "Opening issue ${1}"
    case "$(uname)" in
        (*Linux*) open_cmd='xdg-open' ;;
        (*Darwin*) open_cmd='open' ;;
        (*CYGWIN*) open_cmd='cygstart' ;;
        (*) echo 'Error: Unsupported platform'; exit 1
    esac
    ${open_cmd} "${JIRA_DOMAIN}/browse/${1}"
}

parse_git_branch() {
    local key=$(git describe --contains --all | grep -e '[A-Z]\+-[0-9]\+' -o)
    if [[ -n "$key" ]]; then
        open_issue "$key"
    else
        echo "Could not parse ticket key"
    fi
}

usage() {
    echo "Your jira details must be entered in .jiraconfig before using this tool"
    echo "Usage:"
    echo "  ./jira.sh fetch <project-key>"
    echo "  ./jira.sh <project-key>"
    echo "  ./jira.sh <issue-key>"
    echo "  ./jira.sh ."
    echo "Examples:"
    echo "  ./jira.sh fetch PROJ      Fetch issues for project 'PROJ'"
    echo "  ./jira.sh PROJ            Search fetched issues within 'PROJ'"
    echo "  ./jira.sh PROJ-123        Open issue 'PROJ-123' in browser"
    echo "  ./jira.sh .               Parse current git branch for an issue key and open in browser"
}

jira "$@"

