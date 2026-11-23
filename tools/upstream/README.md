# Upstream package watch

This is a **read-only** release inventory, not a package updater. It reads every
`packages/*/package.zon`, never imports a recipe or runs upstream code, and never
changes versions, hashes, branches or PRs. It uses only Python's standard library.

The workflow runs daily at **06:23 UTC**, or with **Run workflow**. Scheduled
runs start only after the workflow is merged into the default branch. Pull
requests and relevant pushes run offline tests/inventory only, never a network
scan. `contents: read` is the only GitHub token permission. There is no PAT or
write credential and no automatic merge, release, issue or update PR.

Open the Actions run summary for counts and candidates. Download its
`upstream-report` artifact for `report.md` (all packages), `report.json`
(machine-readable evidence, source URLs and tracking policy), and `summary.md`.
Reports are kept for 30 days. This alone does **not** send chat/email alerts on
version changes; GitHub's workflow failure notifications are separate.

## What coverage means

At introduction on `ba0edc0`, there are **1,422 recipes**. All are inventoried;
**907** have an inferred/reviewed adapter and **515** explicitly need manual
tracking. These are static mapping counts, **not 907 successful live checks**.
The first network report gives actual success/error/unknown counts. Newly added
recipes appear automatically, either with an adapter or a concrete gap reason.

Only the **first source archive** is checked for upstream version changes. All
source URLs are inventoried, but secondary archives and patches are not watched
independently. Local/metapackages, non-numeric/pinned versions, unrecognized
hosts, ambiguous tags and hashed URLs with no reliable project identity remain
manual. In particular, CPAN version semantics, GitLab upload URLs and
SourceForge projects need explicit adapters rather than guessed comparisons.

Statuses:

- `review`: a numerically newer candidate was found. This is **not** a tested,
  authenticated or compatible upgrade. See the upstream link and release notes.
  The latest candidate and latest same-major.minor candidate are separate.
- `no-newer-observed`: nothing newer within this adapter's scope was observed.
  It does **not** prove the package is globally up to date.
- `manual`: no safe adapter; the reason tells you what needs a mapping or policy.
- `unknown`: the index yielded no comparable releases, e.g. GitHub tags without
  published releases. Never silently interpreted as current.
- `error`: transport, limits or malformed upstream metadata. Other packages keep
  running and the workflow fails visibly after saving the report.
- `not-checked`: offline inventory or exhausted run budget/interrupted scan.

Adapters intentionally favor avoiding false claims over universal guessing:

- **GitHub:** public published releases, first 100, excluding draft/prerelease
  flags, future publication dates and non-numeric tags. The tag prefix/suffix is
  inferred from the current source URL, not the recipe's name. A newer stable
  release buried beyond this window can be missed. Tags-only projects need
  manual tracking or a reviewed release feed, not an unsafe tags fallback.
- **PyPI:** project identity from a `/packages/source/.../PROJECT/` source path;
  numeric, non-yanked releases with an sdist. Post/dev/epoch/local versions are
  deliberately not interpreted. Package metadata does not establish build
  compatibility or Python-version support.
- **GNOME:** `cache.json` archive versions, within current major.minor for
  traditional versioning and current major for GNOME 40+ numbering. Development
  suffixes are excluded. This rule is conservative and must be overridden for
  projects with other versioning conventions; it does not discover new series.
- **Linux:** kernel.org stable/longterm, non-EOL entries. RC/mainline excluded.
- **Official archive directories:** allowlisted HTTPS hosts, exact filename
  prefix/suffix, numeric versions only, same directory. A numeric archive is
  **not evidence of stability**; these are review candidates. Versioned
  subdirectories, old archives and current filename suffixes can hide updates.

No results automatically bypass Joe Linux's LFS/BLFS recipe conventions,
intentional version pins, patch rebases, privileged-operation policy, source
signature/hash validation, isolated builds, dependency rebuilds or boot tests.
Core packages (kernel, libc, compiler, Mesa, init) especially need explicit
maintainer review. Recipe `.release` is not an upstream version.

## Local use and testing

```sh
python3 -m unittest discover -s tools/upstream -p 'test_*.py' -v
python3 tools/upstream/check.py --inventory-only --output /tmp/upstream-inventory
python3 tools/upstream/check.py --packages linux mesa jq mako libsoup zlib --output /tmp/upstream-smoke
# Full live scan. GITHUB_TOKEN is optional locally; GitHub's unauthenticated
# limit is usually insufficient for this catalog. Never paste a token in logs.
python3 tools/upstream/check.py --workers 6 --output /tmp/upstream-report
```

Requests are grouped by exact URL, with bounded concurrency (1-8), per-host
spacing, an 8-second socket timeout and a 12 MiB metadata limit. HTTP 403/429
stops further requests to that host for the run (already queued concurrent
requests may finish). Work not started after a 15-minute network budget is
marked `not-checked`. An initial inventory and checkpoints every 50 indices
preserve partial coverage if interrupted; the final report supersedes them.
Actions has a 25-minute job limit as an outer bound. No metadata cache persists
between runs, so stale cache data cannot look like a current upstream check.

All endpoints are allowlisted public HTTPS hosts. Redirects must stay on that
allowlist and strip authorization; the read-only GitHub token is initially sent
only to `api.github.com`. Metadata and source URLs are data, never commands.

## Extending coverage

Add a reviewed mapping to `overrides.json` by package directory name. Explain
why it is authoritative and what policy it encodes. A deliberate pin can use:

```json
{"example": {"kind": "manual", "reason": "Pinned to ABI used by dependent X; review major releases manually"}}
```

An archive override uses `kind: directory`, an HTTPS `url`, an anchored-by-code
filename `pattern` with a single numeric version capture group, and `reason`.
See Mesa's mapping for the canonical HTTPS archive instead of its legacy URL.
Other supported kinds are `github`, `pypi`, `gnome` (with `project`), and `kernel`.
New hosts/adapters need code review and offline fixture tests. Deleted recipes
with stale overrides fail inventory rather than silently drifting out of scope.

Tests require no network: ordering, identity inference, exact archive matching,
prereleases/yanks/future dates, bounded-feed unknowns, GNOME series, redirects and
authorization stripping, deduplication, isolated failures, budget exhaustion,
report escaping, and full catalog accounting. Live metadata checks do not prove
any proposed package builds or boots.
