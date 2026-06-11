# Migration: agent-ops → Olympus

This mechanism was renamed **agent-ops → Olympus**
(see [pantheon.md](pantheon.md) for the rename and the agent→deity mapping).
This page answers one question: **if your repo already uses the mechanism, what
breaks — and what do you change?**

Short answer: **a wrapper pinned to a pre-rename tag keeps working unchanged.**
You only do the edits below when you *re-pin* to an Olympus-named release.

## Impact by how you pinned

Consumers touch the mechanism in exactly one place: `uses:
Netis/agent-ops/.github/workflows/<x>.yml@<ref>` in their wrapper workflows
(plus their own `.agent-ops.json`). What happens depends on `<ref>`:

| You pinned to… | What happens after the rename | What to do |
|---|---|---|
| **A pre-rename tag** (`@v0.2.0`) — the documented, recommended way | **Nothing breaks.** That tag's content is frozen at the old (agent-ops-named) code, and GitHub permanently redirects the old `Netis/agent-ops` `uses:` path to `Netis/olympus`. The old code reads your old `.agent-ops.json` — fully self-consistent. | Nothing now. Migrate only when you choose to upgrade to an Olympus-named tag. |
| **A moving ref** (`@main`, a branch) — an anti-pattern the README warns against | **Drifts on the next run.** You'll pull post-rename HEAD, whose loader looks for `.olympus.json`; your file is still `.agent-ops.json`, so config silently falls back to built-in defaults (label names, gate thresholds, bot login, build command all revert) → wrong behavior, not a clean error. | Migrate now (below), or pin to a tag. |
| **Upgrading to an Olympus tag** (`@v0.3.0`+) | The new code expects the new names. | Do the full migration below before bumping. |

The redirect is a courtesy, not a contract: it lapses the moment anyone creates
a new repo at the old `Netis/agent-ops` path. Treat it as a grace period, not a
permanent alias.

## heron specifically

heron is **not a consumer yet** — it still runs its own in-tree
`scripts/agent-bot/*` + `.github/workflows/*` (the roadmap's standing dogfood
target is to *replace* those with pinned Olympus wrappers). So the rename's
impact on heron today is **zero**. When heron onboards as consumer #1, it
onboards straight to the Olympus names — no migration debt. This is the whole
point of doing the rename now, at zero live consumers.

## The mapping (when you do migrate)

| Legacy (agent-ops) | New (Olympus) | Where |
|---|---|---|
| `Netis/agent-ops` | `Netis/olympus` | wrapper `uses:` |
| `agent_ops_ref:` | `olympus_ref:` | wrapper input |
| `.agent-ops.json` | `.olympus.json` | your policy file (rename it) |
| `schema/agent-ops.schema.json` | `schema/olympus.schema.json` | `$schema` ref |
| `AGENT_OPS_*` | `OLYMPUS_*` | env overrides in workflows |
| `MARA_*` | `ARGUS_*` | systemd observer env |
| `self-hosted,agent-ops` | `self-hosted,olympus` | runner label + `runs-on` |
| default bot/agent names `vivi` / `wiwi` / `mara` | `themis` / `hephaestus` / `argus` | only if you used the defaults |

Not in any file, so a linter can't catch it: **the review bot's GitHub
account.** `agents.review_bot_login` names a real account; rename or
re-provision it and update `AUTO_MERGE_TEAM` / any allowlists that reference it.

## Check your repo

Run the migration linter in your repo root — it prints exactly what to change
and exits non-zero if anything remains:

```bash
bash <(curl -fsSL \
  https://raw.githubusercontent.com/Netis/olympus/main/scripts/lint/check-legacy-naming.sh)
```

The same linter runs in Olympus's own CI as a regression guard, so the
mechanism never silently grows the old names back.
