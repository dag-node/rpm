#!/usr/bin/env python3
"""Select which release tags to publish, bounding the served repository's history.

Reads release tags (one per line) on stdin and prints the tags to keep, newest first. Retention,
applied per project by publish.yml:

  * Discard any tag below MIN_VERSION (default v0.11.1). This drops the pre-integrations-split
    line (the 0.6.x packages) that only clutters the repo and is no longer recommended, without
    touching projects that version independently -- dagnode-release (v1.0.0+) sits above the
    floor and is kept.
  * Of the tags at or above the floor, for each MAJOR.MINOR series keep only the latest
    MAJOR.MINOR.PATCH -- patch releases are bugfixes, so an older patch of the same minor is
    superseded and dropped. Every minor at or above the floor is kept (no rolling window), so a
    client can pin or downgrade across the whole retained range.

Tags that are not vMAJOR.MINOR.PATCH are ignored. Signature verification is a separate, later
step: an unsigned selected package is dropped there, not here.

Usage:
    gh release list ... | select-releases.py [MIN_VERSION]   # MIN_VERSION default 0.11.1
"""
import re
import sys

TAG = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
DEFAULT_MIN = "0.11.1"


def parse(spec):
    """Parse vMAJOR.MINOR.PATCH (leading v optional) into an (int, int, int) tuple, or None."""
    matched = TAG.match(spec.strip())
    return tuple(int(g) for g in matched.groups()) if matched else None


def select(tags, min_version):
    """Return the retained tags (newest first): the latest patch of every MAJOR.MINOR series at
    or above min_version."""
    latest = {}  # (major, minor) -> (major, minor, patch), the highest patch seen for that minor
    for tag in tags:
        version = parse(tag)
        if version is None or version < min_version:
            continue
        major, minor, patch = version
        current = latest.get((major, minor))
        if current is None or patch > current[2]:
            latest[(major, minor)] = version
    kept = sorted(latest.values(), reverse=True)
    return [f"v{major}.{minor}.{patch}" for major, minor, patch in kept]


def main():
    spec = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MIN
    min_version = parse(spec)
    if min_version is None:
        sys.exit(f"select-releases: invalid MIN_VERSION {spec!r} (want MAJOR.MINOR.PATCH)")
    for tag in select(sys.stdin.read().splitlines(), min_version):
        print(tag)


if __name__ == "__main__":
    main()
