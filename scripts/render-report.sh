#!/usr/bin/env bash
# Render findings.json into report.md, report.html and issue.md.
# Usage: scripts/render-report.sh <findings.json> <out-dir> [run-url]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

FINDINGS="${1:?usage: $0 <findings.json> <out-dir> [run-url]}"
OUT_DIR="${2:?usage: $0 <findings.json> <out-dir> [run-url]}"
RUN_URL="${3:-}"
ISSUE_TOP="${CCG_ISSUE_TOP:-15}"

require_cmd jq
mkdir -p "$OUT_DIR"

jq -r -L "$ROOT/lib" -f "$ROOT/lib/render-markdown.jq" "$FINDINGS" >"$OUT_DIR/report.md"
jq -r -L "$ROOT/lib" -f "$ROOT/lib/render-html.jq" "$FINDINGS" >"$OUT_DIR/report.html"
jq -r -L "$ROOT/lib" --arg run_url "$RUN_URL" --arg top "$ISSUE_TOP" \
  -f "$ROOT/lib/render-issue.jq" "$FINDINGS" >"$OUT_DIR/issue.md"

log "wrote $OUT_DIR/report.md, $OUT_DIR/report.html, $OUT_DIR/issue.md"
