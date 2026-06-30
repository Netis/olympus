#!/usr/bin/env python3
"""Unit tests for the staging-soak pure helpers — stdlib only, no gh/network:

    python3 scripts/agent-bot/tests/test_soak.py

  - classify_pr.sh's `classify_pr_decision`: simple vs complex by size + area.
  - soak.sh's `soak_comment_body`: the exact PR comment per outcome.

Both scripts support a LIB_ONLY mode (CLASSIFY_LIB_ONLY / SOAK_LIB_ONLY): sourced
that way they load the pure function and return before the live (gh) flow.

Exit 0 = all pass, 1 = a failure.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOT = os.path.dirname(HERE)
CLASSIFY = os.path.join(BOT, "classify_pr.sh")
SOAK = os.path.join(BOT, "soak.sh")


def classify(lines, files, max_loc, max_files, areas, paths):
    script = (
        f'CLASSIFY_LIB_ONLY=1 source "{CLASSIFY}"; '
        'classify_pr_decision "$1" "$2" "$3" "$4" "$5" "$6"'
    )
    r = subprocess.run(
        ["bash", "-c", script, "bash",
         str(lines), str(files), str(max_loc), str(max_files), areas, paths],
        capture_output=True, text=True, timeout=30,
    )
    assert r.returncode == 0, f"classify exited {r.returncode}: {r.stderr}"
    return r.stdout.strip()


def soak_body(result, detail, mins):
    script = (
        f'SOAK_LIB_ONLY=1 source "{SOAK}"; '
        'soak_comment_body "$1" "$2" "$3"'
    )
    r = subprocess.run(
        ["bash", "-c", script, "bash", result, detail, str(mins)],
        capture_output=True, text=True, timeout=30,
    )
    assert r.returncode == 0, f"soak_comment_body exited {r.returncode}: {r.stderr}"
    return r.stdout


# ---- classify_pr_decision -------------------------------------------------

def test_simple_within_ceilings_no_areas():
    assert classify(50, 3, 300, 10, "", "") == "simple"


def test_complex_when_lines_exceed():
    assert classify(500, 2, 300, 10, "", "") == "complex"


def test_complex_when_files_exceed():
    assert classify(10, 99, 300, 10, "", "") == "complex"


def test_boundary_is_simple():
    # at the ceiling (<=) is still simple
    assert classify(300, 10, 300, 10, "", "") == "simple"


def test_areas_all_inside_is_simple():
    paths = "docs/a.md\nscripts/b.sh"
    assert classify(20, 2, 300, 10, "docs/,scripts/", paths) == "simple"


def test_areas_one_outside_is_complex():
    paths = "docs/a.md\nsrc/core.rs"
    assert classify(20, 2, 300, 10, "docs/,scripts/", paths) == "complex"


def test_areas_with_spaces_are_trimmed():
    paths = "docs/a.md"
    assert classify(5, 1, 300, 10, "docs/, scripts/", paths) == "simple"


def test_size_over_beats_area_match():
    # even if all paths are in-area, an over-size diff is still complex
    assert classify(9999, 1, 300, 10, "docs/", "docs/a.md") == "complex"


# ---- soak_comment_body ----------------------------------------------------

def test_soaked_comment():
    out = soak_body("soaked", "polled healthy throughout", 30)
    assert "Staging soak passed" in out, out
    assert "30 min" in out, out
    assert "<!-- olympus-soak:soaked -->" in out, out


def test_failed_comment():
    out = soak_body("failed", "the deploy step failed", 30)
    assert "did not pass" in out, out
    assert "the deploy step failed" in out, out
    assert "pr-soak" in out, out  # tells the human how to retry
    assert "<!-- olympus-soak:failed -->" in out, out


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    fails = 0
    for t in tests:
        try:
            t()
            print(f"ok   {t.__name__}")
        except AssertionError as e:
            fails += 1
            print(f"FAIL {t.__name__}: {e}")
        except Exception as e:  # noqa: BLE001
            fails += 1
            print(f"ERR  {t.__name__}: {type(e).__name__}: {e}")
    print(f"\n{len(tests) - fails}/{len(tests)} passed")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
