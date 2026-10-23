#!/usr/bin/env bash
# Create or update the single "Weekly cloud savings report" issue with the rendered issue body.
# Usage: scripts/publish-issue.sh <issue.md>
# Needs: gh CLI, GH_TOKEN with issues:write on THIS repository only, GITHUB_REPOSITORY.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

BODY_FILE="${1:?usage: $0 <issue.md>}"
TITLE="${CCG_ISSUE_TITLE:-Weekly cloud savings report}"
LABEL="${CCG_ISSUE_LABEL:-cost-report}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

require_cmd gh
require_cmd jq

# Best effort: the label makes the issue easy to filter; failing to create it is not fatal.
gh label create "$LABEL" --repo "$REPO" --color 0E8A16 \
  --description "Automated cloud cost findings" --force >/dev/null 2>&1 || true

number="$(gh issue list --repo "$REPO" --state open --limit 100 --json number,title |
  jq -r --arg t "$TITLE" '[.[] | select(.title == $t)] | sort_by(.number) | first | .number // empty')"

if [[ -n "$number" ]]; then
  gh issue edit "$number" --repo "$REPO" --body-file "$BODY_FILE" >/dev/null
  log "updated issue #$number"
else
  gh issue create --repo "$REPO" --title "$TITLE" --body-file "$BODY_FILE" --label "$LABEL" >/dev/null ||
    gh issue create --repo "$REPO" --title "$TITLE" --body-file "$BODY_FILE" >/dev/null
  log "created issue '$TITLE'"
fi
