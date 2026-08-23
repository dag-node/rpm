#!/usr/bin/env bash
#
# Tests for verify-deploy.sh against the ALREADY-PUBLISHED repository.
#
#   test-verify-deploy.sh [site-url]           # defaults to https://rpm.dagnode.com/
#
# Read-only: it fetches the served tree and never deploys, signs, or writes anything outside its
# own temp dir, so it is safe to run on every branch. The CI workflow that calls it holds no
# `pages:` or `id-token:` permission, so it cannot modify the site even by accident.
#
# Method: mirror what the live site serves into a local directory shaped like `_site`, then run
# verify-deploy.sh against the live URL with that mirror as the built tree. That first case must
# PASS, exercising the whole plane end to end -- HTTPS to Pages, tree discovery, real gpg
# verification of the real detached signatures -- which is the surface no fixture can reproduce.
#
# The later cases must FAIL, because a verifier that cannot fail is not a verifier: the pass above
# would equally be produced by a script that returns 0 unconditionally. They corrupt one side of
# the comparison and assert the specific message. Corrupting the SERVED side needs a served side
# under test control, so they re-serve the mirrored bytes over file:// -- the live site is
# read-only and stays that way. Note that verify-deploy.sh reads only the local repomd.xml and
# checks the SERVED signature against it, so a case about signatures has to mutate what is served.
#
# Exit: 0 all cases behaved as specified, 1 otherwise.
set -euo pipefail

site="${1:-https://rpm.dagnode.com/}"; site="${site%/}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verify="${here}/verify-deploy.sh"

work="$(mktemp -d)"; trap 'rm -rf "${work}"' EXIT
mirror="${work}/mirror"
passed=0; failed=0

# Keep the timeout paths in seconds: the cases below deliberately fail, and the default budget is
# ten minutes of retrying before they do.
export VERIFY_BUDGET_SECONDS=4 VERIFY_POLL_SECONDS=2

# Same identification as verify-deploy.sh: the site sits behind a CDN/proxy whose bot protection
# can block unattributed automated traffic.
ua="dagnode-rpm-verify/1 (+https://github.com/dag-node/rpm)"

# Fetch or explain why not. A bare `curl -f` reports "403" and nothing else, which is how a proxy
# block first reached us looking like an unexplained failure.
get() {
  local url="$1" dest="$2" code
  code="$(curl -sSL -A "${ua}" --max-time 60 --retry 3 \
               -D "${work}/hdr" -w '%{http_code}' -o "${dest}" "${url}" 2>/dev/null)" || code=000
  [ "${code}" = "200" ] && return 0
  echo "FATAL: ${url} -> HTTP ${code}"
  grep -iE '^(server|cf-ray|cf-mitigated):' "${work}/hdr" 2>/dev/null | tr -d '\r' | sed 's/^/       /'
  if [ "${code}" = "403" ]; then
    echo "       A 403 here is the proxy in front of the site refusing an automated client, not a"
    echo "       missing file. dnf reaches this repository the same way, so allow this agent (or"
    echo "       package-manager traffic generally) in the proxy's bot-protection rules."
  fi
  return 1
}

# Directory entries from a genindex.py page, so the mirrored tree follows what is actually served
# rather than a hard-coded list of EL majors.
list_dirs() {
  get "$1" "${work}/idx" || exit 1
  grep -oE 'href="[^"]+/"' "${work}/idx" | sed 's/^href="//; s/\/"$//' | grep -vE '^\.\.$'
}

echo "== mirroring ${site} =="
mkdir -p "${mirror}"
get "${site}/RPM-GPG-KEY-dag-node" "${mirror}/RPM-GPG-KEY-dag-node" || exit 1
get "${site}/dagnode-release-latest.noarch.rpm" "${mirror}/dagnode-release-latest.noarch.rpm" \
  || echo "  (no bootstrap alias served)"
trees=0
for major in $(list_dirs "${site}/el/"); do
  for arch in $(list_dirs "${site}/el/${major}/"); do
    [ "${arch}" = "repodata" ] && continue
    d="${mirror}/el/${major}/${arch}/repodata"; mkdir -p "${d}"
    get "${site}/el/${major}/${arch}/repodata/repomd.xml"     "${d}/repomd.xml"     || exit 1
    get "${site}/el/${major}/${arch}/repodata/repomd.xml.asc" "${d}/repomd.xml.asc" || exit 1
    trees=$((trees+1)); echo "  el/${major}/${arch}"
  done
done
[ "${trees}" -gt 0 ] || { echo "FATAL: no trees discovered at ${site}/el/ -- nothing to test"; exit 1; }

# Run one case: name, expected exit status, pattern the output must contain, then the site dir.
# A case that fails for the wrong reason is not a pass, hence matching on the message too.
case_is() {
  local name="$1" want_rc="$2" want_msg="$3" dir="$4" url="${5:-${site}}" out rc=0
  out="$(bash "${verify}" "${url}" "${dir}" 2>&1)" || rc=$?
  if [ "${rc}" -eq "${want_rc}" ] && grep -qF "${want_msg}" <<<"${out}"; then
    echo "PASS  ${name}"; passed=$((passed+1))
  else
    echo "FAIL  ${name}: expected exit ${want_rc} matching '${want_msg}', got exit ${rc}"
    while IFS= read -r line; do echo "        | ${line}"; done < <(tail -6 <<<"${out}")
    failed=$((failed+1))
  fi
}

echo
echo "== cases =="
# The plane works end to end against the real site: real HTTPS, real Pages, real signatures.
case_is "live site verifies against what it serves" 0 "deployed site verified" "${mirror}"

# Mutations need a served side under test control -- the live site is read-only and must stay that
# way -- so the cases below serve a local copy over file:// and corrupt whichever side they are
# about. The bytes and signatures are still the real ones fetched above.
served="${work}/served"; url="file://${served}"
built="${work}/built"

reset_pair() { rm -rf "${served}" "${built}"; cp -r "${mirror}" "${served}"; cp -r "${mirror}" "${built}"; }

reset_pair
first_xml="$(find "${served}/el" -path '*/repodata/repomd.xml' | sort | head -1)"
printf '<repomd>tampered</repomd>\n' > "${first_xml}"
case_is "detects served metadata that differs from the built tree" 1 \
        "does not serve this run's tree" "${built}" "${url}"

# A valid signature over DIFFERENT metadata: the case a naive "does the .asc verify at all" check
# waves through. Pick a donor from a tree whose metadata genuinely differs, since trees with
# identical metadata carry identical signatures.
reset_pair
mapfile -t xmls < <(find "${served}/el" -path '*/repodata/repomd.xml' | sort)
donor=""
for x in "${xmls[@]:1}"; do
  if ! cmp -s "${xmls[0]}" "${x}"; then donor="${x}.asc"; break; fi
done
if [ -n "${donor}" ]; then
  cp -f "${donor}" "${xmls[0]}.asc"
  case_is "detects a valid signature over the wrong metadata" 1 \
          "does not sign the repomd.xml" "${built}" "${url}"
else
  echo "SKIP  wrong-metadata signature (every served tree carries identical metadata)"
fi

reset_pair
printf 'a different key\n' > "${served}/RPM-GPG-KEY-dag-node"
case_is "detects a served public key that is not the one exported" 1 \
        "does not serve this run's tree" "${built}" "${url}"

reset_pair
rm -f "${served}"/el/*/*/repodata/repomd.xml.asc
case_is "detects missing signatures on the served tree" 1 \
        "does not serve this run's tree" "${built}" "${url}"

reset_pair
printf 'not a key\n' > "${built}/RPM-GPG-KEY-dag-node"
case_is "rejects a public key that is not OpenPGP data" 1 "is not valid OpenPGP data" "${built}" "${url}"

reset_pair
rm -rf "${built:?}/el"; mkdir -p "${built}/el"
case_is "refuses a built tree with no metadata" 1 "nothing to verify" "${built}" "${url}"

# Unreachable must read as "could not observe", never as "the repository is wrong" -- the two call
# for different responses, and conflating them is what turned a good publish into a false alarm.
case_is "reports an unreachable site as UNVERIFIED" 1 "UNVERIFIED" "${mirror}" \
        "https://rpm-does-not-exist.dagnode.invalid"

echo
echo "== ${passed} passed, ${failed} failed =="
[ "${failed}" -eq 0 ]
