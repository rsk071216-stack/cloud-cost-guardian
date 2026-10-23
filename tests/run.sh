#!/usr/bin/env bash
# Deterministic test suite for cloud-cost-guardian. Needs only bash + jq; no cloud credentials.
#
# The az/aws CLIs are replaced by test doubles in tests/mocks/bin that serve recorded API responses
# from tests/fixtures and refuse any non read-only call. The full pipeline (query scripts -> normaliser
# -> assembler -> renderers) runs end-to-end and is compared with the golden files in tests/expected.
#
# Usage: tests/run.sh            run all tests
#        tests/run.sh --update   regenerate golden files (review the git diff before committing!)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE=false
if [[ "${1:-}" == "--update" ]]; then
  UPDATE=true
fi

PASS=0
FAIL=0
pass() {
  PASS=$((PASS + 1))
  printf 'ok    %s\n' "$1"
}
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %s\n' "$1"
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$2" | sed 's/^/      /'
  fi
}
check() { # description, command...
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PATH="$ROOT/tests/mocks/bin:$PATH"
FIXED_TS="2026-10-19T06:00:00Z"
FIXED_EPOCH="1792389600" # 2026-10-19T06:00:00Z
RUN_URL="https://github.com/rsk071216-stack/cloud-cost-guardian/actions/runs/0"
CATALOGUE="$ROOT/rules/catalogue.json"

golden() { # name, expected file, actual file
  if $UPDATE; then
    mkdir -p "$(dirname "$2")"
    cp "$3" "$2"
    pass "$1 (golden file updated)"
  elif diff -u "$2" "$3" >"$TMP/diff.txt" 2>&1; then
    pass "$1"
  else
    fail "$1" "$(head -n 60 "$TMP/diff.txt")"
  fi
}

scan() { # out-dir, extra args...
  local out="$1"
  shift
  bash "$ROOT/scripts/scan.sh" --out "$out" --aws-regions us-east-1 \
    --generated-at "$FIXED_TS" --now-epoch "$FIXED_EPOCH" --run-url "$RUN_URL" "$@"
}

echo "== catalogue and rule documentation"

check "catalogue: rule ids are unique" \
  jq -e '[.rules[].id] | length == (unique | length)' "$CATALOGUE"

check "catalogue: every rule has the required fields and valid enums" \
  jq -e 'all(.rules[];
    (.id | test("^(az|aws)-[a-z0-9-]+$"))
    and (.provider == "azure" or .provider == "aws")
    and ((.provider == "azure") == (.id | startswith("az-")))
    and (.severity | IN("high", "medium", "low"))
    and (.risk | IN("high", "medium", "low"))
    and (.category | IN("waste", "rightsizing", "governance", "hygiene"))
    and ([.title, .source, .finds, .typical_saving, .savings_formula, .remediation] | all(type == "string" and length > 0)))' \
  "$CATALOGUE"

missing=""
while IFS=$'\t' read -r id source; do
  if [[ ! -f "$ROOT/$source" ]]; then
    missing+="$id -> $source (missing file)"$'\n'
    continue
  fi
  for field in "rule_id: $id" "What it finds:" "Why it costs money:" "Typical saving:" "Remediation:" "Risk:"; do
    grep -qF "$field" "$ROOT/$source" || missing+="$source: header field '$field' missing"$'\n'
  done
done < <(jq -r '.rules[] | [.id, .source] | @tsv' "$CATALOGUE")
if [[ -z "$missing" ]]; then pass "queries: every rule has a query with a documented header"; else fail "queries: every rule has a query with a documented header" "$missing"; fi

orphans=""
for f in "$ROOT"/queries/azure/*.kql "$ROOT"/queries/aws/*.sh; do
  rel="${f#"$ROOT"/}"
  jq -e --arg s "$rel" 'any(.rules[]; .source == $s)' "$CATALOGUE" >/dev/null || orphans+="$rel"$'\n'
done
if [[ -z "$orphans" ]]; then pass "queries: every query file is registered in the catalogue"; else fail "queries: every query file is registered in the catalogue" "$orphans"; fi

echo "== formatting helpers"

money_out="$(jq -c -n -L "$ROOT/lib" 'include "format"; [0, 3.65, 1234.5, 1234567.891, 0.004] | map(money)')"
check "format: money() renders dollars with separators and 2 decimals" \
  test "$money_out" == '["$0.00","$3.65","$1,234.50","$1,234,567.89","$0.00"]'

md_out="$(jq -r -n -L "$ROOT/lib" 'include "format"; "a|b" | md')"
check "format: md() escapes table pipes" test "$md_out" == 'a\|b'

echo "== end-to-end scan against fixtures (mocked az/aws)"

export CCG_MOCK_LOG="$TMP/calls.log"
: >"$CCG_MOCK_LOG"
OUT="$TMP/full"
if scan "$OUT" --provider all >"$TMP/scan.log" 2>&1; then
  pass "scan: exits 0"
else
  fail "scan: exits 0" "$(tail -n 30 "$TMP/scan.log")"
fi

check "scan: no rule failed" jq -e '.rules_failed == []' "$OUT/findings.json"
check "scan: both clouds scanned" jq -e '.providers == ["azure", "aws"]' "$OUT/findings.json"
check "scan: every catalogue rule executed once" \
  jq -e --slurpfile c "$CATALOGUE" '.rule_executions == ($c[0].rules | length)' "$OUT/findings.json"
check "scan: Resource Graph paging followed the skip token" \
  jq -e '[.findings[] | select(.rule_id == "az-untagged-resource")] | length == 3' "$OUT/findings.json"

check "schema: every finding has the required fields and types" \
  jq -e 'all(.findings[];
    (.provider | IN("azure", "aws"))
    and (.rule_id | type == "string" and length > 0)
    and (.resource_id | type == "string" and length > 0)
    and (.region | type == "string")
    and (.monthly_cost_estimate | type == "number" and . >= 0)
    and (.recommendation | type == "string" and length > 0)
    and (.risk | IN("low", "medium", "high"))
    and .currency == "USD")' "$OUT/findings.json"

check "schema: findings use only the fields declared in schema/finding.schema.json" \
  jq -e --slurpfile s "$ROOT/schema/finding.schema.json" 'all(.findings[];
    ((keys - ($s[0].properties | keys)) == []) and (($s[0].required - keys) == []))' "$OUT/findings.json"

check "report: findings are sorted by estimated monthly saving (descending)" \
  jq -e '[.findings[].monthly_cost_estimate] as $c | $c == ($c | sort | reverse)' "$OUT/findings.json"

check "report: summary total equals de-duplicated sum of findings" \
  jq -e '(.summary.estimated_monthly_saving) as $t
    | ([.findings[] | select(.monthly_cost_estimate > 0)] | group_by(.resource_id) | map(max_by(.monthly_cost_estimate).monthly_cost_estimate) | add) as $sum
    | (($t - $sum) | fabs) < 0.01' "$OUT/findings.json"

check "filters: snapshots younger than 90 days, deleted NAT gateways and targets-in-use LBs are excluded" \
  jq -e '[.findings[].resource_id] | (index("snap-0e00000000000a003") == null)
    and (index("nat-0c00000000000a002") == null) and (index("nat-0c00000000000a003") == null)
    and (map(select(test("alb-web-prod|clb-intranet"))) | length == 0)' "$OUT/findings.json"

check "filters: instances stopped for less than 7 days are excluded" \
  jq -e '[.findings[] | select(.rule_id == "aws-stopped-ec2-volumes") | .resource_id] | sort == ["i-0aaa00000000000002", "i-0aaa00000000000005"]' \
  "$OUT/findings.json"

bad_calls="$(grep -vE '^(az (account show|graph query)|aws [a-z0-9]+ (describe|get|list)-[a-z-]+)$' "$CCG_MOCK_LOG" || true)"
if [[ -z "$bad_calls" ]]; then pass "safety: scanner made only read-only CLI calls ($(wc -l <"$CCG_MOCK_LOG" | tr -d ' ') calls)"; else fail "safety: scanner made only read-only CLI calls" "$bad_calls"; fi
unset CCG_MOCK_LOG

golden "golden: findings.json" "$ROOT/tests/expected/findings.json" "$OUT/findings.json"
golden "golden: report.md" "$ROOT/tests/expected/report.md" "$OUT/report.md"
golden "golden: report.html" "$ROOT/tests/expected/report.html" "$OUT/report.html"
golden "golden: issue.md" "$ROOT/tests/expected/issue.md" "$OUT/issue.md"
golden "docs: committed sample report is current" "$ROOT/docs/sample-report.md" "$OUT/report.md"
golden "docs: committed sample HTML report is current" "$ROOT/docs/sample-report.html" "$OUT/report.html"

echo "== resilience and provider selection"

OUT2="$TMP/denied"
if CCG_MOCK_AWS_FAIL="ec2:describe-addresses" scan "$OUT2" --provider all >"$TMP/denied.log" 2>&1; then
  pass "resilience: an AccessDenied rule does not abort the scan"
else
  fail "resilience: an AccessDenied rule does not abort the scan" "$(tail -n 20 "$TMP/denied.log")"
fi
check "resilience: the failed rule is reported with its region" \
  jq -e '.rules_failed | length == 1 and .[0].rule_id == "aws-unused-eip" and .[0].region == "us-east-1" and (.[0].message | test("UnauthorizedOperation"))' \
  "$OUT2/findings.json"
check "resilience: the report lists rules that could not run" grep -q "## Rules that could not run" "$OUT2/report.md"

OUT3="$TMP/no-azure"
if CCG_MOCK_AZ_LOGGED_OUT=1 scan "$OUT3" --provider all >"$TMP/no-azure.log" 2>&1; then
  pass "providers: 'all' skips a cloud that is not logged in"
else
  fail "providers: 'all' skips a cloud that is not logged in" "$(tail -n 20 "$TMP/no-azure.log")"
fi
check "providers: only AWS appears when Azure is skipped" jq -e '.providers == ["aws"]' "$OUT3/findings.json"

if CCG_MOCK_AZ_LOGGED_OUT=1 scan "$TMP/explicit" --provider azure >"$TMP/explicit.log" 2>&1; then
  fail "providers: an explicitly requested cloud that is not logged in is a hard error"
else
  pass "providers: an explicitly requested cloud that is not logged in is a hard error"
fi

OUT4="$TMP/one-rule"
scan "$OUT4" --provider aws --rules aws-unused-eip >"$TMP/one-rule.log" 2>&1 || true
check "filters: --rules runs only the selected rule" \
  jq -e '.rule_executions == 1 and ([.findings[].rule_id] | unique == ["aws-unused-eip"])' "$OUT4/findings.json"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
