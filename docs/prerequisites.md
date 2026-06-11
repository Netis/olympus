# Prerequisites

Olympus runs LLM agents on **your** infrastructure. Before onboarding a repo,
have these in place — most are set once per org and shared.

## 1. A self-hosted runner the agents can use

The triage / implement / review / revise / observe jobs run on a self-hosted
runner (the hygiene `guard` job does **not** — it's GitHub-hosted). The runner
must have:

- network reach to your **model gateway** (a LiteLLM-style endpoint that accepts
  Anthropic-shaped requests and maps a model name onto your backend);
- the **`claude`** CLI, plus **`jq`**, **`python3`**, **`git`**, **`gh`**, and
  `curl` on `PATH`;
- enough disk for a checkout + a working tree per concurrent job.

A **shared org runner pool** is the enabler for multi-repo: point every repo's
wrappers at the same labels (e.g. `'["self-hosted","agent-pool"]'`). Scale the
pool, not the per-repo config.

## 2. Secrets (org-level recommended)

| Secret | Used by | Notes |
|---|---|---|
| `LITELLM_BASE_URL` | all LLM jobs | model gateway base URL |
| `LITELLM_API_KEY` | all LLM jobs | gateway key |
| `LITELLM_NO_PROXY` | all LLM jobs | optional; hosts to bypass an HTTP proxy for |
| `AGENT_GH_TOKEN` | label/dispatch/merge/clone | a **PAT** (see below) |
| `AUTO_MERGE_TEAM` | implement / review | optional CSV of logins eligible for auto-merge |

Set once at the org and grant the repos that onboard, or set per-repo.

## 3. Why `AGENT_GH_TOKEN` must be a PAT (not `GITHUB_TOKEN`)

GitHub deliberately **suppresses workflow-triggering events emitted under the
default `GITHUB_TOKEN`** to prevent recursive workflow storms. The Olympus
loop depends on exactly those events:

- triage adds `agent:try` → that `labeled` event must start the implement job;
- the dev agent's **push** must re-trigger your `ci` → `pr-review`;
- review dispatches `pr-revise` via `gh workflow run`.

All of these are no-ops under `GITHUB_TOKEN`. So they run under
`AGENT_GH_TOKEN`, a PAT owned by a real user (or a machine account) with
`repo` + `workflow` scope. The same token is used to admin-merge (it needs
branch-protection bypass) and to clone `Netis/olympus` if you keep it private.

> This is the single most common onboarding failure. If "nothing happens" after
> triage labels an issue, check that `AGENT_GH_TOKEN` is set and is a PAT.

## 4. Keep Olympus reachable to the runner

The reusable workflows `git clone` `Netis/olympus` at the pinned ref to get
the scripts. If you keep Olympus **public**, nothing extra is needed (it holds
no secrets — all infra lives in the consumer's secrets). If **private**, the
checkout uses `AGENT_GH_TOKEN`, which must have read access.

## 5. Cost & governance

Every issue and PR spends model tokens + runner minutes. Across many repos this
adds up, and auto-merge raises blast radius. Sensible defaults for a new repo:

- leave `AUTO_MERGE_TEAM` **empty** at first (every PR waits for a human);
- keep humans on the review-approval until you trust the loop in that repo;
- watch runner saturation before fanning out to more repos.
