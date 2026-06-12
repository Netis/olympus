#!/usr/bin/env bash
# config.sh — load a consumer repo's .olympus.json into OLYMPUS_* / agent
# env vars, so the portable agent scripts carry NO repo-specific values.
#
# The single source of truth for "how this repo wants the agents to behave"
# is the consumer's .olympus.json (see schema/olympus.schema.json). This
# loader resolves it with jq (already a hard dependency of every agent script)
# — no YAML parser, no new runtime dep.
#
# Usage (from any agent script):
#     source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"
#     olympus_load_config            # reads $OLYMPUS_CONFIG or .olympus.json
#
# Every value has a default chosen so a repo with NO .olympus.json behaves
# exactly like heron did before extraction (back-compatible). A consumer
# overrides only what differs.
#
# Precedence: an already-exported env var wins over the config file, which wins
# over the built-in default. That lets a workflow or a test pin one value
# without rewriting the file.

# _olc_get always succeeds, so the export+command-substitution pattern in
# olympus_load_config can't mask a meaningful return value — silence SC2155.
# shellcheck disable=SC2155

# _olc_get <jq-filter> <default> : echo config value or default.
# Honors an env override named by the 3rd arg (if that env var is already set,
# it wins and the file is not consulted).
_olc_get() {
  local filter="$1" default="$2" envname="${3:-}"
  if [ -n "$envname" ]; then
    local cur="${!envname-__unset__}"
    if [ "$cur" != "__unset__" ] && [ -n "$cur" ]; then printf '%s' "$cur"; return; fi
  fi
  local v=""
  if [ -n "${_OLC_FILE:-}" ] && [ -f "$_OLC_FILE" ]; then
    v="$(jq -r "$filter // empty" "$_OLC_FILE" 2>/dev/null || true)"
  fi
  printf '%s' "${v:-$default}"
}

olympus_load_config() {
  _OLC_FILE="${OLYMPUS_CONFIG:-.olympus.json}"
  if [ ! -f "$_OLC_FILE" ]; then
    echo "olympus: no ${_OLC_FILE}; using built-in defaults" >&2
    _OLC_FILE=""
  fi

  # --- project / branch ---
  export OLYMPUS_DEFAULT_BRANCH="$(_olc_get '.project.default_branch' 'main' OLYMPUS_DEFAULT_BRANCH)"

  # --- agent identities ---
  export OLYMPUS_REVIEW_BOT_LOGIN="$(_olc_get '.agents.review_bot_login' 'themis' OLYMPUS_REVIEW_BOT_LOGIN)"
  export OLYMPUS_DEV_AGENT_NAME="$(_olc_get '.agents.dev_agent_name' 'hephaestus' OLYMPUS_DEV_AGENT_NAME)"

  # --- labels ---
  export OLYMPUS_LABEL_ASSESS="$(_olc_get '.labels.assess' 'agent:assess' OLYMPUS_LABEL_ASSESS)"
  export OLYMPUS_LABEL_TRY="$(_olc_get '.labels.try' 'agent:try' OLYMPUS_LABEL_TRY)"
  export OLYMPUS_LABEL_SKIP="$(_olc_get '.labels.skip' 'agent:skip' OLYMPUS_LABEL_SKIP)"
  export OLYMPUS_LABEL_AUTO_AGENT="$(_olc_get '.labels.auto_agent' 'auto-agent' OLYMPUS_LABEL_AUTO_AGENT)"

  # --- triage gates ---
  export OLYMPUS_MAX_LOC="$(_olc_get '.triage.gates.max_loc' '300' OLYMPUS_MAX_LOC)"
  export OLYMPUS_MAX_FILES="$(_olc_get '.triage.gates.max_files' '10' OLYMPUS_MAX_FILES)"
  export OLYMPUS_CONTAINED="$(_olc_get '(.triage.gates.contained_areas | join(", "))' 'one module, docs, or one workflow' OLYMPUS_CONTAINED)"
  export OLYMPUS_TEST_HINT="$(_olc_get '.triage.gates.test_hint' 'a unit / integration test' OLYMPUS_TEST_HINT)"
  export OLYMPUS_LANGUAGE="$(_olc_get '.triage.language' 'auto' OLYMPUS_LANGUAGE)"
  # When a verdict=do issue may AUTO-dispatch the unattended dev agent:
  # trusted (default) = only authors with write+ access; all = any author
  # (internal repos); never = always require a maintainer to add the try-label.
  export OLYMPUS_AUTO_DISPATCH="$(_olc_get '.triage.auto_dispatch' 'trusted' OLYMPUS_AUTO_DISPATCH)"

  # --- implement (dev agent) ---
  export OLYMPUS_BUILD_CMD="$(_olc_get '.implement.build_cmd' '' OLYMPUS_BUILD_CMD)"
  # Network egress for the implement/revise agent. Default false → the claude
  # harness denies curl/wget/ssh/... (a prompt-injected issue can't exfiltrate).
  # jq's `// empty` treats boolean false as empty, so normalise to a string.
  export OLYMPUS_IMPLEMENT_ALLOW_NETWORK="$(_olc_get '(.implement.allow_network | if . == true then "true" else "false" end)' 'false' OLYMPUS_IMPLEMENT_ALLOW_NETWORK)"

  # --- model (harness.model wins over top-level .model) ---
  export ANTHROPIC_MODEL="$(_olc_get '(.harness.model // .model)' "${ANTHROPIC_MODEL:-claude-3-5-sonnet-20241022}" ANTHROPIC_MODEL)"

  # --- harness (which agent CLI drives the surfaces; default claude) ---
  # Read by scripts/lib/agent-harness.sh's agent_run. kind=custom runs the
  # command template OLYMPUS_HARNESS_CMD ({model}/{prompt_file}/{out}/{tools}/
  # {write}/{max_turns} placeholders). health_probe=false skips the gateway
  # /v1/models wait (for harnesses whose endpoint isn't OpenAI-compatible).
  export OLYMPUS_HARNESS="$(_olc_get '.harness.kind' 'claude' OLYMPUS_HARNESS)"
  export OLYMPUS_HARNESS_CMD="$(_olc_get '.harness.command' '' OLYMPUS_HARNESS_CMD)"
  # jq's `// empty` (in _olc_get) treats boolean false as empty, so a literal
  # `health_probe: false` would be lost — normalise to the string "false"/"true"
  # inside the filter so only an explicit false disables the probe.
  export OLYMPUS_HEALTH_PROBE="$(_olc_get '(.harness.health_probe | if . == false then "false" else "true" end)' 'true' OLYMPUS_HEALTH_PROBE)"

  # --- observer (argus): map .observer.* onto the ARGUS_* env argus.sh reads,
  #     unless the env already carries them (workflow/unit override wins). ---
  export ARGUS_SERVICE_NAME="$(_olc_get '.observer.service_name' 'the service' ARGUS_SERVICE_NAME)"
  export ARGUS_HEALTH_URL="$(_olc_get '.observer.health_url' "${ARGUS_HEALTH_URL:-}" ARGUS_HEALTH_URL)"
  export ARGUS_REPO="$(_olc_get '.observer.repo' "${ARGUS_REPO:-}" ARGUS_REPO)"
  export ARGUS_LABELS="$(_olc_get '.observer.labels' 'incident' ARGUS_LABELS)"
  export ARGUS_READY_JQ="$(_olc_get '.observer.readiness.jq' '' ARGUS_READY_JQ)"
  export ARGUS_READY_EXPECT="$(_olc_get '.observer.readiness.expect' 'true' ARGUS_READY_EXPECT)"
}
