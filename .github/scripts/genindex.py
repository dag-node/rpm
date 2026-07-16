#!/usr/bin/env python3
"""Generate utilitarian autoindex pages for the served RPM tree.

Walks the site root given as argv[1] (default _site) and writes an index.html into every
directory: a plain <pre> listing of child directories and files (name + size), Apache-style.
GitHub Pages has no directory listing, and dnf only ever requests explicit file paths, so these
pages are for humans browsing rpm.dagnode.com and are inert to clients. The root index also
carries the install snippet. Regenerated from the assembled tree each run, so it never drifts;
the empty initial state (no releases yet) still renders a valid root page with just the key.
"""
import html
import os
import sys

HOST = "rpm.dagnode.com"
SKIP = {"index.html", "CNAME"}  # infra files, not repository content
FRONT = """DagNode RPM Repository - https://rpm.dagnode.com/

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
sudo dnf install <package>"""


def human(size):
    """Format a byte count as a short Apache-style size (e.g. 12K, 3.4M)."""
    n = float(size)
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024


def render(disp, rows, is_root):
    """Wrap listing rows in the minimal page; the root also carries the install snippet."""
    front = f"<pre>{html.escape(FRONT)}</pre>\n<hr>\n" if is_root else ""
    return (
        "<!doctype html>\n"
        '<html><head><meta charset="utf-8">'
        f"<title>Index of {html.escape(disp)}</title></head><body>\n"
        f"<h1>Index of {html.escape(disp)}</h1>\n{front}"
        "<pre>\n" + "\n".join(rows) + "\n</pre>\n"
        f"<hr><address>{html.escape(HOST)}</address>\n</body></html>\n"
    )


def main(root):
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        is_root = rel == "."
        disp = "/" if is_root else "/" + rel.replace(os.sep, "/") + "/"
        rows = []
        if not is_root:
            rows.append('<a href="../">../</a>')
        for name in sorted(dirnames):
            esc = html.escape(name)
            rows.append(f'<a href="{esc}/">{esc}/</a>')
        for name in sorted(filenames):
            if name in SKIP:
                continue
            size = human(os.path.getsize(os.path.join(dirpath, name)))
            pad = " " * max(1, 44 - len(name))
            esc = html.escape(name)
            rows.append(f'<a href="{esc}">{esc}</a>{pad}{size:>8}')
        with open(os.path.join(dirpath, "index.html"), "w") as fh:
            fh.write(render(disp, rows, is_root))
    print(f"indexed {root}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "_site")
