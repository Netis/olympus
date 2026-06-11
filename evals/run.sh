#!/usr/bin/env bash
# evals/run.sh — benchmark an agent harness on the standard tasks.
#
# Qualifies a candidate agent CLI BEFORE wiring it into the live loop: it runs
# each evals/tasks/<surface>/<name>/ task through Part A's agent_run adapter
# (i.e. exactly how the loop invokes the CLI), in a throwaway sandbox, and scores
# the result with the task's objective binary check. No judge.
#
#   evals/run.sh                                  # baseline: the built-in claude harness
#   evals/run.sh --harness custom \
#                --command 'codex exec --model {model} --full-auto < {prompt_file} > {out}' \
#                --model gpt-5 --repeat 3 --label codex
#   evals/run.sh --list                           # list task ids
#
# Needs: the model endpoint reachable (ANTHROPIC_BASE_URL/API_KEY in env) and the
# chosen CLI installed. Runs on demand — NOT in CI (CI only lints this + the checks).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

harness="claude"; command_tmpl=""; model=""; repeat=1; label=""
while [ $# -gt 0 ]; do
  case "$1" in
    --harness) harness="$2"; shift 2 ;;
    --command) command_tmpl="$2"; shift 2 ;;
    --model)   model="$2"; shift 2 ;;
    --repeat)  repeat="$2"; shift 2 ;;
    --label)   label="$2"; shift 2 ;;
    --list)    find "$HERE/tasks" -name task.json -print0 | xargs -0 -n1 dirname \
                 | sed "s#$HERE/tasks/##" | sort; exit 0 ;;
    *) echo "run.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
done
[ -n "$label" ] || label="$harness"

# Configure the harness via env (config.sh / agent-harness.sh honor env over file).
export OLYMPUS_HARNESS="$harness"
[ -n "$command_tmpl" ] && export OLYMPUS_HARNESS_CMD="$command_tmpl"
[ -n "$model" ] && export ANTHROPIC_MODEL="$model"
# A custom harness usually isn't behind an OpenAI-compatible /v1/models probe.
[ "$harness" = "custom" ] && export OLYMPUS_HEALTH_PROBE="${OLYMPUS_HEALTH_PROBE:-false}"
# shellcheck source=scripts/lib/agent-harness.sh
source "$REPO/scripts/lib/agent-harness.sh"

mkdir -p "$HERE/runs"
results="$HERE/runs/${label}.jsonl"
: > "$results"

run_one() {
  local task_dir="$1"
  local name; name="${task_dir#"$HERE"/tasks/}"
  local profile prompt_rel sandbox out t0 t1 rc=0 pass=0
  profile="$(jq -r '.profile' "$task_dir/task.json")"
  prompt_rel="$(jq -r '.prompt // "prompt.md"' "$task_dir/task.json")"
  sandbox="$(mktemp -d)"
  [ -d "$task_dir/repo" ] && cp -R "$task_dir/repo/." "$sandbox/"
  out="$sandbox/.agent-out"

  t0="$(date +%s)"
  ( cd "$sandbox" && agent_run --profile "$profile" --prompt "$task_dir/$prompt_rel" \
      --out "$out" --errlog "$sandbox/.agent-err" --label "eval:$name" ) || rc=$?
  t1="$(date +%s)"

  if [ "$rc" -eq 0 ]; then
    if [ -f "$task_dir/check.py" ]; then
      TASK_DIR="$task_dir" SANDBOX="$sandbox" python3 "$task_dir/check.py" "$out" && pass=1 || pass=0
    elif [ -f "$task_dir/check.sh" ]; then
      TASK_DIR="$task_dir" SANDBOX="$sandbox" bash "$task_dir/check.sh" "$out" && pass=1 || pass=0
    fi
  else
    echo "  agent exited $rc (see sandbox err); scored fail" >&2
  fi
  printf '{"task":"%s","pass":%d,"rc":%d,"secs":%d}\n' "$name" "$pass" "$rc" "$((t1 - t0))" >> "$results"
  rm -rf "$sandbox"
}

echo "harness=$label  repeat=$repeat  results=$results"
while IFS= read -r -d '' tj; do
  td="$(dirname "$tj")"
  for _ in $(seq 1 "$repeat"); do
    echo "» ${td#"$HERE"/tasks/}"
    run_one "$td"
  done
done < <(find "$HERE/tasks" -name task.json -print0 | sort -z)

python3 "$HERE/score.py" "$results"
