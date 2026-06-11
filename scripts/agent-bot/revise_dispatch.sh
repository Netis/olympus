#!/usr/bin/env bash
# Called from the tail of pr-review.yml AFTER themis posts her review.
# If themis REQUEST_CHANGES'd a hephaestus PR (label `auto-agent`), dispatch the
# `pr-revise` workflow so hephaestus addresses the feedback automatically — unless
# the round cap is reached, in which case hand off to a human.
#
# Idempotent + safe to call for every PR: it bails out for human PRs, for
# non-CHANGES_REQUESTED verdicts, and for closed PRs.
#
# REQUIRES AGENT_GH_TOKEN (a PAT) as GH_TOKEN. A `gh workflow run` issued with
# the default GITHUB_TOKEN would be dropped by GitHub's anti-recursion rule
# (events from GITHUB_TOKEN don't start new workflow runs), and the dispatched
# revise run must itself be able to push + re-trigger ci/pr-review.
set -euo pipefail

# Load .olympus.json → OLYMPUS_* (review-bot login, labels).
# shellcheck source=scripts/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/config.sh"
olympus_load_config

PR="${PR_NUMBER:?PR_NUMBER required}"
# Number of times themis may block a PR before we stop auto-revising and
# escalate. Counts CHANGES_REQUESTED reviews already on the PR (including the
# one just posted), so cap=3 gives hephaestus two automated revision attempts.
MAX_REVISE_ROUNDS="${MAX_REVISE_ROUNDS:-3}"

meta=$(gh pr view "$PR" --json labels,reviews,state)

[ "$(echo "$meta" | jq -r '.state')" = "OPEN" ] || { echo "PR #$PR not open; skip"; exit 0; }
echo "$meta" | jq -r '.labels[].name' | grep -qx "$OLYMPUS_LABEL_AUTO_AGENT" || { echo "PR #$PR not auto-agent; skip"; exit 0; }

# Review states in chronological order. Identify the review bot the same way
# auto_merge.sh does (login OR its footer in the body).
themis_states=$(echo "$meta" | jq -r '
  [ .reviews[]
    | select(.author.login==env.OLYMPUS_REVIEW_BOT_LOGIN or ((.body // "") | contains(env.OLYMPUS_REVIEW_BOT_LOGIN)))
    | .state ] | .[]')

latest=$(printf '%s\n' "$themis_states" | grep -v '^$' | tail -1 || true)
if [ "$latest" != "CHANGES_REQUESTED" ]; then
  echo "themis latest verdict=${latest:-none} (not CHANGES_REQUESTED); skip"
  exit 0
fi

rounds=$(printf '%s\n' "$themis_states" | grep -c CHANGES_REQUESTED || true)

if [ "$rounds" -ge "$MAX_REVISE_ROUNDS" ]; then
  echo "revise rounds=$rounds ≥ cap=$MAX_REVISE_ROUNDS — escalating PR #$PR to a human"
  gh label create needs-human --color B60205 \
    --description "Auto-agent loop paused; needs a human" 2>/dev/null || true
  gh pr edit "$PR" --add-label needs-human >/dev/null 2>&1 || true
  gh pr comment "$PR" --body "🤖 themis has requested changes ${rounds}× — at the auto-revise cap (\`${MAX_REVISE_ROUNDS}\`). Pausing the hephaestus ↔ themis loop and handing off to a human. To resume an automated pass, remove the \`needs-human\` label and re-run the \`pr-revise\` workflow for this PR."
  exit 0
fi

echo "themis REQUEST_CHANGES on auto-agent PR #$PR (round $rounds/$MAX_REVISE_ROUNDS) → dispatching pr-revise"
gh workflow run pr-revise.yml -f pr_number="$PR"
