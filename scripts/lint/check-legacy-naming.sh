#!/usr/bin/env bash
# check-legacy-naming.sh — flag pre-rename "agent-ops" naming.
#
# This mechanism was renamed agent-ops → Olympus (see docs/migration.md). This
# linter has two users:
#
#   1. A CONSUMER repo upgrading to an Olympus-named release. Run it in the repo
#      root to see exactly what to change before you re-pin:
#        bash <(curl -fsSL \
#          https://raw.githubusercontent.com/Netis/olympus/main/scripts/lint/check-legacy-naming.sh)
#
#   2. THIS repo's own CI — a regression guard so the rename never silently
#      leaks back in (the new label/bot/config/env names stay the only ones).
#
# IMPORTANT for consumers: GitHub Actions does NOT redirect `uses:` on a repo
# rename, so a wrapper pinned to a PRE-rename tag (e.g. @v0.2.0) must still
# change its `uses:` owner to Netis/olympus (same @tag — the tag travelled with
# the repo). Keep `.agent-ops.json` + `agent_ops_ref` until you re-pin to an
# Olympus-named tag, when the rest of these edits apply.
#
#   scripts/lint/check-legacy-naming.sh [DIR]    # default: current repo
#
# Exit 0 = no legacy naming found · 1 = items found · 2 = bad usage.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

root="${1:-.}"
cd "$root" 2>/dev/null || { echo "check-legacy-naming: no such directory: $root" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "check-legacy-naming: run inside a git repository (or pass its path)" >&2; exit 2; }

# Files that legitimately retain the old names: this linter (it carries the
# patterns), the rename-record docs, and the migration guide. Harmless no-ops
# in a consumer repo, which won't have these paths.
ex=(
  ':!scripts/lint/check-legacy-naming.sh'
  ':!docs/pantheon.md' ':!docs/roadmap.md' ':!docs/improvement-plan.md'
  ':!docs/migration.md'
)

issues=0
scan() {  # <severity> <title> <ere> <fix>
  local sev="$1" title="$2" pat="$3" fix="$4" hits
  hits="$(git grep -nIE "$pat" -- . "${ex[@]}" 2>/dev/null || true)"
  [ -n "$hits" ] || return 0
  issues=$((issues + 1))
  printf '\n  [%s] %s\n        → %s\n' "$sev" "$title" "$fix"
  printf '%s\n' "$hits" | sed 's/^/        /'
}

echo "olympus migration check — scanning for legacy agent-ops naming"

# --- MUST fix before re-pinning to an Olympus-named tag --------------------
scan MUST "Mechanism repo reference (uses:)" \
  'Netis/agent-ops' \
  'Netis/agent-ops → Netis/olympus (Actions does NOT redirect uses: on rename — change the owner; the same @tag still works)'
scan MUST "Version-pin workflow input" \
  'agent_ops_ref' \
  'agent_ops_ref: → olympus_ref:'
scan MUST "Policy config filename reference" \
  '\.agent-ops\.json' \
  '.agent-ops.json → .olympus.json'
scan MUST "Config schema reference" \
  'agent-ops\.schema\.json' \
  'agent-ops.schema.json → olympus.schema.json'
scan MUST "Env-var overrides" \
  'AGENT_OPS_[A-Z_]+' \
  'AGENT_OPS_* → OLYMPUS_*'
scan MUST "Observer (systemd) env" \
  'MARA_[A-Z_]+' \
  'MARA_* → ARGUS_*'
scan MUST "Self-hosted runner label" \
  '(self-hosted,[[:space:]]*agent-ops|"agent-ops")' \
  'agent-ops runner label → olympus (keep workflow runs-on + runner registration in sync)'

# --- cosmetic: brand + retired agent personas ------------------------------
# Substring match (git grep's regex engine has no \b; -w would miss the
# underscore-embedded forms like run_wiwi / test_mara). Broad on purpose —
# COSMETIC severity, and 'mara' as a stray substring is a tolerable false hit.
scan COSMETIC "Brand / retired agent names" \
  '(agent-ops|wiwi|vivi|mara)' \
  'rebrand: agent-ops→Olympus · wiwi→hephaestus · vivi→themis · mara→argus (overlaps the structural items above)'

# --- the policy file itself ------------------------------------------------
if [ -f .agent-ops.json ]; then
  issues=$((issues + 1))
  printf '\n  [MUST] Policy file is named .agent-ops.json\n        → git mv .agent-ops.json .olympus.json\n'
fi

echo
if [ "$issues" -eq 0 ]; then
  echo "check-legacy-naming: ✓ no legacy agent-ops naming found"
else
  cat <<'EOF'
check-legacy-naming: ✗ legacy naming found (see above).

  Also outside these files (this linter cannot see them):
    • the review bot's GitHub account — the login in agents.review_bot_login is
      a real account; rename or re-provision it, then update AUTO_MERGE_TEAM and
      any allowlists that reference it.

  Full mapping + impact-by-pin-strategy: docs/migration.md
EOF
fi
exit $(( issues > 0 ? 1 : 0 ))
