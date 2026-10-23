# shellcheck shell=bash
# Shared helpers for cloud-cost-guardian scripts. Source this file; do not execute it.

# shellcheck disable=SC2034  # read by scripts that source this file
CCG_VERSION="1.0.0"

log() { printf '[ccg] %s\n' "$*" >&2; }
warn() { printf '[ccg] WARN: %s\n' "$*" >&2; }
die() {
  printf '[ccg] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# csv_contains "a,b,c" "b" -> success when the item is in the comma-separated list
csv_contains() {
  [[ ",$1," == *",$2,"* ]]
}
