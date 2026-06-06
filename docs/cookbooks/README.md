# agent-ops cookbooks

Recipes for standing up the infrastructure a consumer repo needs to run the
agent-ops loop. Pick a platform:

- [Self-hosting](./self-hosting.md) — your own box, VM, or hypervisor (libvirt /
  Proxmox / bare metal)
- [DigitalOcean](./digitalocean.md) — a Droplet
- [AWS](./aws.md) — an EC2 instance

> New to agent-ops? Read [`../setup.md`](../setup.md) and
> [`../prerequisites.md`](../prerequisites.md) first. These cookbooks are the
> *platform-specific* half of that setup.

---

## Do you even need a runner?

| Surface | Needs a self-hosted runner? | Why |
|---|---|---|
| **guard** (leakage / secret hygiene) | **No** — runs on GitHub-hosted `ubuntu-latest` | Pure linters; only need the repo + the public internet. Free on public repos. |
| **triage, implement (wiwi), review (vivi), revise** | **Yes** | They run the `claude` CLI against a model endpoint. A GitHub-hosted runner can't reach a private/internal model gateway, and you usually don't want your API key on ephemeral cloud runners. |
| **observe (mara)** | A small box, **isolated from prod** | A systemd timer; see [`../../SELF-DOGFOOD.md`](../../SELF-DOGFOOD.md) and the observer notes in `setup.md`. |

So: if you only want the **guard** gate, you need **zero infrastructure** — just
add the `guard.yml` wrapper. Everything below is for the **agentic** surfaces.

---

## The model endpoint (decide this first)

agent-ops's workflows read three secrets to reach the model. The names start
with `LITELLM_` for historical reasons — **it's just "an Anthropic-compatible
endpoint."** Two common choices:

| Choice | `LITELLM_BASE_URL` | `LITELLM_API_KEY` | model |
|---|---|---|---|
| **Anthropic API directly** (simplest) | `https://api.anthropic.com` | your `sk-ant-…` key | a real Claude model id (the workflow default `claude-3-5-sonnet-20241022`, or pass a newer one via the `model` input) |
| **A gateway you run** (LiteLLM / OpenAI-compatible proxy) | `https://your-gateway/v1` | the gateway's key | whatever name the gateway maps |

The `claude` CLI on the runner reads `ANTHROPIC_BASE_URL` / `ANTHROPIC_API_KEY`,
which the workflows set from these secrets. **Pointing straight at the Anthropic
API is the least moving parts** — start there.

---

## Sizing

| Workload | Suggested box |
|---|---|
| triage / review only (read + comment) | 2 vCPU / 4 GB |
| + implement (wiwi runs your `build_cmd`) | size for **your build** — wiwi needs your project's full toolchain + enough RAM/CPU to compile. A Rust/heavy build often wants 4 vCPU / 8–16 GB. |

The runner also needs **whatever `.agent-ops.json` `implement.build_cmd`
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
  --name agent-ops-runner \
  --labels self-hosted,agent-ops \
  --unattended --replace

sudo ./svc.sh install "$USER"   # install as a systemd service so it survives reboots
sudo ./svc.sh start
```

> **Label** = whatever you put in your wrapper workflows' `runner_labels`
> (`'["self-hosted","agent-ops"]'` here). Keep them in sync. You can register one
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

Then add `.agent-ops.json` (see [`../config-reference.md`](../config-reference.md))
and the thin wrapper workflows (copy from
[`../../examples/consumer/`](../../examples/consumer/)), making sure each
wrapper's `runner_labels` matches your runner's label.

### D. Smoke test

1. Open an issue → the triage workflow runs on your runner and replies.
2. (implement) add the `agent:try` label → wiwi branches, builds, opens a DRAFT PR.
3. Push a PR → after CI, the review workflow posts a review.

If a job sits **queued** forever, the runner isn't online or its label doesn't
match. If it fails at the `claude` step, check the model secrets + that the box
can reach `LITELLM_BASE_URL`.

---

## Security notes

- The runner holds your **model API key** and a **GitHub PAT** — treat the box as
  sensitive. Prefer a dedicated box per trust boundary; don't co-host it with
  untrusted workloads.
- Self-hosted runners on **public** repos can run code from forked PRs. agent-ops's
  reusable workflows only act on **same-repo** PRs by design, but review your
  repo's `pull_request` vs `pull_request_target` settings before exposing a runner.
- Keep the box patched; the runner auto-updates itself, the OS does not.
