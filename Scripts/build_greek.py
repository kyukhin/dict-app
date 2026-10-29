#!/usr/bin/env python3
"""
build_greek.py
Everything Greek for the dictionary file (Issue #87): the search-key
normaliser, the definition decomposer, and the four sources of the
"Greek – English" pair.

    wordnet-ell-eng   Greek → English    Greek WordNet via OMW 1.4 (Apache 2.0)
    wordnet-eng-ell   English → Greek    the same data, reverse view
    freedict-ell-eng  Greek → English    FreeDict+WikDict (CC BY-SA 3.0)
    freedict-eng-ell  English → Greek    FreeDict 0.1.1, Freelang origin
                                         (CC BY-SA 3.0 option)

Accent-free Greek search. SQLite's `unicode61 remove_diacritics 2`
tokenizer folds Greek case and final sigma, but not precomposed tonos or
dialytika (ά, ϊ, ΐ). It does strip the *combining* U+0301 and U+0308.
So, for every row of the four sources:
  - `word` stays NFC (display, history, exact lookup);
  - `word_normalized = normalize_greek(word)` (accent-free, lowercase, σ);
  - `definition` stores its Greek decomposed (`decompose_greek`): the
    tokenizer indexes it accent-free, and the text renders the same.
The app folds the query with `Search.foldGreek`, which mirrors
`normalize_greek` exactly. Both helpers touch Greek code points only: a
global decompose-and-strip would fold Russian й into и.

Usage:
    python Scripts/build_greek.py            # fold self-check (offline, fast)
    python Scripts/build_greek.py --dump 3   # build all four sources, 3 rows each

Requirements:
    pip install -r Scripts/requirements.txt
    # inputs pinned in Scripts/inputs.json (fetched on first run)
"""

from __future__ import annotations

import argparse
import os
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

# Sibling build modules (FreeDict fetch/parse, pinned inputs), whether this
# file runs directly or is imported by build_dictionaries.py.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputs  # noqa: E402


# ---------------------------------------------------------------------------
# Greek folding: the single source of truth for the search key
# ---------------------------------------------------------------------------

def _is_greek(cp: int) -> bool:
    """Greek and Coptic (U+0370–U+03FF) or Greek Extended (U+1F00–U+1FFF)."""
    return 0x0370 <= cp <= 0x03FF or 0x1F00 <= cp <= 0x1FFF


def _has_greek(s: str) -> bool:
    return any(_is_greek(ord(ch)) for ch in s)


def normalize_greek(s: str) -> str:
    """Return the accent-, case- and final-sigma-free search key of `s`.

    The app's `Search.foldGreek` must produce the same scalars:
    1. A string without a Greek code point is returned unchanged.
    2. Otherwise NFC-normalise it, then for each code point in
       U+0370–U+03FF or U+1F00–U+1FFF: NFD-decompose it, drop every
       General Category Mn scalar, lowercase the rest.
    3. Replace every ς (U+03C2) with σ (U+03C3).
    Every non-Greek code point passes through unchanged."""
    if not _has_greek(s):
        return s
    out = []
    for ch in unicodedata.normalize("NFC", s):
        if _is_greek(ord(ch)):
            base = "".join(c for c in unicodedata.normalize("NFD", ch)
                           if unicodedata.category(c) != "Mn")
            out.append(base.lower())
        else:
            out.append(ch)
    return "".join(out).replace("ς", "σ")


def decompose_greek(s: str) -> str:
    """Replace every Greek code point with its NFD decomposition
    (ά → α + U+0301) and leave every other code point byte-identical."""
    if not _has_greek(s):
        return s
    return "".join(unicodedata.normalize("NFD", ch) if _is_greek(ord(ch)) else ch
                   for ch in s)


def nocase_key(s: str) -> str:
    """SQLite's `COLLATE NOCASE`: ASCII A–Z lowercased, nothing else. Rows
    merged by this key can never collide in
    `UNIQUE(word COLLATE NOCASE, source)`."""
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)


def _row(word: str, definition: str, phonetic: str, pos: str, source: str) -> tuple:
    """A 6-column `entries` row with the Greek search key and decomposed
    definition."""
    return (word, normalize_greek(word), decompose_greek(definition), phonetic, pos, source)


# ---------------------------------------------------------------------------
# Sources and metadata
# ---------------------------------------------------------------------------

WORDNET_ELL_ENG = "wordnet-ell-eng"
WORDNET_ENG_ELL = "wordnet-eng-ell"
FREEDICT_ELL_ENG = "freedict-ell-eng"
FREEDICT_ENG_ELL = "freedict-eng-ell"

WORDNET_URL = "https://github.com/okfngr/wordnet"
FREEDICT_ELL_ENG_URL = "https://freedict.org/freedict-database/ell-eng/"
FREEDICT_ENG_ELL_URL = "https://freedict.org/freedict-database/eng-ell/"

WORDNET_ELL_ENG_DESCRIPTION = (
    "Greek WordNet, by the Open Knowledge Foundation Greece, maps about "
    "18,000 Greek words and phrases to Princeton WordNet synsets. Each Greek "
    "headword lists its English translations and the English gloss of every "
    "sense, grouped by part of speech.\n\n"
    "The data comes through the Open Multilingual WordNet (OMW 1.4) packaged "
    "with NLTK. It is mostly nouns. Search ignores Greek accents, case and "
    "final sigma."
)

WORDNET_ENG_ELL_DESCRIPTION = (
    "The English → Greek view of Greek WordNet: about 30,700 English WordNet "
    "headwords with their Greek equivalents and the English gloss of every "
    "sense, grouped by part of speech.\n\n"
    "The data comes through the Open Multilingual WordNet (OMW 1.4) packaged "
    "with NLTK. Search finds an entry by the Greek in its translations too, "
    "with or without accents."
)

FREEDICT_ELL_ENG_DESCRIPTION = (
    "About 41,600 Greek headwords with English translations, parts of speech "
    "and IPA pronunciation, generated by WikDict from Wiktionary data and "
    "distributed by the FreeDict project.\n\n"
    "Entries that share a headword are merged into one. Search ignores Greek "
    "accents, case and final sigma."
)

FREEDICT_ENG_ELL_DESCRIPTION = (
    "About 20,700 English headwords with Greek translations, from the "
    "Freelang English–Greek word list via FreeDict. No part of speech or "
    "pronunciation."
)

FREEDICT_ENG_ELL_LICENSE_TEXT = (
    "English–Greek dictionary from the FreeDict project (eng-ell 0.1.1). "
    "Originally the Freelang English–Greek dictionary (freelang.net), "
    "converted from XDXF and cleaned up for FreeDict by Piotr Bański "
    "(2009).\n\n"
    "FreeDict distributes it under the GNU GPL 2.0 or later, or "
    "alternatively under Creative Commons Attribution-ShareAlike 3.0; "
    "LibreDict uses it under CC BY-SA 3.0 Unported, "
    "https://creativecommons.org/licenses/by-sa/3.0/legalcode.\n\n"
    "LibreDict converted the data to its dictionary format (entries with "
    "the same headword merged); the converted data is distributed under "
    "the same license."
)


def wordnet_license_text() -> str:
    """License of both Greek WordNet sources: attribution, change notice,
    the Princeton WordNet paragraph and the full Apache 2.0 text shipped
    with OMW (Apache 2.0 §4(a)). Fails the build if that file is missing."""
    import nltk

    apache = nltk.data.load("corpora/omw-1.4/ell/LICENSE", format="text")
    if "Apache License" not in apache or "Version 2.0" not in apache:
        raise RuntimeError("corpora/omw-1.4/ell/LICENSE is not the Apache License 2.0")
    return "\n\n".join([
        "Greek WordNet by the Open Knowledge Foundation Greece "
        "(https://github.com/okfngr/wordnet), distributed via the Open "
        "Multilingual WordNet (OMW 1.4). Licensed under the Apache License, "
        "Version 2.0; the full license text follows below.",
        "LibreDict converted this data to its dictionary format: lemmas "
        "regrouped per headword, Latin-only lemmas removed; the converted "
        "data remains under the Apache License 2.0.",
        "The English glosses and synset structure derive from Princeton "
        "WordNet 3.0, used under the WordNet 3.0 License (BSD-style), "
        "Copyright 2006 Princeton University. Full license text: "
        "https://wordnet.princeton.edu/license-and-commercial-use",
        apache.strip(),
    ])


@dataclass(frozen=True)
class GreekSource:
    """One source's rows plus its `dict_metadata` fields."""
    source: str
    display_name: str
    version: str
    license: str
    url: str
    description: str
    from_lang: str
    to_lang: str
    rows: list


# ---------------------------------------------------------------------------
# Greek WordNet (OMW 1.4, lang 'ell'), both directions
# ---------------------------------------------------------------------------

_OMW_LANG = "ell"


def _clean_greek_lemma(name: str) -> str | None:
    """`_` → space, whitespace and a trailing editorial `*` stripped. Lemmas
    without a Greek letter (Latin taxon names such as `Accipiter`) are
    dropped."""
    word = " ".join(name.replace("_", " ").split())
    if word.endswith("*"):
        word = word[:-1].rstrip()
    if not any(_is_greek(ord(c)) and c.isalpha() for c in word):
        return None
    return word


def _omw_definition(synsets, translations) -> str:
    """WordNet-style markdown grouped by POS (the Arabic WordNet shape):
    `**noun**` / `1. <translations> — <English gloss>`."""
    from build_arabic_wordnet import _pos_label

    by_pos: dict[str, list] = {}
    for ss in synsets:
        by_pos.setdefault(_pos_label(ss.pos()), []).append(ss)
    parts: list[str] = []
    for pos_label in sorted(by_pos):
        parts.append(f"**{pos_label}**")
        for i, ss in enumerate(sorted(by_pos[pos_label], key=lambda s: s.name()), 1):
            lemmas = ", ".join(translations(ss))
            gloss = ss.definition() or ""
            if lemmas and gloss:
                parts.append(f"{i}. {lemmas} — {gloss}")
            else:
                parts.append(f"{i}. {lemmas or gloss}")
        parts.append("")
    return "\n".join(parts).strip()


def _omw_pos(synsets) -> str:
    from build_arabic_wordnet import _pos_label

    return ", ".join(sorted({_pos_label(ss.pos()) for ss in synsets}))


def build_omw(cache_dir: Path) -> tuple[list[tuple], list[tuple], str]:
    """Return `(ell_eng_rows, eng_ell_rows, version)` from one WordNet
    instance, so the synset join is exact (as for Arabic and Spanish)."""
    inputs.use_nltk_data(cache_dir)
    from nltk.corpus import wordnet as wn

    version = f"OMW 1.4 / WordNet {wn.get_version() or 'unknown'}"

    greek_of: dict[str, list[str]] = {}      # synset name → cleaned Greek lemmas
    by_key: dict[str, tuple[list, dict]] = {}  # NOCASE key → (spellings, synsets)
    for ss in wn.all_synsets():
        lemmas: list[str] = []
        for name in ss.lemma_names(_OMW_LANG):
            word = _clean_greek_lemma(name)
            if word and word not in lemmas:
                lemmas.append(word)
        if not lemmas:
            continue
        greek_of[ss.name()] = lemmas
        for word in lemmas:
            spellings, synsets = by_key.setdefault(nocase_key(word), ([], {}))
            if word not in spellings:
                spellings.append(word)
            synsets.setdefault(ss.name(), ss)

    # Greek → English: one row per Greek headword. Spellings that differ
    # only in ASCII case (`δέντρο Quercus virginiana` / `… quercus …`) share
    # a row under the code-point-smallest spelling (the capitalised taxon).
    ell_rows = []
    for spellings, synsets in by_key.values():
        senses = list(synsets.values())
        definition = _omw_definition(
            senses, lambda ss: [n.replace("_", " ") for n in ss.lemma_names()])
        ell_rows.append(_row(min(spellings), definition, "", _omw_pos(senses),
                             WORDNET_ELL_ENG))
    ell_rows.sort(key=lambda r: r[0])

    # English → Greek: one row per English WordNet headword (as in the
    # `wordnet` source) that has at least one Greek lemma.
    eng_rows = []
    for lemma in sorted(set(wn.all_lemma_names())):
        senses = list({ss.name(): ss for ss in wn.synsets(lemma)
                       if ss.name() in greek_of}.values())
        if not senses:
            continue
        definition = _omw_definition(senses, lambda ss: greek_of[ss.name()])
        eng_rows.append(_row(lemma.replace("_", " "), definition, "",
                             _omw_pos(senses), WORDNET_ENG_ELL))

    return ell_rows, eng_rows, version


# ---------------------------------------------------------------------------
# FreeDict Greek → English (WikDict)
# ---------------------------------------------------------------------------

def build_freedict_ell_eng(cache_dir: Path) -> tuple[list[tuple], str]:
    """Parse with the shared FreeDict importer, then merge homographs by the
    NOCASE key (125 of them; unmerged, `INSERT OR IGNORE` would keep e.g.
    the `suffix` entry of λάτρης and hide "worshipper"). Definition blocks
    are joined with a blank line in file order, `phonetic` is the first
    non-empty one, `pos` the sorted distinct labels."""
    from build_freedict_eng_spa import download_and_parse

    parsed, version = download_and_parse(pair="ell-eng", cache_dir=cache_dir)
    groups: dict[str, list[tuple]] = {}
    for word, definition, phonetic, pos, _source in parsed:
        groups.setdefault(nocase_key(word), []).append((word, definition, phonetic, pos))

    rows = []
    for items in groups.values():
        blocks = list(dict.fromkeys(definition for _, definition, _, _ in items))
        phonetic = next((p for _, _, p, _ in items if p), "")
        pos = ", ".join(sorted({p for _, _, _, p in items if p}))
        rows.append(_row(items[0][0], "\n\n".join(blocks), phonetic, pos,
                         FREEDICT_ELL_ENG))
    return rows, version


# ---------------------------------------------------------------------------
# FreeDict English → Greek (Freelang origin)
# ---------------------------------------------------------------------------

def _eng_ell_definition(word: str, items: list[tuple[str, str, str]]) -> str:
    """One numbered line per source entry, in file order. The comma list of
    each `<def>` is kept as written (commas do not mark senses here). A line
    from a spelling other than `word` names it: `1. (AD) μετά Χριστόν`. A
    `**pos**` header opens a block only where the source tags a POS (six
    entries); numbering restarts per block, as in the other sources."""
    parts: list[str] = []
    block_pos = None
    n = 0
    for spelling, pos, text in items:
        if pos != block_pos:
            if parts:
                parts.append("")
            if pos:
                parts.append(f"**{pos}**")
            block_pos, n = pos, 0
        n += 1
        prefix = f"({spelling}) " if spelling != word else ""
        parts.append(f"{n}. {prefix}{text}")
    return "\n".join(parts)


def build_freedict_eng_ell(cache_dir: Path) -> tuple[list[tuple], str]:
    """Parse the `<sense><def>` TEI and merge by the NOCASE key (22 exact
    duplicates and ~216 case-only groups such as `AD`/`ad`). The display
    word is the all-lowercase spelling when the group has one, else the
    first."""
    from build_freedict_eng_spa import fetch_tei, parse_def_tei

    tei_path, version = fetch_tei(pair="eng-ell", cache_dir=cache_dir)
    groups: dict[str, list[tuple[str, str, str]]] = {}
    for item in parse_def_tei(tei_path):
        groups.setdefault(nocase_key(item[0]), []).append(item)

    rows = []
    for items in groups.values():
        items = list(dict.fromkeys(items))  # an identical entry repeated: once
        word = next((s for s, _, _ in items if s == s.lower()), items[0][0])
        pos = ", ".join(sorted({p for _, p, _ in items if p}))
        rows.append(_row(word, _eng_ell_definition(word, items), "", pos,
                         FREEDICT_ENG_ELL))
    return rows, version


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def _check_rows(src: GreekSource) -> None:
    """Fail the build rather than let `INSERT OR IGNORE` drop a row, or ship
    a `word` that is not NFC."""
    seen: set[str] = set()
    for row in src.rows:
        word = row[0]
        key = nocase_key(word)
        if key in seen:
            raise RuntimeError(f"{src.source}: duplicate NOCASE headword {word!r}")
        seen.add(key)
        if not unicodedata.is_normalized("NFC", word):
            raise RuntimeError(f"{src.source}: headword {word!r} is not NFC")


def build_all(cache_dir: Path = inputs.DEFAULT_CACHE_DIR) -> list[GreekSource]:
    """Build the four Greek sources, in insertion order."""
    omw_ell_eng, omw_eng_ell, omw_version = build_omw(cache_dir)
    fd_ell_eng, fd_ell_eng_version = build_freedict_ell_eng(cache_dir)
    fd_eng_ell, fd_eng_ell_version = build_freedict_eng_ell(cache_dir)
    from build_freedict_eng_spa import LICENSE_TEXT as WIKDICT_LICENSE_TEXT

    wordnet_license = wordnet_license_text()
    sources = [
        GreekSource(WORDNET_ELL_ENG, "Greek – English (WordNet)", omw_version,
                    wordnet_license, WORDNET_URL, WORDNET_ELL_ENG_DESCRIPTION,
                    "ell", "eng", omw_ell_eng),
        GreekSource(WORDNET_ENG_ELL, "English – Greek (WordNet)", omw_version,
                    wordnet_license, WORDNET_URL, WORDNET_ENG_ELL_DESCRIPTION,
                    "eng", "ell", omw_eng_ell),
        GreekSource(FREEDICT_ELL_ENG, "Greek – English (FreeDict)", fd_ell_eng_version,
                    WIKDICT_LICENSE_TEXT, FREEDICT_ELL_ENG_URL,
                    FREEDICT_ELL_ENG_DESCRIPTION, "ell", "eng", fd_ell_eng),
        GreekSource(FREEDICT_ENG_ELL, "English – Greek (FreeDict)", fd_eng_ell_version,
                    FREEDICT_ENG_ELL_LICENSE_TEXT, FREEDICT_ENG_ELL_URL,
                    FREEDICT_ENG_ELL_DESCRIPTION, "eng", "ell", fd_eng_ell),
    ]
    for src in sources:
        _check_rows(src)
    return sources


# ---------------------------------------------------------------------------
# Self-check (the Python half of the Swift parity vectors) and debug runner
# ---------------------------------------------------------------------------

def _nfd(s: str) -> str:
    return unicodedata.normalize("NFD", s)


# Shared with the app's `Search.foldGreek` tests: input → expected key.
PARITY_FOLDS = [
    ("Λόγος", "λογοσ"),
    ("ΆΝΘΡΩΠΟΣ", "ανθρωποσ"),
    ("προϊόν", "προιον"),
    ("ΐδιος", "ιδιοσ"),
    ("ΰπνος", "υπνοσ"),
    ("θάλασσα", "θαλασσα"),
    (_nfd("λόγος"), "λογοσ"),
    ("γένος Rudbeckia", "γενοσ Rudbeckia"),
    ("σκύλος", "σκυλοσ"),
    ("ΣΚΥΛΟΣ", "σκυλοσ"),
    ("σοφός σοφός", "σοφοσ σοφοσ"),
]
# Left byte-identical by both normalize_greek and decompose_greek; the NFD
# spellings prove that non-Greek text is not even re-normalised.
PARITY_IDENTITY = ["café", "йод", "ёлка", "niños", "كِتَاب", "كتاب", "apple",
                   _nfd("йод"), _nfd("niños"), _nfd("café")]


def _self_check() -> None:
    import sqlite3

    for raw, expected in PARITY_FOLDS:
        got = normalize_greek(raw)
        assert got == expected, (ascii(raw), ascii(got), ascii(expected))
        assert normalize_greek(got) == got, ascii(raw)  # idempotent
        print(f"  fold  {raw} {ascii(raw)} -> {expected}")
    for text in PARITY_IDENTITY:
        assert normalize_greek(text).encode() == text.encode(), ascii(text)
        assert decompose_greek(text).encode() == text.encode(), ascii(text)
        print(f"  same  {text} {ascii(text)}")

    mixed = "dog — σκύλος; йод, niños, كِتَاب"
    expected = "dog — " + _nfd("σκύλος") + "; йод, niños, كِتَاب"
    assert decompose_greek(mixed).encode() == expected.encode(), ascii(decompose_greek(mixed))
    assert normalize_greek(mixed) == "dog — σκυλοσ; йод, niños, كِتَاب"

    # The point of decomposing: the app's tokenizer then indexes Greek
    # accent-free, while precomposed й stays distinct from и.
    db = sqlite3.connect(":memory:")
    db.execute("CREATE VIRTUAL TABLE t USING fts5(d, "
               "tokenize='unicode61 remove_diacritics 2')")
    rows = ["σκύλος", "προϊόν", "σαΐτα", "καταπραΰνω", "йод", "иод"]
    db.executemany("INSERT INTO t(d) VALUES (?)", [(decompose_greek(r),) for r in rows])

    def hits(query: str) -> list[str]:
        sql = "SELECT d FROM t WHERE t MATCH ?"
        return [unicodedata.normalize("NFC", r[0]) for r in db.execute(sql, (query + "*",))]

    for word in rows[:4]:
        assert hits(normalize_greek(word)) == [word], word
        assert hits(normalize_greek(word.upper())) == [word], word
    assert hits("йод") == ["йод"] and hits("иод") == ["иод"]
    print("  FTS5 unicode61 remove_diacritics 2: decomposed Greek matches the "
          "folded query; й and и stay distinct")
    print("OK: Greek folding self-check passed.")


def _main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dump", type=int, default=None, metavar="N",
                    help="Build all four sources and print N rows of each.")
    args = ap.parse_args()

    if args.dump is None:
        _self_check()
        return 0

    for src in build_all():
        print(f"\n{src.source} ({src.version}): {len(src.rows):,} rows")
        for word, key, definition, phonetic, pos, _ in src.rows[: args.dump]:
            print(f"--- {word} (search: {key}) [{pos}] {phonetic}")
            print(unicodedata.normalize("NFC", definition))
    return 0


if __name__ == "__main__":
    sys.exit(_main())
