# Setup — onboarding a repo

A walkthrough of putting Olympus on a repo. Assumes the
[prerequisites](prerequisites.md) (runner + secrets) are in place.

## 1. Add `.olympus.json`

Copy [`examples/consumer/.olympus.json`](../examples/consumer/.olympus.json)
to the repo root and edit it. Minimum useful config:

```json
{
  "$schema": "https://raw.githubusercontent.com/Netis/olympus/main/schema/olympus.schema.json",
  "project": { "name": "my-service", "default_branch": "main" },
  "triage": {
    "gates": {
      "contained_areas": ["one package", "docs/", "one workflow"],
      "test_hint": "a unit / integration test (e.g. pytest)"
    }
  },
  "implement": { "build_cmd": "make build && make test" }
}
```

Everything omitted falls back to a default ([config reference](config-reference.md)).

## 2. Add the workflow wrappers

Copy the files from
[`examples/consumer/.github/workflows/`](../examples/consumer/.github/workflows/)
into your repo's `.github/workflows/`:

| File | Triggers | Needs |
|---|---|---|
| `triage.yml` | issue opened / `agent:assess` | self-hosted runner |
| `implement.yml` | issue labeled `agent:try` | self-hosted runner |
| `pr-review.yml` | your `ci` workflow completes on a PR | self-hosted runner |
| `pr-revise.yml` | dispatched by review | self-hosted runner |
| `guard.yml` | every PR + push | GitHub-hosted |
| `observe.yml` | schedule (prod repos only) | self-hosted runner |

Edit each wrapper's `runner_labels` to match your pool, and keep both the
`uses: ...@v0.2.0` and `olympus_ref: v0.2.0` on the **same** release.

> `pr-review.yml` keys off a workflow named **`ci`** completing. If your CI
> workflow has a different name, change `workflows: [ci]` in the wrapper.
> `pr-revise.yml` **must** be named `pr-revise.yml` (the dispatch target) unless
> you set `OLYMPUS_REVISE_WORKFLOW`.

## 3. Set permissions on the wrappers

The example wrappers already declare the right `permissions:` blocks. Reusable
workflows inherit the caller's permissions, so these matter:

- triage: `issues: write`
- implement: `contents: write, issues: write, pull-requests: write`
- review: `contents: write, issues: write, pull-requests: write, statuses: read`
- revise: `contents: write, pull-requests: write`
- observe: `issues: write`

## 4. Create the labels

Create the four labels (or your renamed equivalents from `.olympus.json`):
`agent:assess`, `agent:try`, `agent:skip`, `auto-agent`. The agents add/read
them; GitHub won't auto-create a missing label.

## 5. Smoke-test

1. Open a small, well-specified issue → triage should comment within a few
   minutes (a warm reply in your language). A clean one gets `agent:try`.
2. Watch the implement job open a draft PR.
3. Your `ci` runs → review posts a structured review.
4. (Prod repos) trigger `observe.yml` with `dry_run: true` → it prints what it
   *would* file without opening an issue.

## 6. Upgrading later

Bump the tag in **all** wrappers (`@vNEXT` + `olympus_ref: vNEXT`) in one PR.
The mechanism updates for the whole repo at once; your `.olympus.json` stays.
