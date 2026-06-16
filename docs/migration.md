# Migration: agent-ops → Olympus

This mechanism was renamed **agent-ops → Olympus**
(see [pantheon.md](pantheon.md) for the rename and the agent→deity mapping).
This page answers one question: **if your repo already uses the mechanism, what
breaks — and what do you change?**

Short answer: **GitHub Actions does not follow repo renames for `uses:`, so
every consumer must change the `uses:` owner to `Netis/olympus`** — even one
pinned to a pre-rename tag. For a pinned-tag consumer that owner edit is the
*only* change needed (the tag travelled with the repo; keep `.agent-ops.json`
and `agent_ops_ref`). The rest of the migration below applies only when you
*re-pin* to an Olympus-named release.

## Impact by how you pinned

Consumers touch the mechanism in exactly one place: `uses:
Netis/agent-ops/.github/workflows/<x>.yml@<ref>` in their wrapper workflows
(plus their own `.agent-ops.json`). What happens depends on `<ref>`:

| You pinned to… | What happens after the rename | What to do |
|---|---|---|
| **A pre-rename tag** (`@v0.2.0`) — the documented, recommended way | **The `uses:` reference breaks.** GitHub Actions does **not** follow repository renames when resolving `uses:` — the run fails with `repository not found`. (git/web/API *do* redirect, which is why the reusable workflow's own inner `actions/checkout` of `Netis/agent-ops` still clones — but the outer `uses:` is resolved first, and that resolution is not redirected.) | **Change the `uses:` owner** to `Netis/olympus`, keeping the same `@tag`. The tag travelled with the repo, so `Netis/olympus@v0.2.0` is the same frozen code; keep your `.agent-ops.json` and the `agent_ops_ref` input exactly as they are. |
| **A moving ref** (`@main`, a branch) — an anti-pattern the README warns against | The `uses:` reference breaks the same way (no rename redirect), **and** once you fix the owner you'll pull post-rename HEAD, whose loader looks for `.olympus.json`; your file is still `.agent-ops.json`, so config silently falls back to built-in defaults (label names, gate thresholds, bot login, build command all revert) → wrong behavior, not a clean error. | Repoint the owner **and** do the full migration below (or pin to a tag). |
| **Upgrading to a post-rename Olympus tag** (a tag cut after the rebrand, once one exists) | The new code expects the new names. | Repoint the owner **and** do the full migration below before bumping. |

Be precise about *which* redirect: GitHub redirects **git, web, and API** access
from the old `Netis/agent-ops` path — that (and only that) is what keeps the
inner `actions/checkout` working. It is a courtesy, not a contract: it lapses
the moment anyone creates a new repo at the old path, so **never recreate
`Netis/agent-ops`.** The Actions `uses:` resolver is **not** redirected at all,
which is why the owner edit above is mandatory rather than optional.

## heron specifically

heron **is** consumer #1: its `.github/workflows/` wrappers delegate to the
mechanism via pinned tags — `guard`/`implement`/`triage`/`revise` at `@v0.2.0`
and `review` at `@v0.3.1` — plus a `.agent-ops.json` policy file. Every one of
those tags predates the rebrand, so the rename hits heron exactly as the
pre-rename-tag row above describes: the five `uses: Netis/agent-ops/...@tag`
lines fail to resolve until their owner segment becomes `Netis/olympus` (same
tags; `.agent-ops.json` and `agent_ops_ref` stay). Tracked in
[Netis/heron#164](https://github.com/Netis/heron/issues/164).

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
