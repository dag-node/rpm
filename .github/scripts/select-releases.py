#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Select which release tags to publish, bounding the served repository's history.

Reads release tags (one per line) on stdin and prints the tags to keep, newest first, each as it
was listed. Retention, applied per project by publish.yml:

  * Discard any tag below MIN_VERSION, the project's floor from projects.txt (default 0.0.0, no
    floor). The floor drops a retired line -- tools-agent-tools-restricted's pre-integrations-split
    0.6.x packages -- without touching a project that versions independently.
  * Of the tags at or above the floor, for each series keep only the latest MAJOR.MINOR.PATCH --
    patch releases are bugfixes, so an older patch of the same minor is superseded and dropped.
    Every minor at or above the floor is kept (no rolling window), so a client can pin or
    downgrade across the whole retained range.

A tag is `vMAJOR.MINOR.PATCH` or `<set>/vMAJOR.MINOR.PATCH`, the form a repository releasing
several packages uses (ai-tools-assets tags `core/v0.1.0`); a set is its own run of series, so
`core/v0.1.0` and `v0.1.0` in one project are two series. Any other tag is ignored. Signature
verification is a separate, later step: an unsigned selected package is dropped there, not here.

Usage:
    gh release list ... | select-releases.py [MIN_VERSION]   # MIN_VERSION default 0.0.0
"""
import re
import sys

TAG = re.compile(r"^(?:(?P<set>[a-z0-9][a-z0-9-]*)/)?v?(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)$")
DEFAULT_MIN = "0.0.0"


def parse(spec):
    """Parse `[<set>/]vMAJOR.MINOR.PATCH` (leading v optional) into (set, (major, minor, patch)),
    with the set '' for a bare tag, or None."""
    matched = TAG.match(spec.strip())
    if not matched:
        return None
    return matched.group("set") or "", tuple(int(matched.group(part)) for part in ("major", "minor", "patch"))


def select(tags, min_version):
    """Return the retained tags: the latest patch of every MAJOR.MINOR series at or above
    min_version, each tag as it was given -- the bare tags first, then each set by name, newest
    first within each."""
    latest = {}  # (set, major, minor) -> ((major, minor, patch), tag), the highest patch seen for that series
    for tag in tags:
        parsed = parse(tag)
        if parsed is None or parsed[1] < min_version:
            continue
        set_name, version = parsed
        key = (set_name, version[0], version[1])
        current = latest.get(key)
        if current is None or version[2] > current[0][2]:
            latest[key] = (version, tag.strip())
    kept = sorted(latest.items(), key=lambda item: (item[0][0] != "", item[0][0], tuple(-part for part in item[1][0])))
    return [tag for _, (_, tag) in kept]


def main():
    spec = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MIN
    parsed = parse(spec)
    if parsed is None or parsed[0]:
        sys.exit(f"select-releases: invalid MIN_VERSION {spec!r} (want MAJOR.MINOR.PATCH)")
    for tag in select(sys.stdin.read().splitlines(), parsed[1]):
        print(tag)


if __name__ == "__main__":
    main()
