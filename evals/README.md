# evals/ — harness qualification bench

Benchmark a candidate agent CLI on standard tasks **before** wiring it into the
live loop. New CLIs (codex now; pi agent, kilo cli, … later) get *qualified*,
not just plugged in.

It reuses Part A's `agent_run` adapter — so a candidate is invoked **exactly how
the loop would invoke it** (`harness.kind=custom` + your command template).
Scoring is **objective binary** (no judge): build passes / bug caught / valid
JSON verdict.

## Run it

```bash
# baseline: the built-in claude harness (needs ANTHROPIC_BASE_URL/API_KEY in env)
evals/run.sh

# a candidate CLI (codex shown). --repeat N for pass-rate over stochastic runs.
evals/run.sh --harness custom \
  --command 'codex exec --model {model} --full-auto < {prompt_file} > {out}' \
  --model gpt-5 --repeat 3 --label codex

evals/run.sh --list          # list task ids
```

Each run writes `runs/<label>.jsonl` (per-task results) + a `runs/<label>.scorecard.json`,
and prints a table:

```
=== scorecard: codex ===
TASK                                         PASS   RATE   AVG s
implement/failing-test                        2/3  0.667    41.0
review/planted-bug                            3/3    1.0     9.0
triage/do-issue                               3/3    1.0     5.0
triage/skip-issue                             2/3  0.667     5.0
----------------------------------------------------------------
implement (surface)                           2/3  0.667
review (surface)                              3/3    1.0
triage (surface)                              5/6  0.833
OVERALL                                       10/12 0.833
```

Compare two CLIs by running each with a different `--label` and diffing the
scorecards. **Decide integration from the numbers.**

> Needs the model endpoint reachable + the chosen CLI installed on the box. Runs
> **on demand** — NOT in CI (CI only lints `run.sh` + runs the scoring unit tests
> in `tests/test_checks.py`).

## Tasks

`tasks/<surface>/<name>/` — each is one objective check:

| Task | Surface | Pass = |
|---|---|---|
| `triage/do-issue` | investigate | output JSON `verdict` ∈ {do, try} for a small actionable issue |
| `triage/skip-issue` | investigate | `verdict` ∈ {skip, needs_info} for an out-of-scope issue |
| `implement/failing-test` | implement | the agent's edit makes the fixture's `python3 test_add.py` pass |
| `review/planted-bug` | review | the review flags a hardcoded secret in the diff |

### Add a task

Drop a `tasks/<surface>/<name>/` folder with:
- `task.json` — `{ "surface", "profile": "investigate|implement|review", "prompt": "prompt.md", "expect": {…} }`
- `prompt.md` — the instruction fed to the agent.
- `repo/` *(optional)* — fixture files copied into the sandbox.
- `check.py` (import `checks_lib`) or `check.sh` (gets `$SANDBOX` + `$TASK_DIR`) — exit 0 = pass.

## Known constraint

agent-ops's prompts are Claude-shaped (triage wants JSON, review wants a
`### Summary` heading the live `post_review.py` parses). The eval's task prompts
are deliberately representative/simplified to test the *capability*; a candidate
that scores well here but formats differently may still need prompt tuning for the
live parsers. See the harness cookbook section. This bench is the *go/no-go gate*,
not a guarantee of drop-in output compatibility.
