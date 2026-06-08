#!/usr/bin/env python3
"""Validate the eval scoring logic deterministically — feed canned agent outputs
to the real task checks + checks_lib, no agents, no network. This is what CI runs
(the live bench runs on demand). Stdlib only.
"""
import os
import shutil
import subprocess
import sys
import tempfile

EVALS = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, EVALS)
from checks_lib import extract_json, triage_ok, review_ok  # noqa: E402
from score import aggregate  # noqa: E402

fails = []


def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails.append(name)


# --- checks_lib units ----------------------------------------------------------
check("extract_json: bare object", extract_json('{"verdict":"do"}') == {"verdict": "do"})
check("extract_json: wrapped in prose/fence",
      extract_json('Here you go:\n```json\n{"verdict":"skip","reply":"x"}\n```\n')["verdict"] == "skip")
check("extract_json: none", extract_json("no json here") is None)
check("triage_ok: verdict in set", triage_ok('{"verdict":"do"}', {"verdict": ["do", "try"]})[0])
check("triage_ok: verdict not in set", not triage_ok('{"verdict":"skip"}', {"verdict": ["do"]})[0])
check("triage_ok: no json", not triage_ok("nope", {"verdict": ["do"]})[0])
check("review_ok: any-of present",
      review_ok("This HARDCODES a secret token.", {"must_contain_any": ["hardcod", "secret"]})[0])
check("review_ok: any-of absent",
      not review_ok("Looks fine.", {"must_contain_any": ["hardcod", "secret"]})[0])

# --- score.aggregate -----------------------------------------------------------
card = aggregate([
    {"task": "triage/do-issue", "pass": 1, "rc": 0, "secs": 4},
    {"task": "triage/do-issue", "pass": 0, "rc": 0, "secs": 6},
    {"task": "review/planted-bug", "pass": 1, "rc": 0, "secs": 9},
])
check("aggregate: per-task pass_rate", card["tasks"]["triage/do-issue"]["pass_rate"] == 0.5)
check("aggregate: surface rollup", card["surfaces"]["triage"]["pass_rate"] == 0.5)
check("aggregate: overall", card["overall"]["passes"] == 2 and card["overall"]["runs"] == 3)


# --- the real task check files, against canned outputs -------------------------
def run_check_py(task, output_text, expect_pass):
    td = os.path.join(EVALS, "tasks", task)
    with tempfile.NamedTemporaryFile("w", suffix=".out", delete=False) as f:
        f.write(output_text)
        outf = f.name
    env = dict(os.environ, TASK_DIR=td)
    rc = subprocess.run([sys.executable, os.path.join(td, "check.py"), outf],
                        env=env, capture_output=True).returncode
    os.unlink(outf)
    check(f"check.py {task} ({'good' if expect_pass else 'bad'} → {'pass' if expect_pass else 'fail'})",
          (rc == 0) == expect_pass)


run_check_py("triage/do-issue", '{"verdict":"do","reply":"on it"}', True)
run_check_py("triage/do-issue", '{"verdict":"skip"}', False)
run_check_py("triage/skip-issue", 'I think we should {"verdict":"skip","reply":"too big"}', True)
run_check_py("triage/skip-issue", '{"verdict":"do"}', False)
run_check_py("review/planted-bug", "The diff hardcodes an API token and password in source.", True)
run_check_py("review/planted-bug", "LGTM, ship it.", False)


# --- implement check.sh: a passing vs failing sandbox --------------------------
def run_impl_check(add_body, expect_pass):
    if not shutil.which("jq"):
        print("skip implement check.sh (jq not installed locally; CI has it)")
        return
    td = os.path.join(EVALS, "tasks", "implement", "failing-test")
    sandbox = tempfile.mkdtemp()
    shutil.copytree(os.path.join(td, "repo"), sandbox, dirs_exist_ok=True)
    with open(os.path.join(sandbox, "add.py"), "w") as f:
        f.write(add_body)
    env = dict(os.environ, SANDBOX=sandbox, TASK_DIR=td)
    rc = subprocess.run(["bash", os.path.join(td, "check.sh"), "x"], env=env,
                        capture_output=True).returncode
    shutil.rmtree(sandbox)
    check(f"check.sh implement ({'fixed' if expect_pass else 'buggy'} → {'pass' if expect_pass else 'fail'})",
          (rc == 0) == expect_pass)


run_impl_check("def add(a, b):\n    return a + b\n", True)
run_impl_check("def add(a, b):\n    return a - b\n", False)

print()
if fails:
    print(f"{len(fails)} FAILED")
    sys.exit(1)
print("all checks passed")
