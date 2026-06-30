#!/usr/bin/env bash
# soak.sh — deploy a PR's head to the consumer's testing environment, let it
# soak (stay healthy) for testing.soak_minutes, then label the PR for a human:
#   staging-soaked → soak passed; a human makes the merge call (we NEVER merge).
#   soak-failed    → deploy or health check did not hold; left unmerged.
#
# Olympus orchestrates; the repo supplies the work: testing.deploy_cmd (+ an
# optional health_cmd / teardown_cmd) in .olympus.json. Dispatched per PR by the
# consumer's pr-soak workflow (see soak_dispatch.sh / soak.yml).
#
# The comment text is pure (soak_comment_body) so tests can drive it directly;
# `SOAK_LIB_ONLY=1 source soak.sh` loads it and returns before the live flow.
set -euo pipefail

# soak_comment_body <result: soaked|failed> <detail> <minutes> — the exact PR
# comment for each outcome. Carries an invisible breadcrumb so tooling can tell
# a soak comment apart. Pure: no gh / network.
soak_comment_body() {
  local result="$1" detail="$2" mins="$3"
  if [ "$result" = "soaked" ]; then
    cat <<EOF
✅ **Staging soak passed** — this change stayed healthy in the testing environment for ${mins} min (${detail}).

It's deployed and looking good. Over to you for the merge call — if it looks right, go ahead and merge.

<!-- olympus-soak:soaked -->
EOF
  else
    cat <<EOF
⚠️ **Staging soak did not pass** — ${detail}.

I've left this PR unmerged. The soak workflow logs have the details; once it's addressed, re-run the \`pr-soak\` workflow for this PR to try again.

<!-- olympus-soak:failed -->
EOF
  fi
}

# Sourced by tests with SOAK_LIB_ONLY=1: stop before the live flow.
if [ "${SOAK_LIB_ONLY:-}" = "1" ]; then
  # shellcheck disable=SC2317  # reached only when executed, not sourced
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=scripts/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/config.sh"
olympus_load_config

PR="${PR_NUMBER:?PR_NUMBER required}"
[ "${OLYMPUS_TESTING_ENABLED:-false}" = "true" ] || { echo "testing not enabled; nothing to soak"; exit 0; }
[ -n "${OLYMPUS_TESTING_DEPLOY_CMD:-}" ] || { echo "no .testing.deploy_cmd configured; cannot soak PR #$PR"; exit 0; }

SOAK_MIN="${OLYMPUS_TESTING_SOAK_MINUTES:-30}"
POLL_S="${OLYMPUS_TESTING_POLL_SECONDS:-30}"
MAX_FAILS="${OLYMPUS_TESTING_MAX_FAILS:-3}"

# Ensure the result labels exist (best-effort), and clear any stale soak labels
# — we're (re-)soaking the current head.
gh label create "$OLYMPUS_LABEL_STAGING_SOAKED" --color 0E8A16 --description "Passed staging soak; ready for a human to merge" 2>/dev/null || true
gh label create "$OLYMPUS_LABEL_SOAK_FAILED"   --color B60205 --description "Staging soak failed; left unmerged" 2>/dev/null || true
gh pr edit "$PR" --remove-label "$OLYMPUS_LABEL_STAGING_SOAKED" --remove-label "$OLYMPUS_LABEL_SOAK_FAILED" >/dev/null 2>&1 || true

# A single health probe: prefer the explicit command; else hit the observer's
# health_url; else treat a successful deploy as healthy.
soak_health() {
  if [ -n "${OLYMPUS_TESTING_HEALTH_CMD:-}" ]; then
    PR_NUMBER="$PR" bash -c "$OLYMPUS_TESTING_HEALTH_CMD"
  elif [ -n "${ARGUS_HEALTH_URL:-}" ]; then
    curl -fsS -o /dev/null --max-time 10 "$ARGUS_HEALTH_URL"
  else
    return 0
  fi
}

teardown() {
  [ -n "${OLYMPUS_TESTING_TEARDOWN_CMD:-}" ] || return 0
  echo "::group::teardown"
  PR_NUMBER="$PR" bash -c "$OLYMPUS_TESTING_TEARDOWN_CMD" || echo "teardown failed (non-fatal)"
  echo "::endgroup::"
}

finish() {  # finish <soaked|failed> <detail>
  local result="$1" detail="$2" label
  [ "$result" = "soaked" ] && label="$OLYMPUS_LABEL_STAGING_SOAKED" || label="$OLYMPUS_LABEL_SOAK_FAILED"
  gh pr edit "$PR" --add-label "$label" >/dev/null 2>&1 || true
  soak_comment_body "$result" "$detail" "$SOAK_MIN" | gh pr comment "$PR" --body-file -
}

# 1. Deploy the PR head to the testing environment.
echo "::group::deploy PR #$PR to the testing environment"
if ! PR_NUMBER="$PR" bash -c "$OLYMPUS_TESTING_DEPLOY_CMD"; then
  echo "::endgroup::"
  echo "deploy failed for PR #$PR"
  teardown
  finish failed "the deploy step failed"
  exit 0
fi
echo "::endgroup::"

# 2. Soak: poll health across the window; require it to hold (a short run of
#    consecutive failures ends the soak).
echo "soaking PR #$PR for ${SOAK_MIN} min (poll ${POLL_S}s, tolerate <${MAX_FAILS} consecutive failures)"
deadline=$(( $(date +%s) + SOAK_MIN * 60 ))
fails=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if soak_health; then
    fails=0
  else
    fails=$((fails + 1))
    echo "health check failed (${fails}/${MAX_FAILS})"
    if [ "$fails" -ge "$MAX_FAILS" ]; then
      teardown
      finish failed "health checks failed ${fails}× in a row during the soak"
      exit 0
    fi
  fi
  sleep "$POLL_S"
done

# 3. Survived the window → ready for a human merge decision.
teardown
finish soaked "polled healthy throughout"
echo "PR #$PR soaked cleanly"
