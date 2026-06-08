#!/usr/bin/env python3
"""Objective check for a triage task: the agent's output must contain a JSON
object whose `verdict` is one of the expected verdicts (from task.json)."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
from checks_lib import load_expect, triage_ok  # noqa: E402

task_dir = os.environ.get("TASK_DIR", os.path.dirname(os.path.abspath(__file__)))
out = open(sys.argv[1], encoding="utf-8", errors="replace").read()
ok, why = triage_ok(out, load_expect(task_dir))
print(("  check: PASS " if ok else "  check: FAIL ") + why)
sys.exit(0 if ok else 1)
