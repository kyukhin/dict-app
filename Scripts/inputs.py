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
"""

from __future__ import annotations

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


def _pins() -> dict:
    with open(INPUTS_JSON, encoding="utf-8") as f:
        return json.load(f)


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
    pins = _pins()
    if key not in pins:
        raise RuntimeError(f"{key} is not pinned in {INPUTS_JSON.name}")
    url, expected = pins[key]["url"], pins[key]["sha256"]
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


def use_nltk_data(cache_dir: Path) -> None:
    """Fetch the pinned WordNet 3.0 and OMW 1.4 corpora and point NLTK at
    them alone, so neither `~/nltk_data` nor `nltk.download()` (unversioned)
    can change the rows. NLTK reads the corpora straight from the zips."""
    try:
        import nltk
    except ImportError as err:
        raise RuntimeError("Missing build dependency 'nltk'. Install it first: "
                           "pip install -r Scripts/requirements.txt") from err
    for key in NLTK_CORPORA:
        fetch(key, cache_dir)
    nltk.data.path[:] = [str(Path(cache_dir) / "nltk_data")]
