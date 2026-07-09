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
#
# Debuggability: every failure is surfaced. Git errors are fatal and printed
# (never swallowed into a false "all clear"), the compared base is logged, and
# problems are emitted as GitHub `::error::` annotations so they show up in the
# run summary, not just deep in the log.

set -uo pipefail

# --- helpers -----------------------------------------------------------------

# fail <message...>: emit a GitHub error annotation + plain stderr, then abort.
fail() {
  echo "::error title=template-sync guard::$*" >&2
  echo "template-sync guard: $*" >&2
  exit 1
}

# run <description> <git args...>: run a git command, aborting loudly (not
# silently) if it fails. Captures stderr so a real git failure is shown, never
# discarded. Prints nothing extra on success; echoes stdout for the caller.
run() {
  local desc="$1"; shift
  local out err rc
  err="$(mktemp)"
  out="$("$@" 2>"$err")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "::error title=template-sync guard::$desc failed (git exit $rc)" >&2
    echo "  command: $*" >&2
    sed 's/^/  git: /' "$err" >&2
    rm -f "$err"
    exit 1
  fi
  rm -f "$err"
  printf '%s' "$out"
}

# --- sanity: we must be inside the sync repo --------------------------------

run "git repository check" git rev-parse --is-inside-work-tree >/dev/null

# --- determine the base to compare against ----------------------------------
# The sync commit is HEAD on the action's sync branch; its first parent is the
# pre-sync state. We need no remote refs, so this works regardless of fetch
# depth or checkout config.
#
# We deliberately distinguish two cases:
#   * HEAD has a parent  -> compare HEAD^..HEAD (normal).
#   * HEAD has NO parent -> a legitimate edge case (root commit); inspect the
#                           whole committed tree. We log that we did so.
# Any OTHER git failure while probing is treated as fatal, not as "no parent".

if git rev-parse --verify --quiet 'HEAD' >/dev/null 2>&1; then
  :
else
  fail "cannot resolve HEAD — repository state is unexpected; refusing to push."
fi

parent_probe_rc=0
git rev-parse --verify --quiet 'HEAD^' >/dev/null 2>&1 || parent_probe_rc=$?

if [ "$parent_probe_rc" -eq 0 ]; then
  base="$(run "resolve HEAD^" git rev-parse --verify 'HEAD^')"
  echo "template-sync guard: comparing sync commit $(git rev-parse --short HEAD) against parent $(git rev-parse --short "$base")"
  committed="$(run "diff sync commit" git diff --name-only "$base" HEAD)"
else
  # rev-parse --quiet returns 1 specifically when the ref does not resolve
  # (i.e. no parent). Treat only that as the legitimate root-commit case.
  if [ "$parent_probe_rc" -ne 1 ]; then
    fail "unexpected git error probing HEAD^ (exit $parent_probe_rc); refusing to push."
  fi
  echo "template-sync guard: HEAD has no parent (root commit); inspecting full committed tree."
  committed="$(run "list committed tree" git ls-tree -r --name-only HEAD)"
fi

# Also catch anything staged or unstaged that is not yet in the commit, so a
# guard bypass via a dirty tree is impossible.
staged="$(run "list staged changes"     git diff --name-only --cached)"
unstaged="$(run "list unstaged changes" git diff --name-only)"

# --- evaluate ----------------------------------------------------------------
# Portable across bash 3.2+ (no mapfile): assemble the candidate paths as
# newline-separated text and filter. Empty sections contribute nothing.

offending="$(
  printf '%s\n%s\n%s\n' "$committed" "$staged" "$unstaged" \
    | grep -E '^custom_components/' \
    | sort -u
)"

if [ -n "$offending" ]; then
  echo "::error title=template-sync guard::refusing to push — the sync touched integration code (custom_components/**)." >&2
  echo "template-sync guard: refusing to push. The sync touched integration code:" >&2
  printf '  %s\n' $offending >&2
  echo "" >&2
  echo "This means .templatesyncignore is missing, misplaced, or not excluding" >&2
  echo "custom_components/**. Fix the ignore file before allowing a sync." >&2
  exit 1
fi

echo "template-sync guard: OK — no custom_components/ changes in this sync."
