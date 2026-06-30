#!/usr/bin/env bash
# classify_pr.sh — decide whether a PR takes the auto-merge FAST PATH ("simple")
# or must SOAK in a testing environment before a human merges it ("complex").
#
# Prints exactly one word on stdout:
#   disabled  → .testing.enabled is false → callers merge as they did before.
#   simple    → within the fast-path ceilings → callers keep the auto-merge path.
#   complex   → over a ceiling (or touches a non-allowed area) → callers soak it.
#
# The decision is pure (classify_pr_decision) so it's unit-testable without gh;
# the live path below pulls the PR's size + touched files from gh and applies it.
#
# Lib-only: `CLASSIFY_LIB_ONLY=1 source classify_pr.sh` loads the pure function
# and returns BEFORE the live flow (which needs gh / a config file).
set -euo pipefail

# classify_pr_decision <changed_lines> <changed_files> <max_loc> <max_files> \
#                      <areas_csv> <paths_newline_separated>
# A PR is "simple" iff: changed_lines <= max_loc AND changed_files <= max_files
# AND (areas empty OR every changed path is under one of the area prefixes).
# Anything else is "complex".
classify_pr_decision() {
  local lines="$1" files="$2" max_loc="$3" max_files="$4" areas="$5" paths="$6"
  [ "${lines:-0}"  -le "${max_loc:-2147483647}"   ] || { echo complex; return; }
  [ "${files:-0}"  -le "${max_files:-2147483647}" ] || { echo complex; return; }
  if [ -n "$areas" ]; then
    local -a arr=()
    IFS=',' read -ra arr <<< "$areas"
    local i a
    for i in "${!arr[@]}"; do                      # trim surrounding whitespace
      a="${arr[$i]}"
      a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
      arr[$i]="$a"
    done
    local p ok
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      ok=0
      for a in "${arr[@]}"; do
        [ -n "$a" ] || continue
        case "$p" in "$a"*) ok=1; break ;; esac
      done
      [ "$ok" = "1" ] || { echo complex; return; }
    done <<< "$paths"
  fi
  echo simple
}

# Sourced by tests with CLASSIFY_LIB_ONLY=1: stop before the live flow.
if [ "${CLASSIFY_LIB_ONLY:-}" = "1" ]; then
  # shellcheck disable=SC2317  # reached only when executed, not sourced
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=scripts/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/config.sh"
olympus_load_config

if [ "${OLYMPUS_TESTING_ENABLED:-false}" != "true" ]; then
  echo disabled
  exit 0
fi

PR="${PR_NUMBER:?PR_NUMBER required}"
meta=$(gh pr view "$PR" --json additions,deletions,changedFiles,files 2>/dev/null || echo '{}')
add=$(echo   "$meta" | jq -r '.additions   // 0')
del=$(echo   "$meta" | jq -r '.deletions   // 0')
files=$(echo "$meta" | jq -r '.changedFiles // 0')
paths=$(echo "$meta" | jq -r '.files[].path // empty' 2>/dev/null || true)
lines=$(( add + del ))

classify_pr_decision "$lines" "$files" \
  "${OLYMPUS_TESTING_FAST_MAX_LOC:-300}" "${OLYMPUS_TESTING_FAST_MAX_FILES:-10}" \
  "${OLYMPUS_TESTING_FAST_AREAS:-}" "$paths"
