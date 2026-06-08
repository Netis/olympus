#!/usr/bin/env bash
# Orchestrate one PR review:
#   1) export PR_NUMBER / HEAD_SHA / BASE_REF for the prompt template
#   2) substitute them into prompt.md
#   3) run `claude -p` in print mode with the read-only tool allowlist
#   4) drop the model's stdout into /tmp/pr-review-${N}-out.md for
#      post_review.py to consume
#
# Exits non-zero only on infrastructure failure (LiteLLM unreachable,
# claude binary missing, etc). The post-review step inspects the
# output file content to decide review verdict.

set -euo pipefail

PR_NUMBER="${1:?usage: $0 <pr_number>}"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .agent-ops.json so the configured harness (harness.kind) + model land in
# the env before the agent runs. No config ⇒ claude (back-compatible).
# shellcheck source=../lib/config.sh
source "$(cd "$WORKDIR/../lib" && pwd)/config.sh"
agent_ops_load_config

OUT="/tmp/pr-review-${PR_NUMBER}-out.md"
LOG="/tmp/pr-review-${PR_NUMBER}-agent.log"
PROMPT="/tmp/pr-review-${PR_NUMBER}-prompt.md"

# Resolve PR metadata for the prompt. The workflow has already
# checked out the head SHA — pull base_ref + head_sha back out of
# git so this script is also runnable locally (`bash run_review.sh
# 27` from a checkout) for development / debugging.
HEAD_SHA="$(git rev-parse HEAD)"
BASE_REF="$(gh pr view "$PR_NUMBER" --json baseRefName --jq .baseRefName)"

export PR_NUMBER HEAD_SHA BASE_REF
envsubst < "$WORKDIR/prompt.md" > "$PROMPT"

# Source the harness adapter — it sources litellm-wait.sh and owns the gateway
# pre-flight wait + the retry-on-gateway-down loop. The CLI is the consumer's
# .agent-ops.json harness.kind (default: claude).
# shellcheck source=../lib/agent-harness.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/agent-harness.sh"

# Build the tool allowlist as a single comma-separated string (the
# format `claude --allowed-tools` accepts).
ALLOWED_TOOLS="$(grep -v '^#' "$WORKDIR/allowed_tools.txt" \
  | grep -v '^[[:space:]]*$' \
  | paste -sd, -)"

# Headless agent run via the configured harness (default: claude). The 7200 s
# outer timeout is a hard fence — large-diff reviews (200+ files) can run long,
# but we'd rather post "review timed out" than wedge the workflow. agent-harness.sh
# owns the gateway wait + retry-on-gateway-down loop; review is idempotent ($OUT is
# overwritten) so a from-scratch retry is safe. The prompt is fed on stdin because
# claude's --allowed-tools is variadic (a positional prompt would be swallowed as a
# tool name).
claude_rc=0
agent_run --profile review --prompt "$PROMPT" --out "$OUT" --errlog "$LOG" \
  --tools "$ALLOWED_TOOLS" --max-turns 60 --timeout 7200 \
  --output-format text --permission-mode acceptEdits --label vivi || claude_rc=$?

if [ "$claude_rc" -ne 0 ]; then
    echo "ERROR: agent exited with code $claude_rc" >> "$LOG"
    # Don't synthesize a PR-bound failure summary here — post_review.py
    # is gated on AGENT_EXIT and will skip the PR entirely on non-zero.
    # The OUT file is left as-is (possibly empty) for workflow-log
    # consumption.
    exit "$claude_rc"
fi

# Sanity: non-empty markdown with at least a `### Summary` heading.
if ! grep -q '^### Summary' "$OUT"; then
  echo "WARN: agent output missing ### Summary heading" >> "$LOG"
  printf '\n\n---\n_Agent output was missing required heading._\n' >> "$OUT"
fi

echo "review written to $OUT ($(wc -c < "$OUT") bytes)"
