#!/usr/bin/env bash
# Called from the tail of pr-review.yml AFTER themis posts her review.
# Auto-merges iff:
#   - PR has label `auto-agent`
#   - PR is not draft (hephaestus may have flipped it; or the linked issue
#     author was a team member and we promoted earlier — see below)
#   - themis's latest review state == APPROVED
#   - the linked issue's author is on the auto-merge allowlist
#
# When staging soak is enabled (.testing.enabled) AND the PR is too big for the
# fast path (classify_pr.sh → complex), the merge step is replaced by a soak:
# we dispatch pr-soak instead and a human merges after a clean soak. Simple PRs
# (and repos with soak off) keep the immediate admin-merge below.
set -euo pipefail

# Load .olympus.json → OLYMPUS_* (review-bot login, labels).
# shellcheck source=scripts/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/config.sh"
olympus_load_config

# Auto-merge allowlist (GitHub logins). Sourced from the AUTO_MERGE_TEAM env
# (CSV or whitespace-separated), injected from a repo secret by the workflow
# — kept out of committed source. Empty ⇒ no author is auto-merge-eligible.
TEAM=$(printf '%s' "${AUTO_MERGE_TEAM:-}" | tr ',' ' ')

PR="${PR_NUMBER:?PR_NUMBER required}"

meta=$(gh pr view "$PR" --json isDraft,labels,body)
labels=$(echo "$meta" | jq -r '.labels[].name')
echo "$labels" | grep -qx "$OLYMPUS_LABEL_AUTO_AGENT" || { echo "not an auto-agent PR; skip"; exit 0; }

# Latest review state. Some reviews have a null .body (e.g. quick
# APPROVE clicks without a comment); coerce to "" before contains()
# or jq aborts the whole pipeline. The review bot is identified by login OR
# its footer in the body (handles bot-account attribution quirks).
state=$(gh pr view "$PR" --json reviews --jq '
  [.reviews[] | select(.author.login==env.OLYMPUS_REVIEW_BOT_LOGIN or ((.body // "") | contains(env.OLYMPUS_REVIEW_BOT_LOGIN)))]
  | last | .state // empty')
[ "$state" = "APPROVED" ] || { echo "review verdict=$state; skip"; exit 0; }

# Extract issue number from PR body `Closes #N`.
issue=$(echo "$meta" | jq -r '.body' | grep -oE 'Closes #[0-9]+' | head -1 | tr -dc 0-9)
[ -n "$issue" ] || { echo "no linked issue; skip"; exit 0; }

BOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
author=$(gh issue view "$issue" --json author --jq '.author.login')
for m in $TEAM; do
  if [ "$m" = "$author" ]; then
    # The author is merge-trusted. If staging soak is on and this PR is too big
    # for the fast path, soak it first (a human merges after) instead of merging
    # now. classify_pr.sh prints disabled|simple|complex (disabled = soak off).
    klass=$(PR_NUMBER="$PR" bash "$BOT_DIR/classify_pr.sh" 2>/dev/null || echo disabled)
    if [ "$klass" = "complex" ]; then
      echo "themis APPROVED + author=$author ∈ TEAM, but PR is complex → soak before merge"
      PR_NUMBER="$PR" bash "$BOT_DIR/soak_dispatch.sh"
      exit 0
    fi
    echo "themis APPROVED + author=$author ∈ TEAM (${klass}) → admin-merge"
    # Lift draft (if still draft) and merge.
    gh pr ready "$PR" >/dev/null 2>&1 || true
    gh pr merge "$PR" --admin --squash --delete-branch
    exit 0
  fi
done
echo "author=$author not in TEAM; leaving PR for human review"
