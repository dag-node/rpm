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
