#!/usr/bin/env bash
# Run one Azure Resource Graph query with paging and write all rows as a JSON array.
# Usage: run-azure-rule.sh <query.kql> <out.json> [subscriptions-csv] [management-groups-csv]
# Read-only: only calls `az graph query`.
set -euo pipefail

QUERY_FILE="${1:?usage: $0 <query.kql> <out.json> [subscriptions] [management-groups]}"
OUT_FILE="${2:?usage: $0 <query.kql> <out.json> [subscriptions] [management-groups]}"
SUBSCRIPTIONS="${3:-}"
MANAGEMENT_GROUPS="${4:-}"
MAX_PAGES="${CCG_AZ_MAX_PAGES:-100}"
PAGE_SIZE=1000

# Strip full-line // comments (the rule header) so only the query text is sent.
query="$(grep -v '^[[:space:]]*//' "$QUERY_FILE")"

scope=()
if [[ -n "$SUBSCRIPTIONS" ]]; then
  IFS=',' read -r -a subs <<<"$SUBSCRIPTIONS"
  scope+=(--subscriptions "${subs[@]}")
fi
if [[ -n "$MANAGEMENT_GROUPS" ]]; then
  IFS=',' read -r -a mgs <<<"$MANAGEMENT_GROUPS"
  scope+=(--management-groups "${mgs[@]}")
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '[]' >"$tmp/rows.json"
token=""
pages=0
while true; do
  args=(graph query -q "$query" --first "$PAGE_SIZE" --output json)
  if [[ -n "$token" ]]; then
    args+=(--skip-token "$token")
  fi
  az "${args[@]}" "${scope[@]}" >"$tmp/page.json"
  jq --slurpfile page "$tmp/page.json" '. + ($page[0].data // [])' "$tmp/rows.json" >"$tmp/next.json"
  mv "$tmp/next.json" "$tmp/rows.json"
  pages=$((pages + 1))
  token="$(jq -r '.skip_token // empty' "$tmp/page.json")"
  if [[ -z "$token" ]]; then
    break
  fi
  if ((pages >= MAX_PAGES)); then
    printf 'page limit (%s) reached; results truncated\n' "$MAX_PAGES" >&2
    break
  fi
done

cp "$tmp/rows.json" "$OUT_FILE"
