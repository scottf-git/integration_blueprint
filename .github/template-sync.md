# Staying in sync with the blueprint

> This file is the canonical documentation for the template-sync recipe. It lives
> at `.github/template-sync.md` — a path the sync itself carries forward, so future
> improvements to these instructions reach your repo on the next sync (unlike the
> README, which stays yours and is never synced).

After you generate a repository from this template, the blueprint keeps
improving (CI workflows, linter config, dev container, helper scripts). This
repository ships an **opt-in** recipe that periodically opens a pull request with
those upstream *scaffold* changes, so you can review and merge them at your own
pace.

It uses the community action
[`AndreasAugustin/actions-template-sync`](https://github.com/AndreasAugustin/actions-template-sync)
and is deliberately conservative: **it never syncs your integration code.**

### What it does and does not sync

| Synced (scaffold) | Never synced (yours) |
| -- | -- |
| `.github/workflows/*`, `.ruff.toml`, `scripts/*`, `requirements.txt`, `.gitignore`, `.github/dependabot.yml` | `custom_components/**` (all of your integration code) |
| | `manifest.json`, `hacs.json` |
| | `README.md`, `CONTRIBUTING.md`, `.devcontainer.json`, `config/configuration.yaml`, issue templates |

The exclusions live in [`.templatesyncignore`](./.templatesyncignore). The sync
pulls with `-X theirs` (upstream wins on conflict), so that file is the **only**
thing protecting your code — keep it accurate.

> A PR from this workflow may include upstream scaffold changes. Review them like
> any other PR; there is no automatic "always be in sync."

### Enable it

1. Copy [`.github/workflows/template-sync.yml`](./.github/workflows/template-sync.yml),
   [`.github/template-sync-guard.sh`](./.github/template-sync-guard.sh) (make it
   executable: `chmod +x`), and [`.templatesyncignore`](./.templatesyncignore)
   into your repository.
2. Create a **Personal Access Token** with `repo` + `workflow` scope (classic), or
   a fine-grained PAT with **Contents**, **Pull requests**, and **Workflows**
   read/write on the repo. Save it as a repository secret named
   `TEMPLATE_SYNC_PAT`.
3. That's it — the workflow runs monthly and via **Actions → Template sync → Run
   workflow**.

#### Why a PAT is required, and exactly which scopes

The synced payload includes files under `.github/workflows/`. GitHub does **not**
allow the default `GITHUB_TOKEN` to write workflow files — so this recipe uses a
PAT, and the *same* PAT authenticates both the checkout and the push/PR. It
therefore needs **write** access, not just read:

**Fine-grained PAT** (recommended — restrict it to this one repo):

| Permission | Access | Used for |
| -- | -- | -- |
| Contents | Read and write | pushing the sync branch |
| Pull requests | Read and write | opening the sync PR |
| Workflows | Read and write | the payload touches `.github/workflows/*` |

**Classic PAT** (simpler): the **`repo`** scope (contents + pull requests) **plus**
the **`workflow`** scope. `workflow` is separate from `repo`; ticking only `repo`
is the most common reason the run fails.

Both tokens must be wired the same way — note `persist-credentials: false`:

```yaml
      - uses: actions/checkout@... # pinned
        with:
          token: ${{ secrets.TEMPLATE_SYNC_PAT }}
          persist-credentials: false   # required with a non-default token
      - uses: AndreasAugustin/actions-template-sync@... # pinned
        with:
          target_gh_token: ${{ secrets.TEMPLATE_SYNC_PAT }}
          ...
```

**Reading the failure:** the checkout and sync will succeed even with a
read-only or too-narrow token — the problem only shows at the end.

- `remote: Permission … denied … 403` on push → the PAT is missing **Contents**
  (or classic `repo`) write, or **Workflows** (classic `workflow`) write.
- the PR step fails → missing **Pull requests** write.
- an error naming `.github/workflows/*` specifically → the workflow permission,
  or `persist-credentials: false` is not set.

### A safety net

Because `-X theirs` means upstream would win on conflict, the workflow also runs
a small **fail-closed guard** (`.github/template-sync-guard.sh`) as a `prepush`
hook. If a sync ever tries to touch `custom_components/**` — for example because
`.templatesyncignore` got moved or misspelled — the guard aborts the run **before**
any PR is opened. The guard only validates; it never edits files.

The guard is built to be **debuggable, not silent**:

- On every run it logs the commits it compared, e.g.
  `template-sync guard: comparing sync commit <a> against parent <b>`.
- If it blocks, it lists the exact offending paths and the likely cause
  (`.templatesyncignore` missing/misplaced) as a GitHub `::error::` annotation,
  so the reason shows up in the run summary — not buried in the log.
- If an underlying `git` command itself fails, the guard **does not** treat that
  as "no changes" and wave the sync through. It prints the failing command and
  git's own error and exits non-zero. A guard that can't verify never approves.

So a failed run always tells you *why*: either the ignore file needs fixing, the
PAT lacks push/PR permission (the action's own error is shown verbatim), or a git
error is printed in full.

### Two things that will *not* auto-sync

- **`README.md` is not synced.** Upstream's README is entirely *"how to use this
  template"* (the "this is a blueprint" notice, the file overview, the
  "click Use this template / rename the domain" steps). The moment you generate a
  repo you replace all of it with your integration's own docs — so upstream's
  README and yours are different documents that happen to share a filename, not
  two versions of one. Syncing it would overwrite your docs with template
  boilerplate.

  *This is why these instructions live in `.github/template-sync.md` and not in
  the README:* that path **is** synced, so improvements to the recipe itself do
  reach your repo on the next sync. The README stays yours; the recipe docs stay
  current.
- **`.devcontainer.json` is not synced** (only because it carries your repo's
  name). If the blueprint improves the dev container, cherry-pick those changes
  by hand.

### Advanced: also review component updates (opt-in, not enabled by default)

The conservative recipe skips `custom_components/**` because a straight sync would
overwrite your real code. If you *do* want to see upstream component changes, the
safe pattern is to route them into a **staging path** you diff by hand rather than
letting them land on your code. With `is_allow_hooks: true`, add a `precommit`
hook that copies the incoming `custom_components/<upstream_domain>/` into e.g.
`.template-sync-staging/` and then removes it from the tracked tree, so the PR
shows upstream's version for manual cherry-picking without touching your files.
This is more moving parts and is intentionally left as a manual opt-in — the
default stays boring and safe.
