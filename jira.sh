#!/bin/bash

# Setup
# -----------------------------------------------------------------------
script_absolute_path() {
    # https://stackoverflow.com/a/246128
    local src="${BASH_SOURCE[0]}"
    while [ -h "$src" ]; do
        dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"
        [[ $src != /* ]] && src="$dir/$src"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
}

set -e

script_absolute_path
# -----------------------------------------------------------------------

jira() {
    if [[ -z "$1" ]]; then
        usage
        return 0
    fi
    read_config
    if [[ $1 == 'fetch' ]]; then
        if [[ -n "$2" ]]; then
            set_project "$2"
        else
            echo 'Please specify a project to fetch from'
            return 1
        fi
        fetch_issues "$PROJECT"
    elif [[ $1 == '.' ]]; then
        parse_git_branch
    elif [[ -n $(echo "$1" | grep -e '[A-Za-z]\+-[0-9]\+' -o) ]]; then
        open_issue "$(tr a-z A-Z <<< "$1")"
    else
        set_project "$1"
        [[ "${@: -1}" == '-f' ]] && fetch_issues "$PROJECT"
        search_issues "$PROJECT"
    fi
}

set_project() {
    PROJECT=$(tr a-z A-Z <<< "$1")
    local cache_dir="${SCRIPT_DIR}/.cache"
    [[ ! -d "${cache_dir}" ]] && mkdir "${cache_dir}"
    CACHE="${cache_dir}/${PROJECT}"
}

fetch_issues() {
    local url="${JIRA_URL}/rest/api/2/search?jql=project=${PROJECT}&fields=summary&maxResults=1000"
    echo "Fetching issues for $PROJECT..."
    echo "From ${url}"
    [[ ! -f "${PROJECT}" ]] && touch "${CACHE}"
    local curl_args=(
        --silent
        --show-error
        --fail
        --user "${JIRA_USERNAME}:${JIRA_PASSWORD}"
        --header 'Content-type: application/json'
        --request GET "${url}"
    )
    local response=$(curl "${curl_args[@]}")
    if [[ -z "$response" ]]; then
        # Remove empty cache on error
        [[ -z $(cat "${CACHE}") ]] && rm "${CACHE}"
        return 1
    fi
    local result=$(echo "${response}" \
        | jq -r '.issues[] | .key + " " + .fields.summary' \
        | sort --version-sort --field-separator=$'\t' --unique --key=1,1 "${CACHE}" - \
        | tee -a "${CACHE}" \
        | wc -l \
        | tr -d ' ')
    local total=$(< "${CACHE}" wc -l | tr -d ' ')
    echo "Success: $result issues added to cache (${total} total)"
}

search_issues() {
    [[ ! -f "${CACHE}" ]] && fetch_issues "${PROJECT}"
    # Apply bold style to ticket key
    local colorPrefix='\\033[1m'
    local colorSuffix='\\033[0m'
    local regex=$'s/([^ ]+)/'$colorPrefix'\1'$colorSuffix'/'
    local issue=$(echo -e "$(sed -E "${regex}" "${CACHE}")" | fzf --ansi --tac | cut -d ' ' -f 1 | cat)
    [[ -n "${issue}" ]] && open_issue "${issue}"
}

open_issue() {
    echo "Opening issue ${1}"
    case "$(uname)" in
        (*Linux*) open_cmd='xdg-open' ;;
        (*Darwin*) open_cmd='open' ;;
        (*CYGWIN*) open_cmd='cygstart' ;;
        (*) echo 'Error: Unsupported platform'; return 1
    esac
    ${open_cmd} "${JIRA_URL}/browse/${1}"
}

parse_git_branch() {
    local key=$(git describe --contains --all | grep -e '[A-Z]\+-[0-9]\+' -o)
    if [[ -n "$key" ]]; then
        open_issue "$key"
    else
        echo "Could not parse ticket key"
    fi
}

read_config() {
    local config_dir="${SCRIPT_DIR}/.jiraconfig"
    if [[ ! -f "$config_dir" ]]; then
        printf '%s\n' \
            'JIRA_URL=' \
            'JIRA_USERNAME=' \
            'JIRA_PASSWORD=' > "$config_dir"
    fi
    JIRA_URL=$(awk -F= '/^JIRA_URL/{print $2}' ${config_dir})
    JIRA_USERNAME=$(awk -F= '/^JIRA_USERNAME/{print $2}' ${config_dir})
    JIRA_PASSWORD=$(awk -F= '/^JIRA_PASSWORD/{print $2}' ${config_dir})
    if [[ -z "$JIRA_URL" || -z "$JIRA_USERNAME" || -z "$JIRA_PASSWORD" ]]; then
        [[ -z "$JIRA_URL" ]] && echo "JIRA_URL has not been set in ${config_dir}"
        [[ -z "$JIRA_USERNAME" ]] && echo "JIRA_USERNAME has not been set in ${config_dir}"
        [[ -z "$JIRA_PASSWORD" ]] && echo "JIRA_USERNAME has not been set in ${config_dir}"
        return 1
    fi
    return 0
}

usage() {
    echo "Usage:"
    echo "  jira fetch <project-key>"
    echo "  jira <project-key> [-f]"
    echo "  jira <issue-key>"
    echo "  jira ."
    echo "Examples:"
    echo "  jira fetch proj      Fetch issues for project 'proj'"
    echo "  jira proj            Search fetched issues within 'proj'"
    echo "  jira proj -f         Fetch issues before performing a search within 'proj'"
    echo "  jira proj-123        Open issue 'proj-123' in browser"
    echo "  jira .               Parse current git branch for an issue key and open in browser"
    echo
    read_config
}

jira "$@"

