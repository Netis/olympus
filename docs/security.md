# Security model

Olympus runs LLM agents that read issues/PRs and **write code, push branches,
and (optionally) merge** on your repo. This page states the threat model and the
controls, so an operator can reason about what the agents can and cannot do —
and what hardening is still the operator's job.

## Threat model

The defining assumption for a **public** repo: **issue and PR authors are
untrusted.** Anyone can file an issue, and its text flows into an agent. The two
highest-risk surfaces:

- **Implement / revise** (`hephaestus`) — runs work *derived from issue/review
  text* with broad shell + file-write tools. Untrusted text reaching a
  shell-wielding LLM is a remote-code-execution / exfiltration vector.
- **Triage** (`hermes`) — investigates untrusted text and posts public replies;
  a `do` verdict dispatches the implement agent.

Trusted, by contrast: the maintainers (repo write access), the runner, the model
gateway, and `.olympus.json` itself (committed by maintainers).

## Controls (defense in depth)

| Layer | Control | Where |
|---|---|---|
| **Authorization** | **Maintainer-dispatch gate.** A `do` verdict auto-dispatches the unattended agent only for authors with write/maintain/admin access; others get a warm reply + a maintainer control to dispatch by hand. A human reviews stranger issues before the agent acts. | `.triage.auto_dispatch` (`trusted`\|`all`\|`never`, default `trusted`) — `run_triage.sh` |
| **Prompt** | **Untrusted-input framing.** Every agent prompt states that issue/review text is data describing *what to change*, never instructions to obey, with the interpolated title fenced in explicit BEGIN/END UNTRUSTED markers. | `run_hephaestus.sh`, `run_triage.sh`, `run_revise.sh` |
| **Tools** | **Network egress denied.** The implement/revise agent runs with `--disallowed-tools` for `curl/wget/nc/ncat/netcat/telnet/ssh/scp/sftp/socat/ftp` + `mcp__*`. Deny beats the broad `Bash` allow and survives `bash -c` / `&&` / `;` / `|` wrappers. | `agent-harness.sh`; opt out with `.implement.allow_network` |
| **Credentials** | **Token stripping.** `GH_TOKEN`/`GITHUB_TOKEN`/`AGENT_GH_TOKEN`/`ADMIN_GH_TOKEN` are removed from the implement subprocess (it edits code + builds; the *driver* script makes the `gh` calls). Model-gateway creds are kept. | `agent-harness.sh` (`env -u`) |
| **Outbound hygiene** | **Guard linters (no LLM).** Leakage / secret-reference / secret-value gates keep internal IPs, machine paths, and key material out of every outbound surface (issues, PR bodies, reviews, commits). | `guard.yml`, `scripts/lint/check-*.sh` |
| **Blast radius** | Revise round cap → human escalation; per-issue/PR workflow concurrency; the observer scrubs incident bodies before filing. | `revise_dispatch.sh`, workflow `concurrency` |

A regression test for the combined prompt+tool defense lives at
`evals/tasks/implement/prompt-injection/` — an issue whose body embeds a
malicious instruction; it passes only if the legitimate fix lands **and** the
injected command does not run.

## Residual risks — NOT covered by the above

These need controls the operator owns at the OS / infrastructure layer:

- **Indirect network egress.** The deny-list blocks *direct* `curl`/`ssh`. It
  does **not** stop a build script, a package manager, or `python -c "..."` that
  shells out to the network. **Mitigation: run the implement/revise agent on a
  runner with an egress firewall that allows only the model gateway.** This is
  the single most important hardening step and the only complete fix for exfil.
- **Trusted-author assumption.** `auto_dispatch: trusted` trusts anyone with
  repo write access. A compromised or malicious maintainer account bypasses the
  dispatch gate. Scope write access accordingly.
- **Arbitrary build toolchain.** `build_cmd` runs whatever the consumer
  configured; a malicious `.olympus.json` (committed by a maintainer) is out of
  scope — config is part of the trusted base.
- **Model fallibility.** Prompt framing reduces, but cannot guarantee, that the
  agent ignores a cleverly injected instruction. The tool/network/credential
  controls are what bound the damage when framing fails.

## Operator hardening checklist

- **Egress-firewall the runner** to the model gateway only (closes indirect
  egress).
- Use a **dedicated, low-privilege, ideally ephemeral** self-hosted runner for
  implement/revise — not a shared CI box.
- **Minimize `AGENT_GH_TOKEN` scope** to exactly what the loop needs (issues,
  PRs, contents, workflow); never an org-admin token.
- Keep `auto_dispatch: trusted` (or `never`) on public repos; reserve `all` for
  internal repos where every author is already trusted.
- Leave `AUTO_MERGE_TEAM` empty until you trust the loop; gated auto-merge is
  opt-in.

## Reporting a vulnerability

Until a dedicated `SECURITY.md` disclosure policy is published, report suspected
vulnerabilities privately via the repository's GitHub **Security advisories**
(Report a vulnerability) rather than a public issue.
