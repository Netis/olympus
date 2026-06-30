#!/usr/bin/env python3
"""Unit test for config.sh — the loader that maps a consumer's .olympus.json
onto the OLYMPUS_* / ARGUS_* env every agent script reads. Stdlib only.

    python3 scripts/agent-bot/tests/test_config.py

Asserts: (1) values come through from a config file, (2) absent file → the
built-in defaults (back-compat), (3) an already-exported env var overrides the
file, (4) observer.* maps onto the ARGUS_* names argus.sh consumes.

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
    OLYMPUS_* / ARGUS_* env as a dict."""
    env = dict(os.environ)
    tmp = None
    if config_obj is not None:
        fd, tmp = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump(config_obj, f)
        env["OLYMPUS_CONFIG"] = tmp
    else:
        env["OLYMPUS_CONFIG"] = "/definitely/nonexistent.json"
    env.update(env_over)
    script = (
        f'source "{CONFIG_SH}"; olympus_load_config 2>/dev/null; '
        "env | grep -E \"^(OLYMPUS_|ARGUS_)\""
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
    assert cfg["OLYMPUS_MAX_LOC"] == "150", cfg.get("OLYMPUS_MAX_LOC")
    assert cfg["OLYMPUS_CONTAINED"] == "pkg/, docs/", cfg.get("OLYMPUS_CONTAINED")


def test_defaults_when_no_file():
    cfg = load(None)
    assert cfg["OLYMPUS_MAX_LOC"] == "300", cfg
    assert cfg["OLYMPUS_LABEL_TRY"] == "agent:try", cfg
    assert cfg["OLYMPUS_REVIEW_BOT_LOGIN"] == "themis", cfg


def test_env_overrides_file():
    cfg = load({"triage": {"gates": {"max_loc": 150}}}, OLYMPUS_MAX_LOC="999")
    assert cfg["OLYMPUS_MAX_LOC"] == "999", cfg.get("OLYMPUS_MAX_LOC")


def test_observer_maps_to_argus_env():
    cfg = load({"observer": {"service_name": "svc-x", "repo": "Acme/svc",
                             "readiness": {"jq": ".status", "expect": "ok"}}})
    assert cfg["ARGUS_SERVICE_NAME"] == "svc-x", cfg
    assert cfg["ARGUS_REPO"] == "Acme/svc", cfg
    assert cfg["ARGUS_READY_JQ"] == ".status", cfg
    assert cfg["ARGUS_READY_EXPECT"] == "ok", cfg


def test_custom_labels_and_bot():
    cfg = load({"agents": {"review_bot_login": "rex"}, "labels": {"try": "bot:go"}})
    assert cfg["OLYMPUS_REVIEW_BOT_LOGIN"] == "rex", cfg
    assert cfg["OLYMPUS_LABEL_TRY"] == "bot:go", cfg


def test_new_label_defaults():
    cfg = load(None)
    assert cfg["OLYMPUS_LABEL_DISCUSSING"] == "agent:discussing", cfg
    assert cfg["OLYMPUS_LABEL_STAGING_SOAKED"] == "staging-soaked", cfg
    assert cfg["OLYMPUS_LABEL_SOAK_FAILED"] == "soak-failed", cfg


def test_discussion_rounds():
    assert load(None)["OLYMPUS_MAX_DISCUSSION_ROUNDS"] == "4"
    cfg = load({"triage": {"max_discussion_rounds": 7}})
    assert cfg["OLYMPUS_MAX_DISCUSSION_ROUNDS"] == "7", cfg


def test_testing_defaults_disabled():
    cfg = load(None)
    assert cfg["OLYMPUS_TESTING_ENABLED"] == "false", cfg
    assert cfg["OLYMPUS_TESTING_SOAK_MINUTES"] == "30", cfg
    # fast-path ceilings default to the triage gate ceilings
    assert cfg["OLYMPUS_TESTING_FAST_MAX_LOC"] == cfg["OLYMPUS_MAX_LOC"], cfg
    assert cfg["OLYMPUS_TESTING_FAST_MAX_FILES"] == cfg["OLYMPUS_MAX_FILES"], cfg


def test_testing_values_from_file():
    cfg = load({
        "triage": {"gates": {"max_loc": 200, "max_files": 8}},
        "testing": {
            "enabled": True,
            "deploy_cmd": "make deploy-staging",
            "soak_minutes": 45,
            "fast_path": {"max_loc": 40, "areas": ["docs/", "scripts/"]},
        },
    })
    assert cfg["OLYMPUS_TESTING_ENABLED"] == "true", cfg
    assert cfg["OLYMPUS_TESTING_DEPLOY_CMD"] == "make deploy-staging", cfg
    assert cfg["OLYMPUS_TESTING_SOAK_MINUTES"] == "45", cfg
    assert cfg["OLYMPUS_TESTING_FAST_MAX_LOC"] == "40", cfg
    # max_files unset under fast_path → inherits the triage gate ceiling
    assert cfg["OLYMPUS_TESTING_FAST_MAX_FILES"] == "8", cfg
    assert cfg["OLYMPUS_TESTING_FAST_AREAS"] == "docs/,scripts/", cfg


def test_harness_codex_and_proxy():
    # Doc-range IP (RFC5737); the real staging proxy lives in the consumer's
    # config/secret, never in olympus source (leakage gate).
    cfg = load({"harness": {"kind": "codex", "proxy": "http://192.0.2.10:8888"}})
    assert cfg["OLYMPUS_HARNESS"] == "codex", cfg
    assert cfg["OLYMPUS_HARNESS_PROXY"] == "http://192.0.2.10:8888", cfg
    # codex defaults health_probe OFF (backend isn't OpenAI-compatible)
    assert cfg["OLYMPUS_HEALTH_PROBE"] == "false", cfg


def test_codex_health_probe_explicit_true_wins():
    cfg = load({"harness": {"kind": "codex", "health_probe": True}})
    assert cfg["OLYMPUS_HEALTH_PROBE"] == "true", cfg


def test_claude_health_probe_defaults_on():
    # default harness (claude) keeps health_probe ON and is never proxied here
    cfg = load(None)
    assert cfg["OLYMPUS_HEALTH_PROBE"] == "true", cfg
    assert cfg["OLYMPUS_HARNESS"] == "claude", cfg


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
