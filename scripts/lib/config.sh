#!/usr/bin/env bash
# config.sh — load a consumer repo's .agent-ops.json into AGENT_OPS_* / agent
# env vars, so the portable agent scripts carry NO repo-specific values.
#
# The single source of truth for "how this repo wants the agents to behave"
# is the consumer's .agent-ops.json (see schema/agent-ops.schema.json). This
# loader resolves it with jq (already a hard dependency of every agent script)
# — no YAML parser, no new runtime dep.
#
# Usage (from any agent script):
#     source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"
#     agent_ops_load_config            # reads $AGENT_OPS_CONFIG or .agent-ops.json
#
# Every value has a default chosen so a repo with NO .agent-ops.json behaves
# exactly like heron did before extraction (back-compatible). A consumer
# overrides only what differs.
#
# Precedence: an already-exported env var wins over the config file, which wins
# over the built-in default. That lets a workflow or a test pin one value
# without rewriting the file.

# _aoc_get always succeeds, so the export+command-substitution pattern in
# agent_ops_load_config can't mask a meaningful return value — silence SC2155.
# shellcheck disable=SC2155

# _aoc_get <jq-filter> <default> : echo config value or default.
# Honors an env override named by the 3rd arg (if that env var is already set,
# it wins and the file is not consulted).
_aoc_get() {
  local filter="$1" default="$2" envname="${3:-}"
  if [ -n "$envname" ]; then
    local cur="${!envname-__unset__}"
    if [ "$cur" != "__unset__" ] && [ -n "$cur" ]; then printf '%s' "$cur"; return; fi
  fi
  local v=""
  if [ -n "${_AOC_FILE:-}" ] && [ -f "$_AOC_FILE" ]; then
    v="$(jq -r "$filter // empty" "$_AOC_FILE" 2>/dev/null || true)"
  fi
  printf '%s' "${v:-$default}"
}

agent_ops_load_config() {
  _AOC_FILE="${AGENT_OPS_CONFIG:-.agent-ops.json}"
  if [ ! -f "$_AOC_FILE" ]; then
    echo "agent-ops: no ${_AOC_FILE}; using built-in defaults" >&2
    _AOC_FILE=""
  fi

  # --- project / branch ---
  export AGENT_OPS_DEFAULT_BRANCH="$(_aoc_get '.project.default_branch' 'main' AGENT_OPS_DEFAULT_BRANCH)"

  # --- agent identities ---
  export AGENT_OPS_REVIEW_BOT_LOGIN="$(_aoc_get '.agents.review_bot_login' 'vivi' AGENT_OPS_REVIEW_BOT_LOGIN)"
  export AGENT_OPS_DEV_AGENT_NAME="$(_aoc_get '.agents.dev_agent_name' 'the dev agent' AGENT_OPS_DEV_AGENT_NAME)"

  # --- labels ---
  export AGENT_OPS_LABEL_ASSESS="$(_aoc_get '.labels.assess' 'agent:assess' AGENT_OPS_LABEL_ASSESS)"
  export AGENT_OPS_LABEL_TRY="$(_aoc_get '.labels.try' 'agent:try' AGENT_OPS_LABEL_TRY)"
  export AGENT_OPS_LABEL_SKIP="$(_aoc_get '.labels.skip' 'agent:skip' AGENT_OPS_LABEL_SKIP)"
  export AGENT_OPS_LABEL_AUTO_AGENT="$(_aoc_get '.labels.auto_agent' 'auto-agent' AGENT_OPS_LABEL_AUTO_AGENT)"

  # --- triage gates ---
  export AGENT_OPS_MAX_LOC="$(_aoc_get '.triage.gates.max_loc' '300' AGENT_OPS_MAX_LOC)"
  export AGENT_OPS_MAX_FILES="$(_aoc_get '.triage.gates.max_files' '10' AGENT_OPS_MAX_FILES)"
  export AGENT_OPS_CONTAINED="$(_aoc_get '(.triage.gates.contained_areas | join(", "))' 'one module, docs, or one workflow' AGENT_OPS_CONTAINED)"
  export AGENT_OPS_TEST_HINT="$(_aoc_get '.triage.gates.test_hint' 'a unit / integration test' AGENT_OPS_TEST_HINT)"
  export AGENT_OPS_LANGUAGE="$(_aoc_get '.triage.language' 'auto' AGENT_OPS_LANGUAGE)"

  # --- implement (dev agent) ---
  export AGENT_OPS_BUILD_CMD="$(_aoc_get '.implement.build_cmd' '' AGENT_OPS_BUILD_CMD)"

  # --- model (harness.model wins over top-level .model) ---
  export ANTHROPIC_MODEL="$(_aoc_get '(.harness.model // .model)' "${ANTHROPIC_MODEL:-claude-3-5-sonnet-20241022}" ANTHROPIC_MODEL)"

  # --- harness (which agent CLI drives the surfaces; default claude) ---
  # Read by scripts/lib/agent-harness.sh's agent_run. kind=custom runs the
  # command template AGENT_OPS_HARNESS_CMD ({model}/{prompt_file}/{out}/{tools}/
  # {write}/{max_turns} placeholders). health_probe=false skips the gateway
  # /v1/models wait (for harnesses whose endpoint isn't OpenAI-compatible).
  export AGENT_OPS_HARNESS="$(_aoc_get '.harness.kind' 'claude' AGENT_OPS_HARNESS)"
  export AGENT_OPS_HARNESS_CMD="$(_aoc_get '.harness.command' '' AGENT_OPS_HARNESS_CMD)"
  # jq's `// empty` (in _aoc_get) treats boolean false as empty, so a literal
  # `health_probe: false` would be lost — normalise to the string "false"/"true"
  # inside the filter so only an explicit false disables the probe.
  export AGENT_OPS_HEALTH_PROBE="$(_aoc_get '(.harness.health_probe | if . == false then "false" else "true" end)' 'true' AGENT_OPS_HEALTH_PROBE)"

  # --- observer (mara): map .observer.* onto the MARA_* env mara.sh reads,
  #     unless the env already carries them (workflow/unit override wins). ---
  export MARA_SERVICE_NAME="$(_aoc_get '.observer.service_name' 'the service' MARA_SERVICE_NAME)"
  export MARA_HEALTH_URL="$(_aoc_get '.observer.health_url' "${MARA_HEALTH_URL:-}" MARA_HEALTH_URL)"
  export MARA_REPO="$(_aoc_get '.observer.repo' "${MARA_REPO:-}" MARA_REPO)"
  export MARA_LABELS="$(_aoc_get '.observer.labels' 'incident' MARA_LABELS)"
  export MARA_READY_JQ="$(_aoc_get '.observer.readiness.jq' '' MARA_READY_JQ)"
  export MARA_READY_EXPECT="$(_aoc_get '.observer.readiness.expect' 'true' MARA_READY_EXPECT)"
}
