"""Shared, dependency-free helpers for the eval task checks.

Each task's check.{py,sh} scores one agent run **objectively** (binary pass/fail)
— no judge LLM. These helpers cover the common parsing the python checks need.
Importable by evals/tests/test_checks.py so the scoring logic is unit-tested
without running any agent.
"""
import json
import os


def extract_json(text):
    """Return the first balanced {...} substring that parses as JSON (agents
    often wrap the object in prose / markdown fences), else None."""
    for s in (i for i, c in enumerate(text) if c == "{"):
        depth = 0
        for e in range(s, len(text)):
            if text[e] == "{":
                depth += 1
            elif text[e] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[s:e + 1])
                    except Exception:
                        break
    return None


def load_expect(task_dir):
    """The `expect` object from a task's task.json."""
    with open(os.path.join(task_dir, "task.json")) as f:
        return json.load(f).get("expect", {})


def triage_ok(output_text, expect):
    """Triage: output contains a JSON object whose `verdict` is one of the
    expected verdicts."""
    obj = extract_json(output_text)
    if obj is None:
        return False, "no parseable JSON object in output"
    verdict = obj.get("verdict")
    allowed = expect.get("verdict", [])
    if isinstance(allowed, str):
        allowed = [allowed]
    if verdict in allowed:
        return True, f"verdict={verdict}"
    return False, f"verdict={verdict!r} not in {allowed}"


def review_ok(output_text, expect):
    """Review: the review text mentions the planted issue. `must_contain_any`
    = pass if ANY token is present; `must_contain` = ALL must be present
    (case-insensitive)."""
    low = output_text.lower()
    any_of = [s.lower() for s in expect.get("must_contain_any", [])]
    all_of = [s.lower() for s in expect.get("must_contain", [])]
    if any_of and not any(s in low for s in any_of):
        return False, f"none of must_contain_any present: {any_of}"
    missing = [s for s in all_of if s not in low]
    if missing:
        return False, f"missing must_contain: {missing}"
    return True, "matched"
