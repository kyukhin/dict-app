#!/usr/bin/env python3
"""
build_examples.py
Example sentences from Tatoeba, a static data step of `build_dictionaries.py`
(docs/specs/0134-example-sentences.md, "Pipeline (#177)"). Greek rows go into
the Greek pack, English rows into the English lists pack (`Scripts/packs.json`);
the bundle and the stub have the tables, empty (0237, one schema everywhere).

Input: two projections of a Tatoeba export, committed under
`Scripts/data/tatoeba-<date>/` (Git LFS), since Tatoeba keeps only its latest
export. `ell-*` holds every Greek sentence and every eng, rus, spa and ara
sentence directly linked to one; `eng-*` every English sentence directly
linked to a rus, spa, ara or ell one, and those translations. Each has
`sentences` (id, lang, text, author), `links`, `tags` and `natives` (its
authors who declare level 5 in a sentence's language), as `.tsv.xz`, with no
quality filter. `inputs.json` pins every file and records the export it came
from. The step works offline; only FrequencyWords' Greek list (the verb
gate's ranking, already pinned) comes from the cache.

The step reads the Greek forms (`lemma`, `paradigm`, `form_link`,
`form_lookup`) and headwords (`entries`), morphy (`morphy_exception`,
`morphy_lemma`) and the English list words (`wordlist_item`), so it runs after
build_forms, build_morphy and build_wordlists. It fills `example_sentence`,
`example_translation`, `example_word` and the `tatoeba` data_source row,
writes `Scripts/reports/examples-qa.md`, then raises if a gate fails.

Drill examples (#364, 0134 "Drill examples"): every cell the conjugation
drill can ask (`drill_cells.py`, a port of 0132's rules) gets one Greek
candidate sentence that holds the cell's whole form by the match rule
(compound forms with clitics between, particles, auxiliaries, homographs).
Its `example_word` row is keyed `<word>|<facet>|<person>`, `ord` 1, and
highlights the form from its first word to the verb.

#365 adds the data files of `Scripts/data/drill-examples/`: Wiktionary
usage examples (checked against the pinned kaikki subset) and generated
sentences (`ell.tsv`), the second pass's reading verdicts
(`ell-readings.tsv`) and the cells left without a sentence
(`ell-skipped.tsv`). Tatoeba comes first, then Wiktionary, then generated;
the form gate and the coverage gate (`SCOPE`) fail the build.
`Scripts/drill_examples.py` is the tool around the data files.

#371 ties every verdict to what it was given on: the sentence's Greek and
the English and Russian it ships with (`texts_sha256`, in `ell-readings.tsv`
for a verdict and in `ell.tsv` for a data row's own `check`; CodeRabbit on
#384). A verdict whose hash does not match is stale, reported and never
used. The pair gate: every cell row's (cell, sentence) is its data row's own
cell or has an `ok` verdict in the readings file, each with the hash of the
texts the pair ships with.

#385 adds a fourth source, sentences written by people from openly licensed
corpora (`ell-corpus.tsv`, BabyLM-ell first), each tied to its document and
that document's own licence (`ell-corpus-documents.tsv`). They rank after
Tatoeba and Wiktionary and before generated rows, serve their own cell on
their own `check` and another cell only with an `ok` verdict; the corpus
gate (0134, "Corpus sentences", Checks 1 to 9) fails the build, and
`NC_ALLOWED` lets the NonCommercial rows ship. A corpus row's cell keeps a
fallback: its generated row, another sentence or its skip line, which counts
only while no sentence ships for the cell (kyukhin 2026-11-28).

Usage (from the repository root):
    python3 Scripts/build_examples.py --self-check
        offline, on Scripts/fixtures/tatoeba-sample/: builds twice, compares
        the table hashes and checks the spec's cases
    python3 Scripts/build_examples.py --standalone out.sqlite \\
            --source Scripts/.cache/dictionaries-full.sqlite
        the step alone, into its own file, with the QA report and the gates;
        forms, morphy, list words and headwords come from the full file
    python3 Scripts/build_examples.py --refresh
        downloads the current export (22 files, about 80 MB), writes a new
        dated subset and its inputs.json entries; a refresh is a reviewed PR
        of its own. With --export-dir DIR --export-date YYYY-MM-DD it projects
        export files already downloaded into DIR instead.
"""

from __future__ import annotations

import argparse
import bz2
import collections
import email.utils
import functools
import gzip
import hashlib
import heapq
import json
import lzma
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import unicodedata
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Callable, Iterable

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import drill_cells  # noqa: E402  (the drill's cells, #364)
import inputs  # noqa: E402
from build_greek import normalize_greek  # noqa: E402  (the one Greek folding, #87)
from build_wordlists import cleaned_variants  # noqa: E402  (0130's cleaned spellings)

SCHEMA = """
-- One row per Tatoeba sentence used as an example.
CREATE TABLE example_sentence (
    id      INTEGER PRIMARY KEY,   -- the Tatoeba sentence id (stable across exports)
    lang    TEXT NOT NULL,         -- ISO 639-3 of the sentence: 'ell' or 'eng' (the pack filter)
    text    TEXT NOT NULL,         -- NFC, otherwise as Tatoeba has it
    author  TEXT NOT NULL          -- Tatoeba username
);

-- Its direct translations: at most one per language.
CREATE TABLE example_translation (
    sentence_id INTEGER NOT NULL,  -- example_sentence.id
    lang        TEXT NOT NULL,     -- 'eng', 'rus', 'spa', 'arb' (Tatoeba's 'ara'); 'ell' for English sentences
    id          INTEGER NOT NULL,  -- the translation's Tatoeba id
    text        TEXT NOT NULL,
    author      TEXT NOT NULL,
    PRIMARY KEY (sentence_id, lang)
) WITHOUT ROWID;

-- A word's examples, in display order.
CREATE TABLE example_word (
    lang        TEXT NOT NULL,     -- WordKey.lang
    word        TEXT NOT NULL,     -- WordKey.word: a lemma or headword as stored (NFC; A–Z lowercased)
    ord         INTEGER NOT NULL,  -- 1…5
    sentence_id INTEGER NOT NULL,
    form_start  INTEGER NOT NULL,  -- the highlighted form: offset in Unicode scalars of the NFC text
    form_length INTEGER NOT NULL,
    PRIMARY KEY (lang, word, ord)
) WITHOUT ROWID;
"""
TABLES = ("example_sentence", "example_translation", "example_word")
KEY_ORDER = {"example_sentence": "id", "example_translation": "sentence_id, lang",
             "example_word": "lang, word, ord"}

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO = SCRIPTS_DIR.parent
REPORT = SCRIPTS_DIR / "reports" / "examples-qa.md"
FIXTURE = SCRIPTS_DIR / "fixtures" / "tatoeba-sample"

# The pinned subset: `inputs.json` has one entry for the folder (the export
# it was projected from) and one per file (its sha256).
SUBSET_PREFIX = "Scripts/data/tatoeba-"
SUBSETS = ("ell", "eng")
PARTS = ("sentences", "links", "tags", "natives")
EXPORT_URL = "https://downloads.tatoeba.org/exports/per_language/"
EXPORT_FILES = (
    "ell/ell_sentences_detailed.tsv.bz2",
    "ell/ell-eng_links.tsv.bz2", "ell/ell-rus_links.tsv.bz2",
    "ell/ell-spa_links.tsv.bz2", "ell/ell-ara_links.tsv.bz2",
    "eng/eng-rus_links.tsv.bz2", "eng/eng-spa_links.tsv.bz2", "eng/eng-ara_links.tsv.bz2",
    "eng/eng_sentences_detailed.tsv.bz2", "rus/rus_sentences_detailed.tsv.bz2",
    "spa/spa_sentences_detailed.tsv.bz2", "ara/ara_sentences_detailed.tsv.bz2",
    "ell/ell_tags.tsv.bz2", "eng/eng_tags.tsv.bz2", "rus/rus_tags.tsv.bz2",
    "spa/spa_tags.tsv.bz2", "ara/ara_tags.tsv.bz2",
    "ell/ell_user_languages.tsv.bz2", "eng/eng_user_languages.tsv.bz2",
    "rus/rus_user_languages.tsv.bz2", "spa/spa_user_languages.tsv.bz2",
    "ara/ara_user_languages.tsv.bz2",
)
EXPORT_LANGS = ("ell", "eng", "rus", "spa", "ara")  # Tatoeba's codes
NATIVE_LEVEL = "5"

# hermitdave/FrequencyWords, OpenSubtitles 2018 (CC BY-SA 4.0): the verb
# gate's ranking (0136), never shipped.
FREQUENCY_KEY = "frequencywords/el_50k.txt"
GREEK_DICTIONARIES = ("freedict-ell-eng", "wordnet-ell-eng")
GREEK_LISTS = "ky-ell"
ENGLISH_LISTS = "cefr-eng"
# #339: the cornerstone words Kirill reviewed (articles, pronouns, particles,
# numbers), reported with their examples and how many show the word's own form.
CORNERSTONE = (
    "ο", "η", "το", "οι", "τα", "ένας", "μία", "ένα", "εγώ", "εσύ", "αυτός", "αυτή", "αυτό", "εμείς", "εσείς",
    "αυτοί", "αυτές", "αυτά", "με", "σε", "τον", "την", "μας", "σας", "τους", "τις", "μου", "σου", "του", "της",
    "δικός", "ποιος", "ποια", "ποιο", "πότε", "πόσος", "πόσο", "ή", "πως", "εκείνος", "κανένας", "καμία",
    "κανένα", "όλος", "να", "δεν", "μην", "ας", "στο", "στη(ν)", "στον", "στα", "στους", "στις", "ότι", "όταν",
    "επειδή", "τρεις", "τρία", "τέσσερις", "τέσσερα", "δεκατρείς", "δεκατρία", "δεκατέσσερις", "δεκατέσσερα",
)

DATA_SOURCE = {
    "id": "tatoeba",
    "kind": "example_sentences",
    "display_name": "Tatoeba (example sentences)",
    "license": "CC BY 2.0 FR",
    "url": "https://tatoeba.org",
}

# Our ISO 639-3 code of each language, and Tatoeba's.
TATOEBA = {"ell": "ell", "eng": "eng", "rus": "rus", "spa": "spa", "arb": "ara"}
OURS = {tatoeba: ours for ours, tatoeba in TATOEBA.items()}
# The translations an example keeps, per sentence language, in this order.
TRANSLATIONS = {"ell": ("eng", "rus", "spa", "arb"), "eng": ("rus", "spa", "arb", "ell")}

MAX_WORDS = 15
SHORT_WORDS = (3, 10)  # ranked before longer and shorter sentences
PER_WORD = 5
TOP_VERBS = 500
GATE_VERBS = 0.85
SIZE_BUDGET = 10_000_000  # bytes, the word examples of every file together (#364: drill rows not counted)
SAMPLES = {"ell": ("γράφω", "είμαι", "σπίτι", "καλός", "μέρα"), "eng": ("go", "house", "write", "good")}

# Drill examples (#364). Sources by sentence id (0134, "Where it lives").
WIKTIONARY_IDS = 1_000_000_000  # + n, #365
GENERATED_IDS = 2_000_000_000  # + n, #365
CORPUS_IDS = 3_000_000_000  # + n, #385
TATOEBA_SOURCE, WIKTIONARY, GENERATED, CORPUS = 0, 1, 2, 3  # `source_of`
# The choice's order of the sources (#385): people's sentences before generated ones, Tatoeba first.
SOURCE_RANK = {TATOEBA_SOURCE: 0, WIKTIONARY: 1, CORPUS: 2, GENERATED: 3}
# Bytes installed: the cell rows and the sentences only they use (kyukhin 2026-11-22: 3.5 MB; #371, after the
# pilot, kyukhin 2026-11-26: 11 MB).
DRILL_BUDGET = 11_000_000
# The words that may stand between the words of a compound form (match rule 2).
CLITICS = frozenset({"μου", "σου", "του", "της", "μας", "σας", "τους", "τον", "την", "τη", "το", "τα", "τις", "τες",
                     "με", "σε", "μ", "σ", "τ"})
NEGATIONS = frozenset({"μη", "μην"})  # between words only after να
PARTICLES = frozenset({"θα", "να"})
# The tokens of an elided θ' and ν', glued or before a space. They only block
# (rule 3): never the θα or να of a compound form, which needs the whole word.
ELIDED_PARTICLES = {"θ": "θ'", "ν": "ν'"}
# A simple tense, perfect or pluperfect never follows these (match rule 3):
# θα, να, an elided θ' or ν', ας, and μη(ν), after να or prohibitive (Μην ανησυχείς).
BLOCKERS = PARTICLES | frozenset(ELIDED_PARTICLES.values()) | {"ας"} | NEGATIONS
AUXILIARIES = frozenset(drill_cells.HAVE.values()) | frozenset(drill_cells.HAD.values())
# An elided word glued to the next: σ'αγαπώ is σ' and αγαπώ, θ'αγαπούσα θ' and αγαπούσα.
ELIDED = re.compile(r"([μστνθΜΣΤΝΘ])['’](.+)")
APOSTROPHES = "'’"
# Tense families: two cells of one family, person and voice share a reading
# (the aspect-only homographs: κάνε, θα κάνουν, να κάνουν).
FAMILY = {"imperativeContinuous": "imperative", "imperativeSimple": "imperative", "future": "future",
          "futureContinuous": "future", "subjunctiveContinuous": "subjunctive", "subjunctiveSimple": "subjunctive"}
DRILL_SAMPLES = ("κάνω|imperativeSimple.active|2sg", "γράφω|aorist.active|1sg", "γράφω|future.active|1sg",
                 "λέω|subjunctiveSimple.active|2sg", "βλέπω|perfect.active|1sg", "έχω|present.active|3sg")
LEVEL_NAMES = {1: "A1", 2: "A2", 3: "B1"}
# Function words, always allowed in a generated row whatever its verb's level (0134, "B1 drill examples", Words;
# CodeRabbit on #384): the forms of a lemma of these parts of speech, and the forms of έχω and είμαι.
FUNCTION_POS = frozenset({"article", "pron", "det", "prep", "conj", "particle", "num"})
FUNCTION_VERBS = frozenset({"έχω", "είμαι"})

# #365: the drill-example data files (0134, "Data files"), plain text in Git.
DRILL_DATA = SCRIPTS_DIR / "data" / "drill-examples"
DATA_FILE, READINGS_FILE, SKIPPED_FILE = "ell.tsv", "ell-readings.tsv", "ell-skipped.tsv"
DATA_COLUMNS = ("id", "source", "page", "cell", "text", "eng", "rus", "model", "check", "checked_by", "texts_sha256")
READING_COLUMNS = ("cell", "sentence_id", "texts_sha256", "verdict", "checked_by", "reason")
TEXTS_HASH = re.compile(r"[0-9a-f]{16}")  # a verdict's `texts_sha256` (#371)
SKIPPED_COLUMNS = ("cell", "reason", "checked_by")
SOURCE_IDS = {"wiktionary": WIKTIONARY_IDS, "generated": GENERATED_IDS}
AUTHORS = {"wiktionary": "Wiktionary", "generated": "LibreDict"}  # every text keeps an author
GENERATED_AUTHOR = "LibreDict"  # of a generated text, also a Wiktionary sentence's Russian
# The coverage gate's scope: verb lists up to (LEVEL_NAMES) and tenses up to (indexes of drill_cells.LEVELS). 2.0
# (kyukhin 2026-11-22): the A1 and A2 verbs, tenses up to A2; 2.1 (#371, kyukhin 2026-11-23): every verb of the
# three lists, tenses up to B1. This is the one place to change.
SCOPE = (3, 2)
SCOPE_NAMES = {(2, 1): "A1 and A2 verbs, tenses up to A2 (2.0)", (3, 2): "Verbs up to B1, tenses up to B1 (2.1)"}
# #371's pair gate: every shipped (cell, sentence) pair has its verdict (0134, "B1 drill examples", Pipeline 7). On
# since #371's generated rows landed; False only lists the pairs in the report.
PAIR_GATE = True
KAIKKI_PREFIX = "Scripts/data/kaikki-el-"  # the pinned kaikki subset (0136): the Wiktionary usage examples
GREEK_LETTER = re.compile(r"[Ͱ-Ͽἀ-῿]")
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
WIKTIONARY_SOURCE = {
    "id": "wiktionary-ell-examples",
    "kind": "example_sentences",
    "display_name": "Wiktionary (Greek usage examples)",
    "license": "CC BY-SA 4.0",
    "url": "https://kaikki.org/dictionary/",
}
GENERATED_SOURCE = {
    "id": "libredict-drill-ell",
    "kind": "example_sentences",
    "display_name": "Drill examples (LibreDict, generated)",
    "license": "CC BY-SA 4.0",
    "url": "https://github.com/kyukhin/dict-app/tree/master/Scripts/data/drill-examples",
}

# #385: corpus sentences (0134, "Corpus sentences"). The data files are the pin: `original` holds each text, the
# documents file each document's licence; the BabyLM-ell parquet (gated) is not committed.
CORPUS_FILE, DOCUMENTS_FILE = "ell-corpus.tsv", "ell-corpus-documents.tsv"
CORPUS_COLUMNS = ("id", "cell", "doc", "original", "text", "eng", "rus", "model", "check", "checked_by",
                  "texts_sha256")
DOCUMENT_COLUMNS = ("doc", "collection", "work", "licence", "statement", "url", "checked_by")
BABYLM_REVISION = "5a8f8df0fc19"  # BabyLM-community/babylm-ell on Hugging Face, data/train-00000-of-00001.parquet
# The licences that ship (kyukhin 2026-11-27: never ND, never a bare permission to copy): `pd` or the
# `CreditLicense.id` of the app's Credits, with the name Credits gives it. Order: the data_source row's.
CORPUS_LICENCES = {
    "pd": "public domain",
    "cc_by_3_0": "CC BY 3.0", "cc_by_4_0": "CC BY 4.0",
    "cc_by_sa_3_0": "CC BY-SA 3.0", "cc_by_sa_4_0": "CC BY-SA 4.0",
    "cc_by_nc_3_0": "CC BY-NC 3.0", "cc_by_nc_4_0": "CC BY-NC 4.0",
    "cc_by_nc_sa_3_0": "CC BY-NC-SA 3.0", "cc_by_nc_sa_4_0": "CC BY-NC-SA 4.0",
}
NONCOMMERCIAL = frozenset(k for k in CORPUS_LICENCES if "_nc_" in k)
# NonCommercial rows ship while LibreDict is free, with no ads and no purchases (kyukhin 2026-11-27). A change to
# the app's business model turns this off first; the NC rows then drop and each of their cells falls back to its
# next sentence (its generated row) or, for a cell a writer skipped, to its skip line, which `ell-skipped.tsv`
# keeps (kyukhin 2026-11-28: an excluded corpus row never leaves its cell empty; the fallback gate checks it).
NC_ALLOWED = True
# A statement that names NoDerivatives, or only grants copying or distribution, never ships (belt and braces
# against a mislabel like BabyLM's column: 0134, Checks 6).
NO_DERIVATIVES = re.compile(r"\bND\b|NoDerivatives|No Derivatives|Όχι παράγωγα", re.IGNORECASE)
COPY_ONLY = re.compile(r"Ελεύθερη αναπαραγωγή|Ελεύθερη διάθεση", re.IGNORECASE)
# Public domain needs its basis: the author died more than 70 years ago (Greek law 2121/1993), so by 1955 in 2026.
PD_DIED_BY = 1955
LIFE = re.compile(r"\b\d{4}\s*[–-]\s*(\d{4})\b")
CORPUS_SOURCE = {
    "id": "corpus-ell-drill",
    "kind": "example_sentences",
    "display_name": "Greek texts via BabyLM-ell (drill examples)",
    "version": f"babylm-ell {BABYLM_REVISION}",
    "url": "https://github.com/kyukhin/dict-app/blob/master/Scripts/data/drill-examples/ell-corpus-documents.tsv",
}
# Gate 4, the edits a corpus text may have: a leading speaker tag, dash, or exercise number or letter; a
# look-alike character (µ, ∆, a Latin letter inside a Greek word, the digit 0 for Ο); the first letter's case;
# punctuation, quotation marks and spacing. An elision apostrophe and the comma of ό,τι belong to the word. A
# speaker tag is a name of one or two words before a colon, as plays and transcripts write them (*ΜΑ:, ΠΑΙΔΙ 6:,
# Ο Εβραίος:, (Ο τελωνειακός):, Σ.:), or a narrator's part without one (Αφηγητής). A name's words are each
# capitalised or in capitals, a number may follow (ΠΑΙΔΙ-1), and a tag in parentheses may hold any words; so a
# clause before a colon («Δεν μιλάω:», CodeRabbit on #387) is no tag (`SPEAKER_TAG`, `is_speaker_tag`).
SPEAKER_TAG = re.compile(r"^\s*(?P<open>\()?\*?(?P<first>[^\W\d_]+)\.?"
                         r"(?:[ -](?:(?P<second>[^\W\d_]+)\.?|\d{1,2}))?(?(open)\))\s*:\s*")
LEADING_EDIT = re.compile(r"^\s*(?:(?:Αφηγητής|Αφηγήτρια)(?=\s)"
                          r"|[-–—]+|\(?\d{1,3}[^\W\d_]?[.)]?\)?(?=\s)|\(?[^\W\d_][.)](?=\s))\s*")
# Apostrophe look-alikes, and the increment sign ∆ (no letter, so mapped before the words are cut).
APOSTROPHE_LIKE = str.maketrans({"’": "'", "ʼ": "'", "`": "'", "´": "'", "΄": "'", "‘": "'", "∆": "Δ"})
# Apostrophes as quotation marks ('Ναι' είπε; CodeRabbit on #387): one that opens a word, not after a letter or
# digit, and the next apostrophe, which closes a word of two or more letters (or a final mark) and is not followed
# by a letter. They count as quotation marks, not as part of a word. A word-initial elision with no such partner
# ('πείσαν, να 'ναι), or one before a one-letter elision (σ', μ', τ'), stays an elision.
QUOTE_PAIR = re.compile(r"(?<!\w)'(?=[^\W\d_])([^']*?(?:[^\W\d_]{2}|[.!?,;…]))'(?![^\W\d_])")
# An elision apostrophe keeps to its word across a space: σ' ένα, σ'ένα; να 'ναι, να' ναι.
APOSTROPHE_SPACE = re.compile(r"(?<=[^\W\d_])'\s+(?=[^\W\d_])|(?<=[^\W\d_])\s+'(?=[^\W\d_])")
LOOKALIKES = str.maketrans({"µ": "μ", "A": "Α", "B": "Β", "E": "Ε", "H": "Η", "I": "Ι", "K": "Κ",
                            "M": "Μ", "N": "Ν", "O": "Ο", "P": "Ρ", "T": "Τ", "X": "Χ", "Y": "Υ", "Z": "Ζ",
                            "o": "ο"})
GATE_WORD = re.compile(r"[όΌ],τι|'?[^\W\d_]+(?:'[^\W\d_]+)*'?|\d+")
# Gate 5, the final ν: δε, μη and τη never before a vowel or κ, π, τ, ξ, ψ, μπ, ντ, γκ, τσ, τζ.
MISSING_NU = re.compile(r"(?<!\w)(δε|μη|τη)\s+(?=[αεηιουωάέήίόύώϊϋΐΰκπτξψ]|μπ|ντ|γκ|τσ|τζ)", re.IGNORECASE)

# Tatoeba's tags that keep a sentence or translation out. Maintenance tags
# (every tag starting with "@") say the sentence, its language or a link
# needs a fix; only those about audio or adoption do not block.
HARMLESS_MAINTENANCE = frozenset({"@change audio", "@audio: check", "@audio: move", "@unblock", "@please adopt"})
CONTENT_TAGS = frozenset({
    "vulgar", "vulgar (in parts)", "rude", "offensive", "possibly offensive", "potentially offensive",
    "sexual", "sex", "sexuality", "obscene", "pornography", "x-rated", "nsfw",
    "slur", "ethnic slur", "racist", "racism", "sexist", "misogynistic", "misogyny", "homophobic",
    "hate speech", "insult", "insulting", "usually insulting", "derogatory", "derogatory language",
    "swearing", "swearword", "profanity", "violence", "violent", "rape", "drugs",
    "crude machismo", "normalization of sexual harassment", "sensitive", "politically incorrect",
})

# Runs of letters, an inner apostrophe kept (spec, Pipeline step 3).
WORD = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*")
ASCII_LOWER = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def word_key(word: str) -> str:
    """`WordKey.word` (0130): the word with only A–Z lowercased."""
    return word.translate(ASCII_LOWER)


def tokens(text: str) -> list[tuple[str, int, int]]:
    """(token, start, length) of each word, offsets in Unicode scalars."""
    return [(m.group(0), m.start(), m.end() - m.start()) for m in WORD.finditer(text)]


def is_blocking(tag: str) -> bool:
    return (tag.startswith("@") and tag not in HARMLESS_MAINTENANCE) or tag in CONTENT_TAGS


# ---------------------------------------------------------------------------
# The subset
# ---------------------------------------------------------------------------

def read_lines(path: Path) -> list[list[str]]:
    """The tab-separated rows of a subset file (`.tsv.xz`, or `.tsv` in the
    fixture)."""
    data = path.read_bytes()
    if path.name.endswith(".xz"):
        data = lzma.decompress(data)
    return [line.split("\t") for line in data.decode("utf-8").split("\n") if line]


@dataclass
class Subset:
    """One projection, read: sentences by id, links both ways, tags, natives."""
    sentences: dict[int, tuple[str, str, str]]  # id -> (Tatoeba lang, text, author or "")
    links: dict[int, list[int]]  # id -> linked ids, ascending
    tags: dict[int, frozenset[str]]  # lowercased
    natives: frozenset[tuple[str, str]]  # (Tatoeba lang, username)


def read_subset(paths: dict[str, Path]) -> Subset:
    sentences = {}
    for row in read_lines(paths["sentences"]):
        author = row[3] if len(row) > 3 and row[3] != "\\N" else ""
        sentences[int(row[0])] = (row[1], row[2], author)
    links = collections.defaultdict(set)
    for a, b in read_lines(paths["links"]):
        links[int(a)].add(int(b))
        links[int(b)].add(int(a))
    tags = collections.defaultdict(set)
    for row in read_lines(paths["tags"]):
        tags[int(row[0])].add(row[1].strip().lower())
    natives = frozenset((row[0], row[1]) for row in read_lines(paths["natives"]))
    return Subset(sentences, {k: sorted(v) for k, v in links.items()},
                  {k: frozenset(v) for k, v in tags.items()}, natives)


def subset_folder() -> str:
    """The one pinned subset folder, as an `inputs.json` key."""
    keys = [k for k, v in inputs.pins().items() if k.startswith(SUBSET_PREFIX) and "export_files" in v]
    if len(keys) != 1:
        raise RuntimeError(f"inputs.json must pin exactly one {SUBSET_PREFIX}<date> folder, found {keys}")
    return keys[0]


def subset_paths(folder: str) -> dict[str, dict[str, Path]]:
    """Every file of the pinned subset, checked against its pin."""
    return {lang: {part: inputs.committed(f"{folder}/{lang}-{part}.tsv.xz") for part in PARTS}
            for lang in SUBSETS}


# ---------------------------------------------------------------------------
# Keys: Greek through the forms tables, English through morphy
# ---------------------------------------------------------------------------

def term_spellings(term: str) -> list[str]:
    """#339: the spellings of a one-word list term that a token can have:
    the term and its cleaned spellings (0130, linking rule 2), each one
    token. στη(ν) is στη and στην, Γεια! is Γεια; a term with a space,
    such as (ένα) σωρό, has none."""
    if any(c.isspace() for c in term):
        return []
    return [s for s in dict.fromkeys([term, *cleaned_variants(term)]) if WORD.fullmatch(s)]


def own_forms(term: str) -> frozenset[str]:
    """The highlighted forms (lowercase NFC) that are the list term's own."""
    return frozenset(nfc(s.lower()) for s in term_spellings(term))


class GreekWords:
    """The Greek forms, headwords and list words (spec, Pipeline step 4)."""

    def __init__(self, reader: sqlite3.Connection, list_rule: bool = True):
        self.lemmas_of: dict[str, set[str]] = collections.defaultdict(set)  # lowercase NFC form -> lemma words
        self.verbs_of: dict[str, set[str]] = collections.defaultdict(set)  # the same, verb lemmas only
        self.function_words: set[str] = set()  # lowercase NFC forms of `FUNCTION_POS` lemmas and `FUNCTION_VERBS`
        queries = (
            "SELECT word, word, pos FROM lemma WHERE lang = 'ell'",
            "SELECT p.form, l.word, l.pos FROM paradigm p JOIN lemma l ON l.id = p.lemma_id WHERE l.lang = 'ell'",
            "SELECT f.form, l.word, l.pos FROM form_link f JOIN lemma l ON l.id = f.lemma_id WHERE l.lang = 'ell'",
        )
        for sql in queries:
            for form, word, pos in reader.execute(sql):
                self.lemmas_of[nfc(form.lower())].add(nfc(word))
                if pos == "verb":
                    self.verbs_of[nfc(form.lower())].add(nfc(word))
                if pos in FUNCTION_POS or (pos == "verb" and nfc(word) in FUNCTION_VERBS):
                    self.function_words.add(nfc(form.lower()))
        self.verbs = {nfc(word) for (word,) in reader.execute(
            "SELECT word FROM lemma WHERE lang = 'ell' AND pos = 'verb'")}
        self.headwords = {nfc(word) for (word,) in reader.execute(
            f"SELECT word FROM entries WHERE source IN ({','.join('?' * len(GREEK_DICTIONARIES))})",
            GREEK_DICTIONARIES)}
        # #339: the one-word terms of the Greek lists, by spelling. Without
        # `list_rule`, the keys as before #339 (the report compares both).
        self.terms_of: dict[str, set[str]] = collections.defaultdict(set)
        self.terms: set[str] = set()  # the one-word terms
        if list_rule:
            for (term,) in reader.execute("SELECT term FROM wordlist_item WHERE series = ?", (GREEK_LISTS,)):
                for spelling in term_spellings(nfc(term)):
                    self.terms_of[spelling].add(nfc(term))
                    self.terms.add(nfc(term))

    def keys(self, token: str) -> set[str]:
        """A token that is a one-word term of the Greek lists, as written or
        lowercased (#339), keys that term, the token itself when it is a
        headword, and of its lemmas only the verbs: αυτό keys αυτό, not
        αυτός; πάω keys πάω and πηγαίνω. Any other token keys the lemmas it
        is a cell, the word or a link page of, and itself, as written or
        lowercased, when it is a headword."""
        lower = nfc(token.lower())
        keys = {w for w in (token, lower) if w in self.headwords}
        terms = self.terms_of.get(token, set()) | self.terms_of.get(lower, set())
        if terms:
            keys |= terms | self.verbs_of.get(lower, set())
        else:
            keys |= self.lemmas_of.get(lower, set())
        return {word_key(k) for k in keys}

    def own(self, key: str) -> tuple[frozenset[str], bool]:
        """A key's own forms, which its examples keep (#339), and whether
        they come first: a list word's spellings, first unless the word is a
        verb; none for other keys."""
        if key not in self.terms:
            return frozenset(), False
        return own_forms(key), key not in self.verbs


class EnglishWords:
    """WordNet's morphy as the app's `Morphy` has it (0136, "Morphy (#143)"),
    and the one-word terms of the English lists."""

    # WordNet's detachment rules, in its order. Adverbs have none.
    RULES = {
        "v": (("s", ""), ("ies", "y"), ("es", "e"), ("es", ""), ("ed", "e"), ("ed", ""), ("ing", "e"), ("ing", "")),
        "n": (("s", ""), ("ses", "s"), ("xes", "x"), ("zes", "z"), ("ches", "ch"), ("shes", "sh"),
              ("men", "man"), ("ies", "y")),
        "a": (("er", ""), ("est", ""), ("er", "e"), ("est", "e")),
    }
    POS_ORDER = ("v", "n", "a", "r")
    BITS = {"n": 1, "v": 2, "a": 4, "r": 8}
    MIN_NOMINAL_BASE = 3

    # How a token's inferred keys are trusted (CodeRabbit, #177): "guess" is
    # built; the others are measured for the report. "two-lemmas": skip when two
    # or more inferred lemmas are list words. "only-key": an inferred key only
    # as the token's one list-word key, the token itself included. "none".
    AMBIGUITY_RULES = ("guess", "two-lemmas", "only-key", "none")

    def __init__(self, reader: sqlite3.Connection, ambiguity_rule: str = "guess"):
        self.exceptions: dict[str, list[tuple[str, str]]] = collections.defaultdict(list)
        for form, pos, base in reader.execute("SELECT form, pos, base FROM morphy_exception ORDER BY form, pos, base"):
            self.exceptions[form].append((pos, base))
        self.lemma_masks = dict(reader.execute("SELECT word, pos_mask FROM morphy_lemma"))
        self.list_words = {term.lower() for (term,) in reader.execute(
            "SELECT term FROM wordlist_item WHERE series = ?", (ENGLISH_LISTS,))
            if term.isascii() and term.isalpha()}
        self.ambiguity_rule = ambiguity_rule
        self.ambiguous: set[str] = set()  # tokens whose inferred keys are skipped

    @functools.lru_cache(maxsize=None)
    def bases(self, word: str) -> tuple[str, ...]:
        """`Morphy.analyses(of:)`'s bases for a lowercase word, without the
        word itself: per part of speech (verb, noun, adj, adv) all its
        exceptions, else the first rule whose base is a lemma of that part
        of speech."""
        return tuple(base for base, _ in self.analyses(word))

    @functools.lru_cache(maxsize=None)
    def analyses(self, word: str) -> tuple[tuple[str, bool], ...]:
        """`bases`, each with whether WordNet's exception lists give it (else
        a detachment rule guessed it)."""
        detached = []
        for pos in self.POS_ORDER:
            for detach, attach in self.RULES.get(pos, ()):
                if word.endswith(detach):
                    base = word[:len(word) - len(detach)] + attach
                    if base and (pos == "v" or len(base) >= self.MIN_NOMINAL_BASE):
                        detached.append((base, pos))
        found = []
        for pos in self.POS_ORDER:
            own = [base for p, base in self.exceptions.get(word, ()) if p == pos]
            if own:
                found += [(base, True) for base in own]
                continue
            hit = next((base for base, p in detached
                        if p == pos and self.lemma_masks.get(base, 0) & self.BITS[pos]), None)
            if hit is not None:
                found.append((hit, False))
        listed = {base for base, listed_ in found if listed_}
        seen, out = {word}, []
        for base, _ in found:
            if base not in seen:
                seen.add(base)
                out.append((base, base in listed))
        return tuple(out)

    @functools.lru_cache(maxsize=None)
    def keys(self, token: str) -> frozenset[str]:
        """A token of a–z letters keys itself and its morphy lemmas that are
        list words (went → go). Morphy over-generates (CodeRabbit, #177), so a
        token keys no inferred lemma when two of its lemmas are list words
        (lives: live, life), nor a lemma a suffix rule guessed when the token
        is itself a list word (evening ↛ even, building ↛ build). WordNet's
        exception lists are kept: was → be, saw → see."""
        if not (token.isascii() and token.isalpha()):
            return frozenset()
        word = token.lower()
        own = {word} if word in self.list_words else set()
        inferred = {base for base in self.bases(word) if base in self.list_words}
        guessed = {base for base, listed in self.analyses(word) if base in inferred and not listed}
        if (self.ambiguity_rule == "only-key" and len(own | inferred) > 1) or \
                (self.ambiguity_rule == "two-lemmas" and len(inferred) > 1) or \
                (self.ambiguity_rule == "guess" and (len(inferred) > 1 or (own and guessed))):
            self.ambiguous.add(word)
            return frozenset(own)
        return frozenset(own | inferred)


# ---------------------------------------------------------------------------
# The pipeline
# ---------------------------------------------------------------------------

@dataclass
class Candidate:
    id: int
    text: str
    author: str
    tokens: list[tuple[str, int, int]]
    translations: dict[str, tuple[int, str, str]]  # lang -> (id, text, author)
    native: bool
    rank: tuple = ()


@dataclass
class Result:
    """One language's examples and what the report needs."""
    lang: str
    total: int = 0
    drops: dict[str, int] = field(default_factory=dict)  # filter -> sentences, in filter order
    translation_drops: dict[str, collections.Counter] = field(default_factory=dict)
    candidates: dict[int, Candidate] = field(default_factory=dict)
    occurrences: dict[str, int] = field(default_factory=dict)  # key -> candidate sentences
    words: dict[str, list[tuple[int, int, int, str]]] = field(default_factory=dict)  # key -> (sid, start, length, form)
    tag_hits: collections.Counter = field(default_factory=collections.Counter)


def rank(lang: str, native: bool, translations: int, words: int, sid: int) -> tuple:
    """Step 5's order of a candidate, lowest first: Greek by a native author,
    then more translations; English the other way round; then 3 to 10
    words, then the lower id."""
    short = 0 if SHORT_WORDS[0] <= words <= SHORT_WORDS[1] else 1
    return ((0 if native else 1, -translations, short, sid) if lang == "ell"
            else (-translations, 0 if native else 1, short, sid))


def choose(occurrences: list[tuple[tuple, int, int, int, str]], limit: int = PER_WORD,
           own: frozenset[str] = frozenset(), own_first: bool = False) -> list:
    """Up to `limit` occurrences (rank, sid, start, length, form): one
    sentence per new form first, then the rest, each in rank order. With
    `own_first` (a Greek list word that is no verb, #339) the sentences of
    its `own` forms come first, in rank order, and other forms only fill up:
    ο shows ο, not των, τη, τες. Otherwise, when the per-form pass leaves
    out every `own` form (a verb's), the best own-form sentence leads and
    the last pick drops: λέω shows λέω."""
    if own_first and own:
        mine = heapq.nsmallest(limit, (o for o in occurrences if o[4] in own))
        if mine:
            others = [o for o in occurrences if o[4] not in own]
            return mine + (choose(others, limit - len(mine)) if len(mine) < limit else [])
    best: dict[str, tuple] = {}
    for o in occurrences:
        if o[4] not in best or o[0] < best[o[4]][0]:
            best[o[4]] = o
    chosen = sorted(best.values())[:limit]
    if own and not any(o[4] in own for o in chosen):
        mine = [o for form, o in best.items() if form in own]
        if mine:
            chosen = [min(mine)] + chosen[:limit - 1]
    if len(chosen) < limit:
        taken = {o[1] for o in chosen}
        rest = [o for o in heapq.nsmallest(limit + len(chosen), occurrences) if o[1] not in taken]
        chosen += rest[:limit - len(chosen)]
    return chosen


def build_language(lang: str, subset: Subset, keys_of: Callable[[str], Iterable[str]],
                   own_of: Callable[[str], tuple[frozenset[str], bool]] | None = None) -> Result:
    """Spec, Pipeline steps 1 to 5 for the sentences of one language."""
    result = candidates(lang, subset)
    result.occurrences, result.words = index(result, keys_of, own_of)
    return result


def candidates(lang: str, subset: Subset) -> Result:
    """Steps 1 and 2: the sentences that pass the filters, with their
    translations and their rank."""
    result = Result(lang)
    tatoeba = TATOEBA[lang]
    drops = collections.Counter()
    usable_cache: dict[int, str | None] = {}

    def unusable(tid: int, tl: str) -> str | None:
        """Why a translation cannot be used, or None."""
        if tid not in usable_cache:
            _, raw, author = subset.sentences[tid]
            reason = None
            blocking = sorted(t for t in subset.tags.get(tid, ()) if is_blocking(t))
            if not author:
                reason = "no author"
            elif blocking:
                reason = "blocking tag"
                result.tag_hits.update(blocking)
            usable_cache[tid] = reason
            result.translation_drops.setdefault(tl, collections.Counter())[reason or "usable"] += 1
        return usable_cache[tid]

    for sid in sorted(sid for sid, s in subset.sentences.items() if s[0] == tatoeba):
        _, raw, author = subset.sentences[sid]
        result.total += 1
        if not author:
            drops["no author"] += 1
            continue
        blocking = sorted(t for t in subset.tags.get(sid, ()) if is_blocking(t))
        if blocking:
            drops["blocking tag"] += 1
            result.tag_hits.update(blocking)
            continue
        text = nfc(raw)
        toks = tokens(text)
        if len(toks) > MAX_WORDS:
            drops[f"over {MAX_WORDS} words"] += 1
            continue
        linked = [t for t in subset.links.get(sid, ()) if t in subset.sentences]
        translations = {}
        for tl in TRANSLATIONS[lang]:
            options = [t for t in linked if subset.sentences[t][0] == TATOEBA[tl] and not unusable(t, tl)]
            if options:
                tid = min(options, key=lambda t: ((TATOEBA[tl], subset.sentences[t][2]) not in subset.natives, t))
                _, ttext, tauthor = subset.sentences[tid]
                translations[tl] = (tid, nfc(ttext), tauthor)
        if lang == "ell" and "eng" not in translations:
            drops["no usable English translation"] += 1
            continue
        if not translations:
            drops["no usable translation"] += 1
            continue
        native = (tatoeba, author) in subset.natives
        result.candidates[sid] = Candidate(sid, text, author, toks, translations, native,
                                           rank(lang, native, len(translations), len(toks), sid))
    order = ["no author", "blocking tag", f"over {MAX_WORDS} words", "no usable English translation",
             "no usable translation"]
    result.drops = {name: drops[name] for name in order if name in drops}
    return result


def index(result: Result, keys_of: Callable[[str], Iterable[str]],
          own_of: Callable[[str], tuple[frozenset[str], bool]] | None = None) -> tuple[dict[str, int], dict[str, list]]:
    """Steps 4 and 5: every key's candidate count and its chosen examples
    (sentence id, form start, form length, form). A sentence counts once per
    key, highlighted at its first token that gives the key. `own_of` gives
    a key's own forms, which `choose` keeps (#339)."""
    found: dict[str, list] = collections.defaultdict(list)
    for c in result.candidates.values():
        seen = set()
        for tok, start, length in c.tokens:
            for key in keys_of(tok):
                if key not in seen:
                    seen.add(key)
                    found[key].append((c.rank, c.id, start, length, nfc(tok.lower())))
    words = {}
    for key in sorted(found):
        own, own_first = own_of(key) if own_of else (frozenset(), False)
        words[key] = [(o[1], o[2], o[3], o[4]) for o in choose(found[key], own=own, own_first=own_first)]
    return {key: len(occ) for key, occ in found.items()}, words


# ---------------------------------------------------------------------------
# Drill examples (#364): one sentence per drill cell
# ---------------------------------------------------------------------------

def drill_tokens(text: str) -> list[tuple[str, int, int]]:
    """The match rule's tokens of an NFC text: (token lowercased and NFC,
    start, end) in Unicode scalars. Step 3's runs, with an elided word glued
    to the next split off (σ'αγαπώ is σ and αγαπώ), and an elided θ' or ν',
    glued or before a space, as its own token θ' or ν' (θ' αγαπούσα,
    ν'ανεβαίνουν), which blocks but is never θα or να."""
    out = []
    for word, start, _ in tokens(text):
        while (glued := ELIDED.fullmatch(word)) is not None:
            head = glued.group(1).lower()
            out.append((ELIDED_PARTICLES.get(head, head), start, start + 1))
            start, word = start + 2, glued.group(2)
        token, end = nfc(word.lower()), start + len(word)
        if token in ELIDED_PARTICLES and end < len(text) and text[end] in APOSTROPHES:
            token = ELIDED_PARTICLES[token]
        out.append((token, start, end))
    return out


def skip_back(toks: list[tuple[str, int, int]], j: int, negations: bool) -> int:
    """The index of the token before `j` once clitics, and μη(ν) when
    `negations`, are skipped; -1 at the start."""
    k = j - 1
    while k >= 0 and (toks[k][0] in CLITICS or (negations and toks[k][0] in NEGATIONS)):
        k -= 1
    return k


def find_form(toks: list[tuple[str, int, int]], form: str, infinitives: frozenset[str]) -> tuple[int, int] | None:
    """The span (start, end) of the first occurrence of a cell form in a
    sentence's `drill_tokens`, by the match rule (0134, "Match rule"), or
    None:
    1. exact words: accents kept, only case ignored;
    2. a compound form's words in order with only clitics between, and
       μη(ν) after να: θα σου γράψω, να μην το κάνεις, το έχω γράψει;
    3. a form that does not start with θα or να never follows θα, να, an
       elided θ' or ν', ας or μη(ν), clitics skipped: θα έγραφα is no
       imperfect, Μην ανησυχείς, ας γράφει and ν' ανεβαίνουν no present; an
       elided θ' or ν' is never the θα or να of a form: θ' ακούσετε is no
       future;
    4. έχω or είχα with an aorist infinitive in the next 3 tokens, clitics
       or one other word between, is an auxiliary: in έχει γράψει and έχει
       ήδη γράψει, έχει is not έχω's present; in έχει ένα γράμμα it is.
    The span runs from the form's first word to the verb, clitics between
    included (rule 6)."""
    parts = form.split(" ")
    for j, (tok, _, end) in enumerate(toks):
        if tok != parts[-1]:
            continue
        k = j
        for need in reversed(parts[:-1]):
            k = skip_back(toks, k, need == "να")
            if k < 0 or toks[k][0] != need:
                break
        else:
            if parts[0] not in PARTICLES:
                before = skip_back(toks, k, False)
                if before >= 0 and toks[before][0] in BLOCKERS:
                    continue
            if parts[-1] in AUXILIARIES and is_auxiliary(toks, j, infinitives):
                continue
            return toks[k][1], end
    return None


def is_auxiliary(toks: list[tuple[str, int, int]], j: int, infinitives: frozenset[str]) -> bool:
    """Whether the έχω or είχα form at `j` is an auxiliary (match rule 4):
    an aorist infinitive follows within the next 3 tokens, with only clitics
    and at most one other word between (έχει ήδη γράψει)."""
    others = 0
    for tok, _, _ in toks[j + 1:j + 4]:
        if tok in infinitives:
            return True
        if tok not in CLITICS:
            others += 1
            if others > 1:
                return False
    return False


def aorist_infinitives(reader: sqlite3.Connection) -> frozenset[str]:
    """Every aorist infinitive of the forms tables (γράψει), lowercased NFC:
    what makes έχω and είχα an auxiliary (match rule 4)."""
    return frozenset(nfc(form.lower()) for (form,) in reader.execute(
        "SELECT DISTINCT p.form FROM paradigm p JOIN tagset t ON t.id = p.tagset_id "
        "WHERE ' ' || t.tags || ' ' LIKE '% infinitive-aorist %'"))


@dataclass
class Homographs:
    """Spellings that fill several cells (match rule 5), as (cell key, form)."""
    reading: set[tuple[str, str]]  # another reading: another person, tense, mood, voice or verb
    aspect: set[tuple[str, str]]  # aspect only: one family, person and voice (κάνε)
    shared: list[str]  # spellings in the cells of two verbs


def homographs(cells: list[drill_cells.DrillCell]) -> Homographs:
    by_spelling: dict[str, list[drill_cells.DrillCell]] = collections.defaultdict(list)
    for c in cells:
        for form in dict.fromkeys(c.forms):
            by_spelling[form].append(c)
    reading, aspect, shared = set(), set(), []
    for form, group in by_spelling.items():
        if len(group) < 2:
            continue
        readings = {(c.verb, c.voice, c.person, FAMILY.get(c.tense, c.tense)) for c in group}
        (reading if len(readings) > 1 else aspect).update((c.key, form) for c in group)
        if len({c.verb for c in group}) > 1:
            shared.append(form)
    return Homographs(reading, aspect, sorted(shared))


def source_of(sid: int) -> int:
    """A sentence's source by its id (0134): 0 Tatoeba, 1 Wiktionary, 2 generated, 3 corpus (#385)."""
    return (TATOEBA_SOURCE if sid < WIKTIONARY_IDS else WIKTIONARY if sid < GENERATED_IDS
            else GENERATED if sid < CORPUS_IDS else CORPUS)


def cell_order(sid: int, form_index: int, rank: tuple, own: bool = False) -> tuple:
    """The choice's order of a sentence for a cell, lowest first: sentences
    written by people first (Tatoeba, Wiktionary, then a corpus, #385), then
    generated ones; the cell's first form (the option shown as right) before
    another, a data row written or translated for the cell (`own`, #365)
    before one written for another, then the source's own rank (Tatoeba:
    step 5's; the data rows: 3 to 10 words, fewer words, the id)."""
    return (SOURCE_RANK[source_of(sid)], min(form_index, 1), 0 if own else 1) + tuple(rank)


@dataclass
class Drill:
    """The drill's cells and the sentence chosen for each."""
    pool: list
    cells: list[drill_cells.DrillCell]
    homographs: Homographs
    rows: dict[str, tuple[int, int, int, str]]  # cell key -> (sid, start, length, form)
    found: dict[str, int]  # cell key -> sentences that hold it
    waiting: dict[str, int]  # cell key -> sentences held only through another reading, without an ok verdict
    data: dict[int, Candidate] = field(default_factory=dict)  # #365: the Wiktionary and generated rows, by id
    # #385: (cell, corpus id) pairs a corpus row holds besides its own cell, without an ok verdict: not taken.
    corpus_waiting: list[tuple[str, int]] = field(default_factory=list)


def build_drill(pool: list, cells: list[drill_cells.DrillCell], candidates: dict[int, Candidate],
                infinitives: frozenset[str], verdicts: dict[tuple[str, int], str] | None = None,
                data: dict[int, Candidate] | None = None, own: dict[int, str] | None = None,
                skipped: Iterable[str] = ()) -> Drill:
    """One sentence per cell (0134, "Choice"), from the Tatoeba candidates
    and the data files' rows (`data`, #365; `own` gives each row's cell). A
    `no` verdict of the second pass keeps that sentence out of that cell,
    whatever the cell is. A spelling of another reading counts only with an
    `ok` verdict for (cell, sentence); without one the cell stays open. A
    `skipped` cell (`ell-skipped.tsv`) stays without a sentence, even when
    one is found (kyukhin 2026-11-22), unless its own corpus row ships: the
    skip line is its fallback (kyukhin 2026-11-28). A corpus row (#385)
    serves another cell than its own only with an `ok` verdict; without one
    the pair waits (`corpus_waiting`)."""
    verdicts, data, own, skipped = verdicts or {}, data or {}, own or {}, frozenset(skipped)
    homo = homographs(cells)
    by_last: dict[str, set[int]] = collections.defaultdict(set)
    for i, c in enumerate(cells):
        for form in c.forms:
            by_last[form.rsplit(" ", 1)[-1]].add(i)
    occurrences: dict[str, list[tuple]] = collections.defaultdict(list)
    waiting: collections.Counter = collections.Counter()
    corpus_waiting: list[tuple[str, int]] = []
    everything = {**candidates, **data}
    for sid in sorted(everything):
        candidate = everything[sid]
        toks = drill_tokens(candidate.text)
        for i in sorted({i for tok, _, _ in toks for i in by_last.get(tok, ())}):
            c, blocked = cells[i], False
            if verdicts.get((c.key, sid)) == "no":
                continue  # decided: never this sentence for this cell
            # #385: a corpus row serves another cell only with an ok verdict (Open question 24).
            foreign = source_of(sid) == CORPUS and own.get(sid) != c.key and verdicts.get((c.key, sid)) != "ok"
            for form_index, form in enumerate(c.forms):
                span = find_form(toks, form, infinitives)
                if span is None:
                    continue
                if foreign:
                    corpus_waiting.append((c.key, sid))
                    break
                if (c.key, form) in homo.reading and verdicts.get((c.key, sid)) != "ok":
                    blocked = True
                    continue
                occurrences[c.key].append((cell_order(sid, form_index, candidate.rank, own.get(sid) == c.key), sid,
                                           span[0], span[1] - span[0], form))
                break
            else:
                if blocked:
                    waiting[c.key] += 1
    rows = {}
    for key, found in occurrences.items():
        if key in skipped:  # #385: only the cell's own corpus row ships over its skip line
            found = [f for f in found if source_of(f[1]) == CORPUS and own.get(f[1]) == key]
        if found:
            rows[key] = min(found)[1:]
    return Drill(pool, cells, homo, rows, {key: len(found) for key, found in occurrences.items()},
                 {key: n for key, n in waiting.items() if key not in rows and key not in skipped}, data,
                 sorted(corpus_waiting))


@dataclass
class Rows:
    sentences: list[tuple]
    translations: list[tuple]
    words: list[tuple]


def is_cell(key: str) -> bool:
    """A cell key (`<word>|<facet>|<person>`): no word holds a `|`."""
    return "|" in key


def rows_of(results: list[Result], drill: Drill | None = None) -> Rows:
    """The three tables' rows, sorted by their keys: the word examples, and
    the drill's cell rows (`ord` 1) when `drill` is given. A sentence that
    serves several words or cells is one row."""
    sentences, translations, words = [], [], []
    for r in results:
        used = set()
        for key, chosen in r.words.items():
            for order, (sid, start, length, _) in enumerate(chosen, 1):
                words.append((r.lang, key, order, sid, start, length))
                used.add(sid)
        if drill is not None and r.lang == "ell":
            for key, (sid, start, length, _) in drill.rows.items():
                words.append(("ell", key, 1, sid, start, length))
                used.add(sid)
        for sid in used:
            c = r.candidates[sid] if sid in r.candidates else drill.data[sid]
            sentences.append((sid, r.lang, c.text, c.author))
            translations += [(sid, tl, tid, text, author) for tl, (tid, text, author) in c.translations.items()]
    return Rows(sorted(sentences), sorted(translations, key=lambda t: (t[0], t[1])), sorted(words))


def write_rows(conn: sqlite3.Connection, rows: Rows, version: str, credits: Iterable[dict] = ()) -> None:
    """The rows and the `data_source` rows: Tatoeba's, then `credits` (#365:
    the Wiktionary usage examples and the generated sentences)."""
    with conn:
        conn.executemany("INSERT INTO example_sentence(id, lang, text, author) VALUES (?, ?, ?, ?)", rows.sentences)
        conn.executemany("INSERT INTO example_translation(sentence_id, lang, id, text, author) "
                         "VALUES (?, ?, ?, ?, ?)", rows.translations)
        conn.executemany("INSERT INTO example_word(lang, word, ord, sentence_id, form_start, form_length) "
                         "VALUES (?, ?, ?, ?, ?, ?)", rows.words)
        conn.executemany("INSERT INTO data_source(id, kind, display_name, version, license, url) "
                         "VALUES (:id, :kind, :display_name, :version, :license, :url)",
                         [{**DATA_SOURCE, "version": version}, *credits])


def table_hashes(conn: sqlite3.Connection) -> dict[str, tuple[int, str]]:
    """Rows and the sha256 of each example table's rows in key order."""
    result = {}
    for table in TABLES:
        digest, count = hashlib.sha256(), 0
        for row in conn.execute(f"SELECT * FROM {table} ORDER BY {KEY_ORDER[table]}"):
            digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")
            count += 1
        result[table] = (count, digest.hexdigest())
    return result


def rows_hashes(rows: Rows) -> dict[str, tuple[int, str]]:
    """`table_hashes` of rows not written yet: the same digest of the same
    rows in key order."""
    result = {}
    for table, items in zip(TABLES, (rows.sentences, rows.translations, rows.words)):
        digest = hashlib.sha256()
        for row in items:
            digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")
        result[table] = (len(items), digest.hexdigest())
    return result


def split_rows(rows: Rows) -> tuple[Rows, Rows]:
    """The word examples (word rows, their sentences and translations) and
    the drill's part (cell rows and the sentences only they use)."""
    words = [w for w in rows.words if not is_cell(w[1])]
    cells = [w for w in rows.words if is_cell(w[1])]
    word_ids = {w[3] for w in words}
    cell_ids = {w[3] for w in cells} - word_ids

    def part(ids: set[int], word_rows: list[tuple]) -> Rows:
        return Rows([s for s in rows.sentences if s[0] in ids], [t for t in rows.translations if t[0] in ids],
                    word_rows)
    return part(word_ids, words), part(cell_ids, cells)


def shipped_size(rows: Rows, lang: str | None = None) -> tuple[dict[str, int], int]:
    """Bytes per table as the files ship (the rows of `lang`, or all of them,
    in a file of their own, VACUUMed as the build packs its files), and the
    xz size of that file (`lzma` preset 6, as cut_packs.py compresses)."""
    keep = (lambda r_lang: True) if lang is None else (lambda r_lang: r_lang == lang)
    ids = {s[0] for s in rows.sentences if keep(s[1])}
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "examples.sqlite"
        conn = sqlite3.connect(path)
        try:
            conn.execute("PRAGMA page_size = 4096")
            conn.executescript(SCHEMA)
            with conn:
                conn.executemany("INSERT INTO example_sentence VALUES (?, ?, ?, ?)",
                                 [s for s in rows.sentences if s[0] in ids])
                conn.executemany("INSERT INTO example_translation VALUES (?, ?, ?, ?, ?)",
                                 [t for t in rows.translations if t[0] in ids])
                conn.executemany("INSERT INTO example_word VALUES (?, ?, ?, ?, ?, ?)",
                                 [w for w in rows.words if keep(w[0])])
            conn.execute("VACUUM")
            sizes = dict.fromkeys(TABLES, 0)
            for table, size in conn.execute(f"""
                    SELECT m.tbl_name, SUM(d.pgsize) FROM dbstat AS d JOIN sqlite_master AS m ON m.name = d.name
                    WHERE m.tbl_name IN ({",".join("?" * len(TABLES))}) GROUP BY m.tbl_name""", TABLES):
                sizes[table] = size
        finally:
            conn.close()
        xz = len(lzma.compress(path.read_bytes(), format=lzma.FORMAT_XZ, check=lzma.CHECK_NONE, preset=6))
    return sizes, xz


# ---------------------------------------------------------------------------
# Drill example data (#365): Wiktionary and generated rows, verdicts, skips
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DataRow:
    """A row of `ell.tsv` (0134, "Data files")."""
    id: int
    source: str  # wiktionary, generated
    page: str  # the Wiktionary entry the example comes from; empty for a generated row
    cell: str  # the cell key it was written or translated for
    text: str
    eng: str
    rus: str
    model: str
    check: str  # ok, or the second pass's reason
    checked_by: str
    texts_sha256: str = ""  # #371: what `check` was given on, `texts_hash(text, eng, rus)`

    @property
    def texts(self) -> tuple[str, str, str]:
        return self.text, self.eng, self.rus


@dataclass(frozen=True)
class CorpusRow:
    """A row of `ell-corpus.tsv` (#385, 0134 "Corpus sentences", Data files)."""
    id: int
    cell: str  # the cell key it was checked for; one row per cell
    doc: str  # its document, a row of `ell-corpus-documents.tsv`
    original: str  # the sentence as the document has it, runs of whitespace as one space
    text: str  # what ships, NFC: `original` with only the allowed edits (gate 4)
    eng: str
    rus: str
    model: str  # pass 1: it judged the pair, made `text` and translated
    check: str  # ok: pass 2 passed it as written or as fixed
    checked_by: str
    texts_sha256: str = ""

    @property
    def texts(self) -> tuple[str, str, str]:
        return self.text, self.eng, self.rus

    @property
    def adapted(self) -> bool:
        """LibreDict changed punctuation, capitals, a look-alike letter or a speaker tag (the byline's "adapted")."""
        return self.text != nfc(self.original)


@dataclass(frozen=True)
class Document:
    """A row of `ell-corpus-documents.tsv`: a document a corpus row cites, with its licence check (#385)."""
    doc: str
    collection: str  # as the byline names it: openbook.gr, CLARIN:EL, Global Storybooks, Vikidia
    work: str  # the byline's first part: "author, «title»", a corpus record's title, "author, translator"
    licence: str  # `pd` or a key of CORPUS_LICENCES
    statement: str  # the licence as the document or its record states it, verbatim; for pd its basis
    url: str
    checked_by: str  # who read `statement` at `url`, and the date


@dataclass
class DrillData:
    """The data files, read."""
    rows: list[DataRow]
    readings: dict[tuple[str, int], tuple[str, str]]  # (cell, sentence id) -> (ok or no, texts_sha256)
    reading_rows: list[dict[str, str]]
    skipped: dict[str, str]  # cell -> reason
    skipped_rows: list[dict[str, str]]
    pin: dict[str, tuple[int, str, str]]  # a Wiktionary usage example's NFC text -> (n, page, English)
    wiktionary_version: str  # the kaikki subset's dump
    version: str  # the data file's date: the latest in its generated rows
    corpus: list[CorpusRow] = field(default_factory=list)  # #385
    documents: dict[str, Document] = field(default_factory=dict)  # #385: by `doc`
    document_rows: list[Document] = field(default_factory=list)  # #385: as the file has them

    def credits(self) -> list[dict]:
        """The two `data_source` rows (0134, "Credits and `data_source`")."""
        return [{**WIKTIONARY_SOURCE, "version": self.wiktionary_version},
                {**GENERATED_SOURCE, "version": self.version}]


def texts_hash(text: str, eng: str, rus: str) -> str:
    """What ties a verdict to what it was given on (#371, `texts_sha256`;
    CodeRabbit on #384): the first 16 hex digits of the sha256 of the
    sentence's NFC text, its English and its Russian (NFC, empty for none),
    joined by a tab, which no field of the data files can hold."""
    return hashlib.sha256("\t".join(nfc(s) for s in (text, eng, rus)).encode("utf-8")).hexdigest()[:16]


def shipped_texts(c: Candidate) -> tuple[str, str, str]:
    """What a verdict covers of a candidate (#371): its text and the English
    and Russian translations it ships with (empty for none)."""
    return c.text, c.translations.get("eng", (0, "", ""))[1], c.translations.get("rus", (0, "", ""))[1]


def read_tsv(path: Path, columns: tuple[str, ...]) -> list[dict[str, str]]:
    """A data file's rows: UTF-8, tab-separated, the header `columns`. Empty
    fields at the end of a line may be missing (an editor that strips
    trailing whitespace)."""
    lines = path.read_text(encoding="utf-8").split("\n")
    if lines[0].split("\t") != list(columns):
        raise RuntimeError(f"{path.name}: the header must be {' '.join(columns)}")
    rows = []
    for number, line in enumerate(lines[1:], 2):
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) > len(columns):
            raise RuntimeError(f"{path.name}:{number}: {len(fields)} fields, not {len(columns)}")
        rows.append(dict(zip(columns, fields + [""] * (len(columns) - len(fields)))))
    return rows


def kaikki_subset() -> tuple[Path, str]:
    """The pinned kaikki subset (0136), checked against its pin, and its dump's date."""
    keys = [k for k in inputs.pins() if k.startswith(KAIKKI_PREFIX)]
    if len(keys) != 1:
        raise RuntimeError(f"inputs.json must pin exactly one {KAIKKI_PREFIX}*.jsonl.gz, found {keys}")
    return inputs.committed(keys[0]), inputs.pins()[keys[0]]["dump_date"]


def wiktionary_examples(path: Path) -> dict[str, tuple[int, str, str]]:
    """The usage examples of a kaikki subset that 0134 takes, by NFC text:
    (n, page, English). Taken: `type` "example" without a `ref`, with an
    English translation, on one line, in Greek letters, at most 15 words; n
    counts them in the dump's order, and a text met twice keeps its first
    entry."""
    found: dict[str, tuple[int, str, str]] = {}
    with (gzip.open(path, "rt", encoding="utf-8") if path.name.endswith(".gz")
          else open(path, encoding="utf-8")) as f:
        for line in f:
            entry = json.loads(line)
            for sense in entry.get("senses", []):
                for example in sense.get("examples", []):
                    if example.get("type") != "example" or example.get("ref"):
                        continue
                    english = example.get("english") or example.get("translation")
                    text = nfc(example.get("text", "").strip())
                    if (not english or "\n" in text or not GREEK_LETTER.search(text)
                            or len(tokens(text)) > MAX_WORDS or text in found):
                        continue
                    found[text] = (len(found) + 1, nfc(entry.get("word", "")), nfc(english.strip()))
    return found


def read_drill_data(folder: Path, pin: dict[str, tuple[int, str, str]], wiktionary_version: str) -> DrillData:
    rows = []
    for r in read_tsv(folder / DATA_FILE, DATA_COLUMNS):
        if not r["id"].isdigit():
            raise RuntimeError(f"{DATA_FILE}: id {r['id']!r} is not a number")
        rows.append(DataRow(**{**r, "id": int(r["id"])}))
    reading_rows = read_tsv(folder / READINGS_FILE, READING_COLUMNS)
    for r in reading_rows:
        if not r["sentence_id"].isdigit():
            raise RuntimeError(f"{READINGS_FILE}: sentence_id {r['sentence_id']!r} is not a number")
    skipped_rows = read_tsv(folder / SKIPPED_FILE, SKIPPED_COLUMNS)
    dates = [d for r in rows if r.source == "generated" for d in DATE.findall(r.model + " " + r.checked_by)]
    corpus, documents = [], []
    if (folder / CORPUS_FILE).is_file():  # #385
        for r in read_tsv(folder / CORPUS_FILE, CORPUS_COLUMNS):
            if not r["id"].isdigit():
                raise RuntimeError(f"{CORPUS_FILE}: id {r['id']!r} is not a number")
            corpus.append(CorpusRow(**{**r, "id": int(r["id"])}))
        documents = [Document(**r) for r in read_tsv(folder / DOCUMENTS_FILE, DOCUMENT_COLUMNS)]
    return DrillData(rows, {(r["cell"], int(r["sentence_id"])): (r["verdict"], r["texts_sha256"]) for r in reading_rows},
                     reading_rows,
                     {r["cell"]: r["reason"] for r in skipped_rows}, skipped_rows, pin,
                     f"enwiktionary {wiktionary_version}", max(dates, default="none"),
                     corpus, {d.doc: d for d in documents}, documents)


def data_candidates(data: DrillData, cells: dict[str, drill_cells.DrillCell]) -> dict[int, Candidate]:
    """The data rows as candidates of the choice. A row of a cell the drill
    no longer asks is skipped (stale). Its English is Wiktionary's or
    generated, its Russian generated; the rank is 3 to 10 words, then fewer
    words, then the id (for Wiktionary, the dump's order)."""
    out = {}
    for r in data.rows:
        if r.cell not in cells or r.source not in AUTHORS:
            continue
        toks = tokens(r.text)
        short = 0 if SHORT_WORDS[0] <= len(toks) <= SHORT_WORDS[1] else 1
        out[r.id] = Candidate(r.id, r.text, AUTHORS[r.source], toks,
                              {"eng": (r.id, r.eng, AUTHORS[r.source]), "rus": (r.id, r.rus, GENERATED_AUTHOR)},
                              False, (short, len(toks), r.id))
    return out


def data_verdicts(data: DrillData, texts: dict[int, tuple[str, str, str]]) -> dict[tuple[str, int], str]:
    """The reading verdicts, each only while its `texts_sha256` is the hash
    of what its sentence ships with (`texts`: id -> the NFC text, English
    and Russian, `shipped_texts` of every candidate): a verdict on a text or
    a translation since changed is stale, never used (#371; CodeRabbit on
    #384). A data row's `check` ok is its own cell's verdict (the second
    pass checked the row in that reading) while its `texts_sha256` is the
    hash of the row's texts, as edited or not, and of the texts in `texts`
    (a built file read after an edit carries the old ones); the readings
    file's verdicts come on top of it."""
    current = {sid: texts_hash(*shipped) for sid, shipped in texts.items()}
    own = {(r.cell, r.id): "ok" for r in [*data.rows, *data.corpus]
           if r.check == "ok" and r.texts_sha256 == texts_hash(*r.texts) == current.get(r.id)}
    return {**own, **{key: verdict for key, (verdict, digest) in data.readings.items()
                      if current.get(key[1]) == digest}}


# ---------------------------------------------------------------------------
# Corpus sentences (#385): sentences written by people, each under its
# document's own licence
# ---------------------------------------------------------------------------

def gate_words(text: str) -> list[str]:
    """Gate 4's words of a text: runs of letters with an elision apostrophe
    kept ('πείσαν, σ'), ό,τι as one word, and runs of digits; a look-alike
    letter mapped to the Greek one inside a word with Greek letters, or
    alone (a Latin O for the article Ο, the digit 0 too). A pair of
    apostrophes used as quotation marks ('Ναι', `QUOTE_PAIR`) is no part of
    its words."""
    words = []
    unquoted = QUOTE_PAIR.sub(r" \1 ", nfc(text).translate(APOSTROPHE_LIKE))
    for w in GATE_WORD.findall(APOSTROPHE_SPACE.sub("'", unquoted)):
        lookalike = GREEK_LETTER.search(w) or "µ" in w or (len(w) == 1 and ord(w) in LOOKALIKES)
        words.append("Ο" if w == "0" else w.translate(LOOKALIKES) if lookalike else w)
    return words


def is_name(word: str) -> bool:
    """A word of a speaker tag's name: capitalised (Γιώργος, Ο) or in
    capitals, a stray small letter allowed (ΜΑρΘΑ, νΑΤΑΣΑ)."""
    return word[:1].isupper() or 2 * sum(ch.isupper() for ch in word) > len(word)


def is_speaker_tag(m: re.Match) -> bool:
    """A leading `SPEAKER_TAG` match is a speaker tag (0134, Checks 4): in
    parentheses, or its words names (`is_name`), a number allowed as the
    second. "Δεν μιλάω:" is a clause, not a tag (CodeRabbit on #387)."""
    return bool(m.group("open")) or (is_name(m.group("first"))
                                     and (m.group("second") is None or is_name(m.group("second"))))


def same_words(original: str, text: str) -> bool:
    """Gate 4, "never a word": `text` has the words of `original`, in order,
    once the allowed edits are undone (a leading speaker tag, dash or
    exercise label dropped; a look-alike letter; the first letter's case;
    punctuation, quotation marks and spacing). A changed, added, dropped or
    reordered word, or a moved accent, fails; so does ότι made ό,τι, and a
    clause before a colon dropped as if it were a speaker tag."""
    def first_case(words: list[str]) -> list[str]:
        return [words[0][:1].lower() + words[0][1:]] + words[1:] if words else words
    shipped = first_case(gate_words(text))
    trimmed = original
    while True:
        if first_case(gate_words(trimmed)) == shipped:
            return True
        tag = SPEAKER_TAG.match(trimmed)
        cut = trimmed[tag.end():] if tag and is_speaker_tag(tag) else LEADING_EDIT.sub("", trimmed, count=1)
        if cut == trimmed:
            return False
        trimmed = cut


def licence_problems(d: Document | None) -> list[str]:
    """Gate 6 on a document: in the documents file with a `checked_by`; its
    licence `pd` or a CC BY, BY-SA, BY-NC or BY-NC-SA of CORPUS_LICENCES; a
    statement that names no NoDerivatives and is no bare grant to copy or
    distribute; public domain with its basis (a life that ended by
    PD_DIED_BY). NC_ALLOWED is not checked here: an NC row then drops."""
    if d is None:
        return ["not in the documents file"]
    problems = []
    if not d.checked_by:
        problems.append("no checked_by")
    if d.licence not in CORPUS_LICENCES:
        problems.append(f"licence {d.licence!r} is not one that ships")
    if NO_DERIVATIVES.search(d.statement):
        problems.append("the statement names NoDerivatives")
    if COPY_ONLY.search(d.statement):
        problems.append("the statement only grants copying or distribution")
    if d.licence == "pd" and not any(int(died) <= PD_DIED_BY for died in LIFE.findall(d.statement)):
        problems.append(f"public domain without its basis (an author who died by {PD_DIED_BY})")
    if any("|" in s for s in (d.work, d.collection)):
        problems.append("a | in the work or collection")  # gate 8: the `author` field's separator
    if not d.work or not d.collection or not d.url:
        problems.append("no work, collection or url")
    return problems


def corpus_author(r: CorpusRow, d: Document) -> str:
    """The `author` field of a corpus sentence (0134, "How it ships"):
    `<work>|<collection>|<licence>|<change>`, change `adapted` when the text
    is not the original."""
    return "|".join((d.work, d.collection, d.licence, "adapted" if r.adapted else ""))


def corpus_status(data: DrillData, cells: dict[str, drill_cells.DrillCell], nc_allowed: bool = NC_ALLOWED
                  ) -> dict[int, str]:
    """Why each corpus row does not ship, by id ("" when it is a candidate):
    a cell the drill no longer asks or a check given on other texts (stale:
    reported, never used; its cell falls back, gate 7), or a NonCommercial
    document while `nc_allowed` is off (licence)."""
    status = {}
    for r in data.corpus:
        d = data.documents.get(r.doc)
        if r.cell not in cells:
            status[r.id] = "stale: no drill cell"
        elif r.check != "ok" or not r.checked_by or r.texts_sha256 != texts_hash(*r.texts):
            status[r.id] = "stale: checked on other texts"
        elif d is not None and d.licence in NONCOMMERCIAL and not nc_allowed:
            status[r.id] = "licence: NonCommercial while NC_ALLOWED is off"
        else:
            status[r.id] = ""
    return status


def corpus_candidates(data: DrillData, cells: dict[str, drill_cells.DrillCell],
                      nc_allowed: bool = NC_ALLOWED) -> dict[int, Candidate]:
    """The corpus rows as candidates of the choice: those not stale and
    allowed by `nc_allowed`. Author: the structured field; translations by
    LibreDict; rank as a data row's (3 to 10 words, fewer words, the id)."""
    status = corpus_status(data, cells, nc_allowed)
    out = {}
    for r in data.corpus:
        d = data.documents.get(r.doc)
        if status[r.id] or d is None:
            continue
        toks = tokens(r.text)
        short = 0 if SHORT_WORDS[0] <= len(toks) <= SHORT_WORDS[1] else 1
        out[r.id] = Candidate(r.id, r.text, corpus_author(r, d), toks,
                              {"eng": (r.id, r.eng, GENERATED_AUTHOR), "rus": (r.id, r.rus, GENERATED_AUTHOR)},
                              False, (short, len(toks), r.id))
    return out


def corpus_failures(data: DrillData, cells: dict[str, drill_cells.DrillCell],
                    infinitives: frozenset[str]) -> list[str]:
    """The corpus gate (0134, "Corpus sentences", Checks 1 to 6 and 8; 7
    makes a row stale, `corpus_status`; 9, the fallback, is checked on the
    choice, `corpus_without_fallback`): the build fails on each."""
    problems, last, seen = [], 0, set()
    for r in data.corpus:
        where = f"{CORPUS_FILE} {r.id} {r.cell}"
        if not CORPUS_IDS < r.id < CORPUS_IDS + WIKTIONARY_IDS:
            problems.append(f"{where}: id outside 3,000,000,001…3,999,999,999")
        if r.id <= last:
            problems.append(f"{where}: ids must be unique and ascending")
        last = max(last, r.id)
        if r.cell in seen:
            problems.append(f"{where}: a second row for the cell")
        seen.add(r.cell)
        if any(not t or t != nfc(t) for t in (r.text, r.eng, r.rus)):
            problems.append(f"{where}: a text, eng or rus empty or not NFC")
        if not r.original or "\t" in r.original:
            problems.append(f"{where}: no original")
        if len(tokens(r.text)) > MAX_WORDS:
            problems.append(f"{where}: over {MAX_WORDS} words")
        if not same_words(r.original, r.text):
            problems.append(f"{where}: its words are not the original's (gate 4)")
        if MISSING_NU.search(r.text):
            problems.append(f"{where}: δε, μη or τη without its final ν (gate 5)")
        if not TEXTS_HASH.fullmatch(r.texts_sha256):
            problems.append(f"{where}: texts_sha256 {r.texts_sha256!r} is not 16 hex digits")
        if not r.model:
            problems.append(f"{where}: no model")
        problems += [f"{where}: document {r.doc}: {p}" for p in licence_problems(data.documents.get(r.doc))]
        cell = cells.get(r.cell)
        if cell is not None and not any(find_form(drill_tokens(r.text), form, infinitives) for form in cell.forms):
            problems.append(f"{where}: does not hold its cell by the match rule ({' / '.join(cell.forms)})")
    cited = {r.doc for r in data.corpus}
    docs_seen = set()
    for d in data.document_rows:
        if d.doc in docs_seen:
            problems.append(f"{DOCUMENTS_FILE} {d.doc}: twice")
        docs_seen.add(d.doc)
        if d.doc not in cited:
            problems.append(f"{DOCUMENTS_FILE} {d.doc}: no corpus row cites it")
    return problems


def corpus_credit(candidates: dict[int, Candidate], rows: Rows) -> list[dict]:
    """The `corpus-ell-drill` data_source row when corpus rows ship: the
    licences of their documents, by name, in CORPUS_LICENCES' order. Only
    the candidates stored in `rows` count: one that loses its cell, or
    waits for a verdict, credits nothing (CodeRabbit on #387)."""
    stored = {s[0] for s in rows.sentences}
    used = {c.author.split("|")[2] for c in candidates.values() if source_of(c.id) == CORPUS and c.id in stored}
    if not used:
        return []
    names = "; ".join(name for key, name in CORPUS_LICENCES.items() if key in used)
    return [{**CORPUS_SOURCE, "license": f"{names} (each document's own)"}]


def data_failures(data: DrillData, cells: dict[str, drill_cells.DrillCell], infinitives: frozenset[str],
                  sentences: dict[int, tuple[str, str, str]]) -> tuple[list[str], dict[str, list]]:
    """The form gate (0134, Checks 1) on the data files, and what is stale:
    rows, verdicts and skips of cells the drill no longer asks, verdicts on
    sentences that are not candidates (`sentences`: every candidate's id and
    `shipped_texts`), verdicts whose `texts_sha256` is not the hash of what
    their sentence ships with (`hashes`, #371: the text or a translation
    changed since the check) and data rows whose own `check` was given on
    other texts (`own`, the row edited since)."""
    problems, stale = [], {"rows": [], "readings": [], "hashes": [], "own": [], "skipped": []}
    last, texts = 0, set()
    for r in data.rows:
        where = f"{DATA_FILE} {r.id} {r.cell}"
        if r.source not in SOURCE_IDS:
            problems.append(f"{where}: source {r.source!r}")
            continue
        base = SOURCE_IDS[r.source]
        if not base < r.id < base + WIKTIONARY_IDS:
            problems.append(f"{where}: id outside the {r.source} range")
        if r.id <= last:
            problems.append(f"{where}: ids must be unique and ascending")
        last = max(last, r.id)
        if r.text in texts:
            problems.append(f"{where}: the text of another row")
        texts.add(r.text)
        if r.check != "ok" or not r.checked_by or not r.model:
            problems.append(f"{where}: check {r.check!r}, checked_by {r.checked_by!r}, model {r.model!r}")
        if any(not t or t != nfc(t) for t in (r.text, r.eng, r.rus)):
            problems.append(f"{where}: a text, eng or rus empty or not NFC")
        if not TEXTS_HASH.fullmatch(r.texts_sha256):
            problems.append(f"{where}: texts_sha256 {r.texts_sha256!r} is not 16 hex digits")
        if len(tokens(r.text)) > MAX_WORDS:
            problems.append(f"{where}: over {MAX_WORDS} words")
        if r.source == "wiktionary":
            pinned = data.pin.get(r.text)
            if pinned is None:
                problems.append(f"{where}: not a usage example of the pinned subset")
            elif (r.page, r.eng) != pinned[1:]:
                problems.append(f"{where}: page or English differ from the pin ({pinned[1]!r}, {pinned[2]!r})")
        elif r.page:
            problems.append(f"{where}: a generated row with a page")
        cell = cells.get(r.cell)
        if cell is None:
            stale["rows"].append(r)
            continue
        toks = drill_tokens(r.text)
        if not any(find_form(toks, form, infinitives) for form in cell.forms):
            problems.append(f"{where}: does not hold its cell by the match rule ({' / '.join(cell.forms)})")
        if TEXTS_HASH.fullmatch(r.texts_sha256) and r.texts_sha256 != texts_hash(*r.texts):
            stale["own"].append(r)
    seen = set()
    for r in data.reading_rows:
        where = f"{READINGS_FILE} {r['cell']} {r['sentence_id']}"
        if r["verdict"] not in ("ok", "no") or not r["checked_by"] or (r["cell"], r["sentence_id"]) in seen:
            problems.append(f"{where}: verdict {r['verdict']!r}, checked_by {r['checked_by']!r}, or twice")
        if not TEXTS_HASH.fullmatch(r["texts_sha256"]):
            problems.append(f"{where}: texts_sha256 {r['texts_sha256']!r} is not 16 hex digits")
        seen.add((r["cell"], r["sentence_id"]))
        sid = int(r["sentence_id"])
        if r["cell"] not in cells or sid not in sentences:
            stale["readings"].append(r)
        elif texts_hash(*sentences[sid]) != r["texts_sha256"]:
            stale["hashes"].append(r)
    seen = set()
    for r in data.skipped_rows:
        if not r["reason"] or not r["checked_by"] or r["cell"] in seen:
            problems.append(f"{SKIPPED_FILE} {r['cell']}: no reason or checked_by, or twice")
        seen.add(r["cell"])
        if r["cell"] not in cells:
            stale["skipped"].append(r)
    return problems, stale


def in_scope(c: drill_cells.DrillCell, scope: tuple[int, int] = SCOPE) -> bool:
    """A cell of the coverage gate's scope (`SCOPE`; 2.0: an A1 or A2 verb,
    a tense up to A2)."""
    return c.verb_level is not None and c.verb_level <= scope[0] and c.tense_level <= scope[1]


def skipped_with_rows(rows: Rows, skipped: dict[str, str], own: dict[int, str] | None = None) -> list[str]:
    """The skipped cells that have a cell row, checked on the rows as stored:
    a listed cell stays without an example (kyukhin 2026-11-22), unless the
    row is the cell's own corpus row (`own`: a corpus id's cell), which
    ships over the skip line (kyukhin 2026-11-28)."""
    own = own or {}
    return sorted(w[1] for w in rows.words if is_cell(w[1]) and w[1] in skipped
                  and not (source_of(w[3]) == CORPUS and own.get(w[3]) == w[1]))


def open_cells(drill: Drill, skipped: dict[str, str], scope: tuple[int, int] = SCOPE) -> list[str]:
    """The coverage gate's misses: cells in scope without a sentence that
    are not listed as skipped (kyukhin 2026-11-22: a listed cell is done)."""
    return [c.key for c in drill.cells
            if in_scope(c, scope) and c.key not in drill.rows and c.key not in skipped]


def corpus_without_fallback(drill: Drill, without: Drill, skipped: dict[str, str],
                            scope: tuple[int, int] = SCOPE) -> list[str]:
    """The fallback gate (#385; kyukhin 2026-11-28: an excluded corpus row
    never leaves its cell empty): the cells of the scope that show a corpus
    row and would be open in `without`, the choice with no corpus row (each
    stale, or NonCommercial with `NC_ALLOWED` off). A cell that has a
    sentence or a skip line there keeps one whichever corpus rows drop."""
    gaps = set(open_cells(without, skipped, scope))
    return sorted(key for key, (sid, *_) in drill.rows.items() if source_of(sid) == CORPUS and key in gaps)


def unchecked_pairs(rows: Rows, verdicts: dict[tuple[str, int], str]) -> list[tuple[str, int]]:
    """The pair gate's misses (#371), on the rows as stored: cell rows
    whose (cell, sentence) is neither its data row's own cell (`check` ok)
    nor `ok` in the readings file, each with the hash of the texts the pair
    ships with (`verdicts`: `data_verdicts`). The gate proves a verdict
    exists, not that it is right."""
    return sorted((w[1], w[3]) for w in rows.words if is_cell(w[1]) and verdicts.get((w[1], w[3])) != "ok")


def pair_gate_passes(unchecked: list[tuple[str, int]]) -> bool:
    """The pair gate (#371): no pair no check covers, while `PAIR_GATE` is
    on; off, the report only lists them."""
    return not unchecked or not PAIR_GATE


# ---------------------------------------------------------------------------
# Checks on the output (the gates that do not need the frequency list)
# ---------------------------------------------------------------------------

def output_failures(rows: Rows, results: list[Result], subsets: dict[str, Subset],
                    keys_of: dict[str, Callable[[str], Iterable[str]]]) -> dict[str, list[str]]:
    """Problems per gate (spec, Gates), checked on the rows as stored."""
    tags = {}
    for subset in subsets.values():
        tags.update(subset.tags)
    sentences = {s[0]: s for s in rows.sentences}
    by_sentence = collections.defaultdict(dict)
    for t in rows.translations:
        by_sentence[t[0]][t[1]] = t
    complete, spans, clean, references = [], [], [], []
    for sid, lang, text, author in rows.sentences:
        langs = set(by_sentence[sid])
        if lang == "ell" and "eng" not in langs:
            complete.append(f"{sid}: a Greek sentence without an English translation")
        if lang == "eng" and not langs & {"rus", "spa", "arb", "ell"}:
            complete.append(f"{sid}: an English sentence without a translation into rus, spa, arb or ell")
        if not author or text != nfc(text) or not text:
            complete.append(f"{sid}: no author, or a text not in NFC")
        if any(is_blocking(t) for t in tags.get(sid, ())):
            clean.append(f"sentence {sid}: {sorted(tags[sid])}")
    for sid, tl, tid, text, author in rows.translations:
        if sid not in sentences:
            references.append(f"translation {tid} of a sentence not stored: {sid}")
        if not author or text != nfc(text) or not text:
            complete.append(f"translation {tid}: no author, or a text not in NFC")
        if any(is_blocking(t) for t in tags.get(tid, ())):
            clean.append(f"translation {tid} ({tl}): {sorted(tags[tid])}")
    for lang, key, order, sid, start, length in rows.words:
        s = sentences.get(sid)
        if s is None or s[1] != lang:
            references.append(f"{lang} {key} {order}: sentence {sid} not stored in {lang}")
            continue
        if is_cell(key):
            continue  # a drill cell's span: `drill_failures`
        text = s[2]
        if not (0 <= start and length > 0 and start + length <= len(text)) or \
                (text[start:start + length], start, length) not in tokens(text) or \
                key not in keys_of[lang](text[start:start + length]):
            spans.append(f"{lang} {key} {order}: span {start}+{length} of {sid} {text!r}")
    for r in results:
        orders = collections.defaultdict(list)
        for key, chosen in r.words.items():
            orders[key] = [c[0] for c in chosen]
            if len(set(orders[key])) != len(orders[key]) or not 1 <= len(chosen) <= PER_WORD:
                references.append(f"{r.lang} {key}: {len(chosen)} examples, or one sentence twice")
    return {"complete": complete, "spans": spans, "clean": clean, "references": references}


def drill_failures(rows: Rows, cells: list[drill_cells.DrillCell], infinitives: frozenset[str],
                   tatoeba_ids: set[int]) -> dict[str, list[str]]:
    """The drill's gates (0134, "Report and gates"), on the rows as stored:
    every cell row's span holds one of its cell's forms by the match rule;
    every cell key is a cell of the build's list, one row each with `ord` 1;
    every Tatoeba sentence's id is below 10^9."""
    texts = {s[0]: s[2] for s in rows.sentences}
    by_key = {c.key: c for c in cells}
    spans, keys = [], []
    count: collections.Counter = collections.Counter()
    for lang, key, order, sid, start, length in rows.words:
        if not is_cell(key):
            continue
        count[key] += 1
        cell = by_key.get(key)
        if lang != "ell" or cell is None or order != 1:
            keys.append(f"{lang} {key} {order}: not a drill cell, or not ord 1")
            continue
        text = texts.get(sid)
        if text is None:
            continue  # `output_failures` counts it
        toks = drill_tokens(text)
        if (start, start + length) not in {find_form(toks, form, infinitives) for form in cell.forms}:
            spans.append(f"{key}: span {start}+{length} of {sid} {text!r}")
    keys += [f"{key}: {n} rows" for key, n in sorted(count.items()) if n != 1]
    keys += [f"Tatoeba sentence {sid}: id at or above 10^9" for sid, *_ in rows.sentences
             if sid in tatoeba_ids and sid >= WIKTIONARY_IDS]
    return {"cell spans": spans, "cell keys": keys}


# ---------------------------------------------------------------------------
# The verb gate (0136's top-500 ranking)
# ---------------------------------------------------------------------------

def load_frequency(path: Path) -> list[tuple[str, int]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        token, count = line.split()
        rows.append((token, int(count)))
    return rows


def top_lemmas(reader: sqlite3.Connection, frequency: list[tuple[str, int]], pos: str,
               limit: int = TOP_VERBS) -> list[str]:
    """The `limit` most frequent lemmas of `pos`, ranked as build_forms.py's
    coverage ranks them: a token's count goes to every lemma its folded form
    or word is, and ties go alphabetically."""
    lemma = {i: (word, norm, p) for i, word, norm, p in reader.execute(
        "SELECT id, word, word_normalized, pos FROM lemma WHERE lang = 'ell'")}
    by_norm = collections.defaultdict(set)
    for i, (_, norm, _) in lemma.items():
        by_norm[norm].add(i)
    lookup = collections.defaultdict(set)
    for norm, i in reader.execute("SELECT form_norm, lemma_id FROM form_lookup"):
        lookup[norm].add(i)
    score = collections.Counter()
    for token, count in frequency:
        key = normalize_greek(nfc(token.lower()))
        for i in lookup.get(key, set()) | by_norm.get(key, set()):
            score[i] += count
    ranked = sorted((i for i in score if lemma[i][2] == pos), key=lambda i: (-score[i], lemma[i][0]))
    return [word_key(lemma[i][0]) for i in ranked[:limit]]


def verb_gate(verbs: list[str], counts: dict[str, int]) -> tuple[int, bool]:
    """The top verbs with 3 or more examples, and whether that passes the
    gate: all TOP_VERBS ranked, at least GATE_VERBS of them (Kirill,
    2026-11-04: all 500 counted)."""
    three = sum(1 for w in verbs if counts.get(w, 0) >= 3)
    return three, len(verbs) == TOP_VERBS and three >= GATE_VERBS * TOP_VERBS


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def percent(part: int, whole: int) -> str:
    return f"{part / whole:.1%}" if whole else "—"


def highlighted(text: str, start: int, length: int) -> str:
    return cell(text[:start]) + "**" + cell(text[start:start + length]) + "**" + cell(text[start + length:])


def byline(sentence_author: str, translation_author: str | None) -> str:
    names = [sentence_author] + ([translation_author] if translation_author and translation_author != sentence_author
                                 else [])
    return ", ".join(names) + " · Tatoeba"


def list_rule_section(r: Result, greek: GreekWords, before: tuple[dict[str, int], dict[str, list]],
                      plain: dict[str, list]) -> list[str]:
    """#339: the Greek keys under the list-word rule against the keys
    without it, on the same candidates; the list words' own forms (`plain`:
    the choice without keeping them); the cornerstone words."""
    occ_before, words_before = before
    leading = sorted(k for k in r.words if r.words[k] != plain.get(k))
    keys = set(words_before) | set(r.words)
    gained = sorted(k for k in keys if k not in words_before)
    lost = sorted(k for k in keys if k not in r.words)
    changed = sorted(k for k in keys if k in words_before and k in r.words and words_before[k] != r.words[k])
    losers = sorted(((occ_before.get(k, 0) - r.occurrences.get(k, 0), k) for k in keys),
                    key=lambda x: (-x[0], x[1]))
    losers = [(n, k) for n, k in losers if n > 0][:20]
    terms = sorted(greek.terms)
    with_one = [t for t in terms if r.words.get(word_key(t))]
    three = [t for t in with_one if len(r.words[word_key(t)]) >= 3]
    all_own = [t for t in with_one if all(c[3] in own_forms(t) for c in r.words[word_key(t)])]
    out = ["", "### List words (#339)", "",
           "A token that is a one-word term of the Greek lists, as written or lowercased, keys that term, itself "
           "when it is a headword, and of its lemmas only the verbs (αυτό keys αυτό, not αυτός; πάω keys πάω and "
           "πηγαίνω). Other tokens key their lemmas and themselves as headwords, as before. A term's spellings are "
           "the term and its cleaned spellings (στη(ν): στη, στην). A list word that is no verb shows its own forms "
           "first; a verb keeps one sentence per form, and its own form leads when that pass leaves it out.", "",
           f"- One-word terms of `{GREEK_LISTS}`: {len(terms):,}; with an example: {len(with_one):,}; with 3 or "
           f"more: {len(three):,}; every example in the term's own form: {len(all_own):,}",
           f"- List words whose examples differ from the plain per-form choice: {len(leading):,}; "
           f"non-verbs, own forms first: {sum(1 for k in leading if k not in greek.verbs):,}; verbs whose "
           "dropped own form leads: " + (", ".join(k for k in leading if k in greek.verbs) or "none"),
           f"- Keys against the rule without list words, on the same candidates: {len(words_before):,} before, "
           f"{len(r.words):,} now; gain examples (none before): {len(gained):,}; lose them all: {len(lost):,}; "
           f"change them: {len(changed):,}",
           "", "**The 20 keys that lose the most candidate sentences**, candidates and examples before → now:", "",
           ", ".join(f"{k} ({occ_before.get(k, 0):,} → {r.occurrences.get(k, 0):,}; "
                     f"{len(words_before.get(k, ()))} → {len(r.words.get(k, ()))})" for _, k in losers) or "None.",
           "", f"**Keys that lose every example ({len(lost):,})**: " + (", ".join(lost) or "none") + ".",
           "", "**The cornerstone words**: examples, how many show the word's own form, and the forms shown.", "",
           "| Word | Candidates | Examples | Own form | Forms |", "|---|---|---|---|---|"]
    for t in CORNERSTONE:
        chosen = r.words.get(word_key(t), [])
        own = own_forms(t)
        out.append(f"| {cell(t)} | {r.occurrences.get(word_key(t), 0):,} | {len(chosen)} | "
                   f"{sum(1 for c in chosen if c[3] in own)} | {cell(', '.join(c[3] for c in chosen)) or '—'} |")
    return out


def drill_byline(c: Candidate, lang: str) -> str:
    """A cell sentence's byline (0134, "Byline") with its translation in
    `lang`, as the report shows it."""
    source = source_of(c.id)
    if source == TATOEBA_SOURCE:
        shown = c.translations.get(lang) or c.translations.get("eng")
        return byline(c.author, shown[2] if shown else None)
    if source == WIKTIONARY:
        return "Wiktionary" if lang == "eng" else "Wiktionary · translation: LibreDict, generated"
    if source == CORPUS:
        return corpus_byline(c.author)
    return "LibreDict, generated"


def corpus_byline(author: str) -> str:
    """A corpus sentence's byline in English (#385, 0134 "Attribution"): the
    work, the collection, the licence's name, "adapted" when LibreDict
    changed the text, and the translation's source."""
    work, collection, licence, change = (author.split("|") + ["", "", "", ""])[:4]
    parts = [work, collection, CORPUS_LICENCES.get(licence, licence)] + (["adapted"] if change else [])
    return " · ".join(parts) + " · translation: LibreDict, generated"


def list_word_share(data: DrillData, cells: dict[str, drill_cells.DrillCell], greek: GreekWords,
                    levels: dict[str, int]) -> list[tuple[float, DataRow, list[str]]]:
    """#365: each generated row's share of words that are list words up to
    its verb's level (a token that spells a term of the Greek lists, or a
    form of one), function words (`FUNCTION_POS`, `FUNCTION_VERBS`; #371,
    0134's Words: always allowed) or forms of the row's own verb (a token
    whose lemma is the cell's verb, or a word of the cell's forms: the cell
    carries the verb's level; CodeRabbit on #384), with the words that are
    none of these, lowest share first."""
    out = []
    for r in data.rows:
        if r.source != "generated" or r.cell not in cells:
            continue
        level = cells[r.cell].verb_level
        own = {nfc(word.lower()) for form in cells[r.cell].forms for word in form.split()}
        outside = []
        toks = [nfc(tok.lower()) for tok, _, _ in tokens(r.text)]
        for tok in toks:
            if tok in greek.function_words or tok in own or cells[r.cell].verb in greek.lemmas_of.get(tok, ()):
                continue
            known = [levels[w] for w in greek.terms_of.get(tok, set()) | greek.lemmas_of.get(tok, set()) if w in levels]
            if not known or min(known) > level:
                outside.append(tok)
        out.append((1 - len(outside) / len(toks) if toks else 0.0, r, outside))
    return sorted(out, key=lambda x: (x[0], x[1].id))


def corpus_section(drill: Drill, data: DrillData, status: dict[int, str], without: Drill | None = None) -> list[str]:
    """#385: the corpus rows by collection and licence, shipped and not with
    the reason; the adapted rows; the waiting pairs; the generated rows a
    corpus row supersedes; the documents by licence; with `without` (the
    choice without corpus rows), the cells that change."""
    rows = drill.rows
    shown = {sid for sid, *_ in rows.values()}
    reasons: dict[int, str] = {}
    for r in data.corpus:
        if status.get(r.id):
            reasons[r.id] = status[r.id]
        elif r.id in shown:  # stored: for its own cell, or for another through an ok verdict (CodeRabbit on #387)
            reasons[r.id] = ""
        elif r.cell in rows:
            reasons[r.id] = ("its cell takes a " + ("Tatoeba", "Wiktionary", "generated", "another corpus")[
                source_of(rows[r.cell][0])] + " sentence")
        else:
            reasons[r.id] = "a no verdict on its own cell"
    shipped = [r for r in data.corpus if not reasons[r.id]]
    groups: dict[tuple[str, str], list[CorpusRow]] = collections.defaultdict(list)
    for r in data.corpus:
        d = data.documents.get(r.doc)
        groups[(d.collection if d else "?", d.licence if d else "?")].append(r)
    out = ["", f"### Corpus sentences (#385)", "",
           f"`{CORPUS_FILE}`: {len(data.corpus):,} rows from {len({r.doc for r in data.corpus}):,} documents "
           f"(`{DOCUMENTS_FILE}`, each with its licence as its document states it); {len(shipped):,} ship, "
           f"{sum(1 for r in shipped if rows.get(r.cell, (0,))[0] == r.id):,} of them for their own cells; "
           f"NonCommercial rows allowed: {'yes' if NC_ALLOWED else 'no'} (`NC_ALLOWED`). A "
           "corpus row ranks after Tatoeba and Wiktionary and before generated rows, and serves another cell "
           "only with an `ok` verdict.", "",
           "| Collection | Licence | Documents | Rows | Shipped | Not shipped |", "|---|---|---|---|---|---|"]
    for (collection, licence), group in sorted(groups.items(), key=lambda g: (-len(g[1]), g[0])):
        why = collections.Counter(reasons[r.id] for r in group if reasons[r.id])
        out.append(f"| {cell(collection)} | {CORPUS_LICENCES.get(licence, licence)} | "
                   f"{len({r.doc for r in group}):,} | {len(group):,} | "
                   f"{sum(1 for r in group if not reasons[r.id]):,} | "
                   + (cell(", ".join(f"{n:,} {w}" for w, n in sorted(why.items()))) or "0") + " |")
    by_licence = collections.Counter(data.documents[r.doc].licence for r in shipped if r.doc in data.documents)
    docs_by_licence = collections.Counter(d.licence for d in data.document_rows)
    out += ["", "By licence (documents in the file; rows shipped): " + ", ".join(
        f"{CORPUS_LICENCES.get(k, k)} {docs_by_licence[k]:,}; {by_licence[k]:,}" for k in CORPUS_LICENCES
        if docs_by_licence[k]) + f". NonCommercial rows shipped: "
        f"{sum(n for k, n in by_licence.items() if k in NONCOMMERCIAL):,}.",
        f"- Adapted (LibreDict changed punctuation, capitals, a look-alike letter or a speaker tag; the byline says "
        f"\"adapted\"): {sum(1 for r in shipped if r.adapted):,} of the {len(shipped):,} shipped rows",
        f"- Shipped rows of cells in the coverage gate's scope: "
        f"{sum(1 for r in shipped if r.cell in {c.key for c in drill.cells if in_scope(c)}):,}"]
    generated_own = {r.cell: r.id for r in data.rows if r.source == "generated"}
    superseded = [generated_own[r.cell] for r in shipped
                  if r.cell in generated_own and rows.get(r.cell, (0,))[0] == r.id]
    still = [sid for sid in superseded if sid in shown]
    out.append(f"- Generated rows superseded by a corpus row (kept in `{DATA_FILE}` as the fallback): "
               f"{len(superseded):,}; {len(superseded) - len(still):,} no longer ship, {len(still):,} still serve "
               "another cell through an `ok` verdict")
    would = [(k, sid) for k, sid in drill.corpus_waiting
             if k not in rows or source_of(rows[k][0]) == GENERATED]
    out.append(f"- Waiting pairs (other cells a corpus row holds without an `ok` verdict; no pair round in #385, "
               f"kyukhin 2026-11-28): {len(drill.corpus_waiting):,} in {len({k for k, _ in drill.corpus_waiting}):,} "
               f"cells; of them in cells that show a generated sentence or none: {len(would):,} in "
               f"{len({k for k, _ in would}):,} cells")
    if without is not None:
        changed = sorted(k for k in set(rows) | set(without.rows) if rows.get(k) != without.rows.get(k))
        own = {k for k, (sid, *_) in rows.items() if source_of(sid) == CORPUS}
        others = sorted(set(changed) - own)
        out.append(f"- Cells that change against the choice without corpus rows: {len(changed):,}; all of them "
                   f"cells that show a corpus row: {'no: ' + ', '.join(others[:20]) if others else 'yes'}")
    out += ["", "The waiting pairs in cells that show a generated sentence or none (cell: corpus ids):", ""]
    grouped: dict[str, list[int]] = collections.defaultdict(list)
    for k, sid in would:
        grouped[k].append(sid)
    out += [f"- {cell(k)}: {', '.join(str(s) for s in ids)}" for k, ids in sorted(grouped.items())] or ["None."]
    return out


def drill_section(drill: Drill, greek: Result, data: DrillData | None = None, stale: dict | None = None,
                  missing: list[str] = (), share: list[tuple[float, DataRow, list[str]]] = (),
                  unchecked: list[tuple[str, int]] = (), corpus_status_: dict[int, str] | None = None,
                  without_corpus: Drill | None = None) -> list[str]:
    """#364, #365: the drill's cells, their sentences and the data files;
    #371: the pairs no check covers and the stale verdicts; #385: the corpus
    sentences, by collection and licence, and what they change."""
    cells, rows = drill.cells, drill.rows
    skipped = data.skipped if data else {}
    stale = stale or {"rows": [], "readings": [], "hashes": [], "own": [], "skipped": []}
    reading = {key for key, _ in drill.homographs.reading}
    aspect = {key for key, _ in drill.homographs.aspect} - reading
    columns = ("Tatoeba", "Wiktionary", "Corpus", "Generated")
    sources = (TATOEBA_SOURCE, WIKTIONARY, CORPUS, GENERATED)  # the columns' `source_of`, in the choice's order

    def counts(group: list[drill_cells.DrillCell]) -> str:
        by_source = collections.Counter(source_of(rows[c.key][0]) for c in group if c.key in rows)
        n = len(group)
        covered = " | ".join(f"{by_source[i]:,} ({percent(by_source[i], n)})" if by_source[i] else "0"
                             for i in sources)
        listed = sum(1 for c in group if c.key not in rows and c.key in skipped)
        none = n - sum(by_source.values()) - listed
        waiting = sum(1 for c in group if c.key in drill.waiting)
        return f"{n:,} | {covered} | {listed:,} | {none:,} ({percent(none, n)}) | {waiting:,}"

    header = "| " + " | ".join(("Cells",) + columns + ("Skipped", "None", "Waiting for a reading verdict")) + " |"
    rule = "|---" * (len(columns) + 4)  # the columns of `header`, without the closing bar
    out = ["## Drill cells (#364, #365)", "",
           "The cells: every cell the conjugation drill can ask (`drill_cells.py`, a port of 0132's rules: the "
           "three Greek lists' verbs, every tense up to B2, both voices). A cell's sentence holds the cell's whole "
           "form by 0134's match rule and is keyed `<word>|<facet>|<person>` in `example_word`. Every cell of the "
           f"coverage gate's scope ({SCOPE_NAMES[SCOPE]}) has one sentence or is skipped; the gate does not cover "
           "the cells outside it, such as the B2 tenses', which can have neither a sentence nor a skip entry. "
           "Sources, in this order: Tatoeba "
           "(#364), Wiktionary usage examples (#365), sentences from openly licensed corpora (#385) and generated "
           "sentences (#365), the last three from `Scripts/data/drill-examples/`. "
           "\"Skipped\": cells with no natural sentence, listed in `ell-skipped.tsv`, which the coverage gate counts "
           "as done. \"Waiting for a reading verdict\": open cells whose found sentences hold them only through a "
           "spelling of another reading (match rule 5), which takes a sentence only with an `ok` verdict of the "
           "second pass.", ""]
    by_list = collections.Counter(v.list_level for v in drill.pool)
    used = {sid for sid, *_ in rows.values()}
    word_sids = {sid for chosen in greek.words.values() for sid, *_ in chosen}
    through = sum(1 for k in reading if k in rows and (k, rows[k][3]) in drill.homographs.reading)
    verdicts = collections.Counter(r["verdict"] for r in data.reading_rows) if data else collections.Counter()
    out += [f"- The pool: {len(drill.pool):,} verbs: " + ", ".join(
                f"{LEVEL_NAMES[level]} {n:,}" for level, n in sorted(by_list.items()))
            + f"; {sum(1 for v in drill.pool if v.main == drill_cells.PASSIVE):,} with passive forms only, "
            f"{sum(1 for v in drill.pool if v.impersonal):,} impersonal",
            f"- Cells: {len(cells):,}; with a sentence: {len(rows):,} ({percent(len(rows), len(cells))}); "
            f"sentences: {len(used):,}, of them already word examples: {len(used & word_sids):,}, new: "
            f"{len(used - word_sids):,}",
            f"- Homographs: aspect-only cells (one sentence serves both) {len(aspect):,}; cells with a spelling of "
            f"another reading {len(reading):,}, of them with a sentence through that spelling (an `ok` verdict, or "
            f"a data row written for the cell) {through:,}, through another of their forms "
            f"{sum(1 for k in reading if k in rows) - through:,}, waiting for a reading verdict "
            f"{len(drill.waiting):,}; reading verdicts in `{READINGS_FILE}`: ok {verdicts['ok']:,}, no "
            f"{verdicts['no']:,}",
            f"- Spellings in the cells of two verbs ({len(drill.homographs.shared)}): "
            + (", ".join(drill.homographs.shared) or "none") + "."]

    if data is not None:
        in_file = collections.Counter(r.source for r in data.rows)
        shipped = collections.Counter(r.source for r in data.rows if r.id in used)
        scope = [c for c in cells if in_scope(c)]
        out += ["", "### Data files (#365)", "",
                f"- `{DATA_FILE}`: " + ", ".join(f"{source} {in_file[source]:,} rows, {shipped[source]:,} in the "
                                                 "pack" for source in SOURCE_IDS)
                + f"; stale (cells the drill no longer asks, skipped): {len(stale['rows']):,}",
                f"- `{READINGS_FILE}`: {len(data.reading_rows):,} verdicts (ok {verdicts['ok']:,}, no "
                f"{verdicts['no']:,}); stale (no drill cell, or no candidate sentence): {len(stale['readings']):,}; "
                f"stale (the sentence's text or a translation changed since the check, #371): "
                f"{len(stale['hashes']):,}; data rows whose own check was given on other texts: "
                f"{len(stale['own']):,}",
                f"- `{SKIPPED_FILE}`: {len(skipped):,} cells, {sum(1 for c in scope if c.key in skipped):,} in the "
                f"gate's scope; of them with their own corpus row, which ships over the skip line (#385): "
                f"{sum(1 for k in skipped if k in rows):,}; with a found sentence, left out: "
                f"{sum(1 for k in skipped if drill.found.get(k) and k not in rows):,}; stale: "
                f"{len(stale['skipped']):,}",
                f"- The coverage gate's scope ({SCOPE_NAMES[SCOPE]}): {len(scope):,} cells; with a sentence "
                f"{sum(1 for c in scope if c.key in rows):,}, skipped "
                f"{sum(1 for c in scope if c.key not in rows and c.key in skipped):,}, open {len(missing):,}"
                + (": " + ", ".join(missing[:50]) + (" …" if len(missing) > 50 else "") if missing else ""),
                f"- The data file's date (`libredict-drill-ell`'s version): {data.version}; Wiktionary: "
                f"{data.wiktionary_version}"]
        if data.corpus:
            out.append(f"- `{CORPUS_FILE}` (#385): {len(data.corpus):,} rows, {len(used & {r.id for r in data.corpus}):,} "
                       f"in the pack; `{DOCUMENTS_FILE}`: {len(data.document_rows):,} documents (\"Corpus sentences\" "
                       "below)")

    out += ["", "### By verb list and tense level", "", "| Verbs, tenses " + header, "|---" + rule + "|"]
    for level in (1, 2, 3):
        for tense_level, name in enumerate(drill_cells.LEVELS):
            group = [c for c in cells if c.verb_level == level and c.tense_level == tense_level]
            if group:
                out.append(f"| {LEVEL_NAMES[level]} verbs, {name} tenses | {counts(group)} |")
    for scope_, name in SCOPE_NAMES.items():
        out.append(f"| **{name}** | {counts([c for c in cells if in_scope(c, scope_)])} |")
    out.append(f"| **All** | {counts(cells)} |")

    out += ["", "### By tense and voice", "", "All verbs and tense levels. Main voice: the active, or the passive "
            "of a verb with passive forms only; passive: the passive of a verb with both voices.", "",
            "| Tense | Voice " + header, "|---|---" + rule + "|"]
    for tense in drill_cells.TENSES:
        for main, voice in ((True, "main"), (False, "passive")):
            group = [c for c in cells if c.tense == tense and c.main_voice == main]
            if group:
                out.append(f"| {tense} | {voice} | {counts(group)} |")

    out += ["", "### Samples", "", "| Cell | Forms | Sentence | eng | rus | Byline (rus) |",
            "|---|---|---|---|---|---|"]
    for key in DRILL_SAMPLES:
        cell_ = next((c for c in cells if c.key == key), None)
        forms = cell(" / ".join(cell_.forms)) if cell_ else "not a cell"
        if key not in rows:
            out.append(f"| {cell(key)} | {forms} | — | | | |")
            continue
        sid, start, length, _ = rows[key]
        c = greek.candidates[sid] if sid in greek.candidates else drill.data[sid]
        trs = [cell(c.translations[tl][1]) if tl in c.translations else "—" for tl in ("eng", "rus")]
        out.append(f"| {cell(key)} | {forms} | {highlighted(c.text, start, length)} | {' | '.join(trs)} | "
                   f"{cell(drill_byline(c, 'rus'))} |")

    top = sorted(drill.pool, key=lambda v: (drill_cells.NO_RANK if v.rank is None else v.rank, v.seq))[:20]
    out += ["", "### Open cells of the 20 most frequent verbs", "",
            "By the lists' frequency rank. Each: cells without a sentence of all its cells, then those at tenses "
            "up to A2 (skipped ones marked).", ""]
    for verb in top:
        mine = [c for c in cells if c.verb == verb.word]
        open_ = [c for c in mine if c.key not in rows]
        early = [f"{c.facet} {c.person}" + (" (skipped)" if c.key in skipped else "")
                 for c in open_ if c.tense_level <= 1]
        out.append(f"- {verb.word} ({LEVEL_NAMES[verb.list_level]}, rank {verb.rank}): {len(open_)} of "
                   f"{len(mine)} open; up to A2: " + (", ".join(early) or "none"))
    if data is None:
        return out

    out += ["", "### Stale data rows", "", "Rows of cells the drill no longer asks, which the build skips.", "",
            ", ".join(f"{r.id} {r.cell}" for r in stale["rows"]) or "None."]
    if data.corpus:
        out += corpus_section(drill, data, corpus_status_ or {}, without_corpus)

    by_source = collections.Counter(source_of(sid) for _, sid in unchecked)
    out += ["", f"### Pairs no check covers ({len(unchecked):,}; #371)", "",
            "Cell rows whose (cell, sentence) is neither its data row's own cell nor `ok` in "
            f"`{READINGS_FILE}`, each with the `texts_sha256` of the Greek, English and Russian the pair ships "
            "with: the pair gate fails on each"
            + ("" if PAIR_GATE else " once `PAIR_GATE` is on (until #371's pair checks land, it lists them)")
            + ". By source: " + ", ".join(f"{name} {by_source[i]:,}" for i, name in zip(sources, columns)) + ".", ""]
    out += [f"- {cell(key)} {sid}" for key, sid in unchecked] or ["None."]
    out += ["", "### Stale verdicts (#371)", "",
            f"- No drill cell, or no candidate sentence: {len(stale['readings']):,}",
            f"- The sentence's text or a translation changed since the check, never used: {len(stale['hashes']):,}"]
    out += [f"  - {cell(r['cell'])} {r['sentence_id']} {r['verdict']} ({r['texts_sha256']})" for r in stale["hashes"]]
    out += [f"- A data row's own check, given on other texts (the row edited since), never used: "
            f"{len(stale['own']):,}"]
    out += [f"  - {r.id} {cell(r.cell)} ({r.texts_sha256})" for r in stale["own"]]

    out += ["", "### List words in the generated rows", "",
            "The share of each generated row's words that are words of the Greek lists up to its verb's level "
            "(the term or a form of it) or function words, always allowed (0134, Words: the forms of an article, "
            "pronoun, determiner, preposition, conjunction, particle or numeral, and of έχω and είμαι) or forms of "
            "the row's own verb, whose level the cell carries; names and other words above the level count as "
            "outside.", ""]
    buckets = (("100%", 1.0, 1.01), ("90 to 99%", 0.9, 1.0), ("75 to 89%", 0.75, 0.9), ("50 to 74%", 0.5, 0.75),
               ("below 50%", -1, 0.5))
    out += ["| Share | Rows |", "|---|---|"] + [f"| {name} | {sum(1 for s, _, _ in share if low <= s < high):,} |"
                                                for name, low, high in buckets]
    out += ["", "The 20 lowest, with the words outside the lists:", ""]
    out += [f"- {r.id} {r.cell} ({s:.0%}): {r.text} — {', '.join(words)}" for s, r, words in share[:20]]

    out += ["", f"### Skipped cells ({len(skipped):,})", "",
            "The cells with no natural sentence (kyukhin 2026-11-22), with the second pass's reason, those in the "
            f"coverage gate's scope ({SCOPE_NAMES[SCOPE]}) first. A cell whose own corpus row ships says so; its "
            "line is the fallback should the row drop (#385).", "", "| Cell | In scope | Reason |", "|---|---|---|"]
    by_key = {c.key: c for c in cells}
    for key in sorted(skipped, key=lambda k: (not (k in by_key and in_scope(by_key[k])), k)):
        shows = f" (shows its corpus row {rows[key][0]})" if key in rows else ""
        out.append(f"| {cell(key)} | {'yes' if key in by_key and in_scope(by_key[key]) else 'no'} | "
                   f"{cell(skipped[key] + shows)} |")
    return out


def report(folder: str, pins: dict, results: list[Result], english: EnglishWords,
           ambiguity: list[tuple], skipped: collections.Counter, verbs: dict, hashes: dict, sizes: dict,
           gates: list, list_rule: list[str], drill: list[str] = (), word_hashes: dict | None = None,
           drill_hashes: dict | None = None) -> str:
    folder_pin = pins[folder]
    out = ["# Example sentences: QA report", "",
           "Written by `Scripts/build_examples.py` on every build of the examples step "
           "([0134-example-sentences.md](../../docs/specs/0134-example-sentences.md)). Do not edit by hand.", "",
           "## Snapshot", "",
           f"Tatoeba export of {folder_pin['export_date']} ({folder_pin['export_url']}), projected into "
           f"`{folder}/`.", "", "| Subset file | Rows | sha256 |", "|---|---|---|"]
    for lang in SUBSETS:
        for part in PARTS:
            key = f"{folder}/{lang}-{part}.tsv.xz"
            out.append(f"| `{key}` | {pins[key].get('rows', 0):,} | `{pins[key]['sha256']}` |")
    out += ["", "| Export file | Bytes | sha256 |", "|---|---|---|"]
    out += [f"| `{f['path']}` | {f['bytes']:,} | `{f['sha256']}` |" for f in folder_pin["export_files"]]
    out += ["", f"Verb ranking (QA only): `{FREQUENCY_KEY}`, sha256 `{pins[FREQUENCY_KEY]['sha256']}`."]

    out += ["", "## Gates", "", "| Gate | Measured | Needed | Result |", "|---|---|---|---|"]
    out += [f"| {name} | {measured} | {needed} | {'pass' if ok else 'FAIL'} |" for name, measured, needed, ok in gates]

    for r in results:
        name = {"ell": "Greek", "eng": "English"}[r.lang]
        shown = rows_of([r])
        with_three = sum(1 for chosen in r.words.values() if len(chosen) >= 3)
        out += ["", f"## {name}", "", "### Filters", "", "| Step | Sentences dropped | Left |", "|---|---|---|"]
        left = r.total
        out.append(f"| {name} sentences in the subset | | {left:,} |")
        for step, count in r.drops.items():
            left -= count
            out.append(f"| {step} | {count:,} | {left:,} |")
        out += ["", "### Translations", "", "| Language | Candidates with one | Stored | Usable links | "
                "No author | Blocking tag |", "|---|---|---|---|---|---|"]
        for tl in TRANSLATIONS[r.lang]:
            with_tl = sum(1 for c in r.candidates.values() if tl in c.translations)
            stored = sum(1 for t in shown.translations if t[1] == tl)
            d = r.translation_drops.get(tl, collections.Counter())
            out.append(f"| {tl} | {with_tl:,} | {stored:,} | {d['usable']:,} | {d['no author']:,} | "
                       f"{d['blocking tag']:,} |")
        out += ["", "### Keys", "",
                f"- Candidates: {len(r.candidates):,}, of them by a native author: "
                f"{sum(1 for c in r.candidates.values() if c.native):,}",
                f"- Keys with an example: {len(r.words):,}; with 3 or more: {with_three:,}",
                f"- Stored: {len(shown.sentences):,} sentences, {len(shown.words):,} word rows, "
                f"{len(shown.translations):,} translations"]
        if r.lang == "ell":
            out += [f"- Top-{TOP_VERBS} verbs with 3 or more: {verbs['three']} of {len(verbs['verbs'])} "
                    f"({percent(verbs['three'], len(verbs['verbs']))}); with one or more: {verbs['one']}",
                    f"- Top-{TOP_VERBS} nouns with 3 or more (reported, not gated): {verbs['nouns_three']} of "
                    f"{len(verbs['nouns'])}",
                    f"- Greek headwords with an example: {verbs['headwords']:,} of {verbs['headwords_total']:,}",
                    "", f"**Top-{TOP_VERBS} verbs with fewer than 3 examples ({len(verbs['missing'])})**, "
                    "with their count:", "",
                    ", ".join(f"{w} ({n})" for w, n in verbs["missing"]) or "None."]
            out += list_rule
        else:
            words = english.list_words
            with_one = sum(1 for w in words if w in r.words)
            three = sum(1 for w in words if len(r.words.get(w, ())) >= 3)
            out += [f"- English list words (one-word terms of `{ENGLISH_LISTS}`): {len(words):,}; with an example: "
                    f"{with_one:,}; with 3 or more (reported, not gated): {three:,}"]
            out += ["", "### Morphy ambiguity (CodeRabbit, #177)", "",
                    "Morphy's suffix rules over-generate (0136; evening → even, singing → singe). A token keys no "
                    "inferred lemma when two of its lemmas are list words (lives: live, life), nor a lemma a "
                    "suffix rule guessed when the token is itself a list word (evening, building); WordNet's "
                    "exception lists stay trusted (was → be, saw → see). The rules compared on the same "
                    "candidates:", "",
                    "| Rule | List words with an example | With 3 or more | Tokens whose inferred keys are skipped "
                    "| List words whose examples differ from no rule |", "|---|---|---|---|---|"]
            out += [f"| {rule} | {one:,} | {three_:,} | {tokens_:,} | {changed:,} |"
                    for rule, one, three_, tokens_, changed in ambiguity]
            out += ["", f"The {min(60, len(skipped))} most frequent of the {len(skipped):,} tokens whose inferred keys "
                    "are skipped, with their morphy lemmas and occurrences in the candidates: "
                    + ", ".join(f"{w} ({', '.join(english.bases(w))}; {n:,})" for w, n in skipped.most_common(60))
                    + "."]

        out += ["", "### Samples", ""]
        for word in SAMPLES[r.lang]:
            chosen = r.words.get(word, [])
            langs, ui = (("eng", "rus"), "rus") if r.lang == "ell" else (("spa", "ell"), "spa")
            out += [f"**{word}** ({len(chosen)}, of {r.occurrences.get(word, 0):,} candidate sentences):", "",
                    f"| Sentence | {' | '.join(langs)} | Byline ({ui} UI) |", "|---" * (len(langs) + 2) + "|"]
            for sid, start, length, _ in chosen:
                c = r.candidates[sid]
                trs = [cell(c.translations[tl][1]) if tl in c.translations else "—" for tl in langs]
                shown_tl = c.translations.get(ui) or (c.translations.get("eng") if r.lang == "ell" else None)
                out.append(f"| {highlighted(c.text, start, length)} | {' | '.join(trs)} | "
                           f"{cell(byline(c.author, shown_tl[2] if shown_tl else None))} |")
            out.append("")

    out += list(drill)
    out += (["", "## Blocking tags hit"] if drill else ["## Blocking tags hit"]) + [
        "", "Sentences and translations each tag kept out."]
    for r in results:
        out += ["", f"- {'Greek' if r.lang == 'ell' else 'English'}: " + ", ".join(
            f"{tag} ({n:,})" for tag, n in sorted(r.tag_hits.items(), key=lambda x: (-x[1], x[0])))]

    out += ["", "## Size and table hashes", "", "| Table | Rows | sha256 of the rows in key order |", "|---|---|---|"]
    out += [f"| `{t}` | {hashes[t][0]:,} | `{hashes[t][1]}` |" for t in TABLES]
    if word_hashes:
        out += ["", "The word examples alone (the rows of word keys, their sentences and translations), which the "
                "drill rows leave unchanged (#364):", "", "| Table | Rows | sha256 of the rows in key order |",
                "|---|---|---|"]
        out += [f"| `{t}` | {word_hashes[t][0]:,} | `{word_hashes[t][1]}` |" for t in TABLES]
    if drill_hashes:
        out += ["", "The drill rows (the cell rows, and the sentences and translations only they use, #364):", "",
                "| Table | Rows | sha256 of the rows in key order |", "|---|---|---|"]
        out += [f"| `{t}` | {drill_hashes[t][0]:,} | `{drill_hashes[t][1]}` |" for t in TABLES]
    out += ["", "| Rows | " + " | ".join(f"`{t}`" for t in TABLES) + " | Installed | Download (xz) |",
            "|---" * (len(TABLES) + 3) + "|"]
    for label, (table_sizes, xz) in sizes.items():
        out.append(f"| {label} | " + " | ".join(f"{table_sizes[t]:,}" for t in TABLES)
                   + f" | {sum(table_sizes.values()):,} | {xz:,} |")
    out += ["", "Bytes from `dbstat` on a VACUUMed file of the rows alone; the xz size is of that file "
            "(preset 6), an estimate of each pack's growth."]
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# The step
# ---------------------------------------------------------------------------

def run(writer: sqlite3.Connection, reader: sqlite3.Connection, cache_dir: Path,
        report_path: Path = REPORT) -> Rows:
    """Build the example tables into `writer`, reading forms, morphy, list
    words and headwords from `reader`; write the report; raise if a gate
    fails."""
    folder = subset_folder()
    pins = inputs.pins()
    paths = subset_paths(folder)

    greek, english = GreekWords(reader), EnglishWords(reader)
    if not greek.lemmas_of or not greek.headwords:
        raise RuntimeError("No Greek forms or headwords: the examples step runs after build_forms")
    if not english.list_words or not english.lemma_masks:
        raise RuntimeError("No English list words or morphy lemmas: the step runs after build_morphy and "
                           "build_wordlists")
    subsets = {lang: read_subset(paths[lang]) for lang in SUBSETS}
    print(f"  subset {folder}: " + ", ".join(f"{lang} {len(s.sentences):,} sentences" for lang, s in subsets.items()))
    results = [build_language("ell", subsets["ell"], greek.keys, greek.own),
               build_language("eng", subsets["eng"], english.keys)]
    list_rule = list_rule_section(results[0], greek, index(results[0], GreekWords(reader, list_rule=False).keys),
                                  index(results[0], greek.keys)[1])
    variants = {"guess": (english, results[1].words)}
    for rule in EnglishWords.AMBIGUITY_RULES[1:]:
        variant = EnglishWords(reader, rule)
        variants[rule] = (variant, index(results[1], variant.keys)[1])
    plain = variants["none"][1]
    labels = {"guess": "no inferred key when two are list words, nor a suffix guess for a list word (built)",
              "two-lemmas": "no inferred key when two or more are list words",
              "only-key": "an inferred key only as the token's one list-word key, the token included",
              "none": "no rule"}
    ambiguity = [(labels[rule], sum(1 for w in english.list_words if w in words),
                  sum(1 for w in english.list_words if len(words.get(w, ())) >= 3), len(variant.ambiguous),
                  sum(1 for w in english.list_words if [x[0] for x in words.get(w, [])] != [x[0] for x in plain.get(w, [])]))
                 for rule, (variant, words) in variants.items()]
    skipped = collections.Counter(tok.lower() for c in results[1].candidates.values() for tok, _, _ in c.tokens
                                  if tok.lower() in english.ambiguous)

    # #364: one sentence per drill cell, from the same Greek candidates;
    # #365: and from the data files' Wiktionary and generated rows;
    # #385: and from the corpus rows of cleared documents.
    pool, cells = drill_cells.drill_cells(reader)
    infinitives = aorist_infinitives(reader)
    kaikki, dump_date = kaikki_subset()
    data = read_drill_data(DRILL_DATA, wiktionary_examples(kaikki), dump_date)
    by_key = {c.key: c for c in cells}
    extra = data_candidates(data, by_key)
    corpus = corpus_candidates(data, by_key)
    texts = {sid: shipped_texts(c) for sid, c in {**results[0].candidates, **extra, **corpus}.items()}
    data_problems, stale = data_failures(data, by_key, infinitives, texts)
    data_problems += corpus_failures(data, by_key, infinitives)
    verdicts = data_verdicts(data, texts)
    own_cells = {**{r.id: r.cell for r in data.rows}, **{r.id: r.cell for r in data.corpus}}
    drill = build_drill(pool, cells, results[0].candidates, infinitives, verdicts, {**extra, **corpus},
                        own_cells, data.skipped)
    # #385: the choice without the corpus rows, for the report's "cells that change" and gate 9: a cell of a
    # corpus row keeps a sentence or a skip line whichever corpus rows drop (kyukhin 2026-11-28).
    without = build_drill(pool, cells, results[0].candidates, infinitives, verdicts, extra, own_cells,
                          data.skipped) if corpus else None
    if without is not None:
        data_problems += [f"{CORPUS_FILE} cell {key}: no fallback: without its corpus row it has no sentence and no "
                          f"line in {SKIPPED_FILE} (gate 9)" for key in corpus_without_fallback(drill, without,
                                                                                                data.skipped)]
    missing = open_cells(drill, data.skipped)
    print(f"  drill: {len(pool):,} verbs, {len(cells):,} cells, {len(drill.rows):,} with a sentence; data rows "
          f"{len(data.rows):,}, corpus rows {len(data.corpus):,} ({len(corpus):,} candidates), skipped cells "
          f"{len(data.skipped):,}, open in the gate's scope {len(missing):,}")

    word_rows = rows_of(results)
    rows = rows_of(results, drill)
    word_part, drill_part = split_rows(rows)
    word_hashes = rows_hashes(word_part)
    write_rows(writer, rows, f"export {pins[folder]['export_date']}", data.credits() + corpus_credit(corpus, rows))
    hashes = table_hashes(writer)
    try:
        sizes = {"all": shipped_size(rows), "Greek (ell pack)": shipped_size(rows, "ell"),
                 "English (eng-lists pack)": shipped_size(rows, "eng"),
                 "Word examples (all files)": shipped_size(word_part),
                 "Drill rows and the sentences only they use": shipped_size(drill_part)}
    except sqlite3.OperationalError as error:
        raise RuntimeError(f"The size gate needs SQLite with dbstat: {error}") from error

    frequency = load_frequency(inputs.fetch(FREQUENCY_KEY, cache_dir))
    top_verbs = top_lemmas(reader, frequency, "verb")
    top_nouns = top_lemmas(reader, frequency, "noun")
    counts = {key: len(chosen) for key, chosen in results[0].words.items()}
    three, verbs_pass = verb_gate(top_verbs, counts)
    verbs = {
        "verbs": top_verbs, "nouns": top_nouns,
        "three": three,
        "one": sum(1 for w in top_verbs if counts.get(w, 0) >= 1),
        "nouns_three": sum(1 for w in top_nouns if counts.get(w, 0) >= 3),
        "missing": [(w, counts.get(w, 0)) for w in top_verbs if counts.get(w, 0) < 3],
        "headwords": sum(1 for h in greek.headwords if word_key(h) in counts),
        "headwords_total": len(greek.headwords),
    }

    failures = output_failures(rows, results, subsets, {"ell": greek.keys, "eng": english.keys})
    failures.update(drill_failures(rows, cells, infinitives,
                                   collections.ChainMap(*(s.sentences for s in subsets.values()))))
    total = sum(sizes["Word examples (all files)"][0].values())
    listed = skipped_with_rows(rows, data.skipped, {r.id: r.cell for r in data.corpus})
    unchecked = unchecked_pairs(rows, verdicts)
    drill_total = sum(sizes["Drill rows and the sentences only they use"][0].values())
    unchanged = rows_hashes(word_rows) == word_hashes
    english_three = sum(1 for w in english.list_words if len(results[1].words.get(w, ())) >= 3)
    gates = [
        (f"Top-{TOP_VERBS} Greek verbs with 3+ examples", f"{verbs['three']} of {len(top_verbs)} "
         f"({percent(verbs['three'], len(top_verbs))})", f"≥ {GATE_VERBS:.0%} of {TOP_VERBS}",
         verbs_pass),
        ("Every Greek sentence has an English translation, every English one a rus, spa, arb or ell one; "
         "every text an author", f"{len(failures['complete'])} problems", "0", not failures["complete"]),
        ("English list words with 3+ examples (reported, not gated)",
         f"{english_three:,} of {len(english.list_words):,}", "—", True),
        ("Every span lies inside its text, and its token gives its key", f"{len(failures['spans'])} problems",
         "0", not failures["spans"]),
        ("No stored sentence or translation has a blocking tag",
         f"{len(failures['clean'])}", "0", not failures["clean"]),
        ("Word example tables of all files (the drill rows not counted, #364)", f"{total / 1e6:.2f} MB",
         f"≤ {SIZE_BUDGET / 1e6:.0f} MB", total <= SIZE_BUDGET),
        ("Every translation and word row points at a stored sentence", f"{len(failures['references'])} problems",
         "0", not failures["references"]),
        ("Drill: every cell row's span holds its cell's form by the match rule",
         f"{len(failures['cell spans'])} problems", "0", not failures["cell spans"]),
        ("Drill: every cell key is a drill cell, one row each (`ord` 1); every Tatoeba id below 10^9",
         f"{len(failures['cell keys'])} problems", "0", not failures["cell keys"]),
        ("Drill: the word examples do not change (the hash of the word rows)",
         "equal" if unchanged else "changed", "equal", unchanged),
        ("Drill rows and the sentences only they use, installed", f"{drill_total / 1e6:.2f} MB",
         f"≤ {DRILL_BUDGET / 1e6:.1f} MB", drill_total <= DRILL_BUDGET),
        (f"Drill: every cell of the gate's scope ({SCOPE_NAMES[SCOPE]}) has a sentence or is listed as "
         "skipped, and no skipped cell has one but its own corpus row (#365, #385)",
         f"{len(missing)} open, {len(listed)} skipped with a sentence",
         "0, 0", not missing and not listed),
        ("Drill: the data files pass the form gate (0134, Checks 1; #365) and the corpus gate (#385, Checks 1 to 9)",
         f"{len(data_problems)} problems", "0",
         not data_problems),
        ("Drill: every cell row's (cell, sentence) is its data row's own cell or `ok` in the readings file, each "
         "with the hash of the Greek, English and Russian the pair ships with (#371)",
         f"{len(unchecked)} unchecked, {len(stale['hashes']) + len(stale['own'])} stale verdicts",
         "0 unchecked" if PAIR_GATE else "0 unchecked (listed, not gated until the pair checks land)",
         pair_gate_passes(unchecked)),
    ]
    failures["data files"] = data_problems
    failures["open cells"] = missing
    failures["skipped cells with a sentence"] = listed
    failures["unchecked pairs"] = [f"{key} {sid}" for key, sid in unchecked]
    levels: dict[str, int] = {}
    for term, level in reader.execute("SELECT term, level_ord FROM wordlist_item WHERE series = ?", (GREEK_LISTS,)):
        levels[nfc(term)] = min(level, levels.get(nfc(term), level))
    share = list_word_share(data, by_key, greek, levels)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report(folder, pins, results, english, ambiguity, skipped, verbs, hashes, sizes, gates,
                                  list_rule, drill_section(drill, results[0], data, stale, missing, share, unchecked,
                                                           corpus_status(data, by_key), without),
                                  word_hashes, rows_hashes(drill_part)),
                           encoding="utf-8")

    print("  " + ", ".join(f"{t} {hashes[t][0]:,}" for t in TABLES) + f"; {total:,} bytes")
    for name, measured, needed, ok in gates:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {measured} (needs {needed})")
    for gate, problems in failures.items():
        for problem in problems[:10]:
            print(f"    {gate}: {problem}")
    print(f"  QA report: {report_path}")
    failed = [name for name, _, _, ok in gates if not ok]
    if failed:
        raise RuntimeError("Examples gates failed: " + "; ".join(failed) + f" (see {report_path})")
    return rows


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """The `STEPS` entry point of build_dictionaries.py: runs after the forms,
    morphy and word list steps, whose tables it reads."""
    run(conn, conn, Path(cache_dir))


# ---------------------------------------------------------------------------
# Standalone and self-check
# ---------------------------------------------------------------------------

def read_only(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"file:{urllib.parse.quote(str(path.resolve()))}?mode=ro", uri=True)


def new_database(path: str) -> sqlite3.Connection:
    """A file with the dictionary file's core schema plus `SCHEMA`."""
    from build_dictionaries import SCHEMA as CORE_SCHEMA
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA page_size = 4096")
    conn.execute("PRAGMA journal_mode = DELETE")
    conn.executescript(CORE_SCHEMA)
    conn.executescript(SCHEMA)
    return conn


def standalone(output: Path, source: Path, cache_dir: Path) -> int:
    output.unlink(missing_ok=True)
    conn = new_database(str(output))
    try:
        run(conn, read_only(source), cache_dir)
        conn.execute("VACUUM")
    finally:
        conn.close()
    print(f"  wrote {output} ({output.stat().st_size:,} bytes)")
    return 0


# The tags of a fixture `verb` line's slot and of each person (Wiktextract's).
FIXTURE_SLOTS = {"present": "present", "imperfect": "imperfect", "aorist": "past perfective",
                 "dependent": "dependent", "imperativeContinuous": "imperative imperfective",
                 "imperativeSimple": "imperative perfective", "infinitive": "infinitive-aorist"}
FIXTURE_PERSONS = ("first-person singular", "second-person singular", "third-person singular",
                   "first-person plural", "second-person plural", "third-person plural")


def fixture_reader(folder: Path) -> sqlite3.Connection:
    """An in-memory file with the tables the step reads, filled from the
    fixture's `lexicon.tsv`: `lemma` (word, pos, untagged cells), `verb`
    (a verb, a slot of `FIXTURE_SLOTS` and its forms per person, εγώ to
    αυτοί, alternatives split by `/`; an infinitive has one form), `link`
    (page, lemma), `headword`, `exception` (form, pos, base), `morphy`
    (word, pos_mask) and `list` (term; the series when not the English
    lists'; the level of a Greek list, for the drill) lines."""
    from build_dictionaries import SCHEMA as CORE_SCHEMA
    import build_forms
    import build_morphy
    import build_wordlists
    conn = sqlite3.connect(":memory:")
    conn.executescript(CORE_SCHEMA)
    conn.executescript(build_forms.SCHEMA)
    conn.executescript(build_morphy.SCHEMA)
    conn.executescript(build_wordlists.SCHEMA)
    conn.execute("INSERT INTO tagset(id, tags) VALUES (1, '')")
    for level, name in enumerate(("a1", "a2", "b1"), 1):
        conn.execute("INSERT INTO wordlist(id, lang, series, level, level_ord, word_count, data_source, "
                     "translation_lang) VALUES (?, 'ell', ?, ?, ?, 0, 'fixture', 'eng')",
                     (f"{GREEK_LISTS}-{name}", GREEK_LISTS, name.upper(), level))
    lemma_ids, cells_of, seq = {}, collections.Counter(), 0

    def lemma(word: str, pos: str) -> int:
        if (word, pos) not in lemma_ids:
            lemma_ids[(word, pos)] = len(lemma_ids) + 1
            conn.execute("INSERT INTO lemma(id, lang, word, word_normalized, pos) VALUES (?, 'ell', ?, ?, ?)",
                         (lemma_ids[(word, pos)], word, normalize_greek(word), pos))
        return lemma_ids[(word, pos)]

    def cell(lemma_id: int, form: str, tags: str) -> None:
        tagset = conn.execute("SELECT id FROM tagset WHERE tags = ?", (tags,)).fetchone()
        if tagset is None:
            tagset = (conn.execute("INSERT INTO tagset(tags) VALUES (?)", (tags,)).lastrowid,)
        cells_of[lemma_id] += 1
        conn.execute("INSERT INTO paradigm(lemma_id, ord, form, tagset_id) VALUES (?, ?, ?, ?)",
                     (lemma_id, cells_of[lemma_id], form, tagset[0]))

    for fields in read_lines(folder / "lexicon.tsv"):
        kind, rest = fields[0], fields[1:]
        if kind == "lemma":
            word, pos, cells = rest
            i = lemma(word, pos)
            for form in cells.split(","):
                cell(i, form, "")
        elif kind == "verb":
            word, slot, forms = rest
            i = lemma(word, "verb")
            if slot == "infinitive":
                cell(i, forms, FIXTURE_SLOTS[slot])
                continue
            for person, alternatives in zip(FIXTURE_PERSONS, forms.split(",")):
                for form in filter(None, alternatives.split("/")):
                    cell(i, form, " ".join(sorted(f"{FIXTURE_SLOTS[slot]} {person}".split())))
        elif kind == "link":
            page, word = rest
            i = next(i for (w, _), i in lemma_ids.items() if w == word)
            conn.execute("INSERT INTO form_link(form, lemma_id) VALUES (?, ?)", (page, i))
        elif kind == "headword":
            conn.execute("INSERT INTO entries(word, definition, source) VALUES (?, '', 'freedict-ell-eng')", rest)
        elif kind == "exception":
            conn.execute("INSERT INTO morphy_exception(form, pos, base) VALUES (?, ?, ?)", rest)
        elif kind == "morphy":
            conn.execute("INSERT INTO morphy_lemma(word, pos_mask) VALUES (?, ?)", (rest[0], int(rest[1])))
        elif kind == "list":
            seq += 1
            conn.execute("INSERT INTO wordlist_item(series, term, seq, sort_key, level_ord) VALUES (?, ?, ?, ?, ?)",
                         (rest[1] if len(rest) > 1 else ENGLISH_LISTS, rest[0], seq, rest[0],
                          int(rest[2]) if len(rest) > 2 else 0))
        else:
            raise RuntimeError(f"lexicon.tsv: unknown line kind {kind!r}")
    return conn


def self_check() -> int:
    """Build the fixture twice, compare the table hashes, check the cases."""
    reader = fixture_reader(FIXTURE)
    greek, english = GreekWords(reader), EnglishWords(reader)
    subsets = {lang: read_subset({part: FIXTURE / f"{lang}-{part}.tsv" for part in PARTS}) for lang in SUBSETS}
    pool, cells = drill_cells.drill_cells(reader)
    infinitives = aorist_infinitives(reader)
    runs = []
    for _ in range(2):
        results = [build_language("ell", subsets["ell"], greek.keys, greek.own),
                   build_language("eng", subsets["eng"], english.keys)]
        drill = build_drill(pool, cells, results[0].candidates, infinitives)
        rows = rows_of(results, drill)
        conn = new_database(":memory:")
        write_rows(conn, rows, "self-check")
        runs.append((results, drill, rows, conn, table_hashes(conn)))
    results, drill, rows, conn, hashes = runs[0]
    assert hashes == runs[1][4], "two builds of the fixture differ"
    for table, (count, digest) in hashes.items():
        print(f"  {table:<20} {count:>3} rows  {digest}")

    stored = {s[0] for s in rows.sentences}

    def forms_of(lang: str, word: str) -> list[str]:
        texts = {s[0]: s[2] for s in rows.sentences}
        return [texts[sid][start:start + length].lower()
                for l, w, _, sid, start, length in rows.words if l == lang and w == word]

    def translation(sid: int, lang: str) -> int | None:
        return next((t[2] for t in rows.translations if t[0] == sid and t[1] == lang), None)

    ell, eng = results
    keys = {"ell": greek.keys, "eng": english.keys}
    # #339: the keys without the list-word rule, on the same candidates.
    unruled = index(ell, GreekWords(reader, list_rule=False).keys)[1]
    failures = output_failures(rows, results, subsets, keys)
    # The output gates on rows they must refuse: the tagged sentence stored
    # as an orphan without English, a translation of no stored sentence, a
    # span that is no token, a token that does not give its key.
    caught = output_failures(Rows(rows.sentences + [(101, "ell", "Το σπίτι είναι μεγάλο.", "")],
                                  rows.translations + [(998, "rus", 997, "Привет.", "olga")],
                                  rows.words + [("ell", "γράφω", 6, 107, 0, 3), ("ell", "πότε", 2, 107, 0, 6)]),
                             results, subsets, keys)
    # (native, translations, words, id) of six candidates, for step 5's order.
    ranks = [(False, 4, 5, 1), (True, 1, 11, 2), (True, 1, 2, 3), (True, 2, 11, 4), (True, 1, 10, 5), (True, 1, 3, 6)]

    def order(lang: str) -> list[int]:
        return [r[-1] for r in sorted(rank(lang, *case) for case in ranks)]

    def chosen(occurrences: list[tuple[int, str]], own: frozenset[str] = frozenset(),
               own_first: bool = False) -> list[int]:
        """The ids `choose` keeps of (rank, form) occurrences, given in
        reverse rank order; the id is 100 + rank."""
        return [o[1] for o in choose([((r,), 100 + r, 0, 1, f) for r, f in reversed(occurrences)],
                                     own=own, own_first=own_first)]

    verbs = [f"v{i}" for i in range(TOP_VERBS)]
    passing = {**{w: 3 for w in verbs[:424]}, verbs[424]: 5, **{w: 2 for w in verbs[425:]}}
    checks = [
        ("a tagged sentence is dropped", 101 not in stored and ell.drops.get("blocking tag") == 1),
        ("an orphan is dropped", 102 not in stored and ell.drops.get("no author") == 1),
        ("a 16-word sentence is dropped", 103 not in stored and ell.drops.get("over 15 words") == 1),
        ("a 15-word sentence stays", 118 in ell.candidates),
        ("an orphan translation is never used", "rus" not in ell.candidates[110].translations
         and ell.translation_drops["rus"]["no author"] == 1),
        ("a translation with a content tag is never used (vulgar)", "rus" not in ell.candidates[109].translations
         and ell.translation_drops["rus"]["blocking tag"] == 1),
        ("direct translations only: the Spanish of πάω σπίτι's English is not its own",
         "spa" not in ell.candidates[117].translations),
        ("a Greek sentence without English is dropped", 106 not in stored
         and ell.drops.get("no usable English translation") == 1),
        ("γράφω: five of six forms, the new forms first",
         forms_of("ell", "γράφω") == ["έγραψε", "έγραψα", "γράψω", "γράψε", "γράφω"]),
        ("μέρα keys its headword and its lemma", forms_of("ell", "μέρα") == ["μέρα"]
         and forms_of("ell", "ημέρα") == ["μέρα"]),
        ("a link page keys its lemma (πάω → πηγαίνω)", forms_of("ell", "πηγαίνω") == ["πάω"]),
        ("a harmless maintenance tag does not block (@change audio)", 107 in stored),
        ("πότε and ποτέ stay apart (exact, not folded)", forms_of("ell", "πότε") == ["πότε"]
         and forms_of("ell", "ποτέ") == ["ποτέ"]),
        ("#339: a Greek list word keys itself, not its lemma: Η keys η, and ο keeps only το",
         forms_of("ell", "η") == ["η"] and forms_of("ell", "ο") == ["το"]
         and sorted(c[3] for c in unruled["ο"]) == ["η", "το"]),
        ("#339: a list word that is a verb's form keys the verb too (πάω → πηγαίνω, Γράφω → γράφω)",
         forms_of("ell", "πάω") == ["πάω"] and "γράφω" in forms_of("ell", "γράφω")),
        ("#339: a list word's optional part: στην keys στη(ν)", forms_of("ell", "στη(ν)") == ["στην"]
         and term_spellings("στη(ν)") == ["στη", "στην"] and term_spellings("(ένα) σωρό") == []),
        ("a native speaker's Russian translation wins over a lower id", translation(116, "rus") == 318),
        ("Arabic is stored as arb, Spanish as spa", translation(116, "arb") == 417 and translation(116, "spa") == 418),
        ("went, going and gone key go, one sentence per form first",
         forms_of("eng", "go")[:4] == ["go", "went", "going", "gone"]),
        ("an English sentence without a translation is dropped", 506 not in stored
         and eng.drops.get("no usable translation") == 1),
        ("an English word not in the lists has no key", not forms_of("eng", "walk") and not forms_of("eng", "walked")),
        ("hopes keys hope, not hop (morphy's first rule whose base is a lemma)",
         forms_of("eng", "hope") == ["hopes"] and not forms_of("eng", "hop")),
        ("lives keys neither live nor life; evening keys evening, not its suffix guess even",
         "lives" not in forms_of("eng", "live") + forms_of("eng", "life")
         and forms_of("eng", "evening") == ["evening"] and not forms_of("eng", "even")),
        ("was, a list word, keys itself and be (WordNet's exception list)",
         forms_of("eng", "was") == ["was"] and forms_of("eng", "be") == ["was"]),
        ("the Greek translation of an English sentence is stored as ell", translation(501, "ell") == 601),
        ("every output gate holds", not any(failures.values())),
        ("the output gates catch bad rows", {gate: len(problems) for gate, problems in caught.items()}
         == {"complete": 2, "spans": 2, "clean": 1, "references": 1}),
        ("Greek ranks a native author first, then more translations, then 3 to 10 words, then the id",
         order("ell") == [4, 5, 6, 2, 3, 1]),
        ("English ranks more translations first, then a native author", order("eng") == [1, 4, 5, 6, 2, 3]),
        ("choice: one sentence per new form first, in rank order, up to 5",
         chosen([(1, "x"), (2, "x"), (3, "x"), (4, "y"), (5, "z"), (6, "w"), (7, "v"), (8, "u")])
         == [101, 104, 105, 106, 107]),
        ("#339 choice: a non-verb list word's own forms come first, other forms fill up",
         chosen([(1, "x"), (2, "y"), (3, "u"), (4, "z"), (5, "u"), (6, "w"), (7, "u")], frozenset({"u"}), True)
         == [103, 105, 107, 101, 102]
         and chosen([(i, "u") for i in range(1, 8)], frozenset({"u"}), True) == [101, 102, 103, 104, 105]
         and chosen([(1, "x"), (2, "y")], frozenset({"u"}), True) == [101, 102]),
        ("#339 choice: a verb's own form, left out by the per-form pass, leads; the last pick drops",
         chosen([(1, "x"), (2, "y"), (3, "z"), (4, "w"), (5, "v"), (6, "u"), (7, "u")], frozenset({"u"}))
         == [106, 101, 102, 103, 104]
         and chosen([(1, "x"), (2, "y"), (3, "z"), (4, "w"), (5, "v"), (6, "u")], frozenset({"v"}))
         == [101, 102, 103, 104, 105]),
        ("choice: then the rest in rank order, each sentence once",
         chosen([(1, "x"), (2, "x"), (3, "x"), (4, "x"), (5, "x"), (6, "x"), (7, "y")]) == [101, 107, 102, 103, 104]
         and chosen([(1, "x"), (2, "x")]) == [101, 102]),
        ("the verb gate: 85% of all 500 verbs with 3+", verb_gate(verbs, passing) == (425, True)
         and verb_gate(verbs, {**passing, verbs[424]: 2}) == (424, False)
         and verb_gate(verbs[:-1], passing)[1] is False),
        ("the data_source row", conn.execute("SELECT id, kind, license, url FROM data_source").fetchall()
         == [("tatoeba", "example_sentences", "CC BY 2.0 FR", "https://tatoeba.org")]),
    ]

    # #364: the drill's cells and their sentences (0134, Test plan). The
    # fixture's drill sentences (1001…) are by a non-native author, so they
    # rank after the word examples above and leave them as they were.
    texts = {s[0]: s[2] for s in rows.sentences}
    asked = {c.key for c in cells}

    def shown(key: str) -> str | None:
        """The highlighted text of a cell's row."""
        if key not in drill.rows:
            return None
        sid, start, length, _ = drill.rows[key]
        return texts[sid][start:start + length]

    def sentence(key: str, built: Drill = drill) -> int | None:
        return built.rows[key][0] if key in built.rows else None

    g, aorist, imperative = "γράφω|", "μιλάω|aorist.active|3sg", "μιλάω|imperativeSimple.active|2sg"
    checked = build_drill(pool, cells, results[0].candidates, infinitives, {(aorist, 1014): "ok"})
    drill_failed = drill_failures(rows, cells, infinitives, set(subsets["ell"].sentences))
    drill_caught = drill_failures(
        Rows(rows.sentences + [(1_000_000_005, "ell", "Γράφω.", "zeus")], rows.translations,
             rows.words + [("ell", g + "aorist.active|2sg", 1, 1013, 0, 4),
                           ("ell", g + "present.active|1sg", 1, 112, 0, 5),
                           ("ell", g + "aorist.active|3pl", 2, 1013, 0, 4)]),
        cells, infinitives, set(subsets["ell"].sentences) | {1_000_000_005})
    checks += [
        ("drill: the cells are the drill's, never the cited present εγώ",
         g + "present.active|1sg" not in asked and {g + "present.active|2sg", "αγαπάω|present.active|2sg",
                                                    "έχω|future.active|1sg"} <= asked),
        ("drill: θα γράψω is the future; a sentence that is a word example is reused",
         shown(g + "future.active|1sg") == "Θα γράψω" and sentence(g + "future.active|1sg") == 110),
        ("drill: clitics and a capital between θα and the verb, highlighted whole",
         shown(g + "future.active|1pl") == "Θα σου τις γράψουμε"),
        ("drill: μην after να", shown(g + "subjunctiveSimple.active|2sg") == "να μην τους γράψεις"),
        ("drill: a clitic before έχω; θα έχω γράψει is no perfect; an adverb between is no match",
         shown(g + "perfect.active|1sg") == "έχω γράψει" and sentence(g + "perfect.active|1sg") == 1005),
        ("drill: θα έχω γράψει is the future perfect, never έχω's future",
         shown(g + "futurePerfect.active|1sg") == "θα έχω γράψει" and "έχω|future.active|1sg" not in drill.rows),
        ("drill: έχει γράψει is γράφω's perfect, never έχω's present αυτός",
         shown(g + "perfect.active|3sg") == "Έχει γράψει" and sentence("έχω|present.active|3sg") == 1007),
        ("drill: έχει with an infinitive a word or clitics later is the auxiliary (έχει ήδη γράψει); έχει ένα γράμμα is έχω",
         find_form(drill_tokens("Έχει ήδη γράψει ένα γράμμα."), "έχει", infinitives) is None
         and find_form(drill_tokens("Δεν το έχει πια γράψει."), "έχει", infinitives) is None
         and find_form(drill_tokens("Έχει ένα γράμμα."), "έχει", infinitives) == (0, 4)
         and drill.found["έχω|present.active|3sg"] == 2 and sentence("έχω|present.active|3sg") == 1007),
        ("drill: θα έγραφα is no imperfect", g + "imperfect.active|1sg" in asked
         and g + "imperfect.active|1sg" not in drill.rows),
        ("drill: να κάνεις is the subjunctive, both aspects in one sentence, never the present",
         sentence("κάνω|subjunctiveSimple.active|2sg") == 1009 == sentence("κάνω|subjunctiveContinuous.active|2sg")
         and "κάνω|present.active|2sg" in asked and "κάνω|present.active|2sg" not in drill.rows),
        ("drill: an elided clitic glued to its word (μ'αγαπάς)", shown("αγαπάω|present.active|2sg") == "αγαπάς"
         and drill_tokens("Δε μ'αγαπάς;") == [("δε", 0, 2), ("μ", 3, 4), ("αγαπάς", 5, 11)]),
        ("drill: an elided ν' or θ', before a space or glued, is a token of its own (both apostrophes)",
         drill_tokens("Δεν θ' αγαπούσα") == [("δεν", 0, 3), ("θ'", 4, 5), ("αγαπούσα", 7, 15)]
         and drill_tokens("ν’αγαπάς") == [("ν'", 0, 1), ("αγαπάς", 2, 8)]),
        ("drill: an elided ν' or θ' is never the να or θα of a form: no subjunctive, no future (θ' αγαπήσεις)",
         find_form(drill_tokens("Θ' αγαπήσεις ξανά."), "θα αγαπήσεις", infinitives) is None
         and {"αγαπάω|future.active|2sg", "αγαπάω|subjunctiveContinuous.active|2sg"} <= asked
         and "αγαπάω|future.active|2sg" not in drill.rows
         and "αγαπάω|subjunctiveContinuous.active|2sg" not in drill.rows
         and "αγαπάω|subjunctiveContinuous.active|3sg" not in drill.rows),
        ("drill: after an elided ν' or θ' no present or imperfect (ν' αγαπάς, θ' αγαπούσα)",
         sentence("αγαπάω|present.active|2sg") == 1010 and "αγαπάω|present.active|3sg" not in drill.rows
         and "αγαπάω|imperfect.active|1sg" in asked and "αγαπάω|imperfect.active|1sg" not in drill.rows),
        ("drill: no simple tense after a prohibitive μη(ν) or ας, clitics skipped (μη μου μιλάς, ας μιλάνε)",
         {"μιλάω|present.active|2sg", "μιλάω|present.active|3pl"} <= asked
         and "μιλάω|present.active|2sg" not in drill.rows and "μιλάω|present.active|3pl" not in drill.rows
         and find_form(drill_tokens("Δε μου μιλάς."), "μιλάς", infinitives) is not None),
        ("drill: a form without its accent is no match (γραψε)",
         find_form(drill_tokens("Γραψε ένα γράμμα."), "γράψε", infinitives) is None
         and all(row[0] != 1011 for row in drill.rows.values())),
        ("drill: κάνε serves both imperatives (aspect only); the cell's first form wins over κάμε",
         sentence("κάνω|imperativeSimple.active|2sg") == 1013 == sentence("κάνω|imperativeContinuous.active|2sg")
         and drill.found["κάνω|imperativeSimple.active|2sg"] == 2
         and ("κάνω|imperativeSimple.active|2sg", "κάνε") in drill.homographs.aspect),
        ("drill: μίλησε, another reading, takes a sentence only with an ok verdict",
         (aorist, "μίλησε") in drill.homographs.reading
         and (g + "present.active|2pl", "γράφετε") in drill.homographs.reading
         and aorist not in drill.rows and imperative not in drill.rows and drill.waiting.get(aorist) == 1
         and sentence(aorist, checked) == 1014 and imperative not in checked.rows),
        ("drill: real sentences first, Tatoeba before Wiktionary and generated",
         min([(cell_order(1_000_000_001, 0, (0, 0, 0, 1)), 1_000_000_001), (cell_order(7, 1, (1, -1, 1, 7)), 7),
              (cell_order(2_000_000_001, 0, ()), 2_000_000_001)])[1] == 7),
        ("drill: every cell row has ord 1 and its span holds its form; the drill gates hold",
         not any(drill_failed.values()) and all(w[2] == 1 for w in rows.words if is_cell(w[1]))),
        ("drill: the gates catch bad cell rows", {gate: len(problems) for gate, problems in drill_caught.items()}
         == {"cell spans": 1, "cell keys": 3}),
        ("drill: the word examples do not change", rows_hashes(rows_of(results)) == rows_hashes(split_rows(rows)[0])),
    ]

    # #365: the data files on the fixture (`drill-examples/`, rows taken from
    # the generated data and the pinned subset, and `kaikki-examples.jsonl`,
    # entries of the pinned subset): Wiktionary and generated rows after
    # Tatoeba, reading verdicts, skips, stale lines, the form gate, the
    # coverage gate and the two data_source rows.
    pin = wiktionary_examples(FIXTURE / "kaikki-examples.jsonl")
    data = read_drill_data(FIXTURE / "drill-examples", pin, "2026-10-01")
    by_key = {c.key: c for c in cells}
    extra = data_candidates(data, by_key)
    known = {sid: shipped_texts(c) for sid, c in {**results[0].candidates, **extra}.items()}
    data_problems, stale = data_failures(data, by_key, infinitives, known)
    verdicts = data_verdicts(data, known)
    builds = []
    for _ in range(2):
        built = build_drill(pool, cells, results[0].candidates, infinitives, verdicts, extra,
                            {r.id: r.cell for r in data.rows}, data.skipped)
        built_rows = rows_of(results, built)
        built_conn = new_database(":memory:")
        write_rows(built_conn, built_rows, "self-check", data.credits())
        builds.append((built, built_rows, built_conn, table_hashes(built_conn)))
    full, full_rows, full_conn, full_hashes = builds[0]
    assert full_hashes == builds[1][3], "two builds of the fixture with its data rows differ"
    w1, w2, g1, g2, g3, g4, g5, g6 = data.rows
    stored = {s[0]: s for s in full_rows.sentences}
    stored_translations = {(t[0], t[1]): t for t in full_rows.translations}
    missing = open_cells(full, data.skipped, (2, 1))  # 2.0's scope; the gate's own (SCOPE) is B1/B1 since #371
    own_cells = {r.id: r.cell for r in data.rows}
    # A `no` verdict on a cell that is no homograph (θα σου τις γράψουμε for
    # the future εμείς), and a skipped cell that a sentence holds (g5's).
    refused = build_drill(pool, cells, results[0].candidates, infinitives,
                          {**verdicts, (g1.cell, 1001): "no"}, extra, own_cells, data.skipped)
    skipping = build_drill(pool, cells, results[0].candidates, infinitives, verdicts, extra, own_cells,
                           {**data.skipped, g5.cell: "fixture"})
    list_levels = {nfc(t): level for t, level in reader.execute(
        "SELECT term, level_ord FROM wordlist_item WHERE series = ?", (GREEK_LISTS,))}
    share = {r.id: (s, words) for s, r, words in list_word_share(data, by_key, greek, list_levels)}
    # #371: the article ο taken out of the lists: its forms stay allowed as function words.
    unlisted = {r.id: words for _, r, words in list_word_share(
        data, by_key, greek, {t: level for t, level in list_levels.items() if t != "ο"})}
    # #371: g5's own verb (αγαπάω) taken out of the lists: its forms stay allowed (CodeRabbit on #384).
    verbless_levels = {t: level for t, level in list_levels.items() if t != by_key[g5.cell].verb}
    verbless = {r.id: words for _, r, words in list_word_share(data, by_key, greek, verbless_levels)}

    def full_sentence(key: str) -> int | None:
        return full.rows[key][0] if key in full.rows else None

    def gate(rows_: Iterable[DataRow] = (), readings: Iterable[dict] = (), skips: Iterable[dict] = ()) -> list[str]:
        """The form gate's problems on these lines alone."""
        probe = replace(data, rows=list(rows_), reading_rows=list(readings), skipped_rows=list(skips))
        return data_failures(probe, by_key, infinitives, known)[0]

    gate_cases = [
        ("id outside", gate([replace(g5, id=1_000_000_009)])),
        ("check 'Russian", gate([replace(g5, check="Russian is clumsy.")])),
        ("not NFC", gate([replace(g5, text=unicodedata.normalize("NFD", g5.text))])),
        ("over 15 words", gate([replace(g5, text=g5.text + " " + g5.text)])),
        ("empty or not NFC", gate([replace(g5, rus="")])),
        ("not a usage example", gate([replace(w1, text=w1.text.rstrip("."))])),
        ("differ from the pin", gate([replace(w1, eng=g5.eng)])),
        ("differ from the pin", gate([replace(w1, page="")])),
        ("with a page", gate([replace(g5, page="γράφω")])),
        ("does not hold its cell", gate([replace(g5, cell="αγαπάω|future.active|1sg")])),
        ("source 'tatoeba'", gate([replace(g5, source="tatoeba")])),
        ("unique and ascending", gate([g5, g4])),
        ("the text of another row", gate([g4, replace(g5, text=g4.text, cell=g4.cell)])),
        ("verdict 'maybe'", gate(readings=[{**data.reading_rows[0], "verdict": "maybe"}])),
        ("no reason", gate(skips=[{**data.skipped_rows[0], "reason": ""}])),
        ("not 16 hex digits", gate(readings=[{**data.reading_rows[0], "texts_sha256": ""}])),
        ("not 16 hex digits", gate(readings=[{**data.reading_rows[0], "texts_sha256": "F365D9A91A7ADC10"}])),
        ("texts_sha256 '' is not 16 hex digits", gate([replace(g5, texts_sha256="")])),
    ]
    # #371: the pair gate. 1014's text fixed in place after its check: the
    # `ok` that let μιλάω's aorist take it is stale, never used; so is it
    # when only the English changes (a re-pinned export choosing another).
    aorist_ok = ("μιλάω|aorist.active|3sg", 1014)
    edited = {**known, 1014: (known[1014][0].replace("δυνατά", "σιγά"), *known[1014][1:])}
    edited_problems, edited_stale = data_failures(data, by_key, infinitives, edited)
    retranslated = {**known, 1014: (known[1014][0], known[1014][1] + " (another translation)", known[1014][2])}

    def edited_row(row: DataRow) -> tuple[list[tuple[str, int]], dict[str, list]]:
        """#371: the fixture built with `row` in place of its line of
        `ell.tsv`, its `texts_sha256` kept: the pair gate's misses and what
        is stale."""
        probe = replace(data, rows=[row if r.id == row.id else r for r in data.rows])
        probe_extra = data_candidates(probe, by_key)
        probe_texts = {sid: shipped_texts(c) for sid, c in {**results[0].candidates, **probe_extra}.items()}
        probe_verdicts = data_verdicts(probe, probe_texts)
        probe_drill = build_drill(pool, cells, results[0].candidates, infinitives, probe_verdicts, probe_extra,
                                  own_cells, probe.skipped)
        return (unchecked_pairs(rows_of(results, probe_drill), probe_verdicts),
                data_failures(probe, by_key, infinitives, probe_texts)[1])

    text_edit = edited_row(replace(g5, text=g5.text.replace(".", "!")))
    russian_edit = edited_row(replace(g5, rus=g5.rus.replace(".", "!")))
    pairs = unchecked_pairs(full_rows, verdicts)
    tatoeba_pairs = [(k, sid) for k, sid in pairs if source_of(sid) == 0]
    another_cell = "αγαπάω|subjunctiveSimple.active|2sg"  # g5's sentence, another cell's row
    serving = Rows([], [], [("ell", g5.cell, 1, g5.id, 0, 1), ("ell", another_cell, 1, g5.id, 0, 1)])
    checks += [
        ("#365: the pin takes usage examples, never a quotation; a text met twice keeps its first page",
         pin == {"Γράφετε βιβλίο;": (1, "γράφω", "Are you writing a book?"), w1.text: (2, "βαρύτητα", w1.eng),
                 w2.text: (3, "αβασάνιστος", w2.eng)}),
        ("#365: the fixture's data files pass the form gate", not data_problems),
        ("#365: the form gate catches bad rows, verdicts and skips",
         all(any(keyword in p for p in problems) for keyword, problems in gate_cases)
         and not gate([w1, w2, g5]) and not gate(readings=data.reading_rows, skips=data.skipped_rows)),
        ("#365: stale rows, verdicts and skips (cells the drill does not ask) are reported and never used",
         [r.id for r in stale["rows"]] == [g6.id] and [r["cell"] for r in stale["readings"]] == [
             "μιλάω|present.passive|3sg"] and [r["cell"] for r in stale["skipped"]] == ["τρέχω|present.active|2sg"]
         and not stale["hashes"] and g6.id not in stored),
        ("#365: Tatoeba comes before a generated row (θα σου τις γράψουμε)",
         full_sentence(g1.cell) == 1001 and g1.id not in stored),
        ("#365: a Wiktionary sentence by Wiktionary, its English from the pin, its Russian by LibreDict",
         full_sentence(w1.cell) == w1.id and stored[w1.id][1:] == ("ell", w1.text, "Wiktionary")
         and stored_translations[(w1.id, "eng")][3:] == (w1.eng, "Wiktionary")
         and stored_translations[(w1.id, "rus")][3:] == (w1.rus, "LibreDict")
         and full_sentence(w2.cell) == w2.id),
        ("#365: a generated sentence by LibreDict with eng and rus only; θ' αγαπήσεις from Tatoeba is no future",
         full_sentence(g5.cell) == g5.id and stored[g5.id][3] == "LibreDict"
         and {lang for sid, lang in stored_translations if sid == g5.id} == {"eng", "rus"}
         and stored_translations[(g5.id, "rus")][3:] == (g5.rus, "LibreDict")),
        ("#365: a row counts for its own cell of another reading (γράφετε, έκανα, αγάπησε), never for the other",
         full_sentence(g2.cell) == g2.id and "γράφω|imperativeContinuous.active|2pl" not in full.rows
         and full_sentence(g3.cell) == g3.id and "κάνω|imperfect.active|1sg" not in full.rows
         and full_sentence(g4.cell) == g4.id and "αγαπάω|aorist.active|3sg" not in full.rows),
        ("#365: the readings file's ok lets Tatoeba's μίλησε fill the aorist; its no keeps it from the imperative",
         full_sentence("μιλάω|aorist.active|3sg") == 1014 and "μιλάω|imperativeSimple.active|2sg" not in full.rows
         and "μιλάω|imperativeSimple.active|2sg" not in full.waiting),
        ("#365: a no verdict keeps its sentence out of any cell, not only a homograph's (Tatoeba's 1001 gives way)",
         (g1.cell, "θα γράψουμε") not in full.homographs.reading and refused.rows[g1.cell][0] == g1.id
         and g1.cell not in refused.waiting and full_sentence(g1.cell) == 1001),
        ("#365: a skipped cell stays without a sentence even when one holds it; the gate catches a row for it",
         g5.cell not in skipping.rows and skipping.found[g5.cell] >= 1 and g5.cell not in skipping.waiting
         and not skipped_with_rows(full_rows, data.skipped)
         and skipped_with_rows(full_rows, {g5.cell: "fixture"}) == [g5.cell]
         and g5.cell not in open_cells(skipping, {**data.skipped, g5.cell: "fixture"})),
        ("#365: an explicit no overrides a row's own check",
         verdicts[(g2.cell, g2.id)] == "ok"
         and data_verdicts(replace(data, readings={(g2.cell, g2.id): ("no", texts_hash(*g2.texts))}), known)[
             (g2.cell, g2.id)] == "no"),
        ("#365: a row comes first for its own cell, after the first form and never before Tatoeba",
         cell_order(2_000_000_009, 0, (1, 12, 9), True) < cell_order(2_000_000_001, 0, (0, 3, 1))
         and cell_order(1_000_000_009, 1, (0, 3, 9), True) > cell_order(1_000_000_001, 0, (1, 12, 1))
         and cell_order(5, 1, (1, 0, 1, 5)) < cell_order(1_000_000_001, 0, (0, 3, 1), True)),
        ("#365: sources by id range", (source_of(999_999_999), source_of(1_000_000_001), source_of(2_000_000_001))
         == (0, 1, 2) and all(source_of(sid) == 0 or sid in extra for sid in stored)),
        ("#365: the 2.0 gate counts a skipped cell as done, fails on any other open cell, and asks only the scope",
         "έχω|subjunctiveSimple.active|3sg" not in missing and "έχω|subjunctiveSimple.active|2sg" in missing
         and all(in_scope(by_key[k], (2, 1)) for k in missing) and "γράφω|imperfect.active|1sg" not in missing
         and not open_cells(full, {**data.skipped, **dict.fromkeys(missing, "x")}, (2, 1))),
        ("#371: the gate's scope is B1/B1: it asks a B1-tense cell (the imperfect) and never a B2-tense one (the "
         "pluperfect)",
         SCOPE == (3, 2) and open_cells(full, data.skipped) == open_cells(full, data.skipped, (3, 2))
         and "γράφω|imperfect.active|1sg" in open_cells(full, data.skipped, (3, 2))
         and g + "pluperfect.active|1sg" in asked and g + "pluperfect.active|1sg" not in full.rows
         and g + "pluperfect.active|1sg" not in open_cells(full, data.skipped, (3, 2))
         and set(missing) <= set(open_cells(full, data.skipped, (3, 2)))),
        ("#371: a B1 verb's cell at a B1 tense is in the gate's scope, at a B2 tense it is not; 2.0's scope had "
         "neither",
         in_scope(replace(by_key[g + "imperfect.active|1sg"], verb_level=3))
         and not in_scope(replace(by_key[g + "imperfect.active|1sg"], verb_level=3, tense_level=3))
         and not in_scope(replace(by_key[g + "imperfect.active|1sg"], verb_level=3), (2, 1))),
        ("#371: a verdict carries the hash of its sentence's Greek, English and Russian; a Tatoeba pair without a "
         "verdict fails the pair gate, an ok verdict passes",
         texts_hash(*known[1014]) == data.readings[aorist_ok][1] and tatoeba_pairs
         and all(r.texts_sha256 == texts_hash(*r.texts) for r in data.rows)
         and (g1.cell, 1001) in pairs and aorist_ok not in pairs),
        ("#371: the pair gate is on (`PAIR_GATE`): a pair no check covers fails the build, none passes",
         PAIR_GATE is True and bool(pairs) and not pair_gate_passes(pairs) and pair_gate_passes([])),
        ("#371: a data row passes for its own cell; serving another cell it needs a verdict",
         unchecked_pairs(serving, verdicts) == [(another_cell, g5.id)]
         and not unchecked_pairs(serving, {**verdicts, (another_cell, g5.id): "ok"})
         and unchecked_pairs(serving, {**verdicts, (another_cell, g5.id): "no"}) == [(another_cell, g5.id)]),
        ("#371: a row fixed in place after its check: its verdicts are stale, never used, and its pair fails",
         not edited_problems and [r["cell"] for r in edited_stale["hashes"]]
         == ["μιλάω|aorist.active|3sg", "μιλάω|imperativeSimple.active|2sg"]
         and aorist_ok not in data_verdicts(data, edited) and aorist_ok in unchecked_pairs(
             full_rows, data_verdicts(data, edited))
         and build_drill(pool, cells, results[0].candidates, infinitives, data_verdicts(data, edited), extra,
                         own_cells, data.skipped).rows.get(aorist_ok[0]) is None),
        ("#365: the two data_source rows", full_conn.execute(
            "SELECT id, version, license FROM data_source ORDER BY id").fetchall()
         == [("libredict-drill-ell", "2026-11-22", "CC BY-SA 4.0"),
             ("tatoeba", "self-check", "CC BY 2.0 FR"),
             ("wiktionary-ell-examples", "enwiktionary 2026-10-01", "CC BY-SA 4.0")]),
        ("#365: the output and drill gates hold with the data rows; the word examples do not change",
         not any(output_failures(full_rows, results, subsets, keys).values())
         and not any(drill_failures(full_rows, cells, infinitives, set(subsets["ell"].sentences)).values())
         and rows_hashes(rows_of(results)) == rows_hashes(split_rows(full_rows)[0])),
        ("#365: the list-word share counts a list verb's forms and articles, not other words",
         0 < share[g5.id][0] < 1 and "αγαπήσεις" not in share[g5.id][1] and "την" not in share[g5.id][1]
         and "νησί" in share[g5.id][1]),
        ("#371: a function word is never outside the lists, listed or not (την with ο taken out); other words "
         "outside the lists still are (νησί)",
         "την" in greek.function_words and "την" not in unlisted[g5.id] and "νησί" in unlisted[g5.id]
         and "νησί" not in greek.function_words),
        ("#371: a form of the row's own verb is never outside the lists, listed or not (αγαπήσεις with αγαπάω "
         "taken out); other words still are (νησί)",
         not [w for w in greek.terms_of.get("αγαπήσεις", set()) | greek.lemmas_of.get("αγαπήσεις", set())
              if w in verbless_levels]
         and "αγαπήσεις" not in verbless[g5.id] and "νησί" in verbless[g5.id]),
        ("#371: a row's own ok covers only the text it was given on: a built file with an older text has no "
         "verdict for the pair (CodeRabbit on #384)",
         verdicts.get((g2.cell, g2.id)) == "ok"
         and (g2.cell, g2.id) not in data_verdicts(data, {**known, g2.id: (g2.text[::-1], g2.eng, g2.rus)})),
        ("#371: a verdict on a sentence whose English changed (its Greek kept) is stale, never used, and its pair "
         "fails (CodeRabbit on #384)",
         aorist_ok not in data_verdicts(data, retranslated)
         and aorist_ok in unchecked_pairs(full_rows, data_verdicts(data, retranslated))
         and [r["cell"] for r in data_failures(data, by_key, infinitives, retranslated)[1]["hashes"]]
         == ["μιλάω|aorist.active|3sg", "μιλάω|imperativeSimple.active|2sg"]),
        ("#371: a checked data row edited in ell.tsv, its text (θα αγαπήσεις … μέρα!) or else its Russian: its "
         "own check is stale, reported, and its pair fails the gate (CodeRabbit on #384)",
         (g5.cell, g5.id) not in pairs and full_sentence(g5.cell) == g5.id
         and (g5.cell, g5.id) in text_edit[0] and [r.id for r in text_edit[1]["own"]] == [g5.id]
         and (g5.cell, g5.id) in russian_edit[0] and [r.id for r in russian_edit[1]["own"]] == [g5.id]
         and not stale["own"]),
    ]
    # #385: the corpus rows of the fixture (rows of the real ell-corpus.tsv on the fixture's verbs) and their
    # documents: the choice's order, own cells and waiting pairs, stale rows, NC_ALLOWED, the corpus gate, the
    # author field and the data_source row.
    c1, c2, c3 = data.corpus  # γράφετε (present 2pl, NC), κάνατε (aorist 2pl, pd), θα μιλάω (adapted, BY-SA)
    corpus = corpus_candidates(data, by_key)
    corpus_known = {**known, **{sid: shipped_texts(c) for sid, c in corpus.items()}}
    corpus_verdicts = data_verdicts(data, corpus_known)
    corpus_own = {**own_cells, **{r.id: r.cell for r in data.corpus}}

    def corpus_build(candidates: dict[int, Candidate] = results[0].candidates, verdicts_: dict | None = None,
                     rows_: dict[int, Candidate] | None = None) -> Drill:
        return build_drill(pool, cells, candidates, infinitives, corpus_verdicts if verdicts_ is None else verdicts_,
                           {**extra, **(corpus if rows_ is None else rows_)}, corpus_own, data.skipped)

    with_corpus = [corpus_build() for _ in range(2)]
    corpus_rows = [rows_of(results, b) for b in with_corpus]
    tatoeba_g2 = {**results[0].candidates, 998: Candidate(998, g2.text, "fixture", tokens(g2.text), {}, True, (0,))}
    over_tatoeba = corpus_build(tatoeba_g2, {**corpus_verdicts, (c1.cell, 998): "ok"})
    imperative = "γράφω|imperativeContinuous.active|2pl"  # γράφετε's other reading
    served = corpus_build(verdicts_={**corpus_verdicts, (imperative, c1.id): "ok"})
    edited = replace(data, corpus=[replace(c1, rus=c1.rus.replace("?", "!")), c2, c3])
    stale_status = corpus_status(edited, by_key)
    no_nc = corpus_candidates(data, by_key, nc_allowed=False)

    def corpus_gate(rows_: list | None = None, documents: list | None = None, skipped: dict | None = None) -> list[str]:
        docs = data.document_rows if documents is None else documents
        probe = replace(data, corpus=data.corpus if rows_ is None else rows_, document_rows=docs,
                        documents={d.doc: d for d in docs}, skipped=data.skipped if skipped is None else skipped)
        return corpus_failures(probe, by_key, infinitives)

    nc_doc = data.documents[c1.doc]
    corpus_gate_cases = [
        ("NoDerivatives", corpus_gate(documents=[replace(nc_doc, statement="Creative Commons BY-NC-ND (Αναφορά "
                                                         "δημιουργού – Μη εμπορική χρήση – Όχι παράγωγα έργα)"),
                                                 *data.document_rows[1:]])),
        ("only grants copying", corpus_gate(documents=[replace(nc_doc, statement="Ελεύθερη αναπαραγωγή (με αναφορά "
                                                               "της πηγής)"), *data.document_rows[1:]])),
        ("no checked_by", corpus_gate(documents=[replace(nc_doc, checked_by=""), *data.document_rows[1:]])),
        ("is not one that ships", corpus_gate(documents=[replace(nc_doc, licence="cc_by_nd_4_0"),
                                                         *data.document_rows[1:]])),
        ("without its basis", corpus_gate(documents=[nc_doc, replace(data.document_rows[1], statement="Public Domain"),
                                                     data.document_rows[2]])),
        ("a | in the work", corpus_gate(documents=[replace(nc_doc, work="Babiniotis|archive"), *data.document_rows[1:]])),
        ("not in the documents file", corpus_gate(documents=data.document_rows[1:])),
        ("no corpus row cites it", corpus_gate(rows_=[c2, c3])),
        ("id outside", corpus_gate(rows_=[replace(c1, id=2_999_999_999), c2, c3])),
        ("unique and ascending", corpus_gate(rows_=[c2, c1, c3])),
        ("a second row for the cell", corpus_gate(rows_=[c1, replace(c2, cell=c1.cell), c3])),
        ("over 15 words", corpus_gate(rows_=[replace(c1, text=" ".join([c1.text] * 3)), c2, c3])),
        ("final ν", corpus_gate(rows_=[replace(c1, text=c1.text.replace("δεν τους", "δε τους"),
                                               original=c1.original.replace("δεν τους", "δε τους")), c2, c3])),
        ("not the original's", corpus_gate(rows_=[replace(c1, text=c1.text.replace("δεν τους", "δεν σας")), c2, c3])),
        # κι ας + an aorist holds no aorist (match rule 3; the run's "Καλώς τους κι ας αργήσανε!").
        ("does not hold its cell", corpus_gate(rows_=[c1, replace(c2, cell="μιλάω|aorist.active|3sg",
                                                                  text="Κι ας μίλησε δυνατά.",
                                                                  original="Κι ας μίλησε δυνατά."), c3])),
        ("not NFC", corpus_gate(rows_=[c1, c2, replace(c3, text=unicodedata.normalize("NFD", c3.text))])),
    ]
    # Gate 4 ("never a word", 0134 Checks 4): each allowed edit passes, each change of a word fails.
    allowed_edits = [("ΑΛΙΚΗ: Θα μιλάω με τα ζώα;", "Θα μιλάω με τα ζώα;"), ("*ΜΑ: θα μιλάω", "Θα μιλάω."),
                     ("ΠΑΙΔΙ 6: Θα μιλάω.", "Θα μιλάω."), ("(Ο τελωνειακός): Θα μιλάω.", "Θα μιλάω."),
                     ("- Θα μιλάω!", "Θα μιλάω!"), ("14) Θα μιλάω.", "Θα μιλάω."), ("ε. Θα μιλάω.", "Θα μιλάω."),
                     ("19 Θα μιλάω.", "Θα μιλάω."), ("Ο µαθητής μιλάει.", "Ο μαθητής μιλάει."),
                     ("O μαθητής μιλάει.", "Ο μαθητής μιλάει."), ("ΜAΘΗΤΗΣ", "ΜΑΘΗΤΗΣ"), ("0 μαθητής", "Ο μαθητής"),
                     ("∆ε μιλάει.", "Δε μιλάει."), ("θα μιλάω", "Θα μιλάω."), ('"Ναι" είπε', "«Ναι» είπε."),
                     ("Ναι θα μιλάω", "Ναι, θα μιλάω."), ("σ'αγαπώ", "Σ' αγαπώ."), ("σαν να' ναι", "Σαν να 'ναι."),
                     # CodeRabbit on #387: apostrophes as quotation marks; both spacings of an elision; the
                     # speaker tags the spec names.
                     ("'Ναι' είπε.", "«Ναι» είπε."), ("να' ναι", "να 'ναι"), ("να 'ναι", "να' ναι"),
                     ("Ο Εβραίος: Θα μιλάω.", "Θα μιλάω."), ("Σ.: Θα μιλάω.", "Θα μιλάω."),
                     ("Αφηγητής Θα μιλάω.", "Θα μιλάω.")]
    changed_words = [("Το είπα.", "Το είπε."), ("μόνο", "μονό"), ("Θα μιλάω αύριο.", "Θα μιλάω."),
                     ("Θα μιλάω.", "Θα μιλάω αύριο."), ("Θα μιλάω αύριο.", "Αύριο θα μιλάω."),
                     ("ότι ήθελε", "ό,τι ήθελε"), ("'πείσαν", "Πείσαν."), ("Θα σου μιλάω.", "Θα μιλάω."),
                     # CodeRabbit on #387: a clause before a colon is no speaker tag.
                     ("Δεν μιλάω: γράφετε.", "Γράφετε.")]
    credit = corpus_credit(corpus, corpus_rows[0])
    corpus_conn = new_database(":memory:")
    write_rows(corpus_conn, corpus_rows[0], "self-check", data.credits() + credit)
    checks += [
        ("#385: the fixture's corpus rows pass the corpus gate", not corpus_failures(data, by_key, infinitives)),
        ("#385: sources by id: 3·10^9 + n is a corpus row, after Tatoeba and Wiktionary and before generated rows",
         (source_of(2_999_999_999), source_of(3_000_000_001)) == (GENERATED, CORPUS)
         and cell_order(1_000_000_009, 1, (1, 12, 9)) < cell_order(3_000_000_001, 0, (0, 3, 1), True)
         < cell_order(2_000_000_001, 0, (0, 3, 1), True)
         and cell_order(5, 1, (1, 0, 1, 5)) < cell_order(3_000_000_001, 0, (0, 3, 1), True)),
        ("#385: a corpus row wins over its cell's generated row, and a Tatoeba sentence over it",
         full_sentence(c1.cell) == g2.id and with_corpus[0].rows[c1.cell][0] == c1.id
         and over_tatoeba.rows[c1.cell][0] == 998),
        ("#385: a corpus row serves its own cell of another reading (κάνατε, the aorist) on its own check, never "
         "the other without a verdict; with an ok verdict it serves (γράφετε, the imperative)",
         with_corpus[0].rows.get(c2.cell, (0,))[0] == c2.id and "κάνω|imperfect.active|2pl" not in with_corpus[0].rows
         and ("κάνω|imperfect.active|2pl", c2.id) in with_corpus[0].corpus_waiting
         and (imperative, c1.id) in with_corpus[0].corpus_waiting and imperative not in with_corpus[0].rows
         and served.rows.get(imperative, (0,))[0] == c1.id and (imperative, c1.id) not in served.corpus_waiting),
        ("#385: a corpus row edited after its check (here its Russian) is stale, never used, and its cell falls back "
         "to its generated row",
         stale_status[c1.id].startswith("stale") and c1.id not in corpus_candidates(edited, by_key)
         and corpus_build(rows_=corpus_candidates(edited, by_key)).rows[c1.cell][0] == g2.id
         and not stale_status[c2.id]),
        ("#385: NC_ALLOWED off drops the NonCommercial rows (CC BY-NC) and their cells fall back; the others stay",
         NC_ALLOWED is True and c1.id in corpus and c1.id not in no_nc and {c2.id, c3.id} <= set(no_nc)
         and corpus_build(rows_=no_nc).rows[c1.cell][0] == g2.id
         and corpus_status(data, by_key, nc_allowed=False)[c1.id].startswith("licence")),
        ("#385: the corpus gate catches each kind of bad row and document",
         all(any(keyword in p for p in problems) for keyword, problems in corpus_gate_cases)),
        ("#385: gate 4 lets each allowed edit pass (a speaker tag, a dash, an exercise label, µ, a Latin O, the "
         "first capital, quotation marks, a final mark, a comma, spacing around an elision)",
         all(same_words(o, t) for o, t in allowed_edits)),
        ("#385: gate 4 fails a changed letter, a moved accent, a dropped, added or moved word, ότι made ό,τι and a "
         "dropped elision apostrophe", not any(same_words(o, t) for o, t in changed_words)),
        ("#385: the author field names the work, collection, licence and change; translations by LibreDict",
         corpus[c3.id].author == "Γιώργος Γαλάτσης, «Όλαφ, ο μικρός πελαργούλης και ο φίλος του ο Θανάσης»|"
         "openbook.gr|cc_by_sa_4_0|adapted"
         and corpus[c2.id].author == "Πηνελόπη Δέλτα, «Τρελαντώνης»|openbook.gr|pd|"
         and {a for _, a in [(t[0], t[2]) for t in corpus[c1.id].translations.values()]} == {GENERATED_AUTHOR}
         and set(corpus[c1.id].translations) == {"eng", "rus"}
         and corpus_byline(corpus[c3.id].author).endswith("· CC BY-SA 4.0 · adapted · translation: LibreDict, "
                                                          "generated")),
        ("#385: the corpus-ell-drill data_source row names the licences of the documents that ship, and only "
         "those of rows stored (CodeRabbit on #387: a candidate that loses its cell credits nothing)",
         [r["license"] for r in credit] == ["public domain; CC BY-SA 4.0; CC BY-NC 4.0 (each document's own)"]
         and corpus_credit(no_nc, rows_of(results, corpus_build(rows_=no_nc)))[0]["license"]
         == "public domain; CC BY-SA 4.0 (each document's own)"
         and corpus_credit(corpus, Rows([s for s in corpus_rows[0].sentences if s[0] != c1.id], [], []))[0][
             "license"] == "public domain; CC BY-SA 4.0 (each document's own)"
         and corpus_conn.execute("SELECT version, url FROM data_source WHERE id = 'corpus-ell-drill'").fetchone()
         == (f"babylm-ell {BABYLM_REVISION}", CORPUS_SOURCE["url"]) and corpus_credit({}, corpus_rows[0]) == []
         and corpus_credit(corpus, rows_of(results, corpus_build(rows_={}))) == []),
        ("#385: two builds with the corpus rows give equal hashes; the drill and output gates hold; the word "
         "examples do not change",
         rows_hashes(corpus_rows[0]) == rows_hashes(corpus_rows[1])
         and not any(drill_failures(corpus_rows[0], cells, infinitives, set(subsets["ell"].sentences)).values())
         and not any(output_failures(corpus_rows[0], results, subsets, keys).values())
         and rows_hashes(rows_of(results)) == rows_hashes(split_rows(corpus_rows[0])[0])
         and not unchecked_pairs(Rows([], [], [w for w in corpus_rows[0].words if source_of(w[3]) == CORPUS]),
                                 corpus_verdicts)),
    ]

    # #385 QA (0134 Test plan): an edit of any of the three checked texts, not only the Russian, makes the row
    # stale and its cell falls back; gate 3 at its bound (15 words pass, 16 fail); gate 5 on a digraph («δε μπορώ»).
    def falls_back(**edit: str) -> bool:
        probe = replace(data, corpus=[replace(c1, **edit), c2, c3])
        status = corpus_status(probe, by_key)
        return (status[c1.id].startswith("stale") and not status[c2.id] and not status[c3.id]
                and corpus_build(rows_=corpus_candidates(probe, by_key)).rows[c1.cell][0] == g2.id)

    def words_of(n: int) -> str:  # c1's text padded with its own last word to n words, as text and original
        base = c1.text.rstrip(";")
        return base + " ξαναγυρίσουν" * (n - len(tokens(base))) + ";"

    def gate_on(**edit: str) -> list[str]:
        return corpus_gate(rows_=[replace(c1, **edit), c2, c3])

    checks += [
        ("#385: a corpus row whose text, English or Russian was edited after its check is stale, and its cell falls "
         "back to its generated row",
         falls_back(text=c1.text.replace(";", "!")) and falls_back(eng=c1.eng.replace("?", "!"))
         and falls_back(rus=c1.rus.replace("?", "!"))),
        ("#385: gate 3 at its bound: a 15-word row passes, a 16-word row fails",
         len(tokens(words_of(15))) == 15 and len(tokens(words_of(16))) == 16
         and not any("words" in p for p in gate_on(text=words_of(15), original=words_of(15)))
         and any(f"over {MAX_WORDS} words" in p for p in gate_on(text=words_of(16), original=words_of(16)))),
        ("#385: gate 5 fails «δε μπορώ» (δε before the digraph μπ)",
         any("final ν" in p for p in gate_on(text=c1.text.replace("δεν τους", "δε μπορώ"),
                                             original=c1.original.replace("δεν τους", "δε μπορώ")))),
    ]

    # #385, review of #387 (kyukhin 2026-11-28; CodeRabbit): an excluded corpus row never leaves its cell empty. A
    # skipped cell keeps its skip line, which counts only while its own corpus row does not ship; gate 9 finds a
    # corpus row whose cell would be open without it. Every cell counts here (the fixture is no full scope).
    everything = (3, 3)
    corpus_ids = {r.id: r.cell for r in data.corpus}
    skips = {**data.skipped, c1.cell: "fixture"}

    def skip_build(rows_: dict[int, Candidate], extra_: dict[int, Candidate] = extra,
                   skipped_: dict[str, str] = skips) -> Drill:
        return build_drill(pool, cells, results[0].candidates, infinitives, corpus_verdicts, {**extra_, **rows_},
                           corpus_own, skipped_)

    over_skip = skip_build(corpus)
    fallbacks = {"NC_ALLOWED off": skip_build(no_nc), "stale": skip_build(corpus_candidates(edited, by_key)),
                 "no corpus row": skip_build({})}
    opened = {why: set(open_cells(b, skips, everything)) - set(open_cells(over_skip, skips, everything))
              for why, b in fallbacks.items()}
    no_generated = {sid: c for sid, c in extra.items() if sid != g2.id}  # c1's cell: no generated row, no skip
    bare = skip_build(corpus, no_generated, data.skipped)
    bare_without = skip_build({}, no_generated, data.skipped)
    # A corpus row stored only for another cell (an ok verdict) while a Tatoeba sentence takes its own cell.
    foreign = corpus_build(tatoeba_g2, {**corpus_verdicts, (c1.cell, 998): "ok", (imperative, c1.id): "ok"})
    foreign_report = "\n".join(corpus_section(foreign, data, corpus_status(data, by_key)))
    pd_doc = data.documents[c2.doc]
    checks += [
        ("#385: a skipped cell takes its own corpus row over its skip line, and no other sentence; the gate allows "
         "that row only",
         over_skip.rows[c1.cell][0] == c1.id and not corpus_failures(replace(data, skipped=skips), by_key, infinitives)
         and not skipped_with_rows(rows_of(results, over_skip), skips, corpus_ids)
         and skipped_with_rows(rows_of(results, over_skip), skips) == [c1.cell]
         and skipped_with_rows(rows_of(results, over_skip), skips, {c1.id: c2.cell}) == [c1.cell]
         and c1.cell not in skip_build({}, skipped_=skips).rows),
        ("#385: NC_ALLOWED off or a stale corpus row: the skipped cell falls back to its skip line and no cell "
         "opens (0 open against the build with the corpus rows); with no corpus row at all, gate 9 names exactly "
         "the cells that open (the fixture's other two rows have neither a generated row nor a skip line)",
         all(c1.cell not in b.rows and c1.cell in skips for b in fallbacks.values())
         and opened["NC_ALLOWED off"] == opened["stale"] == set()
         and opened["no corpus row"] == {c2.cell, c3.cell}
         == set(corpus_without_fallback(over_skip, fallbacks["no corpus row"], skips, everything))),
        ("#385: gate 9 fails a corpus row whose cell has no generated row, no other sentence and no skip line",
         bare.rows[c1.cell][0] == c1.id and c1.cell in open_cells(bare_without, data.skipped, everything)
         and c1.cell in corpus_without_fallback(bare, bare_without, data.skipped, everything)
         and c1.cell not in corpus_without_fallback(with_corpus[0], corpus_build(rows_={}), data.skipped,
                                                    everything)),
        ("#385: the report counts a corpus row stored only for another cell (an ok verdict) as shipped "
         "(CodeRabbit on #387)",
         foreign.rows[c1.cell][0] == 998 and foreign.rows[imperative][0] == c1.id
         and "3 ship, 2 of them for their own cells" in foreign_report
         and f"| CLARIN:EL | {CORPUS_LICENCES[nc_doc.licence]} | 1 | 1 | 1 | 0 |" in foreign_report),
        (f"#385: public domain needs a life that ended by PD_DIED_BY ({PD_DIED_BY}): 1800–1890 and "
         f"1874–{PD_DIED_BY} pass, 1874–{PD_DIED_BY + 4} fails (CodeRabbit on #387)",
         not licence_problems(replace(pd_doc, statement="basis: 1800–1890"))
         and not licence_problems(replace(pd_doc, statement=f"basis: 1874–{PD_DIED_BY}"))
         and any("basis" in p for p in licence_problems(replace(pd_doc, statement=f"basis: 1874–{PD_DIED_BY + 4}")))),
    ]
    for problem in data_problems:
        print(f"    data files: {problem}")
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    for gate, problems in {**failures, **drill_failed}.items():
        for problem in problems:
            print(f"    {gate}: {problem}")

    # A subset file whose sha256 differs from its pin fails the step.
    real_pins = inputs.pins
    key = "Scripts/fixtures/tatoeba-sample/ell-sentences.tsv"
    try:
        inputs.pins = lambda: {key: {"sha256": "0" * 64}}
        try:
            inputs.committed(key)
            failed.append("a tampered subset is refused")
            print("  FAIL a tampered subset is refused")
        except RuntimeError:
            print("  ok   a tampered subset is refused")
    finally:
        inputs.pins = real_pins

    if failed:
        print("FAILED: " + "; ".join(failed))
        return 1
    print("OK: examples self-check passed.")
    return 0


# ---------------------------------------------------------------------------
# Refresh: a new pinned subset from the current export
# ---------------------------------------------------------------------------

def download_export(folder: Path) -> tuple[str, list[dict]]:
    """Downloads every export file into `folder`; returns the export date
    (from Last-Modified, all files of one day) and each file's record."""
    records, dates = [], set()
    for name in EXPORT_FILES:
        url = EXPORT_URL + name
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        print(f"  Downloading {url}")
        with urllib.request.urlopen(url, timeout=600) as resp, open(target, "wb") as out:
            shutil.copyfileobj(resp, out, 1 << 20)
            modified = resp.headers.get("Last-Modified")
        if not modified:
            sys.exit(f"{url}: no Last-Modified header, so no export date")
        dates.add(email.utils.parsedate_to_datetime(modified).date().isoformat())
        records.append({"path": name, "url": url, "bytes": target.stat().st_size, "sha256": inputs.sha256(target)})
    if len(dates) != 1:
        sys.exit(f"The export files carry several dates {sorted(dates)}: a new export came out during the "
                 "download; run --refresh again")
    return dates.pop(), records


def local_export(folder: Path) -> list[dict]:
    """The records of export files already downloaded into `folder`, as
    `<lang>/<file>` or flat."""
    records = []
    for name in EXPORT_FILES:
        path = folder / name if (folder / name).is_file() else folder / Path(name).name
        if not path.is_file():
            sys.exit(f"{name} is not in {folder}")
        records.append({"path": name, "url": EXPORT_URL + name, "bytes": path.stat().st_size,
                        "sha256": inputs.sha256(path), "local": path})
    return records


def export_rows(path: Path) -> Iterable[list[str]]:
    with bz2.open(path, "rt", encoding="utf-8", newline="") as f:
        for line in f:
            yield line.rstrip("\n").split("\t")


def project(files: dict[str, Path]) -> dict[str, dict[str, list[str]]]:
    """The lines of the two subsets (spec, "Source and pin"): no quality
    filter; sentences sorted by language and id, the other files by their
    columns."""
    def links(name: str) -> list[tuple[int, int]]:
        return [(int(row[0]), int(row[1])) for row in export_rows(files[name])]

    ell_links = {other: links(f"ell/ell-{other}_links.tsv.bz2") for other in ("eng", "rus", "spa", "ara")}
    eng_links = {other: links(f"eng/eng-{other}_links.tsv.bz2") for other in ("rus", "spa", "ara")}
    eng_links["ell"] = [(eng, ell) for ell, eng in ell_links["eng"]]
    wanted = {"ell": collections.defaultdict(set), "eng": collections.defaultdict(set)}
    wanted["ell"]["ell"] = {int(row[0]) for row in export_rows(files["ell/ell_sentences_detailed.tsv.bz2"])}
    for subset, by_other in (("ell", ell_links), ("eng", eng_links)):
        for other, pairs in by_other.items():
            wanted[subset][other].update(b for _, b in pairs)
            if subset == "eng":
                wanted[subset]["eng"].update(a for a, _ in pairs)

    sentences = {"ell": [], "eng": []}
    for lang in EXPORT_LANGS:
        for row in export_rows(files[f"{lang}/{lang}_sentences_detailed.tsv.bz2"]):
            sid = int(row[0])
            for subset in SUBSETS:
                if sid in wanted[subset][lang]:
                    sentences[subset].append((sid, row[1], row[2], row[3] if len(row) > 3 else "\\N"))
    tags = collections.defaultdict(set)
    for lang in EXPORT_LANGS:
        for row in export_rows(files[f"{lang}/{lang}_tags.tsv.bz2"]):
            if len(row) >= 2:
                tags[int(row[0])].add(row[1])
    natives = collections.defaultdict(set)
    for lang in EXPORT_LANGS:
        for row in export_rows(files[f"{lang}/{lang}_user_languages.tsv.bz2"]):
            if len(row) >= 3 and row[0] == lang and row[1] == NATIVE_LEVEL:
                natives[lang].add(row[2])

    out = {}
    for subset in SUBSETS:
        rows = sorted(sentences[subset], key=lambda r: (r[1], r[0]))  # by language: xz packs it better
        authors = {(lang, author) for _, lang, _, author in rows if author not in ("", "\\N")}
        by_other = ell_links if subset == "ell" else eng_links
        pairs = sorted({pair for values in by_other.values() for pair in values})
        out[subset] = {
            "sentences": [f"{sid}\t{lang}\t{text}\t{author}" for sid, lang, text, author in rows],
            "links": [f"{a}\t{b}" for a, b in pairs],
            "tags": [f"{sid}\t{tag}" for sid in sorted({r[0] for r in rows} & set(tags)) for tag in sorted(tags[sid])],
            "natives": [f"{lang}\t{user}" for lang, user in sorted(authors) if user in natives[lang]],
        }
    return out


def refresh(export_dir: Path | None, export_date: str | None, cache_dir: Path) -> int:
    """Writes a new dated subset from the export and points inputs.json at
    it; removes the old subset."""
    if export_dir is None:
        download = Path(cache_dir) / "tatoeba-export"
        date, records = download_export(download)
        files = {r["path"]: download / r["path"] for r in records}
    else:
        if not export_date or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", export_date):
            sys.exit("--export-dir needs --export-date YYYY-MM-DD, the export's Last-Modified date")
        date, records = export_date, local_export(export_dir)
        files = {r["path"]: r.pop("local") for r in records}
    folder = f"{SUBSET_PREFIX}{date.replace('-', '')}"
    target = REPO / folder
    target.mkdir(parents=True, exist_ok=True)
    print(f"Projecting the export of {date} into {folder}/")
    pins = inputs.pins()
    for old in [k for k in pins if k.startswith(SUBSET_PREFIX)]:
        del pins[old]
    for subset, parts_ in project(files).items():
        for part, lines in parts_.items():
            key = f"{folder}/{subset}-{part}.tsv.xz"
            data = ("\n".join(lines) + "\n").encode("utf-8")
            (REPO / key).write_bytes(lzma.compress(data, format=lzma.FORMAT_XZ, preset=9))
            pins[key] = {"sha256": inputs.sha256(REPO / key), "rows": len(lines)}
            print(f"  {key}: {len(lines):,} rows, {(REPO / key).stat().st_size:,} bytes")
    pins[folder] = {
        "about": "Two projections of Tatoeba's weekly export (CC BY 2.0 FR), committed because Tatoeba keeps "
                 "only its latest export (docs/specs/0134-example-sentences.md, \"Source and pin\"). "
                 "Written by build_examples.py --refresh.",
        "export_date": date,
        "export_url": EXPORT_URL,
        "export_files": [{"path": r["path"], "url": r["url"], "bytes": r["bytes"], "sha256": r["sha256"]}
                         for r in records],
    }
    inputs.write_pins(pins)
    for old in sorted((REPO / SUBSET_PREFIX).parent.glob(Path(SUBSET_PREFIX).name + "*")):
        if old.is_dir() and old.name != target.name:
            shutil.rmtree(old)
            print(f"Removed {old.relative_to(REPO)}")
    print(f"Pinned {folder} in {inputs.INPUTS_JSON.name}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-check", action="store_true", help="Offline check on the fixture.")
    mode.add_argument("--standalone", type=Path, metavar="OUT",
                      help="Build the example tables alone into OUT, with the QA report and the gates.")
    mode.add_argument("--refresh", action="store_true",
                      help="Download the current export and write a new dated subset.")
    parser.add_argument("--source", type=Path,
                        help="With --standalone: the full dictionary file whose forms, morphy, list words and "
                             "headwords the step reads (default: dictionaries-full.sqlite in the cache folder).")
    parser.add_argument("--export-dir", type=Path, help="With --refresh: export files already downloaded.")
    parser.add_argument("--export-date", help="With --export-dir: the export's date, YYYY-MM-DD.")
    parser.add_argument("--cache-dir", type=Path, default=inputs.DEFAULT_CACHE_DIR,
                        help="Where the frequency list and a refresh's downloads go (default: Scripts/.cache).")
    args = parser.parse_args()
    if args.self_check:
        return self_check()
    if args.refresh:
        return refresh(args.export_dir, args.export_date, args.cache_dir.resolve())
    source = args.source or args.cache_dir / "dictionaries-full.sqlite"
    return standalone(args.standalone.resolve(), source, args.cache_dir.resolve())


if __name__ == "__main__":
    sys.exit(main())
