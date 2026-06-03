#!/usr/bin/env python3
"""
build_arabic_wordnet.py
Build an Arabic→English dictionary from the Open Multilingual WordNet
(OMW) Arabic data (`lang='arb'`) — the Arabic counterpart to the Spanish
WordNet source delivered in Issue #42.

Strategy (see DESIGN_DOC.md, Issue #10): the synset join happens in
Python against a single, synset-aware NLTK WordNet instance. Arabic
lemmas (`Synset.lemma_names('arb')`) and the English glosses/synonyms
(`Synset.definition()` / `Synset.lemma_names()`) are read from the *same*
WordNet object, so the synset IDs are shared by construction — there is
no cross-version offset table to misalign. The app never sees synset IDs;
it receives flat `entries` rows exactly like every other source.

Arabic OMW lemmas are *vocalized* (carry harakat). The displayed `word`
keeps the full vocalization; the search key `word_normalized` is the
harakat-stripped form (via `arabic_normalize.normalize_arabic`, the single
source of truth) so a user typing the bare form still matches. ~69% of
Arabic lemmas carry harakat, so this column is load-bearing, not cosmetic.

Source identifier: "wordnet-arb-eng" (provider-srclang-tgtlang, matching
the convention used by "wordnet-spa-eng" / "freedict-eng-spa").

Usage:
    python Scripts/build_arabic_wordnet.py            # print summary
    python Scripts/build_arabic_wordnet.py --dump 5   # print 5 entries

Requirements (NLTK + the WordNet and OMW corpora):
    pip install nltk
    # corpora are fetched on first run via nltk.download()
"""

from __future__ import annotations

import argparse
import os
import sys

# Import the normalizer as the single source of truth for the search key.
# Works whether this module is run directly or imported by build_seed.py.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arabic_normalize import normalize_arabic

# ---------------------------------------------------------------------------
# Public constants — consumed by build_seed.py for dict_metadata.
# ---------------------------------------------------------------------------

SOURCE = "wordnet-arb-eng"
DISPLAY_NAME = "Arabic – English (WordNet)"
URL = "https://compling.hss.ntu.edu.sg/omw/"

LICENSE_TEXT = (
    "Arabic WordNet (AWN), distributed via the Open Multilingual "
    "WordNet (OMW).\n\n"
    "The Arabic WordNet data is released under the Creative Commons "
    "Attribution 3.0 Unported License (CC BY 3.0).\n\n"
    "You are free to share and adapt the material for any purpose, even "
    "commercially, provided you give appropriate credit to the Arabic "
    "WordNet project and the Open Multilingual WordNet.\n\n"
    "The English glosses and synset structure derive from Princeton "
    "WordNet 3.0, used under the WordNet 3.0 License (BSD-style), "
    "Copyright 2006 Princeton University.\n\n"
    "Full license texts:\n"
    "  • https://creativecommons.org/licenses/by/3.0/\n"
    "  • https://wordnet.princeton.edu/license-and-commercial-use"
)

DESCRIPTION_TEXT = (
    "Arabic WordNet provides Arabic lemmas aligned to Princeton WordNet "
    "synsets. Each Arabic headword is mapped to its English translation "
    "lemmas and the English gloss for every sense, grouped by part of "
    "speech.\n\n"
    "The data comes from the Arabic WordNet (AWN) project, accessed here "
    "through the Open Multilingual WordNet (OMW) packaged with NLTK. "
    "Because the Arabic lemmas and English glosses are read from the same "
    "WordNet 3.0 instance, the synset mapping is exact — no cross-version "
    "alignment is involved.\n\n"
    "Arabic headwords are shown fully vocalized (with harakat); search is "
    "diacritic-insensitive, so the bare unvocalized form matches too."
)

# Arabic lemma lookup language code used by NLTK/OMW.
_OMW_LANG = "arb"


# ---------------------------------------------------------------------------
# NLTK bootstrap (data download only — never a runtime `pip install`)
# ---------------------------------------------------------------------------

def _ensure_nltk():
    """Return the `nltk` module, failing fast if it isn't installed, and
    ensure the WordNet + OMW corpora are present. Mirrors
    `build_spanish_wordnet._ensure_nltk` — never `pip install`s at runtime."""
    try:
        import nltk
    except ImportError as err:
        raise RuntimeError(
            "Missing build dependency 'nltk'. Install it first: pip install nltk"
        ) from err
    for corpus in ("wordnet", "omw-1.4"):
        try:
            nltk.data.find(f"corpora/{corpus}")
        except LookupError:
            print(f"  Downloading NLTK corpus: {corpus}...")
            if not nltk.download(corpus, quiet=True):
                raise RuntimeError(
                    f"Failed to download required NLTK corpus '{corpus}'. "
                    "Ensure network access or pre-install the NLTK data."
                )
    return nltk


# ---------------------------------------------------------------------------
# Synset → row construction
# ---------------------------------------------------------------------------

# Mirror build_seed.pos_tag_to_label so the POS line is consistent across
# sources. Kept local so this module stays stand-alone runnable.
_POS_LABEL = {
    "n": "noun",
    "v": "verb",
    "a": "adjective",
    "r": "adverb",
    "s": "adjective satellite",
}


def _pos_label(pos: str) -> str:
    return _POS_LABEL.get(pos, pos)


def _build_definition(synsets) -> str:
    """Format senses as markdown, grouped by POS. Each sense leads with the
    English translation lemmas (the payload an Arabic speaker wants) followed
    by the English gloss. Stable ordering keeps rebuilds byte-identical."""
    by_pos: dict[str, list] = {}
    for ss in synsets:
        by_pos.setdefault(_pos_label(ss.pos()), []).append(ss)

    parts: list[str] = []
    for pos_label in sorted(by_pos):
        senses = sorted(by_pos[pos_label], key=lambda ss: ss.name())
        parts.append(f"**{pos_label}**")
        for i, ss in enumerate(senses, 1):
            english_lemmas = ", ".join(
                name.replace("_", " ") for name in ss.lemma_names()
            )
            gloss = ss.definition() or ""
            if english_lemmas and gloss:
                parts.append(f"{i}. {english_lemmas} — {gloss}")
            elif english_lemmas:
                parts.append(f"{i}. {english_lemmas}")
            else:
                parts.append(f"{i}. {gloss}")
        parts.append("")
    return "\n".join(parts).strip()


def _extract_pos_tags(synsets) -> str:
    tags = {_pos_label(ss.pos()) for ss in synsets}
    return ", ".join(sorted(tags))


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def build_and_collect() -> tuple[list[tuple], str]:
    """Iterate every WordNet synset, index it by its Arabic lemmas, and emit
    one arb→eng row per Arabic headword.

    Returns:
        (rows, version) where each row is a 6-tuple
        `(word, word_normalized, definition, phonetic, pos, "wordnet-arb-eng")`
        and `version` describes the WordNet/OMW data actually used.
    """
    nltk = _ensure_nltk()  # noqa: F841 — ensures corpora are present
    from nltk.corpus import wordnet as wn

    wn_version = wn.get_version() or "unknown"
    version = f"OMW 1.4 / WordNet {wn_version}"

    # Index synsets by Arabic lemma. One Arabic word can belong to many
    # synsets across multiple parts of speech.
    arabic_index: dict[str, list] = {}
    for ss in wn.all_synsets():
        for lemma in ss.lemma_names(_OMW_LANG):
            display = lemma.replace("_", " ")
            arabic_index.setdefault(display, []).append(ss)

    # Emit headwords in sorted order so the row sequence (and therefore the
    # rebuilt seed.sqlite) is stable across runs.
    rows: list[tuple] = []
    for arabic_word in sorted(arabic_index):
        synsets = arabic_index[arabic_word]
        definition = _build_definition(synsets)
        if not definition:
            continue
        pos = _extract_pos_tags(synsets)
        rows.append((
            arabic_word,
            normalize_arabic(arabic_word),
            definition,
            "",
            pos,
            SOURCE,
        ))

    return rows, version


# ---------------------------------------------------------------------------
# Stand-alone debug runner
# ---------------------------------------------------------------------------

def _main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dump", type=int, default=0,
                    help="Print the first N built entries and exit.")
    args = ap.parse_args()

    rows, version = build_and_collect()
    print(f"\nArabic WordNet ({version}): {len(rows):,} entries built.")
    vocalized = sum(1 for r in rows if r[0] != r[1])
    print(f"  {vocalized:,} headwords carry harakat "
          f"({vocalized / len(rows) * 100:.0f}% — search key differs from display).")
    for row in rows[: args.dump]:
        word, word_normalized, definition, _phonetic, pos, _source = row
        print(f"\n--- {word}  (search: {word_normalized})  [{pos}] ---")
        print(definition)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
