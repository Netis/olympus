#!/usr/bin/env python3
"""Objective check for a review task: the review text must mention the planted
issue (must_contain_any / must_contain from task.json)."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
from checks_lib import load_expect, review_ok  # noqa: E402

task_dir = os.environ.get("TASK_DIR", os.path.dirname(os.path.abspath(__file__)))
out = open(sys.argv[1], encoding="utf-8", errors="replace").read()
ok, why = review_ok(out, load_expect(task_dir))
print(("  check: PASS " if ok else "  check: FAIL ") + why)
sys.exit(0 if ok else 1)
