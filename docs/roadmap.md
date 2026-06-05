# Roadmap

agent-ops v0.1 extracts the heron loop into a reusable, config-driven mechanism.
What's deliberately staged for later — and the principle behind the staging.

## Principle

Decouple **runtime-critical** coupling first (what would make the loop *behave
wrong* on another repo): the label names, the review bot's identity, the default
branch, the build command, the gate thresholds, the observer's readiness check.
All of that is config-driven and tested in v0.1.

Leave **cosmetic** coupling (strings that are merely heron-flavored but don't
change behavior) for when the second repo onboards and gives a real second data
point — avoids guessing the right abstraction from a sample size of one.

## v0.1 — done

- `config.sh` loader + `.agent-ops.json` schema (unit-tested).
- Triage: fully config-driven (gates, labels, language, names), warm
  maintainer-voice replies, reproduce-before-`do`; unit-tested composer.
- Observer (mara): generalized DOWN + optional config-driven readiness/"parked"
  detection; confirm-debounce; scrub; unit-tested.
- Hygiene gates (leakage / secret-ref / secret-value) as a reusable `guard.yml`.
- Reusable workflows for the whole loop (triage / implement / review / revise /
  observe / guard) + consumer wrapper examples.
- Self-CI (shellcheck + the three test suites + leakage).

## v0.2 — deepen on second-repo onboarding

- Dev agent (`run_wiwi.sh`) & revise: replace remaining cosmetic agent-name
  strings in prompts/comments with `dev_agent_name`; parameterize the resume
  hints fully.
- Review (`pr-review/*`): surface the review bot's display name + footer from
  config; confirm the reviewer prompt carries no heron-specific assumptions.
- A `agent-ops doctor` script: validate a consumer's `.agent-ops.json`, secrets,
  runner reachability, and label existence in one command.
- JSON-schema validation wired into `guard.yml` (reject a malformed config at
  PR time).

## v0.3+ — capabilities

- Optional staging-soak / deploy-gate workflows (the heron pre-prod chain),
  with the soak *content* supplied per-repo and only the **gate shape**
  (a `staging-soaked`-style status token) provided by agent-ops.
- A heartbeat/ops dashboard aggregating agent last-seen across repos.
- Per-repo token-budget guards.

## Dogfooding target

Make **heron itself a consumer of agent-ops** — replace its in-tree
`scripts/agent-bot/*` + `.github/workflows/*` with the wrappers here, pinned to a
tag. heron becoming consumer #1 with zero behavior regression is the proof the
extraction is lossless.
