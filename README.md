# fuzzy-jira
Fuzzy search a Jira project to quickly identify issues and open them in a web browser. Powered by [fzf](https://github.com/junegunn/fzf).

![fuzzy-jira](https://user-images.githubusercontent.com/7334346/114291642-b3246200-9abb-11eb-81c9-273e6d6b5b99.gif "Data source: jira.atlassian.com")

## Usage
```
jira fetch <project>      # Fetch the last 1000 issues within <project> and cache the result
jira <project> [-f] [-m]  # Fuzzy search cached issues within <project> [-f with fetch] [-m assigned only]
jira <issue-key>          # Open the issue <issue-key> in a web browser
jira .                    # Parse the current git branch for an issue key and open it in a browser

# Examples
jira fetch proj
jira proj
jira proj -f
jira proj -m
jira proj-123
```

## Setup
Clone the repo and add `/fuzzy-jira/jira.sh` to your PATH
```
# Example
cd ~ && git clone https://github.com/DamonBaker/fuzzy-jira.git
ln -s ~/fuzzy-jira/jira.sh /usr/local/bin/jira
```
Edit your `/fuzzy-jira/.jiraconfig`
```
# Example
JIRA_URL=https://<domain>.atlassian.net
JIRA_USERNAME=<jira-username>
JIRA_PASSWORD=<password/api-token>
```

## Dependencies
- cURL: `brew install curl` / `apt-get install curl`
- fzf: `brew install fzf` / `apt-get install fzf`
- jq: `brew install jq` / `apt-get install jq`

