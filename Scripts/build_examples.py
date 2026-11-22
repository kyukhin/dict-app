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
the form gate and the 2.0 coverage gate fail the build.
`Scripts/drill_examples.py` is the tool around the data files.

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
DRILL_BUDGET = 3_500_000  # bytes installed: the cell rows and the sentences only they use (kyukhin 2026-11-22)
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

# #365: the drill-example data files (0134, "Data files"), plain text in Git.
DRILL_DATA = SCRIPTS_DIR / "data" / "drill-examples"
DATA_FILE, READINGS_FILE, SKIPPED_FILE = "ell.tsv", "ell-readings.tsv", "ell-skipped.tsv"
DATA_COLUMNS = ("id", "source", "page", "cell", "text", "eng", "rus", "model", "check", "checked_by")
READING_COLUMNS = ("cell", "sentence_id", "verdict", "checked_by", "reason")
SKIPPED_COLUMNS = ("cell", "reason", "checked_by")
SOURCE_IDS = {"wiktionary": WIKTIONARY_IDS, "generated": GENERATED_IDS}
AUTHORS = {"wiktionary": "Wiktionary", "generated": "LibreDict"}  # every text keeps an author
GENERATED_AUTHOR = "LibreDict"  # of a generated text, also a Wiktionary sentence's Russian
SCOPE = (2, 1)  # 2.0 (kyukhin 2026-11-22): the A1 and A2 verbs, tenses up to A2 (indexes of drill_cells.LEVELS)
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
    """A sentence's source by its id (0134): 0 Tatoeba, 1 Wiktionary, 2 generated."""
    return 0 if sid < WIKTIONARY_IDS else 1 if sid < GENERATED_IDS else 2


def cell_order(sid: int, form_index: int, rank: tuple, own: bool = False) -> tuple:
    """The choice's order of a sentence for a cell, lowest first: real
    sentences first (Tatoeba, Wiktionary, then generated), the cell's first
    form (the option shown as right) before another, a data row written or
    translated for the cell (`own`, #365) before one written for another,
    then the source's own rank (Tatoeba: step 5's; Wiktionary and
    generated: 3 to 10 words, fewer words, the id)."""
    return (source_of(sid), min(form_index, 1), 0 if own else 1) + tuple(rank)


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
    one is found (kyukhin 2026-11-22)."""
    verdicts, data, own, skipped = verdicts or {}, data or {}, own or {}, frozenset(skipped)
    homo = homographs(cells)
    by_last: dict[str, set[int]] = collections.defaultdict(set)
    for i, c in enumerate(cells):
        for form in c.forms:
            by_last[form.rsplit(" ", 1)[-1]].add(i)
    occurrences: dict[str, list[tuple]] = collections.defaultdict(list)
    waiting: collections.Counter = collections.Counter()
    everything = {**candidates, **data}
    for sid in sorted(everything):
        candidate = everything[sid]
        toks = drill_tokens(candidate.text)
        for i in sorted({i for tok, _, _ in toks for i in by_last.get(tok, ())}):
            c, blocked = cells[i], False
            if verdicts.get((c.key, sid)) == "no":
                continue  # decided: never this sentence for this cell
            for form_index, form in enumerate(c.forms):
                span = find_form(toks, form, infinitives)
                if span is None:
                    continue
                if (c.key, form) in homo.reading and verdicts.get((c.key, sid)) != "ok":
                    blocked = True
                    continue
                occurrences[c.key].append((cell_order(sid, form_index, candidate.rank, own.get(sid) == c.key), sid,
                                           span[0], span[1] - span[0], form))
                break
            else:
                if blocked:
                    waiting[c.key] += 1
    rows = {key: min(found)[1:] for key, found in occurrences.items() if key not in skipped}
    return Drill(pool, cells, homo, rows, {key: len(found) for key, found in occurrences.items()},
                 {key: n for key, n in waiting.items() if key not in rows and key not in skipped}, data)


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


@dataclass
class DrillData:
    """The data files, read."""
    rows: list[DataRow]
    readings: dict[tuple[str, int], str]  # (cell, sentence id) -> ok or no
    reading_rows: list[dict[str, str]]
    skipped: dict[str, str]  # cell -> reason
    skipped_rows: list[dict[str, str]]
    pin: dict[str, tuple[int, str, str]]  # a Wiktionary usage example's NFC text -> (n, page, English)
    wiktionary_version: str  # the kaikki subset's dump
    version: str  # the data file's date: the latest in its generated rows

    def credits(self) -> list[dict]:
        """The two `data_source` rows (0134, "Credits and `data_source`")."""
        return [{**WIKTIONARY_SOURCE, "version": self.wiktionary_version},
                {**GENERATED_SOURCE, "version": self.version}]


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
    return DrillData(rows, {(r["cell"], int(r["sentence_id"])): r["verdict"] for r in reading_rows}, reading_rows,
                     {r["cell"]: r["reason"] for r in skipped_rows}, skipped_rows, pin,
                     f"enwiktionary {wiktionary_version}", max(dates, default="none"))


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


def data_verdicts(data: DrillData) -> dict[tuple[str, int], str]:
    """The reading verdicts: a data row's `check` ok is its own cell's
    verdict (the second pass checked the row in that reading); the readings
    file's verdicts come on top of it."""
    own = {(r.cell, r.id): "ok" for r in data.rows if r.check == "ok"}
    return {**own, **data.readings}


def data_failures(data: DrillData, cells: dict[str, drill_cells.DrillCell], infinitives: frozenset[str],
                  sentences: set[int]) -> tuple[list[str], dict[str, list]]:
    """The form gate (0134, Checks 1) on the data files, and what is stale:
    rows, verdicts and skips of cells the drill no longer asks, and verdicts
    on sentences that are not candidates (`sentences`: every candidate id)."""
    problems, stale = [], {"rows": [], "readings": [], "skipped": []}
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
    seen = set()
    for r in data.reading_rows:
        where = f"{READINGS_FILE} {r['cell']} {r['sentence_id']}"
        if r["verdict"] not in ("ok", "no") or not r["checked_by"] or (r["cell"], r["sentence_id"]) in seen:
            problems.append(f"{where}: verdict {r['verdict']!r}, checked_by {r['checked_by']!r}, or twice")
        seen.add((r["cell"], r["sentence_id"]))
        if r["cell"] not in cells or int(r["sentence_id"]) not in sentences:
            stale["readings"].append(r)
    seen = set()
    for r in data.skipped_rows:
        if not r["reason"] or not r["checked_by"] or r["cell"] in seen:
            problems.append(f"{SKIPPED_FILE} {r['cell']}: no reason or checked_by, or twice")
        seen.add(r["cell"])
        if r["cell"] not in cells:
            stale["skipped"].append(r)
    return problems, stale


def in_scope(c: drill_cells.DrillCell) -> bool:
    """A cell of the 2.0 scope: an A1 or A2 verb, a tense up to A2."""
    return c.verb_level is not None and c.verb_level <= SCOPE[0] and c.tense_level <= SCOPE[1]


def skipped_with_rows(rows: Rows, skipped: dict[str, str]) -> list[str]:
    """The skipped cells that have a cell row, checked on the rows as stored:
    a listed cell stays without an example (kyukhin 2026-11-22)."""
    return sorted(w[1] for w in rows.words if is_cell(w[1]) and w[1] in skipped)


def open_cells(drill: Drill, skipped: dict[str, str]) -> list[str]:
    """The 2.0 coverage gate's misses: cells in scope without a sentence
    that are not listed as skipped (kyukhin 2026-11-22: a listed cell is
    done)."""
    return [c.key for c in drill.cells if in_scope(c) and c.key not in drill.rows and c.key not in skipped]


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
    if source == 0:
        shown = c.translations.get(lang) or c.translations.get("eng")
        return byline(c.author, shown[2] if shown else None)
    if source == 1:
        return "Wiktionary" if lang == "eng" else "Wiktionary · translation: LibreDict, generated"
    return "LibreDict, generated"


def list_word_share(data: DrillData, cells: dict[str, drill_cells.DrillCell], greek: GreekWords,
                    levels: dict[str, int]) -> list[tuple[float, DataRow, list[str]]]:
    """#365: each generated row's share of words that are list words up to
    its verb's level (a token that spells a term of the Greek lists, or a
    form of one), with the words that are not, lowest share first."""
    out = []
    for r in data.rows:
        if r.source != "generated" or r.cell not in cells:
            continue
        level = cells[r.cell].verb_level
        outside = []
        toks = [nfc(tok.lower()) for tok, _, _ in tokens(r.text)]
        for tok in toks:
            known = [levels[w] for w in greek.terms_of.get(tok, set()) | greek.lemmas_of.get(tok, set()) if w in levels]
            if not known or min(known) > level:
                outside.append(tok)
        out.append((1 - len(outside) / len(toks) if toks else 0.0, r, outside))
    return sorted(out, key=lambda x: (x[0], x[1].id))


def drill_section(drill: Drill, greek: Result, data: DrillData | None = None, stale: dict | None = None,
                  missing: list[str] = (), share: list[tuple[float, DataRow, list[str]]] = ()) -> list[str]:
    """#364, #365: the drill's cells, their sentences and the data files."""
    cells, rows = drill.cells, drill.rows
    skipped = data.skipped if data else {}
    stale = stale or {"rows": [], "readings": [], "skipped": []}
    reading = {key for key, _ in drill.homographs.reading}
    aspect = {key for key, _ in drill.homographs.aspect} - reading
    columns = ("Tatoeba", "Wiktionary", "Generated")

    def counts(group: list[drill_cells.DrillCell]) -> str:
        by_source = collections.Counter(source_of(rows[c.key][0]) for c in group if c.key in rows)
        n = len(group)
        covered = " | ".join(f"{by_source[i]:,} ({percent(by_source[i], n)})" if by_source[i] else "0"
                             for i in range(len(columns)))
        listed = sum(1 for c in group if c.key not in rows and c.key in skipped)
        none = n - sum(by_source.values()) - listed
        waiting = sum(1 for c in group if c.key in drill.waiting)
        return f"{n:,} | {covered} | {listed:,} | {none:,} ({percent(none, n)}) | {waiting:,}"

    header = "| " + " | ".join(("Cells",) + columns + ("Skipped", "None", "Waiting for a reading verdict")) + " |"
    rule = "|---" * (len(columns) + 4)  # the columns of `header`, without the closing bar
    out = ["## Drill cells (#364, #365)", "",
           "Every cell the conjugation drill can ask (`drill_cells.py`, a port of 0132's rules: the three Greek "
           "lists' verbs, every tense up to B2, both voices) gets one sentence that holds the cell's whole form by "
           "0134's match rule, keyed `<word>|<facet>|<person>` in `example_word`. Sources, in this order: Tatoeba "
           "(#364), Wiktionary usage examples and generated sentences from `Scripts/data/drill-examples/` (#365). "
           "\"Skipped\": cells with no natural sentence, listed in `ell-skipped.tsv`, which the 2.0 gate counts as "
           "done. \"Waiting for a reading verdict\": open cells whose found sentences hold them only through a "
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
                f"- `{READINGS_FILE}`: {len(data.reading_rows):,} verdicts; stale (no drill cell, or no candidate "
                f"sentence): {len(stale['readings']):,}",
                f"- `{SKIPPED_FILE}`: {len(skipped):,} cells, {sum(1 for c in scope if c.key in skipped):,} in the "
                f"2.0 scope; of them with a found sentence, left out: {sum(1 for k in skipped if drill.found.get(k)):,}; "
                "stale: "
                f"{len(stale['skipped']):,}",
                f"- The 2.0 scope (A1 and A2 verbs, tenses up to A2): {len(scope):,} cells; with a sentence "
                f"{sum(1 for c in scope if c.key in rows):,}, skipped "
                f"{sum(1 for c in scope if c.key not in rows and c.key in skipped):,}, open {len(missing):,}"
                + (": " + ", ".join(missing[:50]) + (" …" if len(missing) > 50 else "") if missing else ""),
                f"- The data file's date (`libredict-drill-ell`'s version): {data.version}; Wiktionary: "
                f"{data.wiktionary_version}"]

    out += ["", "### By verb list and tense level", "", "| Verbs, tenses " + header, "|---" + rule + "|"]
    for level in (1, 2, 3):
        for tense_level, name in enumerate(drill_cells.LEVELS):
            group = [c for c in cells if c.verb_level == level and c.tense_level == tense_level]
            if group:
                out.append(f"| {LEVEL_NAMES[level]} verbs, {name} tenses | {counts(group)} |")
    out.append(f"| **A1 and A2 verbs, tenses up to A2 (2.0)** | {counts([c for c in cells if in_scope(c)])} |")
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

    out += ["", "### List words in the generated rows", "",
            "The share of each generated row's words that are words of the Greek lists up to its verb's level "
            "(the term or a form of it; names and words above the level count as outside).", ""]
    buckets = (("100%", 1.0, 1.01), ("90 to 99%", 0.9, 1.0), ("75 to 89%", 0.75, 0.9), ("50 to 74%", 0.5, 0.75),
               ("below 50%", -1, 0.5))
    out += ["| Share | Rows |", "|---|---|"] + [f"| {name} | {sum(1 for s, _, _ in share if low <= s < high):,} |"
                                                for name, low, high in buckets]
    out += ["", "The 20 lowest, with the words outside the lists:", ""]
    out += [f"- {r.id} {r.cell} ({s:.0%}): {r.text} — {', '.join(words)}" for s, r, words in share[:20]]

    out += ["", f"### Skipped cells ({len(skipped):,})", "",
            "The cells with no natural sentence (kyukhin 2026-11-22), with the second pass's reason, in the 2.0 "
            "scope first.", "", "| Cell | In 2.0 | Reason |", "|---|---|---|"]
    by_key = {c.key: c for c in cells}
    for key in sorted(skipped, key=lambda k: (not (k in by_key and in_scope(by_key[k])), k)):
        out.append(f"| {cell(key)} | {'yes' if key in by_key and in_scope(by_key[key]) else 'no'} | "
                   f"{cell(skipped[key])} |")
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
    # #365: and from the data files' Wiktionary and generated rows.
    pool, cells = drill_cells.drill_cells(reader)
    infinitives = aorist_infinitives(reader)
    kaikki, dump_date = kaikki_subset()
    data = read_drill_data(DRILL_DATA, wiktionary_examples(kaikki), dump_date)
    by_key = {c.key: c for c in cells}
    extra = data_candidates(data, by_key)
    data_problems, stale = data_failures(data, by_key, infinitives, set(results[0].candidates) | set(extra))
    drill = build_drill(pool, cells, results[0].candidates, infinitives, data_verdicts(data), extra,
                        {r.id: r.cell for r in data.rows}, data.skipped)
    missing = open_cells(drill, data.skipped)
    print(f"  drill: {len(pool):,} verbs, {len(cells):,} cells, {len(drill.rows):,} with a sentence; data rows "
          f"{len(data.rows):,}, skipped cells {len(data.skipped):,}, open in 2.0 {len(missing):,}")

    word_rows = rows_of(results)
    rows = rows_of(results, drill)
    word_part, drill_part = split_rows(rows)
    word_hashes = rows_hashes(word_part)
    write_rows(writer, rows, f"export {pins[folder]['export_date']}", data.credits())
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
    listed = skipped_with_rows(rows, data.skipped)
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
        ("Drill: every cell of the 2.0 scope (A1 and A2 verbs, tenses up to A2) has a sentence or is listed as "
         "skipped, and no skipped cell has one (#365)", f"{len(missing)} open, {len(listed)} skipped with a sentence",
         "0, 0", not missing and not listed),
        ("Drill: the data files pass the form gate (0134, Checks 1; #365)", f"{len(data_problems)} problems", "0",
         not data_problems),
    ]
    failures["data files"] = data_problems
    failures["open cells"] = missing
    failures["skipped cells with a sentence"] = listed
    levels: dict[str, int] = {}
    for term, level in reader.execute("SELECT term, level_ord FROM wordlist_item WHERE series = ?", (GREEK_LISTS,)):
        levels[nfc(term)] = min(level, levels.get(nfc(term), level))
    share = list_word_share(data, by_key, greek, levels)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report(folder, pins, results, english, ambiguity, skipped, verbs, hashes, sizes, gates,
                                  list_rule, drill_section(drill, results[0], data, stale, missing, share),
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
    known = set(results[0].candidates) | set(extra)
    data_problems, stale = data_failures(data, by_key, infinitives, known)
    builds = []
    for _ in range(2):
        built = build_drill(pool, cells, results[0].candidates, infinitives, data_verdicts(data), extra,
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
    missing = open_cells(full, data.skipped)
    own_cells = {r.id: r.cell for r in data.rows}
    # A `no` verdict on a cell that is no homograph (θα σου τις γράψουμε for
    # the future εμείς), and a skipped cell that a sentence holds (g5's).
    refused = build_drill(pool, cells, results[0].candidates, infinitives,
                          {**data_verdicts(data), (g1.cell, 1001): "no"}, extra, own_cells, data.skipped)
    skipping = build_drill(pool, cells, results[0].candidates, infinitives, data_verdicts(data), extra, own_cells,
                           {**data.skipped, g5.cell: "fixture"})
    share = {r.id: (s, words) for s, r, words in list_word_share(
        data, by_key, greek, {nfc(t): level for t, level in reader.execute(
            "SELECT term, level_ord FROM wordlist_item WHERE series = ?", (GREEK_LISTS,))})}

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
    ]
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
         and g6.id not in stored),
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
         data_verdicts(data)[(g2.cell, g2.id)] == "ok"
         and data_verdicts(replace(data, readings={(g2.cell, g2.id): "no"}))[(g2.cell, g2.id)] == "no"),
        ("#365: a row comes first for its own cell, after the first form and never before Tatoeba",
         cell_order(2_000_000_009, 0, (1, 12, 9), True) < cell_order(2_000_000_001, 0, (0, 3, 1))
         and cell_order(1_000_000_009, 1, (0, 3, 9), True) > cell_order(1_000_000_001, 0, (1, 12, 1))
         and cell_order(5, 1, (1, 0, 1, 5)) < cell_order(1_000_000_001, 0, (0, 3, 1), True)),
        ("#365: sources by id range", (source_of(999_999_999), source_of(1_000_000_001), source_of(2_000_000_001))
         == (0, 1, 2) and all(source_of(sid) == 0 or sid in extra for sid in stored)),
        ("#365: the 2.0 gate counts a skipped cell as done, fails on any other open cell, and asks only the scope",
         "έχω|subjunctiveSimple.active|3sg" not in missing and "έχω|subjunctiveSimple.active|2sg" in missing
         and all(in_scope(by_key[k]) for k in missing) and "γράφω|imperfect.active|1sg" not in missing
         and not open_cells(full, {**data.skipped, **dict.fromkeys(missing, "x")})),
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
