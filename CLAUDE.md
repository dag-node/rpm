# dag-node/rpm

The single writer of the signed DNF repository served at `https://rpm.dagnode.com/`.
`publish.yml` rebuilds the whole served tree statelessly from the org projects' GitHub
releases and deploys it via GitHub Pages; projects sign their own RPMs and trigger a rebuild
by `repository_dispatch` (event `publish-rpm`). Architecture detail lives in the workflow and
script headers — this file is the invariants and conventions an agent MUST honor.

## Invariants

- **`main` holds config only** — the workflow, its scripts, `README.md`, `projects.txt`.
  Never RPMs, never a key copy: the served public key is exported from the signing secret on
  every run, so a committed copy could only drift from what actually signs.
- **Only final `vX.Y.Z` tags are served.** `select-releases.py` filters tags to
  `^v\d+\.\d+\.\d+$` and bounds history (latest patch of the `KEEP_MINORS` newest minors per
  project). Prereleases (`-rc.N`) never reach the repository.
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

## Working conventions

- **PRs are required on `main`** (ruleset; no direct pushes), and the PR comes from
  `develop`. `develop` is the unblocked integration branch: small fixes commit there
  directly — no branch per fix — while larger features branch from it as
  `feature/RPM-<yyMMdd>-<name>` and merge back to `develop` first. The operator merges and
  pushes — agents do neither.
- Commit messages follow Conventional Commits (`type(scope): summary`).
- The release-process contract (tag grammar, channels, who signs) is owned by the publishing
  projects — see `tools-agent-tools-restricted`'s `docs/branching-and-release.md`. This repo
  verifies and serves; it MUST NOT re-sign packages or grow a second publish path.
