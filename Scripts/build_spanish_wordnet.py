#!/usr/bin/env python3
"""
build_spanish_wordnet.py
Build a Spanish→English dictionary from the Open Multilingual WordNet
(OMW) Spanish data — the spa→eng counterpart to the FreeDict eng-spa
dictionary delivered in Issue #24.

Strategy (see DESIGN_DOC.md, Issue #42): the synset join happens in
Python against a single, synset-aware NLTK WordNet instance. Spanish
lemmas (`Synset.lemma_names('spa')`) and the English glosses/synonyms
(`Synset.definition()` / `Synset.lemma_names()`) are read from the *same*
WordNet object, so the synset IDs are shared by construction — there is
no cross-version offset table to misalign. The app never sees synset
IDs; it receives flat `entries` rows exactly like every other source.

Source identifier: "wordnet-spa-eng" (provider-srclang-tgtlang, matching
the #24 convention used by "freedict-eng-spa").

Usage:
    python Scripts/build_spanish_wordnet.py            # print summary
    python Scripts/build_spanish_wordnet.py --dump 5   # print 5 entries

Requirements (NLTK + the WordNet and OMW corpora):
    pip install nltk
    # corpora are fetched on first run via nltk.download()
"""

from __future__ import annotations

import argparse
import sys

# ---------------------------------------------------------------------------
# Public constants — consumed by build_seed.py for dict_metadata.
# ---------------------------------------------------------------------------

SOURCE = "wordnet-spa-eng"
DISPLAY_NAME = "Spanish – English (WordNet)"
URL = "https://adimen.si.ehu.es/web/MCR"

LICENSE_TEXT = (
    "Spanish WordNet — Multilingual Central Repository (MCR), "
    "distributed via the Open Multilingual WordNet (OMW).\n\n"
    "The Spanish WordNet data is licensed under the Creative Commons "
    "Attribution 3.0 Unported License (CC BY 3.0).\n\n"
    "You are free to share and adapt the material for any purpose, even "
    "commercially, provided you give appropriate credit to the "
    "Multilingual Central Repository (University of the Basque Country) "
    "and the Open Multilingual WordNet project.\n\n"
    "The English glosses and synset structure derive from Princeton "
    "WordNet 3.0, used under the WordNet 3.0 License (BSD-style), "
    "Copyright 2006 Princeton University.\n\n"
    "Full license texts:\n"
    "  • https://creativecommons.org/licenses/by/3.0/\n"
    "  • https://wordnet.princeton.edu/license-and-commercial-use"
)

DESCRIPTION_TEXT = (
    "Spanish WordNet provides Spanish lemmas aligned to Princeton "
    "WordNet synsets. Each Spanish headword is mapped to its English "
    "translation lemmas and the English gloss for every sense, grouped "
    "by part of speech.\n\n"
    "The data comes from the Multilingual Central Repository (MCR), "
    "maintained at the University of the Basque Country (UPV/EHU), and "
    "is accessed here through the Open Multilingual WordNet (OMW) "
    "packaged with NLTK. Because the Spanish lemmas and English glosses "
    "are read from the same WordNet 3.0 instance, the synset mapping is "
    "exact — no cross-version alignment is involved."
)

# Spanish lemma lookup language code used by NLTK/OMW.
_OMW_LANG = "spa"


# ---------------------------------------------------------------------------
# NLTK bootstrap (data download only — never a runtime `pip install`)
# ---------------------------------------------------------------------------

def _ensure_nltk():
    """Return the `nltk` module, failing fast if it isn't installed, and
    ensure the WordNet + OMW corpora are present.

    Like the #24 build scripts, we never `pip install` at runtime (that
    makes builds non-deterministic and breaks in offline CI). Corpus
    *data* downloads via `nltk.download()` are the standard NLTK
    bootstrap and mirror `build_seed.ensure_nltk()`."""
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
    """Format senses as markdown, grouped by POS. Each sense leads with
    the English translation lemmas (the payload a Spanish speaker wants)
    followed by the English gloss:

        **noun**
        1. house, home — a dwelling that serves as living quarters ...
        2. firm, house, business — the members of a business organization ...
    """
    by_pos: dict[str, list] = {}
    for ss in synsets:
        by_pos.setdefault(_pos_label(ss.pos()), []).append(ss)

    # Iterate POS blocks and senses in a stable order so rebuilds produce
    # byte-identical definitions (avoids noisy seed.sqlite diffs). Synsets
    # sort by their unique name (e.g. "house.n.01"), which is deterministic.
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
    # Sort the de-duplicated POS labels so the `pos` column is stable
    # across rebuilds (no traversal-order churn in the seed).
    tags = {_pos_label(ss.pos()) for ss in synsets}
    return ", ".join(sorted(tags))


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def build_and_collect() -> tuple[list[tuple], str]:
    """Iterate every WordNet synset, index it by its Spanish lemmas, and
    emit one spa→eng row per Spanish headword.

    Returns:
        (rows, version) where `rows` is the list of
        `(word, definition, phonetic, pos, "wordnet-spa-eng")` tuples and
        `version` describes the WordNet/OMW data actually used.
    """
    nltk = _ensure_nltk()  # noqa: F841 — ensures corpora are present
    from nltk.corpus import wordnet as wn

    wn_version = wn.get_version() or "unknown"
    version = f"OMW 1.4 / WordNet {wn_version}"

    # Index synsets by Spanish lemma. One Spanish word can belong to many
    # synsets across multiple parts of speech.
    spanish_index: dict[str, list] = {}
    for ss in wn.all_synsets():
        for lemma in ss.lemma_names(_OMW_LANG):
            display = lemma.replace("_", " ")
            spanish_index.setdefault(display, []).append(ss)

    # Emit headwords in sorted order so the row sequence (and therefore
    # the rebuilt seed.sqlite) is stable across runs.
    rows: list[tuple] = []
    for spanish_word in sorted(spanish_index):
        synsets = spanish_index[spanish_word]
        definition = _build_definition(synsets)
        if not definition:
            continue
        pos = _extract_pos_tags(synsets)
        rows.append((spanish_word, definition, "", pos, SOURCE))

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
    print(f"\nSpanish WordNet ({version}): {len(rows):,} entries built.")
    for row in rows[: args.dump]:
        word, definition, _phonetic, pos, _source = row
        print(f"\n--- {word}  [{pos}] ---")
        print(definition)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
