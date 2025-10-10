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

# Main entry point for the jira command
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
        if [[ $3 == '-a' || $3 == '--all' ]]; then
            local paging_start="0"
        fi
        fetch_issues "$paging_start"
    elif [[ $1 == '.' ]]; then
        parse_git_branch
    elif echo "$1" | grep -q -e '[A-Za-z]\+-[0-9]\+'; then
        open_issue "$(tr '[:lower:]' '[:upper:]' <<< "$1")"
    else
        local flag_fetch='false'
        local flag_assignee

        for arg in "$@"
        do
            if [[ $arg == '-f' || $arg == '--force' ]]; then
                flag_fetch='true'
            elif [[ $arg == '-m' || $arg == '--me' ]]; then
                flag_assignee="${JIRA_USERNAME}"
            fi
        done

        set_project "$1"
        [[ "${flag_fetch}" == 'true' ]] && fetch_issues
        search_issues "$flag_assignee"
    fi
}

# Set the project key and cache location
set_project() {
    PROJECT=$(tr '[:lower:]' '[:upper:]' <<< "$1")
    local cache_dir="${SCRIPT_DIR}/.cache"
    [[ ! -d "${cache_dir}" ]] && mkdir "${cache_dir}"
    CACHE="${cache_dir}/${PROJECT}"
}

# Fetch issues from JIRA API and cache them
# Arguments:
#   $1 - (optional) Starting position for pagination
fetch_issues() {
    local url="${JIRA_URL}/rest/api/2/search?jql=project=${PROJECT}&fields=summary,status,assignee&maxResults=1000"
    if [[ -n "$1" ]]; then
        # If start_at arg is present requests will be paginated
        local paging_start="$1"
        if [[ "$paging_start" == "0" ]]; then
            echo "Fetching ALL issues for $PROJECT. This may take some time depending on the max result limit"
            echo
        fi
        url="${url}&startAt=${paging_start}"
    else
        # Otherwise only retrieve the latest issues
        echo "Fetching issues for $PROJECT..."
        echo "From ${url}"
    fi

    local curl_args=(
        --silent
        --show-error
        --fail
        --user "${JIRA_USERNAME}:${JIRA_PASSWORD}"
        --header 'Content-type: application/json'
        --header 'Accept: application/json'
        --request GET "${url}"
    )
    local response
    if ! response=$(curl "${curl_args[@]}" 2>&1); then
        echo "Error: Failed to fetch issues from JIRA"
        echo "${response}"
        return 1
    fi
    if [[ -z "$response" ]]; then
        echo "Error: No issues returned"
        return 1
    fi

    local jq_query='.issues[] | .key + "\t"
        + .fields.status.statusCategory.name + "\t"
        + (.fields.assignee.name // .fields.assignee.emailAddress // "Unassigned") + "\t"
        + .fields.summary'
    local issues
    if ! issues=$(echo "${response}" | jq --raw-output "${jq_query}" 2>&1); then
        echo "Error: Failed to parse JIRA response"
        echo "${issues}"
        return 1
    fi
    echo "${issues}" | save_cache

    if [[ -n "${paging_start}" && -n "${issues}" ]]; then
        read -r start_at max_results total <<< "$(echo "${response}" | jq --raw-output '.startAt, .maxResults, .total')"
        paging_start=$((start_at + max_results))
        if (( paging_start <= total )); then
            echo "$((total - start_at)) issues remaining"
            fetch_issues "${paging_start}"
        fi
    fi
}

# Search cached issues using fzf and open the selected one
# Arguments:
#   $1 - (optional) Filter by assignee username
search_issues() {
    [[ ! -f "${CACHE}" ]] && fetch_issues
    local issue
    issue=$(echo -e "$(read_cache "$1")" | fzf --ansi | cut -d ' ' -f 1 | cat)
    [[ -n "${issue}" ]] && open_issue "${issue}"
}

# Save issues to cache file, merging with existing data
save_cache() {
    [[ ! -f "${CACHE}" ]] && touch "${CACHE}"
    local wc_old
    wc_old=$(< "${CACHE}" wc -l | tr -d ' ')
    < /dev/stdin sort --output="${CACHE}" --version-sort --field-separator=$'\t' --key=1,1 --unique --reverse - "${CACHE}"
    local wc_new
    wc_new=$(< "${CACHE}" wc -l | tr -d ' ')
    echo "Success: $((wc_new - wc_old)) new issues added to cache (${wc_new} total)"
}

# Read and format cached issues with color coding
# Arguments:
#   $1 - (optional) Filter by assignee username
read_cache() {
    local assignee="$1"
    local light_grey='\\033[37m' # OPEN
    local blue='\\033[34m'       # IN PROGRESS
    local green='\\033[32m'      # DONE
    local reset='\\033[0m'
    local bold='\\033[1m'

    while IFS=$'\t' read -r -a row
    do
        local color
        case ${row[1]} in
            ("In Progress") color=$blue ;;
            ("Done") color=$green ;;
            (*) color=$light_grey ;;
        esac
        if [[ -z "$assignee" || "$assignee" == "${row[2]}" ]]; then
            echo -e "$bold$color${row[0]}$reset\t${row[3]}"
        fi
    done < "${CACHE}" | column -s$'\t' -t
}

# Open an issue in the default web browser
# Arguments:
#   $1 - Issue key (e.g., PROJ-123)
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

# Parse current git branch for a JIRA issue key and open it
parse_git_branch() {
    local key
    key=$(git describe --contains --all | grep -e '[A-Z]\+-[0-9]\+' -o)
    if [[ -n "$key" ]]; then
        open_issue "$key"
    else
        echo "Could not parse ticket key"
    fi
}

# Read and validate JIRA configuration from .jiraconfig file
read_config() {
    local config_dir="${SCRIPT_DIR}/.jiraconfig"
    if [[ ! -f "$config_dir" ]]; then
        printf '%s\n' \
            'JIRA_URL=' \
            'JIRA_USERNAME=' \
            'JIRA_PASSWORD=' > "$config_dir"
    fi
    JIRA_URL=$(awk -F= '/^JIRA_URL/{print $2}' "${config_dir}")
    JIRA_USERNAME=$(awk -F= '/^JIRA_USERNAME/{print $2}' "${config_dir}")
    JIRA_PASSWORD=$(awk -F= '/^JIRA_PASSWORD/{print $2}' "${config_dir}")
    if [[ -z "$JIRA_URL" || -z "$JIRA_USERNAME" || -z "$JIRA_PASSWORD" ]]; then
        [[ -z "$JIRA_URL" ]] && echo "JIRA_URL has not been set in ${config_dir}"
        [[ -z "$JIRA_USERNAME" ]] && echo "JIRA_USERNAME has not been set in ${config_dir}"
        [[ -z "$JIRA_PASSWORD" ]] && echo "JIRA_PASSWORD has not been set in ${config_dir}"
        return 1
    fi
    return 0
}

# Display usage information and examples
usage() {
    echo "Usage:"
    echo "  jira fetch <project-key> [-a|--all]"
    echo "  jira <project-key> [-m|--me]"
    echo "  jira <project-key> [-f|--force]"
    echo "  jira <issue-key>"
    echo "  jira ."
    echo
    echo "Examples:"
    echo "  jira fetch proj          Fetch issues for project 'proj'"
    echo "  jira fetch proj --all    Fetch ALL issues for project 'proj' (paginated)"
    echo "  jira proj                Search fetched issues within 'proj'"
    echo "  jira proj --me           Search fetched issues assigned to current user within 'proj'"
    echo "  jira proj --force        Fetch issues before performing a search within 'proj'"
    echo "  jira proj-123            Open issue 'proj-123' in browser"
    echo "  jira .                   Parse current git branch for an issue key and open in browser"
    echo
    echo "Status legend:"
    echo -e "  \\033[37mKEY-123\\033[0m OPEN"
    echo -e "  \\033[34mKEY-123\\033[0m IN PROGRESS"
    echo -e "  \\033[32mKEY-123\\033[0m DONE"
    echo
    read_config
}

jira "$@"

