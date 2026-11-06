#!/usr/bin/env python3
"""
check_release_assets.py
Downloads every pack asset the catalog of the bundled dictionary file names
and checks its size and sha256 (docs/specs/0237-downloads.md, "Build and
release", step 3). It must pass before any TestFlight or App Store upload:
the app downloads exactly these URLs and rejects an asset whose sha256
differs. Standard library only.

Usage (from the repository root):
    python3 Scripts/check_release_assets.py
    python3 Scripts/check_release_assets.py --bundle path/to/dictionaries.sqlite
"""

from __future__ import annotations

import argparse
import hashlib
import sqlite3
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_BUNDLE = REPO / "DictApp/DictApp/Resources/dictionaries.sqlite"


def catalog(bundle: Path) -> list[tuple[str, str, str, int]]:
    """(id, url, sha256, size) of every catalog pack, in `ord` order."""
    with open(bundle, "rb") as f:
        if f.read(16) != b"SQLite format 3\0":
            sys.exit(f"{bundle} is not an SQLite file (a Git LFS pointer? git lfs pull)")
    conn = sqlite3.connect("file:" + str(bundle) + "?mode=ro&immutable=1", uri=True)
    try:
        return conn.execute("SELECT id, url, sha256, size FROM catalog_pack ORDER BY ord").fetchall()
    finally:
        conn.close()


def download(url: str) -> tuple[str, int]:
    """The sha256 and size of what `url` serves, streamed; redirects followed."""
    digest = hashlib.sha256()
    size = 0
    request = urllib.request.Request(url, headers={"User-Agent": "LibreDict check_release_assets"})
    with urllib.request.urlopen(request, timeout=60) as response:
        for chunk in iter(lambda: response.read(1 << 20), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def main() -> int:
    parser = argparse.ArgumentParser(description="Check every catalog asset on GitHub Releases.")
    parser.add_argument("--bundle", type=Path, default=DEFAULT_BUNDLE,
                        help="The dictionary file whose catalog to check (default: the app's).")
    args = parser.parse_args()
    packs = catalog(args.bundle)
    if not packs:
        sys.exit("The catalog lists no packs")
    failures = 0
    for pack_id, url, sha256, size in packs:
        try:
            got_sha, got_size = download(url)
        except Exception as error:  # noqa: BLE001  (any failure is a failed check)
            print(f"FAIL {pack_id}: {url}: {error}")
            failures += 1
            continue
        if (got_sha, got_size) != (sha256, size):
            print(f"FAIL {pack_id}: {url}: {got_size:,} B sha256 {got_sha}, the catalog pins "
                  f"{size:,} B sha256 {sha256}")
            failures += 1
        else:
            print(f"ok   {pack_id}: {size:,} B sha256 {sha256[:16]}…")
    if failures:
        print(f"{failures} of {len(packs)} assets failed")
        return 1
    print(f"All {len(packs)} assets match the catalog.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
