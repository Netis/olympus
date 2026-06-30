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
  # An issue in an active back-and-forth triage discussion (verdict=discuss).
  export OLYMPUS_LABEL_DISCUSSING="$(_olc_get '.labels.discussing' 'agent:discussing' OLYMPUS_LABEL_DISCUSSING)"
  # A PR that has cleared its staging soak (left for a human to merge).
  export OLYMPUS_LABEL_STAGING_SOAKED="$(_olc_get '.labels.staging_soaked' 'staging-soaked' OLYMPUS_LABEL_STAGING_SOAKED)"
  # A PR whose staging soak failed (deploy or health check did not hold).
  export OLYMPUS_LABEL_SOAK_FAILED="$(_olc_get '.labels.soak_failed' 'soak-failed' OLYMPUS_LABEL_SOAK_FAILED)"

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
  # Max back-and-forth rounds triage will hold with a reporter before it stops
  # asking and loops in a human maintainer (each round = one triage reply). The
  # discussion loop fires on issue_comment; this caps cost + prevents ping-pong.
  export OLYMPUS_MAX_DISCUSSION_ROUNDS="$(_olc_get '.triage.max_discussion_rounds' '4' OLYMPUS_MAX_DISCUSSION_ROUNDS)"

  # --- implement (dev agent) ---
  export OLYMPUS_BUILD_CMD="$(_olc_get '.implement.build_cmd' '' OLYMPUS_BUILD_CMD)"
  # Network egress for the implement/revise agent. Default false → the claude
  # harness denies curl/wget/ssh/... (a prompt-injected issue can't exfiltrate).
  # jq's `// empty` treats boolean false as empty, so normalise to a string.
  export OLYMPUS_IMPLEMENT_ALLOW_NETWORK="$(_olc_get '(.implement.allow_network | if . == true then "true" else "false" end)' 'false' OLYMPUS_IMPLEMENT_ALLOW_NETWORK)"

  # --- testing (pre-merge staging soak) ---
  # Default disabled → behavior identical to repos with no .testing block: a
  # review APPROVE on a simple PR auto-merges, everything else waits for a human.
  # When enabled, an APPROVE-d PR is classified: a "simple" PR (within the
  # fast_path thresholds below) keeps the existing auto-merge fast path; a
  # "complex" PR is deployed to a testing environment, soaked, and — on a clean
  # soak — labeled staging-soaked for a human to merge (never auto-merged).
  export OLYMPUS_TESTING_ENABLED="$(_olc_get '(.testing.enabled | if . == true then "true" else "false" end)' 'false' OLYMPUS_TESTING_ENABLED)"
  export OLYMPUS_TESTING_DEPLOY_CMD="$(_olc_get '.testing.deploy_cmd' '' OLYMPUS_TESTING_DEPLOY_CMD)"
  # Health/readiness command run repeatedly during the soak window. Empty falls
  # back to the observer's health_url (a plain HTTP 2xx check in soak.sh).
  export OLYMPUS_TESTING_HEALTH_CMD="$(_olc_get '.testing.health_cmd' '' OLYMPUS_TESTING_HEALTH_CMD)"
  export OLYMPUS_TESTING_SOAK_MINUTES="$(_olc_get '.testing.soak_minutes' '30' OLYMPUS_TESTING_SOAK_MINUTES)"
  export OLYMPUS_TESTING_TEARDOWN_CMD="$(_olc_get '.testing.teardown_cmd' '' OLYMPUS_TESTING_TEARDOWN_CMD)"
  # "Simple" fast-path ceilings: a PR at/below all three skips the soak and may
  # auto-merge. Default to the triage gate ceilings so a PR no bigger than what
  # an unattended agent may attempt is treated as simple.
  export OLYMPUS_TESTING_FAST_MAX_LOC="$(_olc_get '.testing.fast_path.max_loc' "${OLYMPUS_MAX_LOC}" OLYMPUS_TESTING_FAST_MAX_LOC)"
  export OLYMPUS_TESTING_FAST_MAX_FILES="$(_olc_get '.testing.fast_path.max_files' "${OLYMPUS_MAX_FILES}" OLYMPUS_TESTING_FAST_MAX_FILES)"
  # Optional area allow-list: if set, a simple PR must touch ONLY these path
  # prefixes (comma-separated). Empty = areas are not considered.
  export OLYMPUS_TESTING_FAST_AREAS="$(_olc_get '(.testing.fast_path.areas | join(","))' '' OLYMPUS_TESTING_FAST_AREAS)"

  # --- model (harness.model wins over top-level .model) ---
  export ANTHROPIC_MODEL="$(_olc_get '(.harness.model // .model)' "${ANTHROPIC_MODEL:-claude-3-5-sonnet-20241022}" ANTHROPIC_MODEL)"

  # --- harness (which agent CLI drives the surfaces; default claude) ---
  # Read by scripts/lib/agent-harness.sh's agent_run. kind=custom runs the
  # command template OLYMPUS_HARNESS_CMD ({model}/{prompt_file}/{out}/{tools}/
  # {write}/{max_turns} placeholders). health_probe=false skips the gateway
  # /v1/models wait (for harnesses whose endpoint isn't OpenAI-compatible).
  export OLYMPUS_HARNESS="$(_olc_get '.harness.kind' 'claude' OLYMPUS_HARNESS)"
  export OLYMPUS_HARNESS_CMD="$(_olc_get '.harness.command' '' OLYMPUS_HARNESS_CMD)"
  # Optional egress proxy for a NON-claude harness subprocess. codex must reach
  # its model backend through a proxy on staging/testing (a direct connection is
  # blocked); agent-harness.sh exports this as HTTPS_PROXY/HTTP_PROXY/ALL_PROXY
  # for the harness CHILD only. The claude harness talks to the internal model
  # gateway and is never proxied (see the no_proxy step in the workflows).
  export OLYMPUS_HARNESS_PROXY="$(_olc_get '.harness.proxy' '' OLYMPUS_HARNESS_PROXY)"
  # health_probe polls the gateway's OpenAI-compatible /v1/models. It defaults
  # ON, but OFF for the codex harness (its backend isn't OpenAI-compatible). An
  # explicit .harness.health_probe (true OR false) always wins.
  # jq's `// empty` (in _olc_get) treats boolean false as empty, so a literal
  # `health_probe: false` would be lost — normalise to a "false"/"true" string
  # inside the filter, and pick the kind-aware default for the absent case.
  _olc_probe_default=true
  case "$OLYMPUS_HARNESS" in codex) _olc_probe_default=false ;; esac
  export OLYMPUS_HEALTH_PROBE="$(_olc_get "(.harness.health_probe | if . == false then \"false\" elif . == true then \"true\" else \"${_olc_probe_default}\" end)" "$_olc_probe_default" OLYMPUS_HEALTH_PROBE)"
  unset _olc_probe_default

  # --- observer (argus): map .observer.* onto the ARGUS_* env argus.sh reads,
  #     unless the env already carries them (workflow/unit override wins). ---
  export ARGUS_SERVICE_NAME="$(_olc_get '.observer.service_name' 'the service' ARGUS_SERVICE_NAME)"
  export ARGUS_HEALTH_URL="$(_olc_get '.observer.health_url' "${ARGUS_HEALTH_URL:-}" ARGUS_HEALTH_URL)"
  export ARGUS_REPO="$(_olc_get '.observer.repo' "${ARGUS_REPO:-}" ARGUS_REPO)"
  export ARGUS_LABELS="$(_olc_get '.observer.labels' 'incident' ARGUS_LABELS)"
  export ARGUS_READY_JQ="$(_olc_get '.observer.readiness.jq' '' ARGUS_READY_JQ)"
  export ARGUS_READY_EXPECT="$(_olc_get '.observer.readiness.expect' 'true' ARGUS_READY_EXPECT)"
}
