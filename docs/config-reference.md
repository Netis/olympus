# Config reference — `.agent-ops.json`

The single source of per-repo policy. Validated by
[`schema/agent-ops.schema.json`](../schema/agent-ops.schema.json). Every field
is optional; an omitted value uses the **default** shown. With no file at all,
the agents behave exactly as the defaults (back-compatible).

Precedence for any value: an exported **env var** > the **config file** > the
**built-in default**.

## `project`
| Field | Default | Meaning |
|---|---|---|
| `name` | — | Human-readable project name. |
| `default_branch` | `main` | Branch the dev agent forks from and PRs target. |

## `agents`
| Field | Default | Meaning |
|---|---|---|
| `review_bot_login` | `vivi` | GitHub login (or a marker in the review body) used by auto-merge / revise to find the review bot's verdict. |
| `dev_agent_name` | `the dev agent` | Display name for the implementer (commit author, log lines). |

## `labels`
| Field | Default | Meaning |
|---|---|---|
| `assess` | `agent:assess` | Manual re-triage trigger. |
| `try` | `agent:try` | Triage adds this on `do`; starts the dev agent. |
| `skip` | `agent:skip` | Mutes re-triage. |
| `auto_agent` | `auto-agent` | Marks dev-agent PRs for the auto-merge / revise gates. |

## `triage.gates`
| Field | Default | Meaning |
|---|---|---|
| `max_loc` | `300` | Diff-size ceiling for unattended auto-implementation. |
| `max_files` | `10` | File-count ceiling. |
| `contained_areas` | `one module, docs, or one workflow` | Joined into the "contained" gate text — the areas a change may touch and still qualify. |
| `test_hint` | `a unit / integration test` | What a deterministic test looks like here (shown to triage + dev agent). |

## `triage.language`
| Value | Behavior |
|---|---|
| `auto` (default) | Reply in the **same language the reporter used**. |
| a code/name (`en`, `zh`, `日本語`, …) | Always reply in that language. |

## `implement`
| Field | Default | Meaning |
|---|---|---|
| `build_cmd` | — | The build + test command the dev agent must get green before opening a PR (e.g. `make build && make test`, `cargo test`, `npm test`). |

## `observer`
| Field | Default | Meaning |
|---|---|---|
| `service_name` | `the service` | Name used in incident text. |
| `health_url` | — | Health endpoint mara polls. (For the systemd path, set via the unit's `MARA_HEALTH_URL` instead.) |
| `repo` | — (required to file) | `owner/name` the incident issue is filed on. |
| `labels` | `incident` | Comma-separated issue labels. |
| `readiness.jq` | — | Optional jq filter over the health JSON for "parked" (up-but-not-working) detection. Omit → DOWN-only. |
| `readiness.expect` | `true` | Value the jq filter must equal; anything else = parked. |

## `model`
| Field | Default | Meaning |
|---|---|---|
| `model` | `claude-3-5-sonnet-20241022` | Model name sent to the gateway. |

## Example

See [`examples/consumer/.agent-ops.json`](../examples/consumer/.agent-ops.json)
for a complete, commented-by-structure config.
