# Olympus — the rename and the pantheon

agent-ops is being renamed **Olympus**. The metaphor is exact: the *mechanism*
lives on the mountain (this repo, versioned by tag), while each consumer repo
supplies only its mortal *policy* (`.agent-ops.json`). The gods act in the
mortals' repos, but they are governed from Olympus — upgrade the mountain
once and every realm benefits.

This document is the naming plan: the function → deity mapping, the rename
scope, and why the rename must happen **now** (it is item
[0.2-0 of the improvement plan](improvement-plan.md)).

## The pantheon

Each loop surface gets the god whose domain matches its function — not the
most famous god, the *right* one.

| Surface | Deity | Today | Why this deity |
|---|---|---|---|
| Triage | **Hermes** | (unnamed) | Herald and messenger; god of language, boundaries, and guidance. Triage speaks in the reporter's own language, investigates, and guides every issue to its destination — including the ones it doesn't dispatch. |
| Implement + Revise | **Hephaestus** | wiwi | The smith. Works the forge unattended (branch, code, build+test) and delivers a draft. Revise is the same god: CHANGES_REQUESTED sends the piece *back to the forge*. |
| Review | **Themis** | vivi | Goddess of divine law, order, and the scales. Renders a structured verdict on every PR and holds the gate to auto-merge — judgment, not opinion. |
| Observer | **Argus** | mara | Argus Panoptes, the hundred-eyed watchman who never sleeps. Polls production health and raises a scrubbed, deduplicated alarm only on *sustained* failure. (Not an Olympian — the watchman metaphor is too exact to pass up. Purists may prefer Helios, who sees everything; we prefer the eyes.) |
| Guard linters | **Cerberus** | (unnamed) | The gatekeeper at the threshold. Deliberately **no LLM** — and fittingly no god either: a mechanical three-headed dog that does not negotiate about leaked IPs, secret references, or insane secret values. |
| `doctor` | **Asclepius** | (planned) | The healer. Diagnoses a consumer's config, secrets, labels, and runner reachability in one pass. |
| Evals bench | **The Labours** | evals/ | The Labours of Heracles: a candidate harness must complete the trials before it may join the pantheon. Apotheosis through qualification — objective, binary, no judge. |
| Fleet CLI (H3) | **Atlas** | (planned) | Bears the whole fleet on his shoulders: `atlas bump`, `atlas doctor`, `atlas drift` across an org's repos. |
| Demo repo (H2) | **Agora** | (planned) | The public square where mortals come to watch the gods work: file an issue, watch the loop. |

Naming conventions: deity names are the **default display names** in
config (`agents.dev_agent_name: "hephaestus"`, `agents.review_bot_login:
"themis"`, …) — consumers can still override them, as today; the
mechanism/policy split is untouched. Script names follow
(`run_hephaestus.sh`, `argus.sh`); surface names in workflows stay functional
(`triage.yml`, `review.yml`) so a consumer never needs the mythology to
operate the loop.

## Rename scope — two layers

### Brand layer (cheap, cosmetic)

- Repo name `Netis/agent-ops` → `Netis/olympus`; README, docs, cookbooks.
- Default agent display names in `config.sh`: `wiwi` → `hephaestus`,
  `vivi` → `themis`, plus naming the previously-unnamed triage voice
  (`hermes`) and observer (`mara.sh` → `argus.sh`).
- Prompt role lines and PR/comment footers (via the existing config
  variables — this rides on [improvement plan 0.2-3](improvement-plan.md),
  which makes those strings config-driven anyway).

### Mechanism layer (breaking — which is exactly why it happens now)

- Consumer wrapper references: `uses: Netis/agent-ops/.github/workflows/...`
  → `Netis/olympus/...` and the `agent_ops_ref` input → `olympus_ref`.
  (GitHub Actions does **not** redirect renamed-repo `uses:` paths — a pinned
  consumer must change the owner segment by hand; see [migration.md](migration.md).)
- Config file `.agent-ops.json` → `.olympus.json`; schema
  `schema/agent-ops.schema.json` → `schema/olympus.schema.json`.
- Env prefixes: `AGENT_OPS_*` → `OLYMPUS_*`; `MARA_*` → `ARGUS_*`.
- Operational, outside this repo: the review bot's GitHub account
  (`agents.review_bot_login` is a real login) needs renaming or
  re-provisioning, and `AUTO_MERGE_TEAM` / allowlists that reference it
  updated.

**No compatibility shims.** The consumer count is zero today — heron has not
onboarded, self-dogfood is dormant. A dual-read layer (old + new config
filename, old + new env prefixes) would be code we write only to delete. The
entire argument for renaming *now* is that we never have to write it.

## Timing

The rename is **item 0.2-0** — before everything else in v0.2.x, and a hard
prerequisite of [roadmap H1.5](roadmap.md) (heron onboards as consumer #1).
Every consumer that onboards before the rename turns part of the mechanism
layer into a breaking change; at zero consumers the rename is a single
self-contained PR plus one repo-settings change.

## Acceptance

- `grep -rni 'agent-ops\|agent_ops\|wiwi\|vivi\|mara' scripts/ .github/ schema/ examples/ evals/`
  matches nothing (docs may keep historical mentions in this file and the
  changelog).
- Self-CI green after the rename (shellcheck, unit tests, leakage gate,
  evals checks).
- `examples/consumer/` wrappers reference `Netis/olympus@<tag>` and
  `.olympus.json`, and a doctor run against the example passes.
- The old repo URL redirects (GitHub-side, for git/web/API — **not** Actions
  `uses:`) — verified once after the settings change.
