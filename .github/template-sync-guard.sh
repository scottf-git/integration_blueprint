#!/usr/bin/env bash
#
# Fail-closed safety guard for the template-sync workflow.
#
# Runs as the actions-template-sync `prepush` hook: after the upstream changes
# are committed to the sync branch, but BEFORE they are pushed / a PR is opened.
#
# The upstream pull uses "-X theirs", so if .templatesyncignore is ever missing,
# misplaced, or ineffective, the sync would silently overwrite your integration
# code. This guard blocks that: if the pending sync touches custom_components/**
# (or re-creates the original integration_blueprint/ directory), it aborts the
# run with a non-zero exit so nothing is published.
#
# This hook only validates. It never renames, rewrites, or substitutes anything.

set -euo pipefail

# Determine the base to diff against: the sync branch's fork point from the
# repo's previous state. We diff the current HEAD against its first parent when
# available (the sync commit), else against the upstream tracking of the default
# branch. Fall back to comparing against origin/<default>.
default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
default_branch="${default_branch:-main}"

# Collect files changed by the sync. Prefer the committed diff (HEAD vs the base
# the sync branched from); include any not-yet-committed changes for safety.
changed="$(
  {
    git diff --name-only "origin/${default_branch}...HEAD" 2>/dev/null || true
    git diff --name-only HEAD 2>/dev/null || true
    git diff --name-only --cached 2>/dev/null || true
  } | sort -u
)"

# Look for forbidden paths: anything under custom_components/, and specifically
# the upstream's original component directory being re-created.
offending="$(printf '%s\n' "$changed" | grep -E '^custom_components/' || true)"

if [ -n "$offending" ]; then
  echo "::error::template-sync guard: refusing to push. The sync touched integration code:" >&2
  printf '  %s\n' $offending >&2
  echo "" >&2
  echo "This means .templatesyncignore is missing, misplaced, or not excluding" >&2
  echo "custom_components/**. Fix the ignore file before allowing a sync." >&2
  exit 1
fi

echo "template-sync guard: OK — no custom_components/ changes in this sync."
