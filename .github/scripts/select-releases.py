#!/usr/bin/env python3
"""Select which release tags to publish, bounding the served repository's history.

Reads release tags (one per line) on stdin and prints the tags to keep, newest first. Retention,
applied per project by publish.yml:

  * For each MAJOR.MINOR series keep only the latest MAJOR.MINOR.PATCH -- patch releases are
    bugfixes, so an older patch of the same minor is superseded and dropped.
  * Then keep the KEEP_MINORS most-recent minor series and evict older ones.

The result is at most KEEP_MINORS versions per package name, so history cannot balloon over time,
while a client can still pin or downgrade across the recent minors. Tags that are not
vMAJOR.MINOR.PATCH are ignored. Signature verification is a separate, later step: an unsigned
selected package is dropped there, not here.

Usage:
    gh release list ... | select-releases.py [KEEP_MINORS]   # KEEP_MINORS default 10
"""
import re
import sys

TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def select(tags, keep_minors):
    """Return the retained tags (newest first): the latest patch of each of the KEEP_MINORS
    most-recent MAJOR.MINOR series."""
    latest = {}  # (major, minor) -> (major, minor, patch), the highest patch seen for that minor
    for tag in tags:
        matched = TAG.match(tag.strip())
        if not matched:
            continue
        major, minor, patch = (int(g) for g in matched.groups())
        current = latest.get((major, minor))
        if current is None or patch > current[2]:
            latest[(major, minor)] = (major, minor, patch)
    kept = sorted(latest.values(), reverse=True)[:keep_minors]
    return [f"v{major}.{minor}.{patch}" for major, minor, patch in kept]


def main():
    keep_minors = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    for tag in select(sys.stdin.read().splitlines(), keep_minors):
        print(tag)


if __name__ == "__main__":
    main()
