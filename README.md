# agent-ops

**A reusable, multi-repo autonomous software-quality mechanism.** Triage,
implement, review, auto-merge, and observe — driven by LLM agents on your own
runners, wired into any repo through reusable GitHub workflows and a single
per-repo config file.

This is the agent-ops loop, extracted from the [heron](https://github.com/Netis/heron)
project (where it was built and hardened against real production incidents) so
the **mechanism** lives in one versioned place and each repo supplies only its
**policy** (`.agent-ops.json`).

```
issue filed
   │  label: agent:assess (or just open it)
   ▼
TRIAGE ─ investigates + reproduces ─► warm maintainer reply (in the reporter's language)
   │       └─ 5 gates pass ─► label: agent:try
   ▼
IMPLEMENT (dev agent) ─ branch · code · build+test green ─► DRAFT PR (auto-agent)
   ▼
CI (yours) ──► REVIEW (bot) ─ structured review ─┬─ APPROVE ─► gated auto-merge
   │                                              └─ CHANGES ─► REVISE ─► (loop)
   ▼
OBSERVE (prod) ─ sustained-failure detection ─► scrubbed, deduped incident issue ─► (back to triage)

GUARD (every PR): leakage / secret-reference / secret-value linters — no LLM
```

## Mechanism vs. policy

The whole point of the extraction:

| | Lives in | Versioned | Example |
|---|---|---|---|
| **Mechanism** | this repo (`Netis/agent-ops`) | yes — tag `v0.2.0` | the triage gate logic, the warm-reply composer, the auto-merge gate, the observer's confirm-debounce, the hygiene linters |
| **Policy** | the consumer's `.agent-ops.json` | with the consumer | gate thresholds, label names, build command, reply language, the review bot's login, the service health URL |

Upgrade the mechanism once (bump the pinned tag) and every consuming repo
benefits. No copy-pasted scripts to drift.

## What a repo gets by onboarding

- **Triage** that actually investigates every issue and replies like a warm
  human maintainer — *in the language the issue was filed in* — whether or not
  the issue qualifies for auto-implementation. The 5-gate verdict only decides
  *auto-dispatch*, never whether the reporter deserves a thoughtful answer.
- **A dev agent** that implements well-scoped issues unattended and opens a
  draft PR only when the repo's own build+test command is green.
- **A review bot** that reviews every PR after CI and, for agent-authored PRs,
  gates auto-merge (APPROVE + allowlisted author) or dispatches an automated
  revision pass (CHANGES_REQUESTED) up to a round cap, then escalates to a human.
- **A production observer** that files a scrubbed, deduplicated incident issue
  on a *sustained* failure (a confirm-debounce filters deploy/restart blips) —
  closing the loop back to triage.
- **Hygiene gates** that block the mechanical PR-failure classes that motivated
  this whole system: internal-infra leakage, unprovisioned secret references,
  and insane secret values.

## Components & maturity (v0.1)

| Component | Script | Reusable workflow | v0.1 status |
|---|---|---|---|
| Triage | `agent-bot/run_triage.sh` | `triage.yml` | **fully config-driven + unit-tested** |
| Config loader | `lib/config.sh` | — | **unit-tested** |
| Hygiene gates | `lint/check-*.sh` | `guard.yml` | **generic + unit-tested (leakage)** |
| Observer | `agent-bot/mara.sh` | `observe.yml` | **generalized + unit-tested** |
| Dev agent | `agent-bot/run_wiwi.sh` | `implement.yml` | ported; build/branch/labels config-driven · cosmetic prompt strings pending |
| Review bot | `pr-review/*` | `review.yml` | ported; review-bot login + labels config-driven |
| Revise | `agent-bot/run_revise.sh` | `revise.yml` | ported; review-bot login config-driven |

"Pending" = a deliberate follow-up to deepen as the second repo onboards (see
[docs/roadmap.md](docs/roadmap.md), with the codebase-level breakdown in
[docs/improvement-plan.md](docs/improvement-plan.md)); the runtime-critical
coupling (what label, which bot, which branch, which build command) is already
config-driven.

## Onboard a repo in 4 steps

1. **Prerequisites** (once per org): a self-hosted runner that can reach your
   model gateway and has `claude`, `jq`, `python3`; org/repo secrets
   `LITELLM_BASE_URL`, `LITELLM_API_KEY`, `LITELLM_NO_PROXY` (optional),
   `AGENT_GH_TOKEN` (a PAT — see [docs/prerequisites.md](docs/prerequisites.md)
   for the *why*), and optionally `AUTO_MERGE_TEAM`. **Need that runner?** The
   [cookbooks](docs/cookbooks/) have copy-paste recipes for
   [self-hosting](docs/cookbooks/self-hosting.md),
   [DigitalOcean](docs/cookbooks/digitalocean.md), and
   [AWS](docs/cookbooks/aws.md). (The **guard** gate needs no runner at all.)
2. **Drop in `.agent-ops.json`** — copy [`examples/consumer/.agent-ops.json`](examples/consumer/.agent-ops.json)
   and edit the gates / build command / labels / observer for your repo. Every
   field is optional ([schema](schema/agent-ops.schema.json)).
3. **Add the thin wrappers** from [`examples/consumer/.github/workflows/`](examples/consumer/.github/workflows/)
   (`triage`, `implement`, `pr-review`, `pr-revise`, `guard`, `observe`). Each
   is ~15 lines that `uses: Netis/agent-ops/.github/workflows/<x>.yml@v0.2.0`
   and passes your runner labels.
4. **Pin the version**: keep the `@v0.2.0` on the `uses:` and the
   `agent_ops_ref: v0.2.0` input in lockstep, so the workflow YAML and the
   scripts it clones are the same release.

See [docs/setup.md](docs/setup.md) for the full walkthrough and
[docs/config-reference.md](docs/config-reference.md) for every config field.

## Design notes baked in (hard-won in heron)

- **PAT fan-out.** Labels/dispatches that must trigger downstream workflows use
  `AGENT_GH_TOKEN` (a real-user PAT), because GitHub suppresses workflow events
  emitted under the default `GITHUB_TOKEN`. Get this wrong and the loop silently
  never starts.
- **Confirm-debounce on the observer.** A single failed health poll is never
  filed — a deploy/restart looks identical to an outage for ~10s. Only an
  all-polls-failed run opens an incident.
- **Scrub before filing.** The observer masks IPs, home paths, URL hosts, and
  `user@host` tokens out of every incident body. The hygiene gate enforces the
  same rule on tracked files. **No internal infrastructure in any outbound
  surface** — issues, PR bodies, reviews, commits.
- **The gate is about *auto-dispatch*, not worth.** Triage answers `skip` /
  `needs_info` issues just as warmly and just as investigated as `do` ones.

## Development

```bash
python3 scripts/agent-bot/tests/test_triage.py   # reply composition
python3 scripts/agent-bot/tests/test_mara.py      # observer debounce
python3 scripts/agent-bot/tests/test_config.py    # config loader
bash    scripts/lint/check-leakage.sh             # hygiene (self)
shellcheck scripts/agent-bot/*.sh scripts/lib/*.sh scripts/lint/*.sh
```

CI (`.github/workflows/ci.yml`) runs all of the above — agent-ops eats its own
dog food.

## License

Apache-2.0.
