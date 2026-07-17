# DagNode RPM Repository

Signed DNF/YUM repository for DagNode projects, served at **https://rpm.dagnode.com/**.

## Use it

```bash
sudo tee /etc/yum.repos.d/dagnode.repo >/dev/null <<'EOF'
[dagnode]
name=DagNode RPM Repository
baseurl=https://rpm.dagnode.com/el/$releasever/$basearch/
gpgkey=https://rpm.dagnode.com/RPM-GPG-KEY-dag-node
gpgcheck=1
repo_gpgcheck=1
enabled=1
metadata_expire=6h
EOF
sudo chmod 644 /etc/yum.repos.d/dagnode.repo
sudo dnf install <package>
```

One `.repo` serves every Enterprise Linux major and arch: `$releasever` selects `el/9` or
`el/10`, `$basearch` the arch tree. `gpgcheck=1` verifies each package signature and
`repo_gpgcheck=1` verifies the repository metadata — both against the org key at
`/RPM-GPG-KEY-dag-node`, which `dnf` imports from the `gpgkey` URL on first use.

## Signing key

Every package and the repository metadata are signed with the DagNode signing subkey; the
served `RPM-GPG-KEY-dag-node` carries it together with the certify-only primary key that is
the org's signing identity (and lives offline — CI holds only the subkey). Verify the primary
fingerprint out-of-band before trusting the key — don't let the copy the repo serves vouch
for itself:

<!-- Filled at the key ceremony (GPG-HINTS.md §1); placeholders until the fresh key exists. -->
- **Key ID:** `<PRIMARY-KEY-ID>`
- **Fingerprint:** `<PRIMARY-FINGERPRINT>`
- **UID:** `DagNode Package Signing <tools@dagnode.com>`

```bash
# Inspect the served key before importing -- the printed primary fingerprint must match above.
curl -fsSL https://rpm.dagnode.com/RPM-GPG-KEY-dag-node | gpg --show-keys

# dnf imports it on first install (gpgkey= above); to import it into rpm yourself:
sudo rpm --import https://rpm.dagnode.com/RPM-GPG-KEY-dag-node
rpm -q 'gpg-pubkey*' -i | grep -B2 -A4 DagNode    # confirm it landed in the rpm keyring
```

**Rotation.** The primary key is long-lived — one identity across the EL-major lifecycle, as
Rocky and Alma do — and its validity is extended in place, keeping the same fingerprint. A
leaked CI secret burns only the subkey: the offline primary revokes it and certifies a
replacement, the republished `RPM-GPG-KEY-dag-node` keeps the fingerprint above, and affected
releases are re-cut so every served package is signed by the live subkey (the publish
pipeline's verify step drops any that aren't). A brand-new identity is published only if the
primary itself is compromised: the new key and fingerprint are announced here, and the
superseded key stays importable while any package it signed is still served.

## Served layout

```
https://rpm.dagnode.com/
├── RPM-GPG-KEY-dag-node          # org public signing key (packages + metadata)
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
(`repository_dispatch`, event `publish-rpm`). `.github/workflows/publish.yml` rebuilds the whole
repository **statelessly** from the releases listed in `projects.txt` (the source of truth):
it downloads each retained release's signed RPMs, re-verifies them against the org key, regenerates
metadata with `createrepo_c`, detached-signs `repomd.xml`, and deploys via GitHub Pages. A
`rpm-repository` concurrency group serializes concurrent releases. Manual rebuild/backfill:
**Actions → Publish RPM repository → Run workflow**.

History is bounded so the repo cannot grow without limit: for each package it serves the latest
patch of every `MAJOR.MINOR` series, for the 10 most-recent minors (`KEEP_MINORS` in
`publish.yml`). Superseded patches and older minors are evicted from the served repo — their
GitHub Releases remain, so raising the bound or a manual rebuild restores them. Nothing is ever
deleted from a project's releases; this repo only chooses what to serve.

## Licensing

The repository infrastructure and metadata do not define package licensing. Each RPM retains
its own upstream license — see `rpm -qi <package>`.
