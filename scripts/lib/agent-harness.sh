# shellcheck shell=bash
# agent-harness.sh — the configurable agent-CLI adapter.
#
# Every agent surface (triage / implement / review / revise) used to invoke the
# `claude` CLI inline, each with its own copy of the "wait for the gateway, run,
# retry if the gateway died mid-stream" loop. This centralises that into ONE
# function so the harness CLI becomes a `.agent-ops.json` choice:
#
#   harness.kind = "claude"  (default — byte-compatible with the old inline calls)
#                | "custom"  (run AGENT_OPS_HARNESS_CMD, a command template)
#
# Public entry point:
#   agent_run --profile {investigate|implement|review} --prompt <file> \
#             [--out <file>] [--errlog <file>] [--stream <teelog>] \
#             [--tools "<override>"] [--max-turns N] [--timeout S] \
#             [--output-format F] [--permission-mode M] [--label NAME]
#
# Returns the harness exit code. Encapsulates: the pre-flight gateway wait + the
# retry-on-gateway-down loop (both no-ops when AGENT_OPS_HEALTH_PROBE != "true").
#
# Config consumed (exported by config.sh; safe defaults if unset):
#   AGENT_OPS_HARNESS        claude | custom            (default claude)
#   AGENT_OPS_HARNESS_CMD    custom command template    (custom only)
#   AGENT_OPS_HEALTH_PROBE   true | false               (default true)
#   ANTHROPIC_MODEL          model id for the claude harness / {model} placeholder
#
# Dry run: AGENT_HARNESS_DRYRUN=1 prints the command that WOULD run (one line)
# and returns 0 — no pre-flight, no exec. Used by test_harness.py + eval self-check.
#
# The retry loop needs wait_for_litellm + litellm_appears_down from litellm-wait.sh;
# source it here (idempotent) so callers don't have to.
if ! declare -F wait_for_litellm >/dev/null 2>&1; then
  # shellcheck source=scripts/lib/litellm-wait.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/litellm-wait.sh"
fi

# Profile → the claude --allowed-tools set, and whether the agent may write.
_agent_profile_tools() {
  case "$1" in
    investigate) printf '%s' 'Bash Read Grep Glob WebFetch' ;;
    implement)   printf '%s' 'Bash Read Write Edit Grep Glob' ;;
    review)      printf '%s' 'Bash Read Grep Glob' ;;   # default; review usually passes --tools
    *)           printf '%s' 'Bash Read Grep Glob' ;;
  esac
}
_agent_profile_write() {  # "true" if the profile is allowed to edit files
  if [ "$1" = "implement" ]; then printf 'true'; else printf 'false'; fi
}

agent_run() {
  local profile="" prompt="" out="" errlog="/dev/null" streamlog="" tools="" \
        max_turns="" timeout_s="" output_format="" permission_mode="" label=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --profile)         profile="$2"; shift 2 ;;
      --prompt)          prompt="$2"; shift 2 ;;
      --out)             out="$2"; shift 2 ;;
      --errlog)          errlog="$2"; shift 2 ;;
      --stream)          streamlog="$2"; shift 2 ;;
      --tools)           tools="$2"; shift 2 ;;
      --max-turns)       max_turns="$2"; shift 2 ;;
      --timeout)         timeout_s="$2"; shift 2 ;;
      --output-format)   output_format="$2"; shift 2 ;;
      --permission-mode) permission_mode="$2"; shift 2 ;;
      --label)           label="$2"; shift 2 ;;
      *) echo "agent_run: unknown arg '$1'" >&2; return 64 ;;
    esac
  done
  [ -n "$profile" ] && [ -n "$prompt" ] || { echo "agent_run: --profile and --prompt are required" >&2; return 64; }
  [ -n "$label" ] || label="$profile"

  local model="${ANTHROPIC_MODEL:-claude-3-5-sonnet-20241022}"
  local tool_set; tool_set="${tools:-$(_agent_profile_tools "$profile")}"
  local write; write="$(_agent_profile_write "$profile")"
  local kind="${AGENT_OPS_HARNESS:-claude}"

  # --- build the harness command --------------------------------------------
  # For the claude harness we keep a real argv array (no eval). For custom we
  # build a single shell string from the template so consumers can use pipes.
  local -a claude_cmd=()
  local custom_cmd=""
  if [ "$kind" = "custom" ]; then
    [ -n "${AGENT_OPS_HARNESS_CMD:-}" ] || { echo "agent_run: harness.kind=custom but AGENT_OPS_HARNESS_CMD is empty" >&2; return 78; }
    # custom always writes the agent's output to a file we control; for stream
    # profiles that's a temp the loop tees to stdout afterwards.
    local cust_out="${out:-${streamlog:-/dev/stdout}}"
    custom_cmd="$AGENT_OPS_HARNESS_CMD"
    custom_cmd="${custom_cmd//\{model\}/$model}"
    custom_cmd="${custom_cmd//\{prompt_file\}/$prompt}"
    custom_cmd="${custom_cmd//\{out\}/$cust_out}"
    custom_cmd="${custom_cmd//\{tools\}/$tool_set}"
    custom_cmd="${custom_cmd//\{write\}/$write}"
    custom_cmd="${custom_cmd//\{max_turns\}/${max_turns:-0}}"
  else
    claude_cmd=(claude --print --model "$model")
    [ -n "$output_format" ]   && claude_cmd+=(--output-format "$output_format")
    [ -n "$max_turns" ]       && claude_cmd+=(--max-turns "$max_turns")
    [ -n "$permission_mode" ] && claude_cmd+=(--permission-mode "$permission_mode")
    if [ -n "$tools" ]; then
      claude_cmd+=(--allowed-tools "$tools")           # single (comma-sep) override
    else
      # shellcheck disable=SC2206  # deliberate word-split of the tool set
      claude_cmd+=(--allowed-tools $tool_set)
    fi
  fi

  # --- dry run: print the command and stop ----------------------------------
  if [ "${AGENT_HARNESS_DRYRUN:-}" = "1" ]; then
    if [ "$kind" = "custom" ]; then printf '%s\n' "$custom_cmd";
    else printf '%s\n' "${claude_cmd[*]}"; fi
    return 0
  fi

  # --- pre-flight: gateway reachable? ---------------------------------------
  if [ "${AGENT_OPS_HEALTH_PROBE:-true}" = "true" ]; then
    wait_for_litellm || return $?
  fi

  # --- run with retry-on-gateway-down ---------------------------------------
  # Optional `timeout S` prefix as a quoted array (empty array → no prefix).
  local -a runner=()
  [ -n "$timeout_s" ] && runner=(timeout "$timeout_s")
  local retry_max="${CLAUDE_RETRY_MAX:-2}" attempt=0 rc=0
  while true; do
    set +e
    if [ -n "$streamlog" ]; then
      if [ "$kind" = "custom" ]; then
        stdbuf -oL bash -c "$custom_cmd" 2>&1 | stdbuf -oL tee "$streamlog"
      else
        stdbuf -oL "${claude_cmd[@]}" < "$prompt" 2>&1 | stdbuf -oL tee "$streamlog"
      fi
      rc=${PIPESTATUS[0]}
    else
      if [ "$kind" = "custom" ]; then
        "${runner[@]}" bash -c "$custom_cmd" > "${out:-/dev/stdout}" 2> "$errlog"
      else
        "${runner[@]}" "${claude_cmd[@]}" < "$prompt" > "${out:-/dev/stdout}" 2> "$errlog"
      fi
      rc=$?
    fi
    set -e

    [ "$rc" -eq 0 ] && break
    if [ "${AGENT_OPS_HEALTH_PROBE:-true}" != "true" ] || ! litellm_appears_down; then
      break                                   # failure is not a gateway outage — don't retry
    fi
    if [ "$attempt" -ge "$retry_max" ]; then
      echo "::error::${label} agent died $((attempt+1))x with the gateway down; giving up" >&2
      break
    fi
    attempt=$((attempt + 1))
    echo "::warning::${label} agent exited $rc, gateway down; waiting + retrying ($((attempt+1))/$((retry_max+1)))" >&2
    wait_for_litellm || break
  done
  return "$rc"
}
