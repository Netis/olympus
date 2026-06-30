# Config reference — `.olympus.json`

The single source of per-repo policy. Validated by
[`schema/olympus.schema.json`](../schema/olympus.schema.json). Every field
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
| `review_bot_login` | `themis` | GitHub login (or a marker in the review body) used by auto-merge / revise to find the review bot's verdict. |
| `dev_agent_name` | `the dev agent` | Display name for the implementer (commit author, log lines). |

## `labels`
| Field | Default | Meaning |
|---|---|---|
| `assess` | `agent:assess` | Manual re-triage trigger. |
| `try` | `agent:try` | Triage adds this on `do`; starts the dev agent. |
| `skip` | `agent:skip` | Mutes re-triage. |
| `auto_agent` | `auto-agent` | Marks dev-agent PRs for the auto-merge / revise gates. |
| `discussing` | `agent:discussing` | Marks an issue in an active triage discussion (verdict `discuss`); a reporter reply re-runs triage. |
| `staging_soaked` | `staging-soaked` | Added to a PR that cleared its staging soak — a human may merge it. |
| `soak_failed` | `soak-failed` | Added to a PR whose staging soak (deploy/health) didn't hold. |

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

## `triage.auto_dispatch`
When a `do` verdict may auto-start the **unattended** dev agent. See [security.md](security.md).
| Value | Behavior |
|---|---|
| `trusted` (default) | Auto-dispatch only issues whose author has write/maintain/admin access. Others get the warm reply + a maintainer control to dispatch by hand (human-in-the-loop against injected issue text). |
| `all` | Auto-dispatch any author. Internal/trusted repos only. |
| `never` | Never auto-dispatch; a maintainer always adds the `try` label. |

## `triage.max_discussion_rounds`
| Field | Default | Meaning |
|---|---|---|
| `max_discussion_rounds` | `4` | Max back-and-forth rounds triage will hold with a reporter (each round = one triage reply) before it stops asking and loops in a human. The discussion loop fires on `issue_comment` from the reporter or a trusted maintainer (verdict `discuss`); this caps cost and prevents ping-pong. Requires the consumer's `triage.yml` wrapper to subscribe to `issue_comment`. |

## `implement`
| Field | Default | Meaning |
|---|---|---|
| `build_cmd` | — | The build + test command the dev agent must get green before opening a PR (e.g. `make build && make test`, `cargo test`, `npm test`). |
| `allow_network` | `false` | If `false`, the implement/revise agent's harness denies direct network egress (`curl`/`wget`/`ssh`/…) so a prompt-injected issue can't exfiltrate. Set `true` only if your build genuinely needs the agent to reach the network. Not a full sandbox — see [security.md](security.md). |

## `testing`
Optional pre-merge **staging soak**. **Omit the block (or set `enabled: false`)
to keep the original behavior**: a review APPROVE auto-merges a simple PR and
leaves everything else for a human. When enabled, an APPROVE-d PR is classified —
a **simple** PR (within `fast_path`) keeps the auto-merge fast path; a **complex**
PR is deployed to your testing environment, soaked, then labeled `staging-soaked`
for a human to merge (Olympus never auto-merges a soaked PR). Olympus orchestrates
the soak; your repo supplies the deploy + health commands. Requires the consumer
`pr-soak.yml` wrapper. Applies to both agent and human PRs (gated by the same
auto-merge trust). See [cookbooks](cookbooks/README.md#staging-soak-before-merge).

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Turn the soak gate on. |
| `deploy_cmd` | — | Run on the checked-out PR head to deploy it to the testing environment (e.g. `make deploy-staging`). `$PR_NUMBER` is available. |
| `health_cmd` | — | Polled repeatedly during the soak; non-zero exit = unhealthy. Omit to fall back to an HTTP 2xx check against `observer.health_url`. |
| `soak_minutes` | `30` | How long the PR must stay healthy before it's marked `staging-soaked`. Must be under the `pr-soak` workflow's `timeout_minutes`. |
| `teardown_cmd` | — | Optional; run after the soak (pass or fail) to tear the deployment down. |
| `fast_path.max_loc` | `triage.gates.max_loc` | A "simple" PR changes ≤ this many lines (additions + deletions). |
| `fast_path.max_files` | `triage.gates.max_files` | A "simple" PR changes ≤ this many files. |
| `fast_path.areas` | — | If set, a simple PR may touch **only** these path prefixes. Empty = areas not considered. |

## `observer`
| Field | Default | Meaning |
|---|---|---|
| `service_name` | `the service` | Name used in incident text. |
| `health_url` | — | Health endpoint argus polls. (For the systemd path, set via the unit's `ARGUS_HEALTH_URL` instead.) |
| `repo` | — (required to file) | `owner/name` the incident issue is filed on. |
| `labels` | `incident` | Comma-separated issue labels. |
| `readiness.jq` | — | Optional jq filter over the health JSON for "parked" (up-but-not-working) detection. Omit → DOWN-only. |
| `readiness.expect` | `true` | Value the jq filter must equal; anything else = parked. |

## `model`
| Field | Default | Meaning |
|---|---|---|
| `model` | `claude-3-5-sonnet-20241022` | Model name sent to the gateway. Overridden by `harness.model` if set. |

## `harness`
Which agent CLI drives the surfaces. **Omit the whole block for the built-in
`claude` (Claude Code) harness** — that's back-compatible with every existing
consumer.

| Field | Default | Meaning |
|---|---|---|
| `harness.kind` | `claude` | `claude` = built-in Claude Code. `codex` = built-in OpenAI Codex (`codex exec`). `custom` = run `harness.command`. |
| `harness.command` | — | **custom only.** A shell command template run per agent invocation. Placeholders: `{model}` `{prompt_file}` `{out}` `{tools}` `{write}` `{max_turns}`. e.g. `aider --model {model} --message-file {prompt_file} > {out}`. |
| `harness.model` | — | Model id for this harness; overrides `.model`. For codex/custom, the model the CLI is told to use (e.g. `gpt-5`). |
| `harness.proxy` | — | **non-claude only.** Egress proxy URL exported as `HTTPS_PROXY`/`HTTP_PROXY`/`ALL_PROXY` for the harness child, e.g. `http://proxy.internal:8888`. codex reaches its backend through it on staging/testing where a direct connection is blocked; the claude harness is never proxied (it uses the internal gateway). Prefer the `HARNESS_PROXY` repo secret to keep an internal IP out of committed config. |
| `harness.health_probe` | `true` (`false` for `codex`) | Poll the gateway's OpenAI-compatible `/v1/models` before each run (and to detect mid-run outages). Defaults off for codex (its backend isn't OpenAI-compatible); set explicitly to override. |

For the built-in **codex** harness, put `OPENAI_API_KEY` on the runner (or as a
repo secret) and set `harness.proxy` / the `HARNESS_PROXY` secret on staging/testing.
See [docs/cookbooks](cookbooks/README.md#swapping-the-agent-cli-harness) for the
codex walkthrough + the prompt-shape constraint, and [security.md](security.md)
for the egress note (codex lacks the claude harness's tool deny-list).

## Example

See [`examples/consumer/.olympus.json`](../examples/consumer/.olympus.json)
for a complete, commented-by-structure config.
