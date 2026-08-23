# DagNode RPM Package Repository

Signed DNF/YUM repository for [DagNode](https://github.com/dag-node/) projects, served from **https://rpm.dagnode.com/**.

## Install

```bash
# 1. Import the org signing key — verify its fingerprint out of band first (see below)
sudo rpm --import \
  https://rpm.dagnode.com/RPM-GPG-KEY-dag-node

# 2. Install the repository definition (package `dagnode-release`)
sudo dnf install \
  https://rpm.dagnode.com/dagnode-release-latest.noarch.rpm
```

`dagnode-release` is signed by the org key, so `dnf` verifies its signature before installing it —
importing the key first (step 1) is what satisfies that check, since the package that would
otherwise install the key has not run yet. The package then drops `dagnode.repo` and the signing
key `RPM-GPG-KEY-dag-node` for every later `dnf install`, and carries subkey rotations forward as
an ordinary `dnf upgrade`.

Both commands fetch over HTTPS — **verify the public key fingerprint** out of band (DNS) before
importing, so the served copy never vouches for itself:

```bash
# Confirm RPM-GPG-KEY-dag-node public key fingerprint over DNS
# "v=dagnode-gpg1; fpr=67F42DC18BF764B42D82F14256D2F802CF9832E4"
dig +short TXT _dagnode-gpg.dagnode.com
```

|                  | RPM-GPG-KEY-dag-node                                 |
|:-----------------|:-----------------------------------------------------|
| **Short ID:**    | `rsa4096/CF9832E4`                                   |
| **Long ID:**     | `rsa4096/56D2F802CF9832E4`                           |
| **Fingerprint:** | `67F4 2DC1 8BF7 64B4 2D82  F142 56D2 F802 CF98 32E4` |
| **UID:**         | `DagNode Package Signing <tools@dagnode.com>`        |
| **Expires:**     | `2036-07-15` (10y)                                   |
| **Issued:**      | `2026-07-18`                                         |

`dagnode-release` repo source and payload: [`dag-node/rpm-dagnode-release`](https://github.com/dag-node/rpm-dagnode-release).

### Manual install

```bash
# Download the served `.repo`
sudo curl -fsSL -o /etc/yum.repos.d/dagnode.repo \
  https://rpm.dagnode.com/dagnode.repo
# Verify the served key fingerprint before importing
curl -fsSL https://rpm.dagnode.com/RPM-GPG-KEY-dag-node | gpg --show-keys
# dnf imports it on first use (gpgkey= above); to import it into rpm yourself:
sudo rpm --import \
  https://rpm.dagnode.com/RPM-GPG-KEY-dag-node
# Confirm it landed in the rpm keyring:
rpm -q gpg-pubkey --qf '%{version}-%{release} %{summary}\n' | grep -i dagnode
# -> cf9832e4-6a5b959c DagNode Package Signing <tools@dagnode.com> public key
#    (key id cf9832e4 == the published CF9832E4; stable across subkey rotation)
```

```ini
# /etc/yum.repos.d/dagnode.repo
[dagnode]
name=DagNode Package Repository for EL (RPMs)
baseurl=https://rpm.dagnode.com/el/$releasever/$basearch/
gpgkey=https://rpm.dagnode.com/RPM-GPG-KEY-dag-node
gpgcheck=1
repo_gpgcheck=1
metadata_expire=6h
priority=10
enabled=1
```

**Important**: Manually created `dagnode.repo` imports the public key once over HTTPS on first use
(`dnf` prompts with its fingerprint), and will not pick up a rotated signing subkey automatically.
Prefer the recommended installation with dnf package `dagnode-release`, which installs `dagnode.repo` and the public key in one step.

The repository serves every Enterprise Linux major and arch: `$releasever` selects `el/9` or `el/10`, `$basearch` the arch tree.
`gpgcheck=1` verifies each package signature, `repo_gpgcheck=1` verifies the repository metadata;
both against the org key [RPM-GPG-KEY-dag-node](https://rpm.dagnode.com/RPM-GPG-KEY-dag-node).
`priority=10` gives DagNode packages precedence over the base repositories (in dnf the lower priority number wins; the default is 99).

## Signing key

Every package and the repository metadata are signed with the DagNode **signing subkey**;
the served `RPM-GPG-KEY-dag-node` **public key** carries it together with the certify-only primary key that is
the org's signing identity and lives offline — GitHub CI holds only the subkey.

Verify the primary fingerprint before your first import — don't let the copy the repo serves vouch
for itself. `rpm.dagnode.com` is fronted by Cloudflare (proxied DNS): Cloudflare terminates TLS and
could in principle rewrite both the served `RPM-GPG-KEY-dag-node` and the `_dagnode-gpg` TXT record,
which live in the same zone. This README rendered on GitHub is an independent trust root outside that
zone, so the fingerprint table and key block here are a third channel a zone-level compromise cannot
reach. Cross-check the fingerprint across at least two independent channels before importing:

- **served key** — `curl -fsSL https://rpm.dagnode.com/RPM-GPG-KEY-dag-node | gpg --show-keys`
- **DNS TXT** — `dig +short TXT _dagnode-gpg.dagnode.com`
- **this README on GitHub** — [`dag-node/rpm`](https://github.com/dag-node/rpm/blob/main/README.md#signing-key) (the table above and key block below)

<!-- publish.yml derives the same identity block from the subkey at publish time
     and heads the served RPM-GPG-KEY-dag-node with it; these values must match.
     The primary fingerprint is stable across subkey rotation and expiry extension. -->

The served public key is exported from the signing secret by CI and prefixed with the identity block
below, in the exact format `publish.yml` emits during publish.

### Public key contents
```text
DagNode RPM GPG Public Key

This public key is used to verify RPM packages and repository
metadata signed by DagNode. Packages and the repomd.xml index
are signed with the signing subkey this key carries; the
primary key is certify-only.

Import this key to enable gpgcheck and repo_gpgcheck for the
DagNode repositories.

Key valid for 10 years. Questions: tools@dagnode.com

pub   4096R/CF9832E4 2026-07-18
      Key fingerprint = 67F4 2DC1 8BF7 64B4 2D82  F142 56D2 F802 CF98 32E4
uid                  DagNode Package Signing <tools@dagnode.com>

-----BEGIN PGP PUBLIC KEY BLOCK-----

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
6M7mgpYlSg==
=obmv
-----END PGP PUBLIC KEY BLOCK-----
```

**Rotation.** The primary key is long-lived — one identity across the EL-major lifecycle, as
Rocky and Alma do — its validity is extended in place, keeping the same fingerprint. A
leaked CI secret burns only the subkey: the offline primary revokes it and certifies a
replacement, the republished `RPM-GPG-KEY-dag-node` keeps the fingerprint above, affected
releases are re-cut so every served package is signed by the live subkey (the publish
pipeline's verify step drops any that aren't). A brand-new identity is published only if the
primary itself is compromised: the new key and fingerprint are announced here.

## Served repository layout

```
https://rpm.dagnode.com/
├── RPM-GPG-KEY-dag-node              # org public signing key (packages + metadata)
├── dagnode-release-latest.noarch.rpm # bootstrap package (stable alias to the newest build)
├── dagnode.repo                      # manual .repo drop-in
└── el/
    ├── 9/{x86_64,aarch64}/repodata/…
    └── 10/{x86_64,aarch64}/repodata/…
```

Packages are `noarch`; each is published into every supported `$basearch` tree so a client's
`$basearch` baseurl resolves. This is the *served* tree — `main` holds only the workflow, this
README, and `projects.txt`; no RPMs live in git.

## How it is published

This repository is the single publisher. Projects build and **sign** their own RPMs in their
own release workflow, publish them as GitHub Releases, then notify this repo
via `repository_dispatch` (event `publish-rpm`). `.github/workflows/publish.yml` rebuilds the whole
repository **statelessly** from the releases listed in `projects.txt` (the source of truth):
it downloads each retained release's signed RPMs, re-verifies them against the org key, regenerates
metadata with `createrepo_c`, detached-signs `repomd.xml`, and deploys via GitHub Pages. A
`rpm-repository` concurrency group serializes concurrent releases. Manual rebuild/backfill:
**Actions → Publish RPM repository → Run workflow**.

History is bounded by a version floor so the repo does not carry retired lines: for each package
it serves the latest patch of every `MAJOR.MINOR` series at or above `MIN_VERSION` (in
`publish.yml`, currently `0.11.1` — dropping the pre-integrations-split `0.6.x` packages).
Superseded patches and versions below the floor are not served — their GitHub Releases remain, so
lowering the floor or a manual rebuild restores them. Nothing is ever deleted from a project's
releases; this repo only chooses what to serve.

## Licensing

Two separate things, easily confused:

**The packages served here** keep their own licenses. This repository's infrastructure and
metadata do not define package licensing — each RPM retains its upstream license, see
`rpm -qi <package>`. Most of what is served is `AGPL-3.0-only`; nothing below changes that.

**This repository itself** — the publish workflow, its scripts and tests, the docs — is
`MIT` (see `LICENSE`). It holds only packaging and distribution machinery, and the workflow
is the one piece worth reusing, so it is licensed to permit that. Every source file carries an
`SPDX-License-Identifier` header; `REUSE.toml` single-sources the copyright holder and covers
the paths where a header would be noise.
