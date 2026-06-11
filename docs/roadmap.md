# Roadmap

agent-ops is heading somewhere specific: an **open-source, self-hosted,
model-agnostic, policy-as-config closed loop** for autonomous repo
maintenance — issue triage → implement → review → revise → **production
observation feeding back into triage**, plus no-LLM hygiene guards.

The competitors each own a fragment: vendor coding agents (GitHub Copilot
coding agent, Cursor background agents) are vendor-locked issue→PR pipelines;
issue resolvers (sweep.dev, OpenHands resolver) stop at the PR, without review
gating or production feedback. Nobody else ships the *whole loop* as versioned
mechanism + per-repo policy, runnable on your own runners against any gateway.
Three defensible edges, and every roadmap item below either widens the
adoption funnel into the loop or sharpens one of them:

1. **The full closed loop** — including the prod-observe → triage feedback no
   one else closes.
2. **No lock-in** — any model (pluggable harness with an objective
   qualification bench), eventually any forge.
3. **Policy-as-config** — one versioned mechanism, per-repo `.agent-ops.json`
   policy, upgrade by bumping a tag.

This document is the product roadmap (three horizons, no dates — version
numbers are phase names). The codebase-level breakdown with acceptance
criteria lives in the [engineering improvement plan](improvement-plan.md).

## Sequencing principles

- **Safety before promotion.** The implement agent executes work derived from
  stranger-filed issue text. Until that is contained
  ([improvement plan 0.2-1](improvement-plan.md)), there is no demo repo, no
  launch post, no invitation for public issues.
- **Reduce infrastructure before adding features.** The #1 funnel killer is
  "self-hosted runner + gateway + PAT + five secrets + four manual labels"
  before any payoff. A zero-infra tier converts strangers; features convert
  nobody who never onboards.
- **Design seams early, build adapters late.** Multi-forge adapters are
  Horizon 2, but the forge seam (all forge writes through one library, no new
  raw `gh` calls) starts in Horizon 1 — otherwise the refactor cost compounds
  monthly.
- **Dogfood is the credibility proof.** heron as consumer #1 and agent-ops's
  own self-loop (already wired, dormant behind `SELF_DOGFOOD_ENABLED`) precede
  any "use this" marketing.
- **Open-source core, fleet at the edge.** Single-repo and CLI-driven fleet
  tooling is in scope forever; persistent multi-tenant control planes are the
  natural future commercial layer and deliberately *not* promised in OSS
  scope (see Horizon 3).

## Horizon 1 — foundation & credibility (now → ~v0.3)

*A stranger can onboard safely in under 30 minutes, and we can prove the loop
works because we run it on ourselves.*

### 1.1 `agent-ops init` — one-command onboarding (subsumes `doctor`)

A single installer script: creates the four labels, copies/templates the
wrapper workflows with the current pinned tag stamped in both `uses:` and
`agent_ops_ref:` (killing the lockstep-by-hand failure), scaffolds a minimal
`.agent-ops.json`, then runs doctor mode — schema validation, secrets
presence, runner reachability, and an explicit test that `AGENT_GH_TOKEN` is a
PAT able to emit workflow-triggering events (the documented #1 onboarding
failure, today diagnosable only from prose).

**Success:** fresh repo with prerequisites in place → green smoke-test triage
reply in <30 minutes; doctor catches a mistaken `GITHUB_TOKEN` with an
actionable message instead of silence.

### 1.2 Zero-runner tier

A first-class mode where **triage + review + guard run on GitHub-hosted
runners against the Anthropic API directly** — one secret, zero
infrastructure. Implement/revise/observe stay self-hosted (write-heavy,
long-lived, repo-trusting execution). The installer offers "lite" (zero infra)
vs "full" (whole loop) profiles. This is the single largest friction cut
available: a stranger gets warm investigated triage replies and structured PR
reviews first, experiences the value, then graduates to the full loop —
and the read-mostly surfaces coming first is also the right trust story.

**Success:** a repo with only `ANTHROPIC_API_KEY` set gets a triage reply on
its first issue; lite onboarding measured at <15 minutes.

### 1.3 Trust tier 1: containment + approval gates for the implement agent

The open-sourcing security blocker
([improvement plan 0.2-1](improvement-plan.md)): a scoped tool surface for the
implement agent (no bare Bash, egress denied by default), token-stripped agent
subprocess env, untrusted-content fencing in prompts, and a
**maintainer-approval gate** — on a stranger-filed issue, triage may
*recommend* dispatch, never auto-dispatch; the `try` label only counts when
applied by the triage bot or an allowlisted human. Every agent action (label,
comment, push, merge) lands in a structured audit record linked from the PR.

**Gates all Horizon 2 promotion.**

**Success:** a red-team eval suite (injection-laced issues) passes — no
out-of-allowlist execution, no auto-dispatch on unapproved stranger issues;
a documented threat model in `docs/`.

### 1.4 Finish generalization + schema-in-guard + the forge seam

The original v0.2 items — de-heron the review prompt via a
`{project_context}` slot, purge remaining hardcoded identities/labels, wire
config-schema validation into `guard.yml`
([improvement plan 0.2-2/0.2-3/0.2-4](improvement-plan.md)) — **plus** the
seam: extract every forge write (`gh issue comment`, `gh pr merge`,
`gh workflow run`, …) into a single `scripts/lib/forge.sh`, enforced by a
self-CI lint rule ("no raw `gh` outside `lib/forge.sh`"). No adapters yet;
just stop deepening the coupling.

**Success:** zero heron-specific strings reachable from any prompt; a
malformed `.agent-ops.json` fails the PR in guard; raw `gh` outside the seam
is a CI failure.

### 1.5 Dogfood completion

The standing target: **heron becomes consumer #1** — its in-tree scripts
replaced by wrappers pinned to a tag, with zero behavior regression; that's
the proof the extraction is lossless. And once 1.3 lands, flip
`SELF_DOGFOOD_ENABLED` on this repo so agent-ops maintains itself in public.

**Success:** heron runs ≥4 weeks on a pinned tag with zero regression; ≥1
agent-authored PR merged into agent-ops by its own loop.

### 1.6 Eval expansion as the regression safety net

Grow the bench from 4 tasks to 10+ across all five loop stages — multi-file
implement, revise convergence, observer classification, merge-gate matrix,
gate boundaries, non-English triage, and the 1.3 injection suite
([improvement plan 0.4-2](improvement-plan.md), pulled forward as the H1
closer). Everything in later horizons changes prompts and glue; without
evals, every horizon is a regression lottery. "Evals green" becomes the tag
gate.

**Deliberately out of scope in H1:** multi-forge adapters (seam only — demand
sample size is one forge), telemetry (needs H2's privacy design), fleet
tooling (no fleet exists yet), staging-soak (fine to slip to H2/H3).

## Horizon 2 — adoption & ecosystem (~v0.4–0.5)

*Strangers arrive, succeed, extend, and stick around.* Entered only when H1's
trust tier has shipped.

### 2.1 Public demo repo + launch

`agent-ops-demo`: a small real service where the entire loop runs in public —
visitors file an issue and watch triage reply, the agent open a draft PR,
review gate it, and (on a synthetic outage) the observer file an incident.
"File an issue, watch the loop" as the call to action. Coordinated launch
(blog post, Show HN) only after 1.3 + 2.2 — a public demo is by construction
an adversarial-input magnet.

**Success:** the demo handles arbitrary public issues for a month without a
safety incident; ≥10 external repos onboard within a quarter of launch.

### 2.2 Community infrastructure & release discipline

`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` (disclosure policy —
mandatory for a product whose pitch includes "agents with write access"),
issue/PR templates, curated good-first-issues (cookbook gaps and eval tasks
are ideal), semver with a changelog and **migration notes per tag**, a
deprecation window for config fields, and release automation that cuts tags
only on green evals. Release discipline is doubly load-bearing here: every
consumer is pinned and bumps by hand.

**Success:** ≥5 external contributors merged; zero unannounced breaking
config changes; every tag ships migration notes.

### 2.3 Forge adapter layer: GitLab first

Build the adapter behind H1's seam: `forge.sh` dispatches to
`forge-github.sh` / `forge-gitlab.sh` (the ~10 verbs: read issue, comment,
label, open PR/MR, review, merge, dispatch, status), CI templates get a
GitLab `include:` equivalent of the reusable workflows, and agent prompts take
their forge-CLI vocabulary from config. GitLab self-managed users are
precisely the audience that wants self-hosted agents and that vendor coding
agents structurally cannot serve — a differentiation item, not just a
generality item. Gitea/Forgejo follow as community-contributed adapters
against a documented adapter contract + conformance checklist.

**Success:** the full loop (minus observe, already forge-agnostic) green on a
GitLab self-managed repo; the adapter contract documented well enough that a
Forgejo adapter arrives as an external PR.

### 2.4 Harness ecosystem

Promote `harness.kind: custom` into a qualification program: run `evals/`
against alternative agent CLIs, publish a scoreboard in-repo, document the
"qualified" thresholds, and ship a cookbook per qualified harness.
Model-agnosticism is a top-3 differentiator, and agent-ops is unusual in
having an *objective* bench to back the claim — a published scoreboard is also
organic marketing.

**Success:** ≥2 non-claude harnesses qualified and documented; a harness
regression is caught by the bench before a release ships it.

### 2.5 Opt-in telemetry & cost accounting (local-first)

Built on the run-summary primitive
([improvement plan 0.3-5](improvement-plan.md)): per-run structured records
(tokens, wall time, verdict, rounds-to-merge) stay as artifacts in the
consumer's own repo — **no central collection**. An `agent-ops stats` command
aggregates locally over a repo's history. Token budgets land on top: budget
exceeded → escalate to a human with a clear comment, never a silent stop. An
anonymous adoption beacon is strictly opt-in.

**Success:** every agent run produces a cost record; a consumer answers "cost
per merged PR last month" with one command.

### 2.6 Trust tier 2: graduated autonomy levels

Codify a named autonomy ladder in `.agent-ops.json`: **L0** triage-only →
**L1** implement with maintainer-gated dispatch → **L2** auto-dispatch, human
merge → **L3** gated auto-merge. The installer defaults new repos to L1;
promotion is a one-line config change; the audit trail annotates which level
authorized each action. This turns the prerequisites doc's prose advice
("leave `AUTO_MERGE_TEAM` empty at first") into enforceable, legible policy —
policy-as-config *is* the product, so the trust dimension becomes first-class
in it.

**Success:** the demo repo runs publicly at L2; the docs answer "what can the
agent do to my repo?" with a single table.

## Horizon 3 — scale & fleet (v1.0+)

*An org runs agent-ops on 50 repos and one platform engineer can operate it.*
v1.0 is declared when the contracts below carry stability guarantees — a trust
signal earned by H1/H2 discipline, not a feature release.

### 3.1 v1.0 stability contract

Freeze and document compatibility guarantees: the `.agent-ops.json` schema
(additive-only within 1.x), the forge adapter contract, reusable-workflow
inputs, and the harness command template — each with conformance tests. Orgs
pin 50 repos to these tags; the upgrade promise *is* the product at fleet
scale.

**Success:** a consumer upgrades 1.0→1.x fleet-wide with no wrapper edits
beyond the version bump.

### 3.2 `agent-ops fleet` CLI (OSS scope)

Stateless, CLI-driven, against a config-file-listed set of repos:

- `fleet bump` — opens version-bump PRs across N repos with migration notes
  inlined. The bump PRs flow through each repo's own review gate — the fleet
  feature is itself loop-shaped.
- `fleet doctor` — 1.1's doctor across the fleet.
- `fleet drift` — diffs each repo's `.agent-ops.json` against an org baseline
  policy and flags unauthorized divergence (e.g. a repo that quietly enabled
  L3 auto-merge).

Manual lockstep pinning at 50 repos is where adoption dies inside orgs; drift
detection is the governance story that lets a platform team say yes. No
server, no state — cleanly inside OSS scope.

**Success:** one command produces 50 reviewable bump PRs; a deliberately
drifted repo is flagged within one CI cycle.

### 3.3 Heartbeat & cost dashboard (static, OSS) — and the commercial boundary

Aggregate the 2.5 records into a static dashboard (scheduled workflow → JSON →
static page): per-repo agent last-seen, escalation rates, cost per merged PR,
observer incident counts. **Explicit boundary:** the OSS line stops at "static
aggregation of data the org already owns." A hosted multi-tenant control
plane (live dashboards, alerting, cross-org budget enforcement, SSO) is the
natural future commercial layer — stating the boundary now is honest signaling
that protects community trust later.

**Success:** a 50-repo org answers "which agents are silent, what did the
fleet spend, where are humans escalated most" from one self-hosted page.

### 3.4 Staging-soak gate shape + observer depth

The long-deferred pre-prod chain: a `staging-soaked`-style status token where
agent-ops provides only the **gate shape** and each repo supplies the soak
content. Plus observer maturation: multi-endpoint health, latency/error-budget
signals (not just DOWN), richer incident context for triage to consume. The
prod-observe → triage feedback loop is the moat; deepening it compounds
differentiation, and at fleet scale the observer is what makes auto-merge
defensible.

**Success:** ≥2 consumers gate deploys on soak; ≥1 documented incident
auto-filed → auto-triaged → auto-fixed → merged, end-to-end, no human code.

### 3.5 Multi-language ecosystem hardening

Cookbook presets and eval fixtures per major ecosystem (Node, Go, Rust, JVM,
Python): build-command recipes, test-hint conventions, ecosystem-specific
hygiene patterns — mostly community-contributed against an eval-fixture
template.

**Success:** the top five ecosystems each have a cookbook preset and a
passing eval fixture.

## Measurement

Instrumented from 2.5 onward; targets are directional, not promises.

| Metric | Definition | Healthy signal |
|---|---|---|
| Time-to-first-triage | onboard start → first triage reply | <30 min full, <15 min lite |
| Onboarding completion | `init` started → doctor green | PAT failure rate trending to ~0 |
| Auto-dispatch precision | `try` issues yielding a mergeable PR | rising per release |
| Auto-merge rate | agent PRs merged without human edits | rising *only* alongside a flat incident rate |
| Escalation rate | revise loops hitting the round cap | falling per release |
| Cost per merged PR | tokens + runner minutes per merged agent PR | published honestly; trending down |
| Rounds-to-merge | review→revise cycles per merged PR | median ≤2 |
| **Loop-closure count** | observer incident → merged fix, no human code | >0, then growing — the headline stat |
| Fleet pin freshness | % of fleet within one minor of latest | >90% with `fleet bump` |
| Ecosystem counts | external contributors, qualified harnesses, forge adapters | each growing per quarter |

## What each horizon sharpens

- **H1 — trustworthy by construction:** containment + approval gates + audit
  trail, the precondition for self-hosted agents on public repos, and a
  problem vendor agents treat as someone else's.
- **H2 — no lock-in, any model, any forge:** the GitLab adapter and harness
  scoreboard are claims the vendor agents structurally cannot copy.
- **H3 — the closed loop at fleet scale:** prod-observe feedback plus fleet
  governance is the territory between "coding agent" products and
  platform-engineering reality that nobody else occupies.
