#!/usr/bin/env python3
"""Unit tests for post_review.py verdict parser."""

import os
import sys
from pathlib import Path

# Mock PR_NUMBER before importing the module
os.environ["PR_NUMBER"] = "999"

# Import the module under test
sys.path.insert(0, str(Path(__file__).parent))
import post_review


def test_section_nonempty_level3_heading():
    """Original format: ### Blocking with content."""
    body = """### Summary
APPROVE

### Blocking
- Test failure

### Verified
- All tests pass"""
    assert post_review.section_nonempty(body, "Blocking") is True
    assert post_review.section_nonempty(body, "Verified") is True


def test_section_nonempty_level2_heading():
    """New format: ## Summary with content."""
    body = """## Summary
APPROVE

## Verified
- All tests pass"""
    assert post_review.section_nonempty(body, "Verified") is True


def test_section_nonempty_missing_section():
    """Missing section returns False."""
    body = """### Summary
APPROVE"""
    assert post_review.section_nonempty(body, "Blocking") is False


def test_pick_event_explicit_approve_level3():
    """Explicit APPROVE in ### Summary."""
    body = """### Summary
**APPROVE** — ready to merge.

### Verified
- Tests pass"""
    assert post_review.pick_event(body) == "APPROVE"


def test_pick_event_explicit_approve_level2():
    """Explicit APPROVE in ## Summary (the bug case)."""
    body = """## Summary
**APPROVE** — ready to merge.

## Verified
- Tests pass"""
    assert post_review.pick_event(body) == "APPROVE"


def test_pick_event_explicit_approve_markdown_bold():
    """Explicit APPROVE in bold markdown."""
    body = """### Summary
**APPROVE**

### Verified
- All good"""
    assert post_review.pick_event(body) == "APPROVE"


def test_pick_event_request_changes_from_blocking():
    """REQUEST_CHANGES inferred from Blocking section."""
    body = """### Summary
Needs fixes.

### Blocking
- Test failures

### Verified"""
    assert post_review.pick_event(body) == "REQUEST_CHANGES"


def test_pick_event_request_changes_from_blocking_level2():
    """REQUEST_CHANGES inferred from ## Blocking section."""
    body = """## Summary
Needs fixes.

## Blocking
- Test failures"""
    assert post_review.pick_event(body) == "REQUEST_CHANGES"


def test_pick_event_comment_from_suggestions():
    """COMMENT inferred from Suggestions section."""
    body = """### Summary
Minor nits.

### Suggestions
- Consider renaming"""
    assert post_review.pick_event(body) == "COMMENT"


def test_pick_event_approve_default():
    """APPROVE when only Verified present, no explicit token."""
    body = """### Summary
Looks good.

### Verified
- All tests pass"""
    assert post_review.pick_event(body) == "APPROVE"


def test_pick_event_approve_verified_only_level2():
    """APPROVE with ## Verified only (no Summary token)."""
    body = """## Summary
Clean implementation.

## Verified
- Tests pass
- Lint clean"""
    assert post_review.pick_event(body) == "APPROVE"


def test_pick_event_no_headings():
    """No markdown headings → COMMENT."""
    body = "Just a plain text comment"
    assert post_review.pick_event(body) == "COMMENT"


def test_pick_event_error_prefix():
    """ERROR prefix → COMMENT."""
    body = "ERROR: something went wrong"
    assert post_review.pick_event(body) == "COMMENT"


def test_pick_event_explicit_overrides_sections():
    """Explicit APPROVE token overrides Blocking section."""
    body = """### Summary
**APPROVE**

### Blocking
- This would normally block"""
    assert post_review.pick_event(body) == "APPROVE"


def test_pick_event_request_changes_explicit():
    """Explicit REQUEST_CHANGES token."""
    body = """### Summary
**REQUEST_CHANGES**

### Verified
- Tests pass"""
    assert post_review.pick_event(body) == "REQUEST_CHANGES"


def test_pick_event_comment_explicit():
    """Explicit COMMENT token."""
    body = """### Summary
**COMMENT**

### Suggestions
- Minor nits"""
    assert post_review.pick_event(body) == "COMMENT"


def test_build_footer_uses_env_review_bot():
    """Footer attribution is config-driven, never hardcoded."""
    prev = os.environ.get("OLYMPUS_REVIEW_BOT_LOGIN")
    os.environ["OLYMPUS_REVIEW_BOT_LOGIN"] = "athena"
    try:
        footer = post_review.build_footer("http://run/1")
        assert "Reviewed by **athena**" in footer, footer
        assert "http://run/1" in footer, footer
    finally:
        if prev is None:
            del os.environ["OLYMPUS_REVIEW_BOT_LOGIN"]
        else:
            os.environ["OLYMPUS_REVIEW_BOT_LOGIN"] = prev


def test_build_footer_falls_back_without_env():
    """Absent config → a neutral label, never a stale hardcoded name."""
    prev = os.environ.pop("OLYMPUS_REVIEW_BOT_LOGIN", None)
    try:
        footer = post_review.build_footer("http://run/2")
        assert "Reviewed by **the review bot**" in footer, footer
    finally:
        if prev is not None:
            os.environ["OLYMPUS_REVIEW_BOT_LOGIN"] = prev


def _fake_proc(returncode, stdout="", stderr=""):
    return type("P", (), {"returncode": returncode, "stdout": stdout, "stderr": stderr})()


def test_classify_pr_returns_stdout_word():
    """classify_pr surfaces classify_pr.sh's stdout (disabled|simple|complex)."""
    orig = post_review.subprocess.run
    post_review.subprocess.run = lambda *a, **k: _fake_proc(0, "complex\n")
    try:
        assert post_review.classify_pr("999") == "complex"
    finally:
        post_review.subprocess.run = orig


def test_classify_pr_failure_is_disabled():
    """A failing classify script is treated as 'disabled' (merge as before)."""
    orig = post_review.subprocess.run
    post_review.subprocess.run = lambda *a, **k: _fake_proc(1, "", "boom")
    try:
        assert post_review.classify_pr("999") == "disabled"
    finally:
        post_review.subprocess.run = orig


def _drive_main_approve(klass):
    """Run main() on an APPROVE review from a trusted, non-auto-agent author,
    with classify_pr stubbed to `klass`. Returns (merge_calls, soak_calls)."""
    calls = {"merge": 0, "soak": 0}
    saved = {k: getattr(post_review, k) for k in (
        "AGENT_EXIT", "AUTO_MERGE_AUTHORS", "post_via_gh_review", "pr_has_label",
        "pr_author", "classify_pr", "auto_merge", "dispatch_soak")}
    post_review.OUT_PATH.write_text("### Summary\n**APPROVE**\n\n### Verified\n- ok\n")
    try:
        post_review.AGENT_EXIT = "success"
        post_review.AUTO_MERGE_AUTHORS = {"alice"}
        post_review.post_via_gh_review = lambda n, e, b: 0
        post_review.pr_has_label = lambda n, name: False           # not auto-agent
        post_review.pr_author = lambda n: "alice"                  # trusted
        post_review.classify_pr = lambda n: klass
        post_review.auto_merge = lambda n: calls.__setitem__("merge", calls["merge"] + 1)
        post_review.dispatch_soak = lambda n: calls.__setitem__("soak", calls["soak"] + 1)
        post_review.main()
    finally:
        for k, v in saved.items():
            setattr(post_review, k, v)
        if post_review.OUT_PATH.exists():
            post_review.OUT_PATH.unlink()
    return calls["merge"], calls["soak"]


def test_main_complex_soaks_not_merges():
    merge, soak = _drive_main_approve("complex")
    assert (merge, soak) == (0, 1), (merge, soak)


def test_main_simple_merges_not_soaks():
    merge, soak = _drive_main_approve("simple")
    assert (merge, soak) == (1, 0), (merge, soak)


def test_main_disabled_merges_not_soaks():
    # soak off (.testing.enabled false) → unchanged behavior: merge.
    merge, soak = _drive_main_approve("disabled")
    assert (merge, soak) == (1, 0), (merge, soak)


if __name__ == "__main__":
    import traceback
    failed = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"✓ {name}")
            except AssertionError:
                failed += 1
                print(f"✗ {name}")
                traceback.print_exc()
    print(f"\n{failed} failed")
    sys.exit(0 if failed == 0 else 1)