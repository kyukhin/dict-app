#!/usr/bin/env python3
"""
build_freedict_eng_spa.py
Download the FreeDict English–Spanish (`eng-spa`) TEI/XML release and
emit `(word, definition, phonetic, pos, source)` tuples that match the
existing `entries` schema in `seed.sqlite`. Designed to be called from
`build_seed.py` (orchestrator) but also runnable stand-alone for
debugging.

Source identifier convention (for multi-language dictionaries):
    provider-srclang-tgtlang (ISO-639-3 codes)
e.g. "freedict-eng-spa".

Usage:
    python Scripts/build_freedict_eng_spa.py            # print summary
    python Scripts/build_freedict_eng_spa.py --dump 5   # print 5 entries

Requirements:
    pip install requests defusedxml

Network artifacts (TEI tarballs) are cached under
`Scripts/.cache/freedict-eng-spa/<version>/` so re-runs are offline.
"""

from __future__ import annotations

import argparse
import io
import os
import re
import sys
import tarfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Public constants — consumed by build_seed.py for dict_metadata.
# ---------------------------------------------------------------------------

SOURCE = "freedict-eng-spa"
DISPLAY_NAME = "English – Spanish (FreeDict)"
URL = "https://freedict.org/freedict-database/eng-spa/"

LICENSE_TEXT = (
    "GNU General Public License v3.0 (GPL-3.0)\n\n"
    "Copyright (C) The FreeDict project and contributors.\n\n"
    "This dictionary is free software: you can redistribute it and/or "
    "modify it under the terms of the GNU General Public License as "
    "published by the Free Software Foundation, either version 3 of the "
    "License, or (at your option) any later version.\n\n"
    "This dictionary is distributed in the hope that it will be useful, "
    "but WITHOUT ANY WARRANTY; without even the implied warranty of "
    "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the "
    "GNU General Public License for more details.\n\n"
    "Full license text: https://www.gnu.org/licenses/gpl-3.0.en.html"
)

DESCRIPTION_TEXT = (
    "FreeDict is a project that provides free bilingual dictionaries "
    "in machine-readable form. The English–Spanish (eng-spa) dictionary "
    "covers approximately 64,000 headwords with translations, parts of "
    "speech, and pronunciation hints where available.\n\n"
    "The data is distributed in TEI (Text Encoding Initiative) XML and "
    "is converted into the app's storage format at build time. The "
    "underlying entries remain freely redistributable under the GPL."
)

# ---------------------------------------------------------------------------
# Network + cache
# ---------------------------------------------------------------------------

CACHE_ROOT = Path(__file__).parent / ".cache" / "freedict-eng-spa"

# FreeDict hosts dictionaries on their own CDN, one directory per
# language pair. Each version directory exposes `*.src.tar.xz` (which
# contains the TEI XML), `*.dictd.tar.xz`, `*.slob`, and `*.stardict.*`.
FREEDICT_INDEX_URL = "https://download.freedict.org/dictionaries/eng-spa/"
FREEDICT_VERSION_DIR_RE = re.compile(r'href="([0-9]+\.[0-9.]+)/"')
FREEDICT_SRC_ASSET = "freedict-eng-spa-{version}.src.tar.xz"


def _ensure_requests():
    """Return the `requests` module, failing fast if it isn't installed.

    Build dependencies are listed in the module docstring; we don't
    `pip install` at runtime, which would make builds non-deterministic
    and break in offline/restricted CI."""
    try:
        import requests
    except ImportError as err:
        raise RuntimeError(
            "Missing build dependency 'requests'. Install it first: "
            "pip install requests defusedxml"
        ) from err
    return requests


def _safe_etree():
    """Return the defusedxml ElementTree module, failing fast if absent.

    The TEI dump comes from a remote source, so we parse it with
    defusedxml's hardened `iterparse` to mitigate XML attacks (billion
    laughs / entity expansion, external entity resolution). Like
    `_ensure_requests`, this never installs at runtime."""
    try:
        import defusedxml.ElementTree as safe_et
    except ImportError as err:
        raise RuntimeError(
            "Missing build dependency 'defusedxml'. Install it first: "
            "pip install requests defusedxml"
        ) from err
    return safe_et


def _version_sort_key(v: str) -> tuple:
    """Sort '2025.11.23' above '0.3.1' above '0.3'. Pure-numeric tuple
    comparison handles both `0.x` and date-based `YYYY.MM.DD` variants."""
    parts = []
    for chunk in v.split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(-1)
    return tuple(parts)


def _resolve_release(requests_mod) -> tuple[str, str]:
    """Return (version_tag, download_url) for the newest eng-spa source
    tarball available on the FreeDict CDN. Falls back to a known-good
    pinned release if the CDN is unreachable — see `_PINNED_FALLBACK`."""
    try:
        resp = requests_mod.get(FREEDICT_INDEX_URL, timeout=30)
        resp.raise_for_status()
        versions = FREEDICT_VERSION_DIR_RE.findall(resp.text)
        if not versions:
            raise RuntimeError("no version directories found in CDN listing")
        versions.sort(key=_version_sort_key)
        latest = versions[-1]
        url = f"{FREEDICT_INDEX_URL}{latest}/{FREEDICT_SRC_ASSET.format(version=latest)}"
        return latest, url
    except Exception as exc:
        print(f"  WARNING: FreeDict CDN listing failed ({exc}); using pinned fallback.")
    return _PINNED_FALLBACK


# Pinned baseline — updated whenever a known-good release is verified.
_PINNED_FALLBACK = (
    "2025.11.23",
    "https://download.freedict.org/dictionaries/eng-spa/2025.11.23/"
    "freedict-eng-spa-2025.11.23.src.tar.xz",
)


def _download(requests_mod, url: str, dest: Path) -> None:
    print(f"  Downloading {url} -> {dest.name}")
    resp = requests_mod.get(url, stream=True, timeout=120)
    resp.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "wb") as out:
        for chunk in resp.iter_content(chunk_size=64 * 1024):
            if chunk:
                out.write(chunk)


def _ensure_tarball(version: str, url: str) -> Path:
    """Return the local path to the cached tarball, downloading if absent."""
    cache_dir = CACHE_ROOT / version
    tarball = cache_dir / os.path.basename(url)
    if tarball.exists() and tarball.stat().st_size > 0:
        return tarball
    requests_mod = _ensure_requests()
    _download(requests_mod, url, tarball)
    return tarball


def _extract_tei(tarball: Path) -> Path:
    """Extract the .tei file from the tarball and return its path.

    The tarball comes from a remote source, so the member path is
    validated to stay inside `target_dir` before extraction — a crafted
    archive with an absolute path or `..` components could otherwise
    write anywhere on disk (CVE-style tar path traversal)."""
    with tarfile.open(tarball, "r:*") as tf:
        tei_members = [m for m in tf.getmembers() if m.name.endswith(".tei")]
        if not tei_members:
            raise RuntimeError(f"No .tei file inside {tarball}")
        member = tei_members[0]
        target_dir = (tarball.parent / "extracted").resolve()
        target_dir.mkdir(exist_ok=True)

        dest = (target_dir / member.name).resolve()
        try:
            dest.relative_to(target_dir)
        except ValueError:
            raise RuntimeError(
                f"Refusing to extract '{member.name}': resolves outside {target_dir}"
            )

        # Stream the validated member to the validated destination rather
        # than letting tarfile choose the path from member.name.
        extracted = tf.extractfile(member)
        if extracted is None:
            raise RuntimeError(f"Member '{member.name}' is not a regular file")
        dest.parent.mkdir(parents=True, exist_ok=True)
        with extracted, open(dest, "wb") as out:
            out.write(extracted.read())
        return dest


# ---------------------------------------------------------------------------
# TEI parsing
# ---------------------------------------------------------------------------

# Default TEI namespace used by FreeDict.
TEI_NS = "http://www.tei-c.org/ns/1.0"
NS = {"t": TEI_NS}


# Map TEI's abbreviated <pos> values to the long-form labels WordNet uses
# (so search-result POS lines are consistent across sources).
POS_NORMALISATION = {
    "n": "noun",
    "v": "verb",
    "vt": "verb",
    "vi": "verb",
    "adj": "adjective",
    "a": "adjective",
    "adv": "adverb",
    "r": "adverb",
    "prep": "preposition",
    "conj": "conjunction",
    "pron": "pronoun",
    "interj": "interjection",
    "num": "numeral",
    "art": "article",
    "phr": "phrase",
    "pn": "proper noun",
    "propn": "proper noun",
    "abbr": "abbreviation",
}


def _normalise_pos(raw: str) -> str:
    if not raw:
        return ""
    key = raw.strip().lower()
    return POS_NORMALISATION.get(key, key)


def _text(elem) -> str:
    """Concatenated stripped text content of an element, including tails of
    nested children (e.g. <quote> with embedded markup)."""
    if elem is None:
        return ""
    return "".join(elem.itertext()).strip()


def _aggregate_definition(senses_by_pos: dict[str, list[str]]) -> str:
    """Format senses into the same markdown shape WordNet emits:
        **noun**
        1. casa
        2. hogar (informal)
    """
    parts: list[str] = []
    for pos_label, translations in senses_by_pos.items():
        if not translations:
            continue
        if pos_label:
            parts.append(f"**{pos_label}**")
        for i, line in enumerate(translations, 1):
            parts.append(f"{i}. {line}")
        parts.append("")
    return "\n".join(parts).strip()


def parse_tei(tei_path: Path) -> list[tuple]:
    """Stream the TEI file and produce one row per headword.

    Returned tuples are `(word, definition, phonetic, pos, source)` and
    match the schema of the existing `entries` table.
    """
    rows: list[tuple] = []
    skipped_no_sense = 0

    # iterparse keeps memory bounded — the TEI file can be tens of MB.
    # defusedxml's iterparse hardens against XML entity-expansion attacks.
    safe_et = _safe_etree()
    context = safe_et.iterparse(str(tei_path), events=("end",))
    for event, elem in context:
        tag = elem.tag
        if not tag.endswith("entry"):
            continue

        orths = elem.findall(".//t:form/t:orth", NS)
        if not orths:
            elem.clear()
            continue

        pos_elem = elem.find(".//t:gramGrp/t:pos", NS)
        pos_label = _normalise_pos(_text(pos_elem))

        pron_elem = elem.find(".//t:pron", NS)
        phonetic = _text(pron_elem)

        # Aggregate senses; group by POS so a multi-POS entry renders cleanly.
        senses_by_pos: dict[str, list[str]] = {pos_label: []}
        for sense in elem.findall(".//t:sense", NS):
            translation_chunks: list[str] = []
            for cit in sense.findall("t:cit", NS):
                if cit.get("type") != "trans":
                    continue
                quote = cit.find("t:quote", NS)
                qtxt = _text(quote)
                if qtxt:
                    translation_chunks.append(qtxt)
            if not translation_chunks:
                continue
            # Append note text in parentheses when present (e.g. "informal").
            note_elem = sense.find("t:note", NS)
            note = _text(note_elem)
            joined = ", ".join(translation_chunks)
            if note:
                joined = f"{joined} ({note})"
            senses_by_pos.setdefault(pos_label, []).append(joined)

        if not senses_by_pos.get(pos_label):
            skipped_no_sense += 1
            elem.clear()
            continue

        definition = _aggregate_definition(senses_by_pos)
        for orth in orths:
            word = _text(orth)
            if not word:
                continue
            rows.append((word, definition, phonetic, pos_label, SOURCE))

        elem.clear()

    if skipped_no_sense:
        print(f"  Skipped {skipped_no_sense} entries with no usable translation.")
    return rows


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def download_and_parse() -> tuple[list[tuple], str]:
    """Resolve, fetch, cache, extract, and parse the latest eng-spa TEI.

    Returns:
        (rows, version) where `rows` is the list of
        `(word, definition, phonetic, pos, "freedict-eng-spa")` tuples
        and `version` is the upstream release tag (used by `build_seed`
        for `dict_metadata.version`).
    """
    requests_mod = _ensure_requests()
    version, url = _resolve_release(requests_mod)
    tarball = _ensure_tarball(version, url)
    tei_path = _extract_tei(tarball)
    rows = parse_tei(tei_path)
    return rows, version


# ---------------------------------------------------------------------------
# Stand-alone debug runner
# ---------------------------------------------------------------------------

def _main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dump", type=int, default=0,
                    help="Print the first N parsed entries and exit.")
    args = ap.parse_args()

    rows, version = download_and_parse()
    print(f"\nFreeDict eng-spa {version}: {len(rows):,} entries parsed.")
    for row in rows[: args.dump]:
        word, definition, phonetic, pos, source = row
        print(f"\n--- {word}  [{pos}]  /{phonetic}/ ---")
        print(definition)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
