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
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputs  # noqa: E402
from build_greek import normalize_greek  # noqa: E402  (the one Greek folding, #87)

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
ENGLISH_LISTS = "cefr-eng"

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
SIZE_BUDGET = 10_000_000  # bytes, the three tables of every file together
SAMPLES = {"ell": ("γράφω", "είμαι", "σπίτι", "καλός", "μέρα"), "eng": ("go", "house", "write", "good")}

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

class GreekWords:
    """The Greek forms and headwords (spec, Pipeline step 4)."""

    def __init__(self, reader: sqlite3.Connection):
        self.lemmas_of: dict[str, set[str]] = collections.defaultdict(set)  # lowercase NFC form -> lemma words
        queries = (
            "SELECT word, word FROM lemma WHERE lang = 'ell'",
            "SELECT p.form, l.word FROM paradigm p JOIN lemma l ON l.id = p.lemma_id WHERE l.lang = 'ell'",
            "SELECT f.form, l.word FROM form_link f JOIN lemma l ON l.id = f.lemma_id WHERE l.lang = 'ell'",
        )
        for sql in queries:
            for form, word in reader.execute(sql):
                self.lemmas_of[nfc(form.lower())].add(nfc(word))
        self.headwords = {nfc(word) for (word,) in reader.execute(
            f"SELECT word FROM entries WHERE source IN ({','.join('?' * len(GREEK_DICTIONARIES))})",
            GREEK_DICTIONARIES)}

    def keys(self, token: str) -> set[str]:
        """The lemmas the token is a cell, the word or a link page of, and the
        token itself, as written or lowercased, when it is a headword."""
        lower = nfc(token.lower())
        keys = set(self.lemmas_of.get(lower, ()))
        keys.update(w for w in (token, lower) if w in self.headwords)
        return {word_key(k) for k in keys}


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


def choose(occurrences: list[tuple[tuple, int, int, int, str]], limit: int = PER_WORD) -> list:
    """Up to `limit` occurrences (rank, sid, start, length, form): one
    sentence per new form first, then the rest, each in rank order."""
    best: dict[str, tuple] = {}
    for o in occurrences:
        if o[4] not in best or o[0] < best[o[4]][0]:
            best[o[4]] = o
    chosen = sorted(best.values())[:limit]
    if len(chosen) < limit:
        taken = {o[1] for o in chosen}
        rest = [o for o in heapq.nsmallest(limit + len(chosen), occurrences) if o[1] not in taken]
        chosen += rest[:limit - len(chosen)]
    return chosen


def build_language(lang: str, subset: Subset, keys_of: Callable[[str], Iterable[str]]) -> Result:
    """Spec, Pipeline steps 1 to 5 for the sentences of one language."""
    result = candidates(lang, subset)
    result.occurrences, result.words = index(result, keys_of)
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


def index(result: Result, keys_of: Callable[[str], Iterable[str]]) -> tuple[dict[str, int], dict[str, list]]:
    """Steps 4 and 5: every key's candidate count and its chosen examples
    (sentence id, form start, form length, form). A sentence counts once per
    key, highlighted at its first token that gives the key."""
    found: dict[str, list] = collections.defaultdict(list)
    for c in result.candidates.values():
        seen = set()
        for tok, start, length in c.tokens:
            for key in keys_of(tok):
                if key not in seen:
                    seen.add(key)
                    found[key].append((c.rank, c.id, start, length, nfc(tok.lower())))
    return ({key: len(occ) for key, occ in found.items()},
            {key: [(o[1], o[2], o[3], o[4]) for o in choose(found[key])] for key in sorted(found)})


@dataclass
class Rows:
    sentences: list[tuple]
    translations: list[tuple]
    words: list[tuple]


def rows_of(results: list[Result]) -> Rows:
    """The three tables' rows, sorted by their keys."""
    sentences, translations, words = [], [], []
    for r in results:
        used = set()
        for key, chosen in r.words.items():
            for order, (sid, start, length, _) in enumerate(chosen, 1):
                words.append((r.lang, key, order, sid, start, length))
                used.add(sid)
        for sid in used:
            c = r.candidates[sid]
            sentences.append((sid, r.lang, c.text, c.author))
            translations += [(sid, tl, tid, text, author) for tl, (tid, text, author) in c.translations.items()]
    return Rows(sorted(sentences), sorted(translations, key=lambda t: (t[0], t[1])), sorted(words))


def write_rows(conn: sqlite3.Connection, rows: Rows, version: str) -> None:
    with conn:
        conn.executemany("INSERT INTO example_sentence(id, lang, text, author) VALUES (?, ?, ?, ?)", rows.sentences)
        conn.executemany("INSERT INTO example_translation(sentence_id, lang, id, text, author) "
                         "VALUES (?, ?, ?, ?, ?)", rows.translations)
        conn.executemany("INSERT INTO example_word(lang, word, ord, sentence_id, form_start, form_length) "
                         "VALUES (?, ?, ?, ?, ?, ?)", rows.words)
        conn.execute("INSERT INTO data_source(id, kind, display_name, version, license, url) "
                     "VALUES (:id, :kind, :display_name, :version, :license, :url)",
                     {**DATA_SOURCE, "version": version})


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


def report(folder: str, pins: dict, results: list[Result], english: EnglishWords,
           ambiguity: list[tuple], skipped: collections.Counter, verbs: dict, hashes: dict, sizes: dict,
           gates: list) -> str:
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

    out += ["## Blocking tags hit", "", "Sentences and translations each tag kept out."]
    for r in results:
        out += ["", f"- {'Greek' if r.lang == 'ell' else 'English'}: " + ", ".join(
            f"{tag} ({n:,})" for tag, n in sorted(r.tag_hits.items(), key=lambda x: (-x[1], x[0])))]

    out += ["", "## Size and table hashes", "", "| Table | Rows | sha256 of the rows in key order |", "|---|---|---|"]
    out += [f"| `{t}` | {hashes[t][0]:,} | `{hashes[t][1]}` |" for t in TABLES]
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
    results = [build_language("ell", subsets["ell"], greek.keys),
               build_language("eng", subsets["eng"], english.keys)]
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

    rows = rows_of(results)
    write_rows(writer, rows, f"export {pins[folder]['export_date']}")
    hashes = table_hashes(writer)
    try:
        sizes = {"all": shipped_size(rows), "Greek (ell pack)": shipped_size(rows, "ell"),
                 "English (eng-lists pack)": shipped_size(rows, "eng")}
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
    total = sum(sizes["all"][0].values())
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
        ("Example tables of all files", f"{total / 1e6:.2f} MB", f"≤ {SIZE_BUDGET / 1e6:.0f} MB",
         total <= SIZE_BUDGET),
        ("Every translation and word row points at a stored sentence", f"{len(failures['references'])} problems",
         "0", not failures["references"]),
    ]
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report(folder, pins, results, english, ambiguity, skipped, verbs, hashes, sizes, gates),
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


def fixture_reader(folder: Path) -> sqlite3.Connection:
    """An in-memory file with the tables the step reads, filled from the
    fixture's `lexicon.tsv`: `lemma` (word, pos, cells), `link` (page,
    lemma), `headword`, `exception` (form, pos, base), `morphy` (word,
    pos_mask) and `list` (term) lines."""
    from build_dictionaries import SCHEMA as CORE_SCHEMA
    import build_forms
    import build_morphy
    import build_wordlists
    conn = sqlite3.connect(":memory:")
    conn.executescript(CORE_SCHEMA)
    conn.executescript(build_forms.SCHEMA)
    conn.executescript(build_morphy.SCHEMA)
    conn.executescript(build_wordlists.SCHEMA)
    lemma_ids = {}
    for fields in read_lines(folder / "lexicon.tsv"):
        kind, rest = fields[0], fields[1:]
        if kind == "lemma":
            word, pos, cells = rest
            i = lemma_ids.setdefault((word, pos), len(lemma_ids) + 1)
            conn.execute("INSERT INTO lemma(id, lang, word, word_normalized, pos) VALUES (?, 'ell', ?, ?, ?)",
                         (i, word, normalize_greek(word), pos))
            for order, form in enumerate(cells.split(","), 1):
                conn.execute("INSERT INTO paradigm(lemma_id, ord, form, tagset_id) VALUES (?, ?, ?, 1)",
                             (i, order, form))
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
            conn.execute("INSERT INTO wordlist_item(series, term, seq, sort_key) VALUES (?, ?, 0, ?)",
                         (ENGLISH_LISTS, rest[0], rest[0]))
        else:
            raise RuntimeError(f"lexicon.tsv: unknown line kind {kind!r}")
    return conn


def self_check() -> int:
    """Build the fixture twice, compare the table hashes, check the cases."""
    reader = fixture_reader(FIXTURE)
    greek, english = GreekWords(reader), EnglishWords(reader)
    subsets = {lang: read_subset({part: FIXTURE / f"{lang}-{part}.tsv" for part in PARTS}) for lang in SUBSETS}
    runs = []
    for _ in range(2):
        results = [build_language("ell", subsets["ell"], greek.keys),
                   build_language("eng", subsets["eng"], english.keys)]
        rows = rows_of(results)
        conn = new_database(":memory:")
        write_rows(conn, rows, "self-check")
        runs.append((results, rows, conn, table_hashes(conn)))
    results, rows, conn, hashes = runs[0]
    assert hashes == runs[1][3], "two builds of the fixture differ"
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

    def chosen(occurrences: list[tuple[int, str]]) -> list[int]:
        """The ids `choose` keeps of (rank, form) occurrences, given in
        reverse rank order; the id is 100 + rank."""
        return [o[1] for o in choose([((r,), 100 + r, 0, 1, f) for r, f in reversed(occurrences)])]

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
        ("choice: then the rest in rank order, each sentence once",
         chosen([(1, "x"), (2, "x"), (3, "x"), (4, "x"), (5, "x"), (6, "x"), (7, "y")]) == [101, 107, 102, 103, 104]
         and chosen([(1, "x"), (2, "x")]) == [101, 102]),
        ("the verb gate: 85% of all 500 verbs with 3+", verb_gate(verbs, passing) == (425, True)
         and verb_gate(verbs, {**passing, verbs[424]: 2}) == (424, False)
         and verb_gate(verbs[:-1], passing)[1] is False),
        ("the data_source row", conn.execute("SELECT id, kind, license, url FROM data_source").fetchall()
         == [("tatoeba", "example_sentences", "CC BY 2.0 FR", "https://tatoeba.org")]),
    ]
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    for gate, problems in failures.items():
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
