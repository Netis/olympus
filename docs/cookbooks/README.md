# Olympus cookbooks

Recipes for standing up the infrastructure a consumer repo needs to run the
Olympus loop. Pick a platform:

- [Self-hosting](./self-hosting.md) — your own box, VM, or hypervisor (libvirt /
  Proxmox / bare metal)
- [DigitalOcean](./digitalocean.md) — a Droplet
- [AWS](./aws.md) — an EC2 instance

> New to Olympus? Read [`../setup.md`](../setup.md) and
> [`../prerequisites.md`](../prerequisites.md) first. These cookbooks are the
> *platform-specific* half of that setup.

---

## Do you even need a runner?

| Surface | Needs a self-hosted runner? | Why |
|---|---|---|
| **guard** (leakage / secret hygiene) | **No** — runs on GitHub-hosted `ubuntu-latest` | Pure linters; only need the repo + the public internet. Free on public repos. |
| **triage, implement (hephaestus), review (themis), revise** | **Yes** | They run the `claude` CLI against a model endpoint. A GitHub-hosted runner can't reach a private/internal model gateway, and you usually don't want your API key on ephemeral cloud runners. |
| **observe (argus)** | A small box, **isolated from prod** | A systemd timer; see [`../../SELF-DOGFOOD.md`](../../SELF-DOGFOOD.md) and the observer notes in `setup.md`. |

So: if you only want the **guard** gate, you need **zero infrastructure** — just
add the `guard.yml` wrapper. Everything below is for the **agentic** surfaces.

---

## The model endpoint (decide this first)

Olympus's workflows read three secrets to reach the model. The names start
with `LITELLM_` for historical reasons — **it's just "an Anthropic-compatible
endpoint."** Three common choices:

| Choice | `LITELLM_BASE_URL` | `LITELLM_API_KEY` | model |
|---|---|---|---|
| **Anthropic API directly** (simplest) | `https://api.anthropic.com` | your `sk-ant-…` key | a real Claude model id (the workflow default `claude-3-5-sonnet-20241022`, or pass a newer one via the `model` input) |
| **OpenAI / Azure OpenAI / any OpenAI-compatible** (gpt-4o, local vLLM, …) | a **gateway** you run, e.g. `http://your-litellm:4000` | the gateway's key | the name the gateway maps to your OpenAI model (see below) |
| **A gateway you run, generally** (LiteLLM / other proxy) | `https://your-gateway/v1` | the gateway's key | whatever name the gateway maps |

The `claude` CLI on the runner reads `ANTHROPIC_BASE_URL` / `ANTHROPIC_API_KEY`,
which the workflows set from these secrets. **Pointing straight at the Anthropic
API is the least moving parts** — start there.

### Using OpenAI (or any non-Anthropic) models

The agent surfaces run **Claude Code (`claude`)**, which speaks the **Anthropic
Messages API** (`POST /v1/messages`). OpenAI speaks a *different* schema
(`/v1/chat/completions`), so you **cannot point `LITELLM_BASE_URL` straight at
`api.openai.com`** — the shapes don't match.

The bridge is a **proxy that exposes an Anthropic-format endpoint and translates
to OpenAI**. [LiteLLM](https://docs.litellm.ai) is the canonical one. Minimal
setup:

```yaml
# litellm-config.yaml — map the model name Claude Code asks for → an OpenAI model
model_list:
  - model_name: claude-3-5-sonnet-20241022      # what ANTHROPIC_MODEL sends
    litellm_params:
      model: openai/gpt-4o                       # route to OpenAI
      api_key: os.environ/OPENAI_API_KEY
  # Azure: model: azure/<deployment>, api_base/api_version/api_key
  # local/other OpenAI-compatible: model: openai/<name>, api_base: http://…/v1
```

```bash
pip install 'litellm[proxy]'
OPENAI_API_KEY=sk-… litellm --config litellm-config.yaml --port 4000
# LiteLLM serves the Anthropic-format endpoint at /v1/messages on :4000
```

Then set the secrets to the **proxy**, not OpenAI directly:

```bash
gh secret set LITELLM_BASE_URL --repo <OWNER>/<REPO> --body "http://your-litellm:4000"
gh secret set LITELLM_API_KEY  --repo <OWNER>/<REPO> --body "<your LiteLLM master key>"
```

Keep `ANTHROPIC_MODEL` (the wrapper `model` input) equal to the `model_name` you
mapped (`claude-3-5-sonnet-20241022` above), or set both to a name of your
choosing — it's just the routing key into `model_list`. Run the proxy on the
runner box (or anywhere both the runner and OpenAI can reach), and verify with
the official LiteLLM docs since exact flags evolve.

> Same pattern covers **Azure OpenAI**, **Bedrock**, **Gemini**, local **vLLM /
> Ollama**, etc. — anything LiteLLM can route. Claude Code only ever sees the
> Anthropic shape; the proxy does the rest.

---

## Swapping the agent CLI (harness)

The section above changes the **model** behind Claude Code. This changes the
**agent CLI itself**. Set the `harness` block in `.olympus.json`.

### codex (built-in)

```jsonc
{
  "harness": {
    "kind": "codex",
    "model": "gpt-5",
    "proxy": "http://proxy.internal:8888"   // optional; staging/testing egress
  }
}
```

Olympus builds the `codex exec` invocation itself and maps each surface onto
codex's sandbox — **read-only** for triage/review, **workspace-write** for the
implement/revise surface (the only one allowed to edit files). `health_probe`
defaults **off** for codex. The runner needs the `codex` CLI installed and
`OPENAI_API_KEY` in env (add it as a repo secret or set it on the box).

**Proxy (staging/testing).** Where codex can't reach its model backend directly,
give it an egress proxy: either `harness.proxy` above, or — to keep an internal
IP out of committed config — the **`HARNESS_PROXY` repo secret** (it wins when
set). Olympus exports it as `HTTPS_PROXY`/`HTTP_PROXY`/`ALL_PROXY` for the codex
child **only**; the claude harness is never proxied (it uses the internal
gateway). See [security.md](../security.md) — codex has no tool deny-list, so
run it in a trusted environment and rely on the proxy + OS-level egress control.

### custom (any other CLI)

```jsonc
{
  "harness": {
    "kind": "custom",
    "command": "aider --model {model} --message-file {prompt_file} > {out}",
    "model": "gpt-5",
    "health_probe": false
  }
}
```

Olympus fills the placeholders per run: `{model}` `{prompt_file}` (the agent's
instructions) `{out}` (where to write the agent's output) `{tools}` (the
allow-listed tools for that surface) `{write}` (`true` only for the implement
surface — your harness should refuse edits otherwise) `{max_turns}`. Set
`health_probe: false` unless your harness talks to an OpenAI-compatible
`/v1/models` endpoint. `harness.proxy` works for `custom` too.

Omit the `harness` block entirely to use the built-in **`claude`** harness
(the default; identical to every existing consumer).

> ⚠️ **Known constraint — prompt shape.** Olympus's prompts are written for
> Claude Code's behaviour: **triage** expects the agent to emit a JSON object
> (`verdict` / `reply` / …) and **review** expects a `### Summary` heading that
> `post_review.py` parses. A non-claude harness may format its output
> differently and need prompt tuning to satisfy those parsers — Olympus does
> **not** normalise output across harnesses. **Qualify a candidate CLI with the
> `evals/` bench (the harness qualification suite) before wiring it into the live loop:**
> `evals/run.sh --harness codex --model gpt-5 --repeat 3 --label codex`.

---

## Staging soak before merge

By default a review APPROVE auto-merges a simple PR (allowlisted author) and
leaves everything else for a human. Turn on `.testing` to insert a **staging
soak** for bigger changes: a **simple** PR (within `fast_path`) keeps the
auto-merge fast path, while a **complex** PR is deployed to your testing
environment, soaked, and — on a clean soak — labeled `staging-soaked` for a
human to merge. Olympus never auto-merges a soaked PR.

```jsonc
{
  "testing": {
    "enabled": true,
    "deploy_cmd": "make deploy-staging",      // $PR_NUMBER is available
    "health_cmd": "curl -fsS http://localhost:8080/healthz",
    "soak_minutes": 30,
    "teardown_cmd": "make teardown-staging",
    "fast_path": { "max_loc": 40, "max_files": 3, "areas": ["docs/"] }
  }
}
```

1. Add the `pr-soak.yml` wrapper (see `examples/consumer/.github/workflows/`)
   to your repo's default branch — `auto_merge.sh` / `post_review.py` dispatch
   it by that name (override with `OLYMPUS_SOAK_WORKFLOW`).
2. Its `timeout_minutes` must exceed `soak_minutes` (the job stays alive polling
   health for the whole window).
3. The `staging-soaked` / `soak-failed` labels are auto-created on first use.

Olympus orchestrates the soak (deploy → poll health → label); your repo owns
what "deploy" and "healthy" mean. Soak only runs for PRs that would otherwise
auto-merge (same author trust), so untrusted PRs are unchanged.

---

## Sizing

| Workload | Suggested box |
|---|---|
| triage / review only (read + comment) | 2 vCPU / 4 GB |
| + implement (hephaestus runs your `build_cmd`) | size for **your build** — hephaestus needs your project's full toolchain + enough RAM/CPU to compile. A Rust/heavy build often wants 4 vCPU / 8–16 GB. |

The runner also needs **whatever `.olympus.json` `implement.build_cmd`
invokes** installed (your compiler, test tooling, etc.) — that's project-specific
and not covered here.

---

## Shared steps (referenced by every platform recipe)

Once you have a Linux box (Ubuntu 22.04/24.04 assumed) the rest is identical.

### A. Bootstrap the box

```bash
sudo apt-get update
sudo apt-get install -y git jq python3 curl ca-certificates

# Claude Code — the `claude` CLI the agent scripts call.
# See https://docs.claude.com/en/docs/claude-code for the current installer.
# Native install:
curl -fsSL https://claude.ai/install.sh | bash
#   …or via npm if you prefer:  npm install -g @anthropic-ai/claude-code
claude --version    # verify

# (implement only) also install your project's build toolchain here.
```

### B. Register the GitHub Actions runner

Get a registration token: repo **Settings → Actions → Runners → New self-hosted
runner**, or:

```bash
gh api -X POST repos/<OWNER>/<REPO>/actions/runners/registration-token -q .token
```

Then on the box (as a non-root user, e.g. `runner`):

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
# grab the latest release tarball from https://github.com/actions/runner/releases
RUNNER_VER=2.319.1
curl -fsSL -o runner.tar.gz \
  https://github.com/actions/runner/releases/download/v${RUNNER_VER}/actions-runner-linux-x64-${RUNNER_VER}.tar.gz
tar xzf runner.tar.gz

./config.sh --url https://github.com/<OWNER>/<REPO> \
  --token <REGISTRATION_TOKEN> \
  --name olympus-runner \
  --labels self-hosted,olympus \
  --unattended --replace

sudo ./svc.sh install "$USER"   # install as a systemd service so it survives reboots
sudo ./svc.sh start
```

> **Label** = whatever you put in your wrapper workflows' `runner_labels`
> (`'["self-hosted","olympus"]'` here). Keep them in sync. You can register one
> runner at the **org** level and share it across repos instead of per-repo.

### C. Secrets + wrappers

```bash
# model endpoint (see the table above)
gh secret set LITELLM_BASE_URL --repo <OWNER>/<REPO> --body "https://api.anthropic.com"
gh secret set LITELLM_API_KEY  --repo <OWNER>/<REPO> --body "sk-ant-…"

# a PAT — NOT GITHUB_TOKEN. The loop must trigger label/dispatch/push events,
# which GITHUB_TOKEN-authored events are suppressed from. Scope: repo + workflow.
gh secret set AGENT_GH_TOKEN   --repo <OWNER>/<REPO> --body "<PAT>"

# optional
gh secret set LITELLM_NO_PROXY --repo <OWNER>/<REPO> --body "<hosts to bypass a proxy>"
gh secret set AUTO_MERGE_TEAM  --repo <OWNER>/<REPO> --body "alice,bob"   # auto-merge allowlist
```

Then add `.olympus.json` (see [`../config-reference.md`](../config-reference.md))
and the thin wrapper workflows (copy from
[`../../examples/consumer/`](../../examples/consumer/)), making sure each
wrapper's `runner_labels` matches your runner's label.

### D. Smoke test

1. Open an issue → the triage workflow runs on your runner and replies.
2. (implement) add the `agent:try` label → hephaestus branches, builds, opens a DRAFT PR.
3. Push a PR → after CI, the review workflow posts a review.

If a job sits **queued** forever, the runner isn't online or its label doesn't
match. If it fails at the `claude` step, check the model secrets + that the box
can reach `LITELLM_BASE_URL`.

---

## Security notes

- The runner holds your **model API key** and a **GitHub PAT** — treat the box as
  sensitive. Prefer a dedicated box per trust boundary; don't co-host it with
  untrusted workloads.
- Self-hosted runners on **public** repos can run code from forked PRs. Olympus's
  reusable workflows only act on **same-repo** PRs by design, but review your
  repo's `pull_request` vs `pull_request_target` settings before exposing a runner.
- Keep the box patched; the runner auto-updates itself, the OS does not.
