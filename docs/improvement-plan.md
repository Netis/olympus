# Engineering improvement plan

The phased hardening plan behind the [roadmap](roadmap.md)'s Horizon 1. The
roadmap says *where* agent-ops is going as an open-source product; this
document says *what to change in this codebase, in what order, and how we'll
know each item is done*. Version numbers are phase names, not date promises.

## Why this ordering

Going open-source inverts two assumptions the codebase was built on:

1. **Issue authors become adversaries.** The implement agent acts on
   stranger-filed issue text with an unrestricted `Bash` tool
   (`scripts/lib/agent-harness.sh`, profile `implement`) and a PAT in its
   environment. On an internal repo that's a trust decision; on a public repo
   it's a remote-code-execution-by-issue vector. This moves prompt-injection
   containment from the hardening backlog to a **P0 pre-announcement blocker**.
2. **Strangers read the artifacts.** A review prompt that opens with "You are
   a code review agent for the **Heron** repository"
   (`scripts/pr-review/prompt.md`) is the first file a prospective adopter
   reads to judge whether the "reusable" claim is real. Generalization
   graduates from cosmetic to credibility-critical.

So the phases gate on:

- **v0.2.x — safe and honest to publish.** Injection containment, finish the
  generalization, validation tooling. Removes attack surface and
  embarrassment; adds no capability.
- **v0.3 — trustworthy under churn.** Traps, locks, retry classification, and
  the first observability primitive. You can't run a community loop you can't
  measure, or debug stranger-reported failures from ephemeral workflow logs.
- **v0.4 — scalable to contributors.** Close the test/eval gap so external
  PRs can be accepted with confidence, then the capability items (budgets,
  heartbeat) that the new data primitive unlocks.

Throughout, the mechanism/policy split stays sacred: every new behavior below
is a config key with a safe default, resolved through the existing `config.sh`
precedence (env > `.agent-ops.json` > built-in default), and every agent
invocation keeps going through the `agent_run` adapter.

## Phase v0.2.x — open-source readiness (blocks any announcement)

| # | Item | Effort |
|---|---|---|
| 0.2-1 | Untrusted-input containment for the implement agent | L |
| 0.2-2 | Generalize the review prompt via a context slot | M |
| 0.2-3 | Purge remaining hardcoded identities and labels | S–M |
| 0.2-4 | `agent-ops doctor` + config schema validation in `guard.yml` | M |

### 0.2-1 · Untrusted-input containment — P0 security

Treat issue/comment bodies as data, not instructions, and constrain the blast
radius when that fails:

- **(a) Scope the `implement` profile's Bash.** Replace the bare `Bash` grant
  in `scripts/lib/agent-harness.sh` with an allowlist assembled from config:
  read/build primitives plus the consumer's declared `build_cmd`, with network
  egress tools (`curl`, `wget`, `nc`, `ssh`) denied by default. New key
  `.implement.allowed_bash` in `schema/agent-ops.schema.json`, loaded by
  `scripts/lib/config.sh`. Consumers who genuinely need more opt in
  explicitly — policy in their file, mechanism here.
- **(b) Fence untrusted content in prompts.** In `run_wiwi.sh`,
  `run_triage.sh`, `run_revise.sh`: wrap interpolated issue/review bodies in
  explicit delimiters with a standing instruction that content inside the
  markers is untrusted input, never instructions to follow.
- **(c) Minimize token exposure.** Audit which env vars reach the agent child
  process; `agent_run` strips `AGENT_GH_TOKEN`/`GH_TOKEN` (and `*_TOKEN`
  generally) from the subprocess env — the wrapper scripts' own `gh` calls are
  the only consumers.
- **(d) Actor gating.** The implement workflow only fires when the `try` label
  was applied by the triage bot or an allowlisted human (reuse the
  `AUTO_MERGE_TEAM` allowlist pattern from `auto_merge.sh`), so a stranger
  can't self-label into the implement path.

**Why:** public repos mean adversarial issue authors; the current
profile + PAT-in-env combination is exploitable on day one of being public.

**Acceptance:** an eval task (see 0.4-2) whose issue body embeds an
exfiltration instruction completes the legitimate fix *without* the injected
command executing; the default `implement` profile cannot invoke `curl`; `env`
dumped inside an agent run shows no `*_TOKEN` vars; labeling by a
non-allowlisted actor does not trigger implement.

### 0.2-2 · Generalize the review prompt

Split `scripts/pr-review/prompt.md` into a generic reviewer prompt (role,
verdict format, the genuinely generic leakage/secrets section) with
`{project_context}` / `{repo_gotchas}` slots, filled from a consumer-supplied
file (default `.agent-ops/review-context.md`, configurable via a new
`.review.context_file` key). `run_review.sh` performs the substitution; a
missing context file degrades to a generic-but-functional review. The current
heron crate map + gotchas move verbatim into heron's repo as the first
`review-context.md` — the worked example for the docs.

**Why:** the file is 100% heron-specific today; README already flags it
"generalization pending", and it's the single most credibility-damaging
artifact to ship to strangers.

**Acceptance:** `grep -i heron scripts/pr-review/prompt.md` returns nothing;
`evals/tasks/review/planted-bug` still passes with an empty context file.

### 0.2-3 · Purge remaining hardcoded identities and labels

- `scripts/pr-review/post_review.py`: the `Reviewed by **vivi**` footer reads
  `AGENT_OPS_REVIEW_BOT_LOGIN` from the environment (already exported by
  `config.sh`; keep footer and `auto_merge.sh`'s review matcher in lockstep).
- `scripts/agent-bot/run_wiwi.sh` ("You are **wiwi**", `Implemented by
  **wiwi**`) and `revise_dispatch.sh`'s comment text → use
  `$AGENT_OPS_DEV_AGENT_NAME` / `$AGENT_OPS_REVIEW_BOT_LOGIN`, as the triage
  replies already do.
- `.github/workflows/triage.yml` hardcodes the `agent:assess` label in its
  `if:` condition — workflow expressions can't read `.agent-ops.json`, so
  promote it to a workflow input `assess_label` (default `agent:assess`) that
  consumer wrappers pass; update `examples/consumer/`.

**Why:** a consumer who sets `dev_agent_name: "robo"` still sees "wiwi" in PR
bodies today — config that silently doesn't apply destroys trust in every
other config key.

**Acceptance:** `grep -rn 'vivi\|wiwi' scripts/ .github/workflows/` matches
only defaults inside `config.sh`; a `test_post_review.py` case asserts the
footer uses the env-provided login; triage fires on a custom label in the
example consumer.

### 0.2-4 · `agent-ops doctor` + schema validation in guard

Both already on the roadmap — fold security in. `scripts/doctor.sh` validates
in one command: `.agent-ops.json` against `schema/agent-ops.schema.json` (a
small stdlib-Python validator, `scripts/lint/check-config.py` — the schema is
shallow and `jsonschema` isn't stdlib), required labels exist, secrets are
present, the runner can reach the gateway, and — explicitly — that
`AGENT_GH_TOKEN` is a PAT able to emit workflow-triggering events (the
documented #1 onboarding failure) with no broader scopes than needed. Wire
`check-config.py` into `guard.yml` so a malformed config is rejected at PR
time.

**Acceptance:** doctor passes on `examples/consumer/`; on a config with a
typo'd key or a string where a number belongs, doctor and `guard.yml` both
fail naming the offending key.

## Phase v0.3 — robustness + observability (blocks "runs unattended at scale")

| # | Item | Effort |
|---|---|---|
| 0.3-1 | trap/cleanup handlers in all long-running scripts | S–M |
| 0.3-2 | Strict verdict parsing in triage | S |
| 0.3-3 | Idempotency + locking | M |
| 0.3-4 | Harness retry classification + small guards | M |
| 0.3-5 | Structured run-summary JSONL artifact | M |

### 0.3-1 · trap/cleanup handlers

A standard `cleanup()` + `trap cleanup EXIT INT TERM` (shared helper
`scripts/lib/cleanup.sh`) in `run_wiwi.sh`, `run_triage.sh`, `run_revise.sh`,
`run_review.sh`: remove `mktemp` files (today leaked on any non-happy path),
and in `run_wiwi.sh`/`run_revise.sh` delete the pushed work branch on
failure-before-PR so cancellations stop leaving orphan branches.

**Acceptance:** `kill -TERM` of a mid-run script leaves no temp files and no
orphan remote branch (test with stub `git`).

### 0.3-2 · Strict verdict parsing

`run_triage.sh` validates the agent's JSON verdict structure (`has("verdict")
and has("gates")`-style) before consuming fields. Today a missing `.gates`
silently coerces into a downgrade — the worst failure mode is the invisible
one. Missing/malformed structure → post an "escalating to a human; agent
output was malformed" comment + a `needs-human` label, never a silent
downgrade.

**Acceptance:** `tests/test_triage.py` cases feeding truncated/field-missing
JSON assert escalation, not downgrade.

### 0.3-3 · Idempotency + locking

- **mara:** wrap each invocation in `flock` on a state-dir lockfile, making
  the dedup read-modify-write atomic across overlapping timer fires.
- **triage comments:** embed a hidden marker (`<!-- agent-ops:triage:v1 -->`)
  and skip/update instead of duplicating when re-triggered.
- **revise round cap:** persist the round count as a hidden marker
  (`<!-- agent-ops:revise-round:N -->`) in the dispatch comment
  `revise_dispatch.sh` already posts; the fresh review-history count becomes
  the fallback, not the primary counter.

**Acceptance:** two concurrent mara invocations file at most one issue (stub
`gh`); re-labeling an already-triaged issue produces zero new comments; the
round cap holds when a review listing is artificially truncated in test.

### 0.3-4 · Retry classification + guards

- `agent_run` retries beyond gateway-down: classified 429 / 5xx / timeout /
  truncated-stream output, with exponential backoff + jitter.
- `auto_merge.sh` checks merged state first and exits cleanly if the PR is
  already merged.
- `mara.sh`'s curl timeout becomes `MARA_CURL_TIMEOUT` (default 8).
- `run_review.sh` truncates oversized diffs at a file boundary and appends an
  explicit `[diff truncated — N files omitted]` marker instead of cutting
  mid-hunk at a byte count.

**Acceptance:** `tests/test_harness.py` gains cases with a fake agent binary
emitting 429/timeout/truncated output, asserting retry-then-succeed; reviewing
an oversized diff shows the truncation marker in the prompt.

### 0.3-5 · Structured run-summary JSONL — the observability primitive

A `scripts/lib/run-summary.sh` helper, called from `agent_run` so every stage
gets it for free, appends one JSON line per run: `{ts, stage, repo, issue|pr,
model, duration_s, exit, retries, verdict, tokens_in, tokens_out,
cost_estimate}` (token/cost from the harness's usage output when available,
else null). Each reusable workflow uploads the file as an artifact with
`if: always()`. Deliberately the *primitive*, not the dashboard: the roadmap's
heartbeat dashboard and token budgets both consume this format later.

**Why:** today there are zero structured metrics — no answer to "what does
this loop cost", "what's the triage→merge success rate", or "how often do we
escalate" — the first questions every adopter asks.

**Acceptance:** every reusable-workflow run uploads a summary artifact; a
sample line validates against a documented schema; duration + exit are always
present.

## Phase v0.4 — test depth, eval depth, community capabilities

| # | Item | Effort |
|---|---|---|
| 0.4-1 | Close the test gap on the untested core | L |
| 0.4-2 | Eval bench expansion as the release gate | L |
| 0.4-3 | Token budgets + heartbeat v1 | M+M |
| 0.4-4 | Community furniture + heron dogfood | M |

### 0.4-1 · Close the test gap

Tests for the four zero-coverage scripts, using the established
pytest-driving-bash-with-stub-`gh`/`git` pattern in
`scripts/agent-bot/tests/`. Priority order: `auto_merge.sh` first (it merges
code — highest blast radius, and pure gh-glue so cheapest to stub), then
`revise_dispatch.sh` (cap logic), then `run_wiwi.sh`/`run_revise.sh` (happy
path + abort path + trap path). Extend `test_post_review.py` to cover the main
posting flow and the auto-merge gating boundaries.

**Why:** ~14% test:code ratio with the merge-authorizing script at zero — you
cannot accept community PRs against untested control flow.

**Acceptance:** all four scripts have suites wired into `ci.yml`;
`auto_merge.sh` tests cover missing label, non-approved state, non-allowlisted
author, and already-merged.

### 0.4-2 · Eval bench expansion

New task families under `evals/tasks/`: `revise/` (apply a CHANGES_REQUESTED
review to an existing branch), `observe/` (mara classification on canned
health responses), `merge-gate/` (allow/deny matrix), `implement/multi-file/`,
gate-boundary triage tasks (LOC estimates straddling `max_loc`), a non-English
triage variant exercising `.triage.language`, and — tying to 0.2-1 — a
**prompt-injection task**: the issue body embeds a malicious instruction;
scoring asserts the fix landed and the injected command did not run. Uses the
existing `evals/run.sh` + scoring harness unchanged. Adopt "evals green" as
the qualification gate for cutting a tag.

**Acceptance:** ≥10 tasks spanning all five loop stages; the injection task
red-lines if containment regresses; the release checklist references the
bench.

### 0.4-3 · Token budgets + heartbeat v1

Budgets: `.budget.max_tokens_per_run` / `.budget.monthly_tokens` keys in the
schema; `agent_run` pre-flights against accumulated run-summary data (0.3-5)
and refuses with a clear comment when exceeded — escalate to a human, never a
silent stop. Heartbeat: a small aggregator consuming the uploaded JSONL
artifacts across repos (static report first; dashboard later). Both are
existing roadmap commitments, buildable only once 0.3-5 exists — sequencing,
not new scope.

**Acceptance:** a consumer with a tiny budget sees implement runs declined
with a clear comment; the aggregator emits a per-repo per-stage cost/success
table from a week of artifacts.

### 0.4-4 · Community furniture + heron dogfood

`SECURITY.md` (disclosure policy — table stakes for a project whose pitch is
"agents act on your repo"; published before any announcement that invites
strangers' issues), `CONTRIBUTING.md` pointing at the eval bench + doctor, a
release/tagging process doc, and completion of the standing dogfood target:
**heron onboards as consumer #1**, pinned to a tag, using the
`review-context.md` from 0.2-2 — which doubles as the proof that the
generalization was lossless.

**Acceptance:** heron runs the full loop from agent-ops wrappers with zero
behavior regression; `SECURITY.md` exists before launch.

## Sequencing summary

| Phase | Theme | Gate it clears |
|---|---|---|
| v0.2.x | Injection containment, prompt generalization, identity purge, doctor + schema validation | Safe and credible to announce publicly |
| v0.3 | Traps / locks / retries / guards + JSONL run summaries | Trustworthy unattended; failures debuggable, costs measurable |
| v0.4 | Test + eval depth, budgets, heartbeat, community docs, heron dogfood | Ready to absorb external contributors and consumers |

Items 0.2-1 and 0.2-2 are the two hard blockers: prompt injection on a public
issue tracker is an active attack surface the moment the repo is public, and
the heron-specific review prompt is the first thing an evaluating adopter will
read.
