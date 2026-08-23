#!/usr/bin/env bash
#
# Verify that the LIVE site serves exactly the tree a publish run just built.
#
#   verify-deploy.sh <site-url> [site-dir]      # site-dir defaults to _site
#
# This is the repository's monitoring plane: every other gate in publish.yml runs on the build
# side, so nothing observed the result until this ran. It re-fetches the deployed site and
# requires the served public key, every repomd.xml, and the bootstrap alias to match the bytes
# in <site-dir>, with each repomd.xml.asc verified against the LOCAL repomd.xml -- a signature
# left over from the previous deploy verifies against its own metadata, so "internally
# consistent" is not the same as "current".
#
# Timing: actions/deploy-pages returns once the deployment record exists, not once the CDN
# serves it, so every fetch retries against one shared budget rather than a fixed sleep. A slow
# edge is a slow success. The budget is shared so a file that never appears cannot stretch the
# job by (files x per-file timeout); it does starve the later checks of time, which is why every
# message carries its own cause.
#
# Trust: public key only. The tmpfs signing keyring is trap-wiped before the Pages actions run,
# and a detached signature needs no secret -- this performs exactly the check a
# `gpgcheck=1 repo_gpgcheck=1` client performs. It reports and cannot remediate: the deploy has
# already happened, so a failure exits non-zero to raise the run, and the only sanctioned remedy
# is another rebuild, never a hand-upload into the served tree.
#
# Exit: 0 verified; 1 a mismatch, an unreachable site, or a missing prerequisite. The two
# failures are reported distinctly -- "serves the wrong bytes" and "could not be observed" call
# for different responses.
set -euo pipefail

base="${1:?usage: verify-deploy.sh <site-url> [site-dir]}"
base="${base%/}"
site_dir="${2:-_site}"

# Scratch + keyring in one temp dir, removed on exit: the workspace stays clean and nothing
# survives a cancel during a wait.
work="$(mktemp -d)"; trap 'rm -rf "${work}"' EXIT
GNUPGHOME="${work}/gnupg"; export GNUPGHOME
mkdir -p "${GNUPGHOME}"; chmod 700 "${GNUPGHOME}"
# An empty keyring would make every signature check below fail as "does not sign", so assert the
# import took rather than diagnosing that later.
gpg --batch --quiet --import "${site_dir}/RPM-GPG-KEY-dag-node" \
  || { echo "::error::${site_dir}/RPM-GPG-KEY-dag-node is not valid OpenPGP data"; exit 1; }
gpg --batch --with-colons --list-keys | grep -q '^fpr:' \
  || { echo "::error::the exported public key did not import -- cannot verify the deploy"; exit 1; }

# Propagation budget and poll interval, overridable so the test suite can drive the timeout paths
# in seconds rather than minutes. Defaults are what a real publish run uses.
# Identify the checker: the served site sits behind a CDN/proxy whose bot protection can block
# unattributed automated traffic, and a named agent is what an allow-rule and a security-event
# search can key on. It is not a credential -- everything fetched here is public and signed.
ua="dagnode-rpm-verify/1 (+https://github.com/dag-node/rpm)"

deadline=$((SECONDS + ${VERIFY_BUDGET_SECONDS:-600}))
poll="${VERIFY_POLL_SECONDS:-10}"
why=""; http_code=""; reached=0

# curl's --retry covers transient transport failures; 404s and stale bodies are the propagation
# case and belong to the wait loop. stderr is KEPT: when a wait ends in failure it is the only
# evidence of whether the site was 404, unresolvable, or refusing TLS.
fetch() {
  local rc=0
  http_code="$(curl -fsSL --max-time 60 --retry 3 -A "${ua}" \
                    -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
                    -D "${work}/hdr" -w '%{http_code}' -o "$2" "$1" 2>"${work}/curl.err")" || rc=$?
  [ "${rc}" -eq 0 ] && reached=1
  return "${rc}"
}

# Turn a curl exit into something an operator can act on: "not deployed yet" (404), "cannot
# resolve" and "TLS refused" call for completely different responses.
curl_why() {
  local rc="$1" msg
  msg="$(tr '\n' ' ' < "${work}/curl.err" | sed 's/  */ /g; s/ *$//')"
  case "${rc}" in
    6|7)      echo "cannot reach the host (curl ${rc}): ${msg:-DNS or connect failure}" ;;
    22)
      # 403 from a proxy in front of the site is bot protection, not a missing file -- and it
      # reaches package managers the same way, so name it rather than leave it as "not served yet".
      local ray; ray="$(grep -i '^cf-ray:' "${work}/hdr" 2>/dev/null | tr -d '\r' | tail -1)"
      case "${http_code}" in
        403) echo "HTTP 403 -- blocked before reaching the site (bot protection?); ${ray:-no cf-ray}" ;;
        404) echo "HTTP 404 -- not served yet" ;;
        *)   echo "HTTP ${http_code} (curl 22): ${msg:-unexpected status}" ;;
      esac ;;
    28)       echo "timed out (curl 28): ${msg}" ;;
    35|60|77) echo "TLS failure (curl ${rc}): ${msg}" ;;
    *)        echo "fetch failed (curl ${rc}): ${msg}" ;;
  esac
}

# Probes run one attempt and set `why`. Their locals are re-initialised per call, so a later
# attempt can never report an earlier attempt's digest.
probe_match() {
  local url="$1" want_file="$2" want got rc=0
  want="$(sha256sum "${want_file}" | cut -d' ' -f1)"
  fetch "${url}" "${work}/served.bin" || rc=$?
  if [ "${rc}" -ne 0 ]; then why="$(curl_why "${rc}")"; return 1; fi
  got="$(sha256sum "${work}/served.bin" | cut -d' ' -f1)"
  if [ "${got}" != "${want}" ]; then
    why="serves ${got}, this run built ${want}"; return 1
  fi
}

probe_asc() {
  local url="$1" xml="$2" rc=0
  fetch "${url}" "${work}/served.asc" || rc=$?
  if [ "${rc}" -ne 0 ]; then why="$(curl_why "${rc}")"; return 1; fi
  if ! gpg --batch --verify "${work}/served.asc" "${xml}" 2>"${work}/gpg.err"; then
    why="does not sign the repomd.xml this run built"; return 1
  fi
}

# Retry a probe until it passes or the budget runs out, reporting the live cause each time: the
# wait lines say what it is still waiting on, so a failure needs no second investigation.
await() {
  local url="$1" probe="$2"; shift 2
  while :; do
    if "${probe}" "${url}" "$@"; then echo "  ok    ${url}"; return 0; fi
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      echo "::error::${url}: ${why}"; return 1
    fi
    echo "  wait  ${url}: ${why}"
    sleep "${poll}"
  done
}

# Verify the trees this run actually built, so a new EL major is covered the moment the build
# step emits it -- no second list of majors to keep in sync with publish.yml.
mapfile -t repomds < <(find "${site_dir}/el" -path '*/repodata/repomd.xml' | sort)
[ "${#repomds[@]}" -gt 0 ] \
  || { echo "::error::no repomd.xml in ${site_dir} -- the build produced nothing to verify"; exit 1; }

# Collect every failure before exiting: one broken tree must not hide the others.
fail=0
await "${base}/RPM-GPG-KEY-dag-node" probe_match "${site_dir}/RPM-GPG-KEY-dag-node" || fail=1
for xml in "${repomds[@]}"; do
  rel="${xml#"${site_dir}"/}"
  await "${base}/${rel}"     probe_match "${xml}" || fail=1
  await "${base}/${rel}.asc" probe_asc   "${xml}" || fail=1
done
# The documented one-line install fetches this alias; if it was built it must be served.
if [ -f "${site_dir}/dagnode-release-latest.noarch.rpm" ]; then
  await "${base}/dagnode-release-latest.noarch.rpm" \
        probe_match "${site_dir}/dagnode-release-latest.noarch.rpm" || fail=1
fi

if [ "${fail}" -ne 0 ]; then
  # Not one byte was fetched: the monitoring plane could not observe the site at all, which says
  # nothing about what is served. Distinguish it from a real mismatch so the operator checks
  # connectivity instead of hunting a corrupted repository.
  if [ "${reached}" -eq 0 ]; then
    echo "::error::${base} was unreachable for the whole budget -- the deploy is UNVERIFIED, not proven wrong; check Pages/DNS, then re-run"
  else
    echo "::error::${base} does not serve this run's tree -- re-run the publish to rebuild; do not hand-upload"
  fi
  exit 1
fi
echo "deployed site verified against the built tree"
