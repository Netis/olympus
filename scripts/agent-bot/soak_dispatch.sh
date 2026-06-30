#!/usr/bin/env bash
# soak_dispatch.sh — a merge path decided this APPROVED PR is too big for the
# auto-merge fast path, so kick off the consumer's pr-soak workflow instead of
# merging, and leave a heads-up comment. Called by auto_merge.sh (agent PRs) and
# post_review.py (human PRs); both have already cleared their trust gate, so the
# only PRs that reach here are ones that WOULD have auto-merged.
#
# REQUIRES a PAT as GH_TOKEN — a `gh workflow run` issued with the default
# GITHUB_TOKEN is dropped by GitHub's anti-recursion rule and would never start
# the soak run.
set -euo pipefail

PR="${PR_NUMBER:?PR_NUMBER required}"
WORKFLOW="${OLYMPUS_SOAK_WORKFLOW:-pr-soak.yml}"

echo "soak-dispatch: PR #$PR is APPROVED but complex → dispatching ${WORKFLOW} (no auto-merge)"
if gh workflow run "$WORKFLOW" -f pr_number="$PR" 2>/tmp/soak-dispatch.err; then
  gh pr comment "$PR" --body "🤖 This change is bigger than the auto-merge fast path, so before merging I'm deploying it to the testing environment to soak for a bit. I'll post the result right here — a human makes the final merge call once it's soaked cleanly."
else
  echo "soak-dispatch: 'gh workflow run ${WORKFLOW}' failed — is ${WORKFLOW} on the default branch?" >&2
  cat /tmp/soak-dispatch.err >&2 || true
fi
