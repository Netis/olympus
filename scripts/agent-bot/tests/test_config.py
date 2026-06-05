#!/usr/bin/env python3
"""Unit test for config.sh — the loader that maps a consumer's .agent-ops.json
onto the AGENT_OPS_* / MARA_* env every agent script reads. Stdlib only.

    python3 scripts/agent-bot/tests/test_config.py

Asserts: (1) values come through from a config file, (2) absent file → the
built-in defaults (back-compat), (3) an already-exported env var overrides the
file, (4) observer.* maps onto the MARA_* names mara.sh consumes.

Exit 0 = all pass, 1 = a failure.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_SH = os.path.join(os.path.dirname(os.path.dirname(HERE)), "lib", "config.sh")


def load(config_obj=None, **env_over):
    """Source config.sh against an optional config file; return the resulting
    AGENT_OPS_* / MARA_* env as a dict."""
    env = dict(os.environ)
    tmp = None
    if config_obj is not None:
        fd, tmp = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump(config_obj, f)
        env["AGENT_OPS_CONFIG"] = tmp
    else:
        env["AGENT_OPS_CONFIG"] = "/definitely/nonexistent.json"
    env.update(env_over)
    script = (
        f'source "{CONFIG_SH}"; agent_ops_load_config 2>/dev/null; '
        "env | grep -E \"^(AGENT_OPS_|MARA_)\""
    )
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env, timeout=30)
    if tmp:
        os.unlink(tmp)
    out = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


# ---- tests ----------------------------------------------------------------

def test_values_from_file():
    cfg = load({"triage": {"gates": {"max_loc": 150, "contained_areas": ["pkg/", "docs/"]}}})
    assert cfg["AGENT_OPS_MAX_LOC"] == "150", cfg.get("AGENT_OPS_MAX_LOC")
    assert cfg["AGENT_OPS_CONTAINED"] == "pkg/, docs/", cfg.get("AGENT_OPS_CONTAINED")


def test_defaults_when_no_file():
    cfg = load(None)
    assert cfg["AGENT_OPS_MAX_LOC"] == "300", cfg
    assert cfg["AGENT_OPS_LABEL_TRY"] == "agent:try", cfg
    assert cfg["AGENT_OPS_REVIEW_BOT_LOGIN"] == "vivi", cfg


def test_env_overrides_file():
    cfg = load({"triage": {"gates": {"max_loc": 150}}}, AGENT_OPS_MAX_LOC="999")
    assert cfg["AGENT_OPS_MAX_LOC"] == "999", cfg.get("AGENT_OPS_MAX_LOC")


def test_observer_maps_to_mara_env():
    cfg = load({"observer": {"service_name": "svc-x", "repo": "Acme/svc",
                             "readiness": {"jq": ".status", "expect": "ok"}}})
    assert cfg["MARA_SERVICE_NAME"] == "svc-x", cfg
    assert cfg["MARA_REPO"] == "Acme/svc", cfg
    assert cfg["MARA_READY_JQ"] == ".status", cfg
    assert cfg["MARA_READY_EXPECT"] == "ok", cfg


def test_custom_labels_and_bot():
    cfg = load({"agents": {"review_bot_login": "rex"}, "labels": {"try": "bot:go"}})
    assert cfg["AGENT_OPS_REVIEW_BOT_LOGIN"] == "rex", cfg
    assert cfg["AGENT_OPS_LABEL_TRY"] == "bot:go", cfg


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
