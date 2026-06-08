#!/usr/bin/env bash
# Dev agent. Branch off the default branch, implement, ensure the project's
# build + tests are green, open a DRAFT PR labelled `auto-agent`. Auto-merge
# gating happens downstream in the review workflow.
set -euo pipefail

# Load .agent-ops.json → AGENT_OPS_* (default branch, build cmd, labels, name).
# shellcheck source=scripts/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/config.sh"
agent_ops_load_config
BASE="$AGENT_OPS_DEFAULT_BRANCH"

# Auto-merge allowlist (GitHub logins). Sourced from the AUTO_MERGE_TEAM env
# (CSV or whitespace-separated), injected from a repo secret by the workflow
# — kept out of committed source. Used only to add a cosmetic
# "eligible for auto-merge" line to the PR body; the real gate is auto_merge.sh.
TEAM=$(printf '%s' "${AUTO_MERGE_TEAM:-}" | tr ',' ' ')
is_team_member() {
  local who="$1"
  for m in $TEAM; do [ "$m" = "$who" ] && return 0; done
  return 1
}

# Branch name includes a short UTC timestamp so re-runs against the
# same issue don't collide with leftover branches from prior attempts.
STAMP=$(date -u +%Y%m%d-%H%M%S)
BRANCH="agent/dev/issue-${ISSUE_NUMBER}-${STAMP}"
git config user.email "agent-bot@noreply.local"
git config user.name  "$AGENT_OPS_DEV_AGENT_NAME"
git fetch origin "$BASE"
git checkout -B "$BRANCH" "origin/$BASE"

PROMPT=$(mktemp)
cat > "$PROMPT" <<EOF
You are **wiwi**, the dev agent. Implement the change requested by issue
#${ISSUE_NUMBER}. Constraints:

- Stay within the scope the triage agent approved. If you discover the
  task is larger than expected (>${AGENT_OPS_MAX_LOC} LOC or cross-cutting),
  STOP, leave a note in /tmp/wiwi-abort.txt explaining why, and exit non-zero.
- Add a deterministic test for the change (unit / integration / a tiny
  fixture). Don't claim done without one.
- After edits, run the project build + test command:
  \`${AGENT_OPS_BUILD_CMD:-see the repo CONTRIBUTING docs}\` — it must be green
  before you stop.
- Do NOT add new dependencies, new secrets, new network calls.
- Do NOT modify CI workflows, branch protection, or this script.
- YOU are responsible for committing your changes. Run
  \`git add -A && git commit -m "..."\` after each logical chunk. The
  driver script will NOT commit for you; if you finish without any
  commits the run is dropped and your work is lost. Use multiple
  commits if it helps reviewers, or one final commit if the change is
  small — but at least one commit MUST exist before you exit.
- The driver script does have a defensive fallback that will
  auto-commit anything you left uncommitted, but DO NOT rely on it —
  the fallback produces a single "wiwi: auto-commit" message that's
  useless to reviewers compared to your own intentional commit
  messages.
- **You may be a RESUMED run.** If \`git log origin/${BASE}..HEAD\` shows
  existing commits OR \`git status\` shows uncommitted edits when you
  start, the previous attempt crashed mid-run (typically a LiteLLM /
  model backend hiccup) and the driver is retrying. Treat that state as your
  starting point: do NOT redo work that's already committed; do
  verify the partial state makes sense (read the diffs, build, run
  tests); then continue toward the issue's acceptance criteria. If
  the existing state is incoherent and you cannot make sense of it,
  STOP and write to /tmp/wiwi-abort.txt explaining why so a human
  can intervene.

When done, write a brief summary to /tmp/wiwi-summary.md (Markdown) for
the PR body. End it with the literal line:

  Closes #${ISSUE_NUMBER}

Issue title: ${ISSUE_TITLE}
EOF

# Run the configured agent harness (default: claude) on the implement prompt,
# STREAMING its output to BOTH the workflow log (stdout) and /tmp/wiwi-run.log —
# so a developer watching `gh run watch` sees each tool call land in near
# real-time (a silent `> log 2>&1` once hid whether wiwi was progressing or
# hung). agent-harness.sh sources litellm-wait.sh and owns the gateway pre-flight
# wait + retry-on-gateway-down loop (it re-runs from scratch; the prompt above
# tells the agent how to resume from the partial on-disk state). Which CLI runs
# is .agent-ops.json's harness.kind.
# shellcheck source=../lib/agent-harness.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/agent-harness.sh"
claude_exit=0
agent_run --profile implement --prompt "$PROMPT" --stream /tmp/wiwi-run.log --label wiwi || claude_exit=$?

if [ "$claude_exit" != "0" ]; then
  echo "wiwi run failed (claude exit=$claude_exit; see /tmp/wiwi-run.log)" >&2
  gh issue comment "$ISSUE_NUMBER" --body "🤖 wiwi could not complete this task. See workflow log."
  exit 1
fi

if [ -f /tmp/wiwi-abort.txt ]; then
  gh issue comment "$ISSUE_NUMBER" --body "🤖 wiwi aborted: $(cat /tmp/wiwi-abort.txt)"
  exit 0
fi

# Defensive fallback: if claude left uncommitted edits, salvage them
# rather than losing 30+ minutes of work to the runner workspace
# cleanup. The first 26487120283-class incident burned a full Heron
# rebrand because the prompt said "Commit in logical chunks" and
# claude interpreted that as something the driver would handle. Auto-
# commit message is intentionally terse — reviewer can rewrite the
# message after-the-fact if needed, or wiwi can re-run with the
# tightened prompt.
if ! git diff --quiet || ! git diff --cached --quiet || \
   [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "wiwi: detected uncommitted edits at end of run; auto-committing as fallback" >&2
  git add -A
  git commit -m "wiwi: auto-commit uncommitted edits for #${ISSUE_NUMBER}" \
                -m "Generated by run_wiwi.sh fallback. claude finished without committing; this commit captures the working-tree state so the PR isn't empty. Reviewer: consider asking wiwi to re-run with explicit commit guidance if the diff is large or unclear."
fi

# Sanity: must have produced commits.
if [ "$(git rev-list --count "origin/$BASE..HEAD")" = "0" ]; then
  gh issue comment "$ISSUE_NUMBER" --body "🤖 wiwi finished without any commit OR uncommitted edits; nothing to PR."
  exit 0
fi

git push -u origin "$BRANCH"

BODY_FILE=$(mktemp)
{
  cat /tmp/wiwi-summary.md 2>/dev/null || echo "(wiwi did not write a summary)"
  echo
  echo "---"
  echo "🤖 Implemented by **wiwi** • issue author: @${ISSUE_AUTHOR}"
  if is_team_member "$ISSUE_AUTHOR"; then
    echo "Eligible for auto-merge on vivi APPROVE."
  fi
} > "$BODY_FILE"

gh pr create \
  --draft \
  --base "$BASE" \
  --head "$BRANCH" \
  --title "${ISSUE_TITLE}" \
  --body-file "$BODY_FILE" \
  --label "$AGENT_OPS_LABEL_AUTO_AGENT"
