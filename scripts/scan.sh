#!/usr/bin/env bash
# cloud-cost-guardian scanner
#
# Runs every rule in rules/catalogue.json against Azure (Resource Graph) and/or AWS (CLI),
# normalises the results into one JSON schema and renders Markdown + HTML savings reports.
#
# READ-ONLY: the scanner only calls list/describe/query APIs. It never modifies or deletes anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/scan.sh [options]

Options:
  --provider LIST            all | azure | aws | azure,aws        (default: all)
                             "all" skips a cloud whose CLI is missing or not logged in;
                             naming a provider explicitly makes that a hard error.
  --out DIR                  output directory                       (default: ./out)
  --aws-regions LIST         comma-separated AWS regions            (default: all enabled regions)
  --azure-subscriptions LIST comma-separated subscription IDs       (default: all visible to the identity)
  --azure-management-groups LIST  comma-separated management group IDs
  --rules LIST               only run these rule IDs (comma-separated)
  --generated-at TIMESTAMP   report timestamp (default: now, UTC)
  --now-epoch SECONDS        reference time for age calculations (default: now; used by tests)
  --run-url URL              link to the CI run, embedded in the issue body
  --no-render                write findings.json only
  -h, --help                 show this help

Outputs (in --out):
  findings.json   normalised findings + summary (schema/finding.schema.json)
  report.md       Markdown savings report
  report.html     self-contained HTML savings report
  issue.md        short summary used for the weekly GitHub issue
  raw/            raw rule output, useful for audits and debugging
EOF
}

PROVIDERS="all"
OUT_DIR="out"
AWS_REGIONS="${CCG_AWS_REGIONS:-}"
AZ_SUBSCRIPTIONS="${CCG_AZURE_SUBSCRIPTIONS:-}"
AZ_MANAGEMENT_GROUPS="${CCG_AZURE_MANAGEMENT_GROUPS:-}"
RULES=""
GENERATED_AT=""
NOW_EPOCH=""
RUN_URL=""
RENDER=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDERS="${2:?--provider needs a value}"; shift 2 ;;
    --out) OUT_DIR="${2:?--out needs a value}"; shift 2 ;;
    --aws-regions) AWS_REGIONS="${2:?--aws-regions needs a value}"; shift 2 ;;
    --azure-subscriptions) AZ_SUBSCRIPTIONS="${2:?--azure-subscriptions needs a value}"; shift 2 ;;
    --azure-management-groups) AZ_MANAGEMENT_GROUPS="${2:?--azure-management-groups needs a value}"; shift 2 ;;
    --rules) RULES="${2:?--rules needs a value}"; shift 2 ;;
    --generated-at) GENERATED_AT="${2:?--generated-at needs a value}"; shift 2 ;;
    --now-epoch) NOW_EPOCH="${2:?--now-epoch needs a value}"; shift 2 ;;
    --run-url) RUN_URL="${2:?--run-url needs a value}"; shift 2 ;;
    --no-render) RENDER=false; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_cmd jq

CATALOGUE="$ROOT/rules/catalogue.json"
PRICES="$ROOT/pricing/price-sheet.json"
GENERATED_AT="${GENERATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
CCG_NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
export CCG_NOW_EPOCH

explicit=true
if [[ "$PROVIDERS" == "all" ]]; then
  PROVIDERS="azure,aws"
  explicit=false
fi
want_azure=false
want_aws=false
IFS=',' read -r -a requested <<<"$PROVIDERS"
for p in "${requested[@]}"; do
  case "$p" in
    azure) want_azure=true ;;
    aws) want_aws=true ;;
    *) die "unknown provider: $p (expected azure, aws or all)" ;;
  esac
done

mkdir -p "$OUT_DIR/raw" "$OUT_DIR/parts"
rm -f "$OUT_DIR"/raw/*.json "$OUT_DIR"/raw/*.err "$OUT_DIR"/parts/*.json
ERRORS_FILE="$OUT_DIR/raw/errors.jsonl"
: >"$ERRORS_FILE"

scanned=()
executions=0
aws_account=""
aws_region_list=()

rule_selected() {
  [[ -z "$RULES" ]] || csv_contains "$RULES" "$1"
}

record_error() { # rule_id region stderr_file
  local msg
  msg="$(tr -d '\r' <"$3" | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' ' ' | cut -c1-300 || true)"
  [[ -n "$msg" ]] || msg="rule exited with an error and no message"
  warn "rule $1 ${2:+($2) }failed: $msg"
  jq -nc --arg rule_id "$1" --arg region "$2" --arg message "$msg" \
    '{rule_id: $rule_id, region: $region, message: $message}' >>"$ERRORS_FILE"
}

normalise() { # rule_id region account raw_file part_file err_file
  if ! jq --arg rule_id "$1" --arg region "$2" --arg account "$3" \
    --slurpfile catalogue "$CATALOGUE" --slurpfile prices "$PRICES" \
    -f "$ROOT/lib/normalise.jq" "$4" >"$5" 2>"$6"; then
    rm -f "$5"
    record_error "$1" "$2" "$6"
  fi
}

rules_for() { # provider -> lines of "id<TAB>source"
  jq -r --arg p "$1" '.rules[] | select(.provider == $p) | [.id, .source] | @tsv' "$CATALOGUE"
}

# ---------------------------------------------------------------- Azure
if $want_azure; then
  if ! command -v az >/dev/null 2>&1 || ! az account show --output none 2>/dev/null; then
    if $explicit; then die "Azure requested but 'az' is missing or not logged in (run: az login)"; fi
    warn "skipping Azure: 'az' is missing or not logged in"
    want_azure=false
  fi
fi
if $want_azure; then
  scanned+=(azure)
  mapfile -t az_rules < <(rules_for azure)
  for line in "${az_rules[@]}"; do
    IFS=$'\t' read -r id source <<<"$line"
    rule_selected "$id" || continue
    executions=$((executions + 1))
    log "azure  $id"
    raw="$OUT_DIR/raw/$id.json"
    err="$OUT_DIR/raw/$id.err"
    export CCG_RULE_ID="$id"
    if bash "$ROOT/lib/run-azure-rule.sh" "$ROOT/$source" "$raw" "$AZ_SUBSCRIPTIONS" "$AZ_MANAGEMENT_GROUPS" \
      </dev/null 2>"$err"; then
      normalise "$id" "" "" "$raw" "$OUT_DIR/parts/$id.json" "$err"
    else
      record_error "$id" "" "$err"
    fi
  done
fi

# ---------------------------------------------------------------- AWS
if $want_aws; then
  identity=""
  if command -v aws >/dev/null 2>&1; then
    identity="$(aws sts get-caller-identity --output json 2>/dev/null </dev/null || true)"
  fi
  if [[ -z "$identity" ]]; then
    if $explicit; then die "AWS requested but 'aws' is missing or has no credentials"; fi
    warn "skipping AWS: 'aws' is missing or has no credentials"
    want_aws=false
  else
    aws_account="$(jq -r '.Account' <<<"$identity")"
  fi
fi
if $want_aws; then
  scanned+=(aws)
  if [[ -z "$AWS_REGIONS" ]]; then
    AWS_REGIONS="$(aws ec2 describe-regions \
      --region "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}" \
      --filters Name=opt-in-status,Values=opt-in-not-required,opted-in \
      --output json </dev/null | jq -r '[.Regions[].RegionName] | sort | join(",")')"
  fi
  IFS=',' read -r -a aws_region_list <<<"$AWS_REGIONS"
  mapfile -t aws_rules < <(rules_for aws)
  for region in "${aws_region_list[@]}"; do
    for line in "${aws_rules[@]}"; do
      IFS=$'\t' read -r id source <<<"$line"
      rule_selected "$id" || continue
      executions=$((executions + 1))
      log "aws    $id  $region"
      raw="$OUT_DIR/raw/$id.$region.json"
      err="$OUT_DIR/raw/$id.$region.err"
      export CCG_RULE_ID="$id"
      if bash "$ROOT/$source" "$region" >"$raw" 2>"$err" </dev/null; then
        normalise "$id" "$region" "$aws_account" "$raw" "$OUT_DIR/parts/$id.$region.json" "$err"
      else
        record_error "$id" "$region" "$err"
      fi
    done
  done
fi

if [[ ${#scanned[@]} -eq 0 ]]; then
  warn "no cloud provider was available; the report will be empty"
fi

# ---------------------------------------------------------------- assemble
shopt -s nullglob
parts=("$OUT_DIR"/parts/*.json)
shopt -u nullglob
if [[ ${#parts[@]} -gt 0 ]]; then
  jq -s 'add // []' "${parts[@]}" >"$OUT_DIR/raw/all-findings.json"
else
  printf '[]' >"$OUT_DIR/raw/all-findings.json"
fi
jq -s '.' "$ERRORS_FILE" >"$OUT_DIR/raw/errors.json"

providers_csv="$(IFS=','; printf '%s' "${scanned[*]}")"
regions_csv=""
if [[ ${#aws_region_list[@]} -gt 0 ]]; then
  regions_csv="$(IFS=','; printf '%s' "${aws_region_list[*]}")"
fi

jq -n \
  --arg generated_at "$GENERATED_AT" \
  --arg version "$CCG_VERSION" \
  --arg providers "$providers_csv" \
  --arg aws_regions "$regions_csv" \
  --arg aws_account "$aws_account" \
  --arg executions "$executions" \
  --slurpfile findings "$OUT_DIR/raw/all-findings.json" \
  --slurpfile errors "$OUT_DIR/raw/errors.json" \
  --slurpfile prices "$PRICES" \
  -f "$ROOT/lib/assemble.jq" >"$OUT_DIR/findings.json"

log "findings: $(jq '.summary.findings_total' "$OUT_DIR/findings.json"), estimated monthly saving: \$$(jq '.summary.estimated_monthly_saving' "$OUT_DIR/findings.json")"

if $RENDER; then
  bash "$ROOT/scripts/render-report.sh" "$OUT_DIR/findings.json" "$OUT_DIR" "$RUN_URL"
fi
