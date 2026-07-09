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

set -uo pipefail

# The sync commit is HEAD on the action's sync branch. Compare it to its first
# parent (the pre-sync state) to see exactly what the sync introduced. This needs
# no remote refs, so it works regardless of fetch depth or checkout config.
if base="$(git rev-parse --verify --quiet 'HEAD^' 2>/dev/null)"; then
  diff_range=("$base" "HEAD")
else
  # No parent (unlikely) -> inspect the whole committed tree instead.
  diff_range=("HEAD")
fi

changed="$(
  {
    git diff --name-only "${diff_range[@]}" 2>/dev/null
    git diff --name-only HEAD 2>/dev/null       # uncommitted, just in case
    git diff --name-only --cached 2>/dev/null
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
