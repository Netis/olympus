#!/usr/bin/env bash
# Objective: run the fixture's test in the sandbox the agent edited. Pass = exit 0.
set -uo pipefail
cd "${SANDBOX:?SANDBOX unset}" || exit 1
cmd="$(jq -r '.expect.test_cmd // "python3 test_add.py"' "${TASK_DIR:?TASK_DIR unset}/task.json")"
if eval "$cmd" >/dev/null 2>&1; then
  echo "  check: PASS ($cmd)"; exit 0
else
  echo "  check: FAIL ($cmd exited nonzero)"; exit 1
fi
