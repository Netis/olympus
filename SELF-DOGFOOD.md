# agent-ops eats its own dog food

agent-ops is the mechanism repo, but it can also be a **consumer of itself** —
the ultimate validation that the multi-repo loop works. This documents what's
active now and how to activate the rest.

## What's active now (zero infra)

- **`self-guard.yml`** — runs this repo's own `guard.yml` leakage gate on every
  PR + main push. GitHub-hosted ubuntu, no secrets, no runner. This is the first
  real bite of dog food: a leak in agent-ops's own tracked files (or a
  mis-scoped `scripts/lint/leakage-allowlist.txt`) fails the PR.
- **`ci.yml`** — the pre-existing shellcheck self-CI (unchanged).
- **`.agent-ops.json`** — agent-ops's own policy (gates, labels, the
  shellcheck+pytest `build_cmd` wiwi would run, review bot `vivi`, dev agent
  `wiwi`). Read by the agentic surfaces once activated.

## What's dormant (wired, awaiting infra)

`self-triage.yml`, `self-implement.yml`, `self-review.yml`, `self-revise.yml`
are committed but gated on the repo **variable** `SELF_DOGFOOD_ENABLED`. Until
it's `true`, they fire on the matching event but the job is **skipped** (a grey
check — never a red failure). They use `uses: ./...` so they always run the
current branch's reusable workflows + scripts.

`observe` (mara) is **N/A** for agent-ops: it has no deployed prod service to
poll. `.agent-ops.json`'s `observer.health_url` is intentionally empty.

## Activation (when you're ready)

1. **Provision a self-hosted runner** labelled `self-hosted,agent-ops` with the
   `claude` CLI + `jq` + `python3`, reaching the model gateway. (Or change the
   `runner_labels` in the four `self-*.yml` wrappers to an existing shared label,
   e.g. `["self-hosted","heron"]`, if that runner is reachable from this repo.)
2. **Provision secrets** on `Netis/agent-ops` (Settings → Secrets):
   `LITELLM_BASE_URL`, `LITELLM_API_KEY`, `LITELLM_NO_PROXY` (optional),
   `AGENT_GH_TOKEN` (a **PAT**, not `GITHUB_TOKEN` — the loop needs to trigger
   label/dispatch/push events), and optionally `AUTO_MERGE_TEAM`.
3. **Flip the flag**: `gh variable set SELF_DOGFOOD_ENABLED --body true
   --repo Netis/agent-ops`. No file change needed; the wrappers stop skipping.
4. (For `self-revise`) the review loop dispatches the revise workflow by
   filename. Either rename `self-revise.yml` → `pr-revise.yml`, or set
   `AGENT_OPS_REVISE_WORKFLOW=self-revise.yml` in the runner environment.

To pause again, set the variable to anything but `true` (or delete it).

## Prerequisites detail

See `docs/prerequisites.md` for the full runner/secret contract — it's the same
one every consumer (including heron) uses.
