#!/usr/bin/env python3
"""
inputs.py
The pinned inputs of the dictionary build (docs/specs/0129-dictionary-file.md,
"Adding static data"). `inputs.json` maps each input's path in the cache
directory to an immutable URL (a versioned release or a commit SHA, never a
branch or a "latest" listing) and its sha256. `fetch()` downloads an input
once and verifies it before every use, so a build never reads a file that
differs from its pin.

Adding an input: download it, put `"<dir>/<file>": {"url": …, "sha256": …}`
into `inputs.json` and read it through `fetch("<dir>/<file>", cache_dir)`.
Extra keys in an entry are allowed and ignored here.

An entry without `url` is a file committed to the repository (Git LFS),
keyed by its path from the repository root, for a source that keeps no
old versions online (the Greek forms subset, #141). `committed(key)`
verifies it the same way and never downloads.
"""

from __future__ import annotations

import functools
import hashlib
import json
import os
import shutil
import urllib.request
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
INPUTS_JSON = SCRIPTS_DIR / "inputs.json"
# Git-ignored. `build_dictionaries.py --cache-dir` points elsewhere.
DEFAULT_CACHE_DIR = SCRIPTS_DIR / ".cache"

NLTK_CORPORA = ("nltk_data/corpora/wordnet.zip", "nltk_data/corpora/omw-1.4.zip")


def pins() -> dict:
    with open(INPUTS_JSON, encoding="utf-8") as f:
        return json.load(f)


def write_pins(entries: dict) -> None:
    """Rewrite inputs.json with its keys sorted (`build_forms.py --refresh`)."""
    with open(INPUTS_JSON, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(entries.items())), f, indent=2, ensure_ascii=False)
        f.write("\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(key: str, cache_dir: Path) -> Path:
    """Return `cache_dir/key`, the verified local copy of input `key`.

    Downloads it when it is missing or its sha256 differs from the pin, and
    fails the build when the downloaded file does not match either."""
    pins_ = pins()
    if key not in pins_ or "url" not in pins_[key]:
        raise RuntimeError(f"{key} is not pinned to a URL in {INPUTS_JSON.name}")
    url, expected = pins_[key]["url"], pins_[key]["sha256"]
    path = Path(cache_dir) / key
    if path.is_file() and sha256(path) == expected:
        return path

    print(f"  Downloading {url}")
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".part")
    with urllib.request.urlopen(url, timeout=120) as resp, open(partial, "wb") as out:
        shutil.copyfileobj(resp, out, 1 << 16)
    actual = sha256(partial)
    if actual != expected:
        partial.unlink()
        raise RuntimeError(f"{key}: downloaded sha256 {actual} does not match "
                           f"{INPUTS_JSON.name} ({expected}), from {url}")
    os.replace(partial, path)
    return path


def committed(key: str) -> Path:
    """Return the committed input `key` (a path from the repository root)
    after checking its sha256 against the pin; fail the build otherwise."""
    entry = pins().get(key)
    if entry is None or "url" in entry:
        raise RuntimeError(f"{key} is not pinned as a committed file in {INPUTS_JSON.name}")
    path = SCRIPTS_DIR.parent / key
    if not path.is_file():
        raise RuntimeError(f"{key} is missing (git lfs pull?)")
    actual = sha256(path)
    if actual != entry["sha256"]:
        raise RuntimeError(f"{key}: sha256 {actual} does not match {INPUTS_JSON.name} "
                           f"({entry['sha256']}); a Git LFS pointer? git lfs pull")
    return path


def use_nltk_data(cache_dir: Path) -> None:
    """Fetch the pinned WordNet 3.0 and OMW 1.4 corpora and point NLTK at
    them alone, so neither `~/nltk_data` nor `nltk.download()` (unversioned)
    can change the rows. Read them through `corpora/<name>.zip/...` paths:
    a plain `corpora/<name>` path prefers an extracted copy that no pin covers."""
    try:
        import nltk
    except ImportError as err:
        raise RuntimeError("Missing build dependency 'nltk'. Install it first: "
                           "pip install -r Scripts/requirements.txt") from err
    for key in NLTK_CORPORA:
        fetch(key, cache_dir)
    root = Path(cache_dir) / "nltk_data"
    # NLTK 3.10 refuses data that another account can write to, which a
    # umask of 002 gives every download: drop the group and world write bits.
    for path in (root, *root.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"{path} is a symlink; the NLTK cache takes plain files only")
        mode = path.stat().st_mode
        if mode & 0o022:
            path.chmod(mode & ~0o022)
    nltk.data.path[:] = [str(root)]


@functools.cache
def wordnet(cache_dir: Path):
    """The WordNet 3.0 reader with OMW 1.4 on the pinned zips, one instance
    shared by the builders. Since NLTK 3.10 `nltk.corpus.wordnet` reads
    `omw-2.0`, which is not pinned; this is its NLTK 3.9 definition."""
    use_nltk_data(cache_dir)
    import nltk
    from nltk.corpus.reader import CorpusReader, WordNetCorpusReader

    omw = CorpusReader(nltk.data.find("corpora/omw-1.4.zip/omw-1.4/"),
                       r".*/wn-data-.*\.tab", encoding="utf8")
    return WordNetCorpusReader(nltk.data.find("corpora/wordnet.zip/wordnet/"), omw)
