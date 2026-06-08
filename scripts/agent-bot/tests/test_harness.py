#!/usr/bin/env python3
"""Unit test for scripts/lib/agent-harness.sh's agent_run, via its dry-run shim
(AGENT_HARNESS_DRYRUN=1 prints the command it WOULD run, no exec / no gateway).

Two things it locks down:
  1. Back-compat: with NO config, the `claude` harness builds the same flags the
     four inline call sites used before the refactor (per profile).
  2. The `custom` harness substitutes the command-template placeholders.

Stdlib only; no network. Run: python3 scripts/agent-bot/tests/test_harness.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
HARNESS = os.path.join(REPO, "scripts", "lib", "agent-harness.sh")
CONFIG = os.path.join(REPO, "scripts", "lib", "config.sh")

failures = []


def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def dry_run(args, config=None):
    env = dict(os.environ)
    env["AGENT_HARNESS_DRYRUN"] = "1"
    pre = ""
    if config:
        env["AGENT_OPS_CONFIG"] = config
        pre = f'source "{CONFIG}"; agent_ops_load_config 2>/dev/null; '
    script = pre + f'source "{HARNESS}"; agent_run ' + args
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env)
    return r.stdout.strip()


# --- 1. claude back-compat, per profile (no config => default claude) ----------
out = dry_run('--profile investigate --prompt /tmp/p --out /tmp/o --errlog /tmp/e')
check("investigate starts with 'claude --print'", out.startswith("claude --print"))
check("investigate default model", "--model claude-3-5-sonnet-20241022" in out)
check("investigate tools = read-only + WebFetch",
      "--allowed-tools Bash Read Grep Glob WebFetch" in out)

out = dry_run('--profile implement --prompt /tmp/p --stream /tmp/s')
check("implement tools = read+write set",
      "--allowed-tools Bash Read Write Edit Grep Glob" in out)

out = dry_run('--profile review --prompt /tmp/p --out /tmp/o --tools "Bash,Read,Grep" '
              '--max-turns 60 --timeout 7200 --output-format text --permission-mode acceptEdits')
check("review tools override (comma list)", "--allowed-tools Bash,Read,Grep" in out)
check("review --max-turns 60", "--max-turns 60" in out)
check("review --output-format text", "--output-format text" in out)
check("review --permission-mode acceptEdits", "--permission-mode acceptEdits" in out)

# --- 2. custom harness: template substitution ---------------------------------
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump({"harness": {
        "kind": "custom",
        "command": "codex exec --model {model} < {prompt_file} > {out}  # w={write} t={tools} m={max_turns}",
        "model": "gpt-5",
    }}, f)
    cfg = f.name
out = dry_run('--profile implement --prompt /tmp/pp --out /tmp/oo --max-turns 40', config=cfg)
check("custom substitutes {model}", "--model gpt-5" in out)
check("custom substitutes {prompt_file}", "< /tmp/pp" in out)
check("custom substitutes {out}", "> /tmp/oo" in out)
check("custom {write}=true for implement", "w=true" in out)
check("custom substitutes {tools}", "t=Bash Read Write Edit Grep Glob" in out)
check("custom substitutes {max_turns}", "m=40" in out)
os.unlink(cfg)

# {write} is false for a non-implement profile
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump({"harness": {"kind": "custom", "command": "x --w {write}"}}, f)
    cfg = f.name
out = dry_run('--profile review --prompt /tmp/p --out /tmp/o', config=cfg)
check("custom {write}=false for review", "--w false" in out)
os.unlink(cfg)

# --- 3. model resolution from top-level .model --------------------------------
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump({"model": "claude-test-model"}, f)
    cfg = f.name
out = dry_run('--profile investigate --prompt /tmp/p --out /tmp/o', config=cfg)
check("model from .model", "--model claude-test-model" in out)
os.unlink(cfg)

print()
if failures:
    print(f"{len(failures)} check(s) FAILED")
    sys.exit(1)
print("all checks passed")
