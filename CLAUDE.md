# dag-node/rpm

The single writer of the signed DNF repository served at `https://rpm.dagnode.com/`.
`publish.yml` rebuilds the whole served tree statelessly from the org projects' GitHub
releases and deploys it via GitHub Pages; projects sign their own RPMs and trigger a rebuild
by `repository_dispatch` (event `publish-rpm`). Architecture detail lives in the workflow and
script headers — this file is the invariants and conventions an agent MUST honor.

## Invariants

The invariants below bound what a run *can* do; the run log is the only plane that observes
what it *did*; the conventions after them say what the operator does when a gate trips.

- **`main` holds config only** — the workflows, their scripts and tests, `README.md`,
  `projects.txt`, and the licence metadata (`LICENSE`, `LICENSES/`, `REUSE.toml`).
  Never RPMs, never a key copy: the served public key is exported from the signing secret on
  every run, so a committed copy could only drift from what actually signs.
- **Only final `vX.Y.Z` tags are served.** `select-releases.py` filters tags to
  `^v\d+\.\d+\.\d+$` and bounds history by a version floor (latest patch of every MAJOR.MINOR
  series at or above `MIN_VERSION`, per project). Prereleases (`-rc.N`) never reach the
  repository.
- **Verification is fail-closed.** Every downloaded package must show a validating
  `rpmkeys -Kv` signature line against the org key (an unsigned package exits 0 — the exit
  code alone proves nothing); a single failure drops that package with a warning, but if
  every downloaded package fails, the run aborts rather than deploying an empty repository
  over the served one. Each `repomd.xml.asc` is gpg-verified right after it is produced.
- **Secrets never touch disk or scripts.** `GPG_SIGNING_KEY` (the signing-subkey-only
  export) and `GPG_SIGNING_PASSPHRASE` appear only in step `env:` blocks — never
  `${{ secrets.* }}` inside a `run:` script, never argv. The imported keyring lives in a
  tmpfs `GNUPGHOME` and is trap-wiped before the third-party Pages actions run; the
  passphrase streams over a file descriptor.
- **Runs are serialized** (`concurrency: rpm-repository`, no cancel), so concurrent project
  releases queue instead of racing the Pages deploy. A rebuild is idempotent: any dispatch
  means "rebuild everything from the releases".
- **Actions are pinned to full-length commit SHAs**; Dependabot maintains the pins via PRs.
- **Least privilege is a ceiling, not a starting point.** The job holds `contents:read` +
  `pages:write` + `id-token:write`, reads public releases with its own `GITHUB_TOKEN`, and
  writes nothing outside `_site`. It never takes a cross-repo or long-lived write token;
  widening the permission block is an operator decision, never a fix made in passing.
- **Every run is self-reporting.** The retained tags, the aggregated packages, the
  `published/skipped` signature count and the served tree are printed unconditionally, and a
  dropped package always emits `::warning::`. No verification is wrapped in `|| true` and no
  check output is silenced: the log is the only evidence that the fail-closed gates ran at all.
- **CI cannot publish.** `ci.yml` runs the scripts on every branch and PR under `contents: read`
  with no `pages:`/`id-token:` permission and no signing secret, so a script under test cannot
  reach the served repository however wrong it is. `test-verify-deploy.sh` exercises the monitoring
  plane against the already-published site read-only, and must show each failure mode still failing
  — a verifier that cannot fail is not a verifier.
- **The deploy is verified from the served side.** After the Pages deploy the run re-fetches
  `https://rpm.dagnode.com/`, requiring every `repomd.xml` to match the digest it just built and
  every `repomd.xml.asc` to gpg-verify against it, retrying within one bounded budget while the
  CDN propagates. The check imports the public key only and can report, never republish; a
  mismatch fails the run.
- **Client-side verification is the last line, not this workflow.** Everything served must be
  checkable without trusting this repo — packages signed by the org key, `repomd.xml.asc`
  beside every `repomd.xml`, the public key served for out-of-band comparison. Never publish
  an artifact a `gpgcheck=1 repo_gpgcheck=1` client could not verify on its own.

## Working conventions

- **PRs are required on `main`** (ruleset; no direct pushes), and the PR comes from
  `develop`. `develop` is the unblocked integration branch: small fixes commit there
  directly — no branch per fix — while larger features branch from it as
  `feature/RPM-<yyMMdd>-<name>` and merge back to `develop` first. The operator merges and
  pushes — agents do neither.
- **A tripped gate is fixed upstream, never routed around.** An abort, or a package counted
  `skipped`, means a release is wrong (unsigned, wrong key) — the response is to re-release
  from the project. Relaxing the check, bypassing the gate, or hand-uploading into the served
  tree are not available remedies; the tree is only ever restored by a rebuild from releases.
- **This repo is MIT; the packages it serves are not.** Source files carry an
  `SPDX-License-Identifier: MIT` header and `REUSE.toml` single-sources the copyright holder.
  A served package keeps its own upstream licence (mostly `AGPL-3.0-only`) — the two never mix,
  and nothing here relicenses anything it publishes.
- Commit messages follow Conventional Commits (`type(scope): summary`).
- The release-process contract (tag grammar, channels, who signs) is owned by the publishing
  projects — see `tools-agent-tools-restricted`'s `docs/branching-and-release.md`. This repo
  verifies and serves; it MUST NOT re-sign packages or grow a second publish path.
