#!/usr/bin/env python3
"""
build_forms.py
Greek word forms from Wiktionary, a static data step of
`build_dictionaries.py` (docs/specs/0136-word-forms.md, "Pipeline: Greek
forms (#141)"). It fills `lemma`, `tagset`, `paradigm` and `form_lookup` and
the forms' `data_source` row, reads `entries` only, and writes the QA report
`Scripts/reports/forms-qa.md`. Its QA gates raise, so a failing gate fails
the dictionary build.

Input: the Greek lines (`lang_code` el) of kaikki.org's raw Wiktextract dump
of the English Wiktionary. kaikki.org keeps only its latest dump, so the
filtered subset `Scripts/data/kaikki-el-<date>.jsonl.gz` (Git LFS) is the pin:
`inputs.json` records it with its sha256 and the dump's URL, date and sha256,
and the step checks it before use. The step works offline; only the
frequency list of the QA report is downloaded (pinned, to the cache).

Usage (from the repository root):
    python3 Scripts/build_forms.py --self-check
        offline, on Scripts/fixtures/kaikki-el-sample.jsonl: builds twice,
        compares the table hashes and checks the spec's cases
    python3 Scripts/build_forms.py --standalone out.sqlite \\
            --headwords DictApp/DictApp/Resources/dictionaries.sqlite
        the step alone, into its own file, with the QA report
    python3 Scripts/build_forms.py --refresh
        streams the current dump (about 3 GB), writes a new dated subset and
        its inputs.json entry; a refresh is a reviewed PR of its own
    python3 Scripts/build_forms.py --make-fixture
        rewrites the self-check fixture from the pinned subset
"""

from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import io
import json
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputs  # noqa: E402
from build_greek import normalize_greek  # noqa: E402  (the one Greek folding, #87)

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO = SCRIPTS_DIR.parent
REPORT = SCRIPTS_DIR / "reports" / "forms-qa.md"
FIXTURE = SCRIPTS_DIR / "fixtures" / "kaikki-el-sample.jsonl"
ALLOWLIST = SCRIPTS_DIR / "data" / "forms-allowlist.tsv"

DUMP_URL = "https://kaikki.org/dictionary/raw-wiktextract-data.jsonl.gz"
DUMP_PAGE = "https://kaikki.org/dictionary/rawdata.html"
SUBSET_PREFIX = "Scripts/data/kaikki-el-"
# hermitdave/FrequencyWords, OpenSubtitles 2018 (CC BY-SA 4.0): a QA input
# only, never shipped.
FREQUENCY_KEY = "frequencywords/el_50k.txt"

LANG = "ell"
GREEK_DICTIONARIES = ("freedict-ell-eng", "wordnet-ell-eng")
DATA_SOURCE = {
    "id": "wiktionary-ell-forms",
    "kind": "word_forms",
    "display_name": "Wiktionary (Greek word forms)",
    "license": "CC BY-SA 4.0",
    "url": "https://kaikki.org/dictionary/",
}

# Gates (spec, "Coverage metric"): `build()` raises below them.
GATE_VERBS = 0.95
GATE_NOUNS = 0.90
GATE_FINDABLE = 0.87
SIZE_BUDGET = 25_000_000  # bytes, the forms tables with their indexes
TOP_LEMMAS = 500
TOP_TOKENS = 5_000

SCHEMA = """
-- Greek word forms (#141). A lemma's text key is (lang, word, pos); user
-- data never stores lemma.id.
CREATE TABLE lemma (
    id              INTEGER PRIMARY KEY,
    lang            TEXT NOT NULL,
    word            TEXT NOT NULL,   -- NFC
    word_normalized TEXT NOT NULL,   -- build_greek.normalize_greek(word)
    pos             TEXT NOT NULL,   -- Wiktextract POS
    UNIQUE (lang, word, pos)
);
CREATE INDEX idx_lemma_word_normalized ON lemma(word_normalized);

-- Wiktextract tags, sorted and space-separated.
CREATE TABLE tagset (
    id   INTEGER PRIMARY KEY,
    tags TEXT NOT NULL UNIQUE
);

-- Inflection table cells in table order.
CREATE TABLE paradigm (
    lemma_id  INTEGER NOT NULL,
    ord       INTEGER NOT NULL,
    form      TEXT    NOT NULL,   -- NFC, one word
    tagset_id INTEGER NOT NULL,
    PRIMARY KEY (lemma_id, ord)
) WITHOUT ROWID;

-- Folded form -> lemma. Every lookup uses the primary-key prefix form_norm.
CREATE TABLE form_lookup (
    form_norm TEXT    NOT NULL,
    lemma_id  INTEGER NOT NULL,
    tagset_id INTEGER NOT NULL,   -- the first cell in table order with this key
    PRIMARY KEY (form_norm, lemma_id)
) WITHOUT ROWID;
"""
TABLES = ("lemma", "tagset", "paradigm", "form_lookup")
KEY_ORDER = {"lemma": "id", "tagset": "id", "paradigm": "lemma_id, ord",
             "form_lookup": "form_norm, lemma_id"}


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

# Table rows that carry no form.
META_TAGS = frozenset({"romanization", "table-tags", "inflection-template", "class"})
OPEN_POS = frozenset({"verb", "noun", "adj", "adv"})
PERSONS = frozenset({"first-person", "second-person", "third-person"})
CASES = frozenset({"nominative", "genitive", "accusative", "vocative"})
# Hidden from tables (#144) but searchable.
HIDDEN = frozenset({"rare", "archaic", "dated"})

# A one-word cell can carry a note: a trailing parenthesised remark, nested
# once at most (`κάνω (κάμνω →)`, `σκέφτομαι (→ σκέπτομαι (sképtomai))`), or
# footnote marks (`έμπαινε²`, `θέλουν² (θένε)`). Both are stripped before the
# one-word test; a cell that is only a note (`(κακίστρες (kakístres))`) stays
# multi-word.
CELL_NOTE = re.compile(r"(?<=\S)\s*\((?:[^()]|\([^()]*\))*\)$")
FOOTNOTE_MARKS = re.compile(r"[⁰¹²³⁴⁵⁶⁷⁸⁹⁺]+$")
# Contracted verbs give both conjugations in one cell: `θυμάμαι - θυμούμαι`,
# `οδηγώ - οδηγάω`. Each variant is a cell of its own.
VARIANT_SEPARATOR = " - "

# Spelling no Greek word has, left by template errors: two accents
# (`γόνιμός`, `εκστρατεύόμαστε`) or a final sigma inside the word
# (`άφυλλοςος`, the whole word given as the stem). Accents are the acute
# (tonos), grave and circumflex; breathings and the diaeresis are not.
ACCENT_MARKS = frozenset("\u0301\u0300\u0342")

# A link's aspect, when its tags have none, comes from its gloss: "first-person
# singular simple past of μεταθέτω" is perfective (#142 captions it as aorist).
ASPECTS = frozenset({"perfective", "imperfective"})

# Closed-class words Wiktionary tables sometimes carry as junk cells (the
# article ο in καλύπτω's table). Compared exactly: NFC and lowercase, never
# folded, which would also block κάνεις → κάνω (κανείς).
STOPLIST = frozenset("""
    ο η το οι τα του της των τον την τη τους τις ένας μία μια ένα ενός μιας έναν
    και κι αν όταν είτε ή ότι πως που αλλά μα ενώ ούτε ουδέ όμως γιατί επειδή αφού ώστε μήπως
    να θα ας δεν δε μην μη
    σε στο στη στην στον στα στους στις στου στης με για από προς χωρίς κατά μετά παρά ως ώς
    μου σου μας σας εγώ εσύ εμείς εσείς
    """.split())

# Pages without form-of markup: "first-person singular dependent active of
# πηγαίνω and πάω". The description must name a grammatical category.
GREEK_LETTER = "Ͱ-Ͽἀ-῿"
GLOSS_RE = re.compile(
    rf"^(?P<desc>[a-z][a-z \-/,]*?) (?:form )?of "
    rf"(?P<targets>[{GREEK_LETTER}][^\s(),:]*(?: \([^)]*\))?"
    rf"(?: (?:and|or) [{GREEK_LETTER}][^\s(),:]*(?: \([^)]*\))?)*)")
GRAMMAR_WORD = re.compile(
    r"person|singular|plural|present|past|imperfect|aorist|dependent|imperative|participle|"
    r"genitive|accusative|vocative|nominative|feminine|neuter|masculine|comparative|"
    r"superlative|alternative|passive|active|perfective|imperfective|subjunctive|future|"
    r"infinitive|diminutive|spelling|form")
# A sense about a periphrastic form ("θα κάνεις: second-person singular
# perfective future of κάνω") is a "… of X" gloss of a multi-word form.
PERIPHRASTIC = ("θα ", "να ")
# Gloss words → Wiktextract tags; other words are dropped.
GLOSS_TAGS = {word: (word,) for word in (
    "first-person", "second-person", "third-person", "singular", "plural",
    "nominative", "genitive", "accusative", "vocative", "masculine", "feminine", "neuter",
    "present", "past", "perfective", "imperfective", "dependent", "indicative",
    "imperative", "subjunctive", "participle", "infinitive", "nonfinite",
    "active", "passive", "comparative", "superlative", "diminutive", "alternative")}
GLOSS_TAGS.update({
    "imperfect": ("imperfect", "imperfective"),   # as the tables tag it
    "aorist": ("past", "perfective"),
    "simple": ("perfective",),                    # simple past = aorist
    "perfect": ("past",),                         # perfect participle: γραμμένος
    "mediopassive": ("passive",),
    "spelling": ("alternative",),
})


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def is_greek_word(s: str) -> bool:
    """One word of Greek letters (with their accents), nothing else."""
    if not s:
        return False
    for ch in unicodedata.normalize("NFD", s):
        category = unicodedata.category(ch)
        if category == "Mn":
            continue
        cp = ord(ch)
        if not (0x0370 <= cp <= 0x03FF or 0x1F00 <= cp <= 0x1FFF) or not category.startswith("L"):
            return False
    return True


def letters(s: str) -> str:
    """`s` folded to bare lowercase letters: `normalize_greek`, then every
    combining mark dropped (also the ones it keeps, such as a caron)."""
    return "".join(ch for ch in unicodedata.normalize("NFD", normalize_greek(s))
                   if unicodedata.category(ch) != "Mn")


def misspelling(form: str) -> str | None:
    """Why `form` cannot be a Greek word, or None."""
    if sum(ch in ACCENT_MARKS for ch in unicodedata.normalize("NFD", form)) > 1:
        return "two accents"
    if "ς" in form[:-1]:
        return "final sigma inside the word"
    return None


def strip_note(form: str) -> str:
    return FOOTNOTE_MARKS.sub("", CELL_NOTE.sub("", form))


def gloss_tags(desc: str) -> tuple:
    return tuple(sorted({tag for word in re.split(r"[ /,]+", desc) for tag in GLOSS_TAGS.get(word, ())}))


def read_allowlist(path: Path = ALLOWLIST) -> set[tuple[str, str, str]]:
    """`form<TAB>lemma<TAB>pos` lines; `#` starts a comment."""
    entries = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            form, lemma, pos = (nfc(part.strip()) for part in line.split("\t"))
            entries.add((form, lemma, pos))
    return entries


# ---------------------------------------------------------------------------
# The step
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Link:
    form: str     # the page's word
    pos: str      # the page's POS
    target: str
    tags: tuple
    kind: str     # form_of, alt_of, gloss


class Forms:
    """The forms tables in memory, with what every rule caught."""

    def __init__(self):
        self.pages = self.lemma_pages = self.form_pages = 0
        self.junk = collections.Counter()
        self.samples = collections.defaultdict(list)   # rule -> examples
        self.stop_hits: list[str] = []
        self.other_tables: list[str] = []              # tables declined from another word
        self.bare_endings: list[str] = []
        self.allow_uses: list[str] = []
        self.allowed: set[tuple] = set()               # the allowlist entries used
        self.unresolved = collections.Counter()
        self.link_kinds = collections.Counter()
        self.link_aspects = 0                          # links whose aspect comes from the gloss
        self.lemmas: list[tuple] = []                  # (id, word, word_normalized, pos)
        self.cells: dict[int, list[tuple]] = {}        # lemma id -> [(form, tags)]
        self.lookup: dict[tuple, tuple] = {}           # (form_norm, lemma id) -> (rank, tags)
        self.link_forms: list[tuple] = []              # (form, lemma id) of the kept links

    def catch(self, rule: str, example: str, keep: int = 20) -> None:
        self.junk[rule] += 1
        if len(self.samples[rule]) < keep:
            self.samples[rule].append(example)


def table_cells(entry: dict, forms: Forms, word: str) -> list[tuple]:
    """The entry's table cells (forms with a `source`) that pass the
    per-cell rules, in table order."""
    cells = []
    for item in entry.get("forms", []):
        if not item.get("source"):
            continue  # head-template forms: the table has them
        tags = tuple(sorted(set(item.get("tags", []))))
        if META_TAGS & set(tags):
            continue
        raw = nfc(item.get("form", "").strip())
        variants = [part.strip() for part in raw.split(VARIANT_SEPARATOR)]
        if len(variants) > 1 and any(is_greek_word(strip_note(part)) for part in variants):
            forms.catch("cell split into its ' - ' variants (kept)", f"{raw}@{word}")
        else:
            variants = [raw]
        for form in variants:
            bare = strip_note(form)
            if bare != form and is_greek_word(bare):
                forms.catch("note or footnote mark stripped (kept)", f"{form}@{word}")
                form = bare
            if any(ch.isspace() for ch in form):
                forms.catch("multi-word cell", f"{form}@{word}")
            elif not is_greek_word(form):
                forms.catch("placeholder or non-Greek cell", f"{form}@{word}")
            elif reason := misspelling(form):
                forms.catch(f"misspelt cell: {reason}", f"{form}@{word}")
            elif any(tag.startswith("error-") for tag in tags):
                forms.catch("cell tagged error-*", f"{form}@{word}")
            elif "future" in tags:
                forms.catch("single-word future cell", f"{form}@{word}")
            else:
                cells.append((form, tags))
    return cells


def sense_links(entry: dict, word: str, pos: str, forms: Forms) -> tuple[list[Link], bool]:
    """The links of every sense, and whether the entry is a lemma page (a
    sense without form-of or alt-of markup and without a "… of X" gloss)."""
    links, is_lemma = [], False
    for sense in entry.get("senses", []):
        tags = tuple(sorted(set(sense.get("tags", [])) - {"form-of", "alt-of"}))
        gloss = (sense.get("glosses") or [""])[0]
        if sense.get("form_of") or sense.get("alt_of"):
            # The cell rules for markup links: `error-*` (γάτος → γάτα) and a
            # single-word `future` (πέρδεσαι, "present/future of πέρδομαι").
            if any(tag.startswith("error-") for tag in tags) or "future" in tags:
                forms.catch("link tagged error-* or future", f"{word} → {gloss[:60]}")
                continue
            found = GLOSS_RE.match(gloss)
            aspect = ASPECTS & set(gloss_tags(found.group("desc"))) if found else set()
            if ASPECTS & set(tags) or len(aspect) != 1:
                aspect = set()
            tags = tuple(sorted(set(tags) | aspect))
        targets = [(t, tags, "form_of") for t in sense.get("form_of") or []]
        targets += [(t, tuple(sorted(set(tags) | {"alternative"})), "alt_of")
                    for t in sense.get("alt_of") or []]
        if targets:
            found_links = [Link(word, pos, nfc(t["word"]), tg, kind) for t, tg, kind in targets if t.get("word")]
            forms.link_aspects += len(found_links) if aspect else 0
            links += found_links
            continue
        if gloss.startswith(PERIPHRASTIC):
            continue  # "θα κάνεις: … future of κάνω": a multi-word form, no link
        found = GLOSS_RE.match(gloss)
        if found and GRAMMAR_WORD.search(found.group("desc")):
            for target in re.split(r" (?:and|or) ", found.group("targets")):
                links.append(Link(word, pos, nfc(target.split(" (")[0]), gloss_tags(found.group("desc")), "gloss"))
            continue
        is_lemma = True
    return links, is_lemma


def stopped(form: str, lemma_word: str, lemma_pos: str) -> bool:
    return (lemma_pos in OPEN_POS and form.lower() in STOPLIST
            and form.lower() != lemma_word.lower())


def stem(word: str) -> str:
    """The headword's letters without its ending, as the table checks use
    it: without the last two letters, or the last four in -μαι (θυμάμαι →
    θυμ). Too short a headword gives an empty stem, which every cell has."""
    folded = letters(word)
    return folded[:-4] if folded.endswith("μαι") else folded[:-2]


def another_words_table(word: str, cells: list[tuple]) -> bool:
    """Step 3: no cell is the headword or begins with its stem. Wiktionary
    declined another word there (κρεατομηχανή holds μηχανή's forms) or
    gave the template no stem (αισώπειος holds ος, α, ου). A suppletive
    table keeps its headword (βλέπω holds βλέπω and είδα, δω)."""
    head, start = letters(word), stem(word)
    return all(letters(form) != head and not letters(form).startswith(start) for form, _ in cells)


def slot_endings(tables) -> set[tuple]:
    """(tags, ending): what follows the stem in the cells of the tables
    ((headword, cells) pairs), slot by slot (γραφόμαστε gives όμαστε)."""
    endings = set()
    for word, cells in tables:
        head, start = letters(word), stem(word)
        for form, tags in cells:
            folded = letters(form)
            shared = len(os.path.commonprefix([head, folded]))
            if shared >= max(len(start), 2) and len(folded) > shared:
                endings.add((tags, folded[shared:]))
    return endings


def bare_ending(form: str, tags: tuple, word: str, endings: set) -> bool:
    """Step 3: the cell is only the ending that other tables give the same
    slot, and does not begin like its headword (σαλπάρω: όμαστε, ούν). Not
    checked for a stem of one letter or none, whose forms are almost
    endings themselves (είμαι: όντας)."""
    folded = letters(form)
    return (len(stem(word)) >= 2 and folded[:1] != letters(word)[:1]
            and (tags, folded) in endings)


def collect(lines, allowlist: set) -> Forms:
    """Steps 1 to 6 of the spec on the subset's lines, in memory."""
    forms = Forms()
    pages: dict[tuple, list] = {}  # (word, pos) of lemma pages -> their entries
    links: list[Link] = []
    for raw in lines:
        entry = json.loads(raw)
        if entry.get("lang_code") != "el":
            continue
        forms.pages += 1
        word, pos = nfc(entry.get("word", "")), entry.get("pos", "")
        page_links, is_lemma = sense_links(entry, word, pos, forms)
        links += page_links
        if is_lemma:
            forms.lemma_pages += 1
            pages.setdefault((word, pos), []).append(entry)
        else:
            forms.form_pages += 1

    # 1. Lemmas: one per (word, pos), ids in (word, pos) order.
    lemma_ids: dict[str, list[tuple]] = collections.defaultdict(list)  # word -> [(pos, id)]
    lemma_info: dict[int, tuple] = {}
    tables: dict[int, list[tuple]] = {}
    for word, pos in sorted(pages):
        if not is_greek_word(word):
            forms.catch("multi-word or non-Greek lemma", f"{word}/{pos}")
            continue
        lemma_id = len(forms.lemmas) + 1
        forms.lemmas.append((lemma_id, word, normalize_greek(word), pos))
        lemma_ids[word].append((pos, lemma_id))
        lemma_info[lemma_id] = (word, pos)

        # 2-3. Cells, the pronoun template guard, tables of another word.
        cells = [cell for entry in pages[(word, pos)] for cell in table_cells(entry, forms, word)]
        if pos == "pron" and len(PERSONS & {t for _, tags in cells for t in tags}) > 1:
            for form, _ in cells:
                forms.catch("cell of a pronoun table that mixes persons", f"{form}@{word}")
            cells = []
        if cells and another_words_table(word, cells):
            forms.other_tables.append(f"{word} ({pos}): {cells[0][0]}, …")
            forms.junk["cell of a table declined from another word"] += len(set(cells))
            cells = []
        tables[lemma_id] = cells

    # 5. Repeats, the stoplist; 3. bare endings, against the endings of
    # every table; 6. lookup rows.
    endings = slot_endings((lemma_info[i][0], cells) for i, cells in tables.items())
    for lemma_id, cells in tables.items():
        word, pos = lemma_info[lemma_id]
        kept, seen = [], set()
        for form, tags in cells:
            if (form, tags) in seen:
                continue
            seen.add((form, tags))
            if stopped(form, word, pos):
                if (form, word, pos) in allowlist:
                    forms.allowed.add((form, word, pos))
                    forms.allow_uses.append(f"{form} in the table of {word} ({pos})")
                else:
                    forms.stop_hits.append(f"{form} in the table of {word} ({pos})")
                    forms.junk["stoplisted form"] += 1
                    continue
            elif bare_ending(form, tags, word, endings):
                forms.bare_endings.append(f"{form}@{word}")
                forms.junk["bare ending"] += 1
                continue
            kept.append((form, tags))
        forms.cells[lemma_id] = kept
        for order, (form, tags) in enumerate(kept, 1):
            key = (normalize_greek(form), lemma_id)
            if key not in forms.lookup:
                forms.lookup[key] = ((0, order), tags)
        # 6. The head form, when no cell has its key.
        forms.lookup.setdefault((normalize_greek(word), lemma_id), ((2, 0), ()))

    # 4. Links, following form pages for up to 2 steps.
    targets_of: dict[str, list[str]] = collections.defaultdict(list)
    for link in links:
        if link.target not in targets_of[link.form]:
            targets_of[link.form].append(link.target)

    def resolve(target: str, depth: int = 0) -> list[str]:
        if target in lemma_ids:
            return [target]
        if depth >= 2:
            return []
        found = []
        for step in targets_of.get(target, ()):
            found += [w for w in resolve(step, depth + 1) if w not in found]
        return found

    for index, link in enumerate(links):
        forms.link_kinds[link.kind] += 1
        if not is_greek_word(link.form):
            forms.catch("link from a multi-word or non-Greek page", f"{link.form} → {link.target}")
            continue
        candidates = [c for w in resolve(link.target) for c in lemma_ids[w]]
        if not candidates:
            forms.unresolved[link.target] += 1
            continue
        chosen = [i for p, i in candidates if p == link.pos] or [i for _, i in candidates]
        for lemma_id in chosen:
            word, pos = lemma_info[lemma_id]
            if stopped(link.form, word, pos):
                if (link.form, word, pos) in allowlist:
                    forms.allowed.add((link.form, word, pos))
                    forms.allow_uses.append(f"{link.form} → {word} ({pos}, {link.kind})")
                else:
                    forms.stop_hits.append(f"{link.form} → {word} ({pos}, {link.kind})")
                    forms.junk["stoplisted form"] += 1
                    continue
            forms.link_forms.append((link.form, lemma_id))
            key = (normalize_greek(link.form), lemma_id)
            if key not in forms.lookup or forms.lookup[key][0] > (1, index):
                forms.lookup[key] = ((1, index), link.tags)
    return forms


def write_tables(conn: sqlite3.Connection, forms: Forms, version: str) -> None:
    """Step 7: the tables in key order, plus the data_source row."""
    tag_strings = sorted({" ".join(tags) for cells in forms.cells.values() for _, tags in cells}
                         | {" ".join(tags) for _, tags in forms.lookup.values()})
    tagset_id = {tags: i for i, tags in enumerate(tag_strings, 1)}
    with conn:
        conn.executemany("INSERT INTO tagset(id, tags) VALUES (?, ?)",
                         [(i, tags) for tags, i in tagset_id.items()])
        conn.executemany("INSERT INTO lemma(id, lang, word, word_normalized, pos) VALUES (?, ?, ?, ?, ?)",
                         [(i, LANG, word, norm, pos) for i, word, norm, pos in forms.lemmas])
        conn.executemany("INSERT INTO paradigm(lemma_id, ord, form, tagset_id) VALUES (?, ?, ?, ?)",
                         [(i, order, form, tagset_id[" ".join(tags)])
                          for i in sorted(forms.cells)
                          for order, (form, tags) in enumerate(forms.cells[i], 1)])
        conn.executemany("INSERT INTO form_lookup(form_norm, lemma_id, tagset_id) VALUES (?, ?, ?)",
                         [(norm, i, tagset_id[" ".join(tags)])
                          for (norm, i), (_, tags) in sorted(forms.lookup.items())])
        conn.execute("INSERT INTO data_source(id, kind, display_name, version, license, url) "
                     "VALUES (:id, :kind, :display_name, :version, :license, :url)",
                     {**DATA_SOURCE, "version": version})


def table_hashes(conn: sqlite3.Connection) -> dict[str, tuple[int, str]]:
    """Rows and the sha256 of each forms table's rows in key order."""
    result = {}
    for table in TABLES:
        digest, rows = hashlib.sha256(), 0
        for row in conn.execute(f"SELECT * FROM {table} ORDER BY {KEY_ORDER[table]}"):
            digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")
            rows += 1
        result[table] = (rows, digest.hexdigest())
    return result


def table_size(conn: sqlite3.Connection) -> dict[str, int]:
    """Bytes per forms table with its indexes (dbstat)."""
    sizes = dict.fromkeys(TABLES, 0)
    for table, size in conn.execute(f"""
            SELECT m.tbl_name, SUM(d.pgsize) FROM dbstat AS d JOIN sqlite_master AS m ON m.name = d.name
            WHERE m.tbl_name IN ({",".join("?" * len(TABLES))}) GROUP BY m.tbl_name""", TABLES):
        sizes[table] = size
    return sizes


def shipped_size(conn: sqlite3.Connection) -> dict[str, int]:
    """`table_size` as the file ships. The build VACUUMs last, which packs
    the pages; measured on a `VACUUM INTO` copy, so the gate sees that."""
    with tempfile.TemporaryDirectory() as folder:
        copy = Path(folder) / "sizing.sqlite"
        conn.execute("VACUUM INTO ?", (str(copy),))
        sizing = sqlite3.connect(copy)
        try:
            return table_size(sizing)
        finally:
            sizing.close()


# ---------------------------------------------------------------------------
# QA: coverage, findability, report, gates
# ---------------------------------------------------------------------------

def has_table(pos: str, cells: list[tuple]) -> bool:
    """What a learner sees as a table: a verb with a finite cell, or a noun or
    adjective with two case cells. Hidden (rare, archaic, dated) cells do
    not count."""
    shown = [set(tags) for _, tags in cells if not HIDDEN & set(tags)]
    if pos == "verb":
        return any(PERSONS & tags and "participle" not in tags for tags in shown)
    return sum(1 for tags in shown if CASES & tags) >= 2


def coverage(forms: Forms, headwords: set[str], frequency: list[tuple[str, int]]) -> dict:
    lemma = {i: (word, norm, pos) for i, word, norm, pos in forms.lemmas}
    by_norm = collections.defaultdict(set)
    for i, (_, norm, _) in lemma.items():
        by_norm[norm].add(i)
    lookup = collections.defaultdict(set)
    for norm, i in forms.lookup:
        lookup[norm].add(i)
    tables = {i: has_table(lemma[i][2], forms.cells.get(i, [])) for i in lemma}

    tokens = [(normalize_greek(nfc(token.lower())), count) for token, count in frequency]
    classes = collections.Counter()
    examples = collections.defaultdict(list)
    for (token, _), (raw, _) in zip(tokens[:TOP_TOKENS], frequency[:TOP_TOKENS]):
        if not any(0x0370 <= ord(ch) <= 0x03FF or 0x1F00 <= ord(ch) <= 0x1FFF for ch in token):
            kind = "not Greek"
        elif token in headwords:
            kind = "headword"
        elif any(lemma[i][1] in headwords for i in lookup.get(token, ())):
            kind = "via forms"
        elif lookup.get(token):
            kind = "lemma missing from the dictionaries"
        else:
            kind = "unknown"
        classes[kind] += 1
        if len(examples[kind]) < 40:
            examples[kind].append(raw)

    score = collections.Counter()
    for token, count in tokens:
        for i in lookup.get(token, set()) | by_norm.get(token, set()):
            score[i] += count
    top = {}
    for pos in ("verb", "noun", "adj"):
        ranked = sorted((i for i in score if lemma[i][2] == pos), key=lambda i: (-score[i], lemma[i][0]))
        ranked = ranked[:TOP_LEMMAS]
        own = [i for i in ranked if tables[i]]
        linked = [i for i in ranked if not tables[i] and any(
            j != i and lemma[j][2] == pos and tables[j] for j in lookup.get(lemma[i][1], ()))]
        missing = [lemma[i][0] for i in ranked if not tables[i] and i not in linked]
        top[pos] = {"ranked": len(ranked), "own": len(own), "linked": len(linked), "missing": missing}

    lemmas_by_pos = collections.Counter(pos for _, _, _, pos in forms.lemmas)
    tables_by_pos = collections.Counter(lemma[i][2] for i, shown in tables.items() if shown)
    keys = collections.Counter(norm for norm, _ in forms.lookup)
    return {"classes": classes, "examples": examples, "top": top,
            "lemmas_by_pos": lemmas_by_pos, "tables_by_pos": tables_by_pos,
            "keys": len(keys), "ambiguous": sum(1 for n in keys.values() if n > 1)}


def stop_violations(forms: Forms, allowlist: set) -> list[str]:
    """Stoplisted forms that still map to a verb (the gate; 0 by the filter)."""
    lemma = {i: (word, pos) for i, word, _, pos in forms.lemmas}
    found = [(form, i) for i, cells in forms.cells.items() for form, _ in cells] + forms.link_forms
    return sorted({f"{form} → {lemma[i][0]}" for form, i in found
                   if lemma[i][1] == "verb" and stopped(form, *lemma[i])
                   and (form, *lemma[i]) not in allowlist})


def percent(part: int, whole: int) -> str:
    return f"{100 * part / whole:.1f}%" if whole else "n/a"


def report(forms: Forms, qa: dict, hashes: dict, sizes: dict, pins: dict, gates: list, allowlist: set) -> str:
    subset_key = pins["subset_key"]
    subset, frequency = pins["subset"], pins["frequency"]
    paradigm_rows = hashes["paradigm"][0]
    lines = [
        "# Greek word forms: QA report",
        "",
        "Written by `Scripts/build_forms.py` on every build of the forms step "
        "([0136-word-forms.md](../../docs/specs/0136-word-forms.md)). Do not edit by hand.",
        "",
        "## Snapshot",
        "",
        "| Input | Pin |",
        "|---|---|",
        f"| Greek subset | `{subset_key}`, sha256 `{subset['sha256']}`, {subset.get('lines', 0):,} lines |",
        f"| Dump | enwiktionary {subset['dump_date']}, {subset['dump_url']}, {subset['dump_bytes']:,} bytes, "
        f"{subset['dump_lines']:,} lines, sha256 `{subset['dump_sha256']}` |",
        f"| Frequency list (QA only) | {frequency['url']}, sha256 `{frequency['sha256']}` |",
        "",
        "## Counts",
        "",
        f"- Pages: {forms.pages:,} ({forms.lemma_pages:,} lemma pages, {forms.form_pages:,} form pages)",
        f"- Lemmas: {len(forms.lemmas):,} ("
        + ", ".join(f"{pos} {n:,}" for pos, n in sorted(qa["lemmas_by_pos"].items(), key=lambda x: (-x[1], x[0])))
        + ")",
        f"- Lemmas with a table: {sum(qa['tables_by_pos'].values()):,} ("
        + ", ".join(f"{pos} {n:,}" for pos, n in sorted(qa["tables_by_pos"].items(), key=lambda x: (-x[1], x[0])))
        + ")",
        f"- Table cells: {paradigm_rows:,}; lookup rows: {hashes['form_lookup'][0]:,}; lookup keys: {qa['keys']:,}, "
        f"of which ambiguous (more than one lemma): {qa['ambiguous']:,}; tag sets: {hashes['tagset'][0]:,}",
        "- Links: " + ", ".join(f"{kind} {n:,}" for kind, n in sorted(forms.link_kinds.items()))
        + f"; aspect taken from the gloss: {forms.link_aspects:,}"
        + f"; unresolved targets: {len(forms.unresolved):,} ({sum(forms.unresolved.values()):,} links)",
        "",
        "## Junk caught",
        "",
        "| Rule | Caught | Samples |",
        "|---|---|---|",
    ]
    for rule, count in sorted(forms.junk.items()):
        sample = "" if rule == "stoplisted form" else ", ".join(forms.samples[rule][:12])
        lines.append(f"| {rule} | {count:,} | {sample} |")
    lines += ["", f"### Tables declined from another word ({len(forms.other_tables)}, all)", ""]
    lines += [", ".join(forms.other_tables) or "None."]
    lines += ["", f"### Bare endings ({len(forms.bare_endings)}, all)", ""]
    lines += [", ".join(forms.bare_endings) or "None."]
    lines += ["", f"### Stoplist hits ({len(forms.stop_hits)}, all)", ""]
    lines += [f"- {hit}" for hit in forms.stop_hits] or ["None."]
    unused = sorted(f"{f} → {lemma} ({pos})" for f, lemma, pos in allowlist - forms.allowed)
    lines += ["", f"### Allowlist uses ({len(forms.allow_uses)}, all)", ""]
    lines += [f"- {use}" for use in forms.allow_uses] or ["None."]
    if unused:
        lines += ["", "Unused allowlist entries: " + ", ".join(unused)]
    lines += ["", "### Unresolved link targets (top 50)", ""]
    top_unresolved = sorted(forms.unresolved.items(), key=lambda x: (-x[1], x[0]))[:50]
    lines += [", ".join(f"{target} ({n})" for target, n in top_unresolved) or "None."]

    lines += ["", "## Coverage", "", "| Gate | Measured | Needed | Result |", "|---|---|---|---|"]
    lines += [f"| {name} | {measured} | {needed} | {'pass' if ok else 'FAIL'} |" for name, measured, needed, ok in gates]
    for pos, label in (("verb", "verbs"), ("noun", "nouns"), ("adj", "adjectives (reported, not gated)")):
        t = qa["top"][pos]
        lines += ["", f"**Top-{TOP_LEMMAS} {label}**: covered {t['own'] + t['linked']} of {t['ranked']} "
                  f"({percent(t['own'] + t['linked'], t['ranked'])}): own table {t['own']}, via a linked lemma "
                  f"{t['linked']}. Missing ({len(t['missing'])}): " + (", ".join(t["missing"]) or "none") + "."]
    classes = qa["classes"]
    lines += ["", f"**Top-{TOP_TOKENS:,} subtitle tokens**:", ""]
    for kind in ("headword", "via forms", "lemma missing from the dictionaries", "unknown", "not Greek"):
        sample = "" if kind in ("headword", "via forms") else ": " + ", ".join(qa["examples"][kind][:25])
        lines.append(f"- {kind}: {classes[kind]:,} ({percent(classes[kind], TOP_TOKENS)}){sample}")

    lines += ["", "## Size and table hashes", "", "| Table | Rows | Bytes (dbstat) | sha256 of the rows in key order |",
              "|---|---|---|---|"]
    for table in TABLES:
        lines.append(f"| `{table}` | {hashes[table][0]:,} | {sizes[table]:,} | `{hashes[table][1]}` |")
    lines.append(f"| total | | {sum(sizes.values()):,} | |")
    return "\n".join(lines) + "\n"


def load_frequency(path: Path) -> list[tuple[str, int]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        token, count = line.split()
        rows.append((token, int(count)))
    return rows


def run(conn: sqlite3.Connection, cache_dir: Path, headwords_db: sqlite3.Connection,
        report_path: Path = REPORT) -> Forms:
    """Build the forms tables into `conn`, write the QA report, then raise
    if a gate fails."""
    key = subset_key()
    subset = inputs.committed(key)
    pins = inputs.pins()
    allowlist = read_allowlist()
    with gzip.open(subset, "rt", encoding="utf-8") as lines:
        forms = collect(lines, allowlist)
    write_tables(conn, forms, f"enwiktionary {pins[key]['dump_date']}")

    headwords = {row[0] for row in headwords_db.execute(
        f"SELECT word_normalized FROM entries WHERE source IN ({','.join('?' * len(GREEK_DICTIONARIES))})",
        GREEK_DICTIONARIES)}
    if not headwords:
        raise RuntimeError("No Greek headwords in entries: the forms step runs after the dictionaries")
    qa = coverage(forms, headwords, load_frequency(inputs.fetch(FREQUENCY_KEY, cache_dir)))
    hashes = table_hashes(conn)
    try:
        sizes = shipped_size(conn)
    except sqlite3.OperationalError as error:
        raise RuntimeError(f"The size gate needs SQLite with dbstat: {error}") from error

    violations = stop_violations(forms, allowlist)
    verbs, nouns = qa["top"]["verb"], qa["top"]["noun"]
    findable = qa["classes"]["headword"] + qa["classes"]["via forms"]
    gates = [
        (f"Top-{TOP_LEMMAS} verbs covered", percent(verbs["own"] + verbs["linked"], verbs["ranked"]),
         f"≥ {GATE_VERBS:.0%}", verbs["own"] + verbs["linked"] >= GATE_VERBS * verbs["ranked"]),
        (f"Top-{TOP_LEMMAS} nouns covered", percent(nouns["own"] + nouns["linked"], nouns["ranked"]),
         f"≥ {GATE_NOUNS:.0%}", nouns["own"] + nouns["linked"] >= GATE_NOUNS * nouns["ranked"]),
        (f"Top-{TOP_TOKENS:,} findable", percent(findable, TOP_TOKENS), f"≥ {GATE_FINDABLE:.0%}",
         findable >= GATE_FINDABLE * TOP_TOKENS),
        ("Stoplisted forms mapping to a verb", f"{len(violations)}" + (": " + ", ".join(violations) if violations else ""),
         "0", not violations),
        ("Forms tables", f"{sum(sizes.values()) / 1e6:.1f} MB", f"≤ {SIZE_BUDGET / 1e6:.0f} MB",
         sum(sizes.values()) <= SIZE_BUDGET),
    ]
    report_pins = {"subset_key": key, "subset": pins[key], "frequency": pins[FREQUENCY_KEY]}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report(forms, qa, hashes, sizes, report_pins, gates, allowlist), encoding="utf-8")

    print(f"  {len(forms.lemmas):,} lemmas, {hashes['paradigm'][0]:,} cells, {hashes['form_lookup'][0]:,} "
          f"lookup rows, {hashes['tagset'][0]:,} tag sets; {len(forms.stop_hits)} stoplist hits, "
          f"{len(forms.unresolved):,} unresolved link targets")
    for name, measured, needed, ok in gates:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {measured} (needs {needed})")
    print(f"  QA report: {report_path}")
    failed = [name for name, _, _, ok in gates if not ok]
    if failed:
        raise RuntimeError("Forms QA gates failed: " + "; ".join(failed) + f" (see {report_path})")
    return forms


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """The `STEPS` entry point of build_dictionaries.py: runs after the
    dictionaries and reads their Greek headwords from `entries`."""
    run(conn, Path(cache_dir), conn)


def subset_key() -> str:
    """The one `inputs.json` key of the Greek subset."""
    keys = [k for k in inputs.pins() if k.startswith(SUBSET_PREFIX)]
    if len(keys) != 1:
        raise RuntimeError(f"inputs.json must pin exactly one {SUBSET_PREFIX}*.jsonl.gz, found {keys}")
    return keys[0]


# ---------------------------------------------------------------------------
# Standalone, self-check, fixture
# ---------------------------------------------------------------------------

def new_database(path: str) -> sqlite3.Connection:
    """A file with the dictionary file's core schema plus `SCHEMA`."""
    from build_dictionaries import SCHEMA as CORE_SCHEMA
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA page_size = 4096")
    conn.execute("PRAGMA journal_mode = DELETE")
    conn.executescript(CORE_SCHEMA)
    conn.executescript(SCHEMA)
    return conn


def read_only(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"file:{urllib.parse.quote(str(path.resolve()))}?mode=ro", uri=True)


def standalone(output: Path, headwords: Path, cache_dir: Path) -> int:
    output.unlink(missing_ok=True)
    conn = new_database(str(output))
    try:
        run(conn, cache_dir, read_only(headwords))
        conn.execute("VACUUM")
        sizes = table_size(conn)
        print(f"  after VACUUM: forms tables {sum(sizes.values()):,} bytes, file {output.stat().st_size:,} bytes")
    finally:
        conn.close()
    return 0


# The pages of the self-check fixture: (word, pos), cut from the pinned subset.
FIXTURE_PAGES = [
    ("γράφω", "verb"), ("έγραψα", "verb"), ("ξέρω", "verb"), ("ξέρεις", "verb"),
    ("πηγαίνω", "verb"), ("πάω", "verb"), ("αγαπάω", "verb"), ("αγαπώ", "verb"),
    ("καλύπτω", "verb"), ("σαλπάρω", "verb"), ("διαβαίνω", "verb"), ("βλέπω", "verb"),
    ("δω", "verb"), ("έχω", "verb"), ("κάνω", "verb"), ("τα", "pron"), ("σπίτι", "noun"),
    ("καλός", "adj"), ("θα", "particle"), ("παράς", "noun"),
    ("θυμάμαι", "verb"), ("μεταθέτω", "verb"), ("μετέθεσα", "verb"), ("γόνιμος", "adj"),
    ("κρεατομηχανή", "noun"), ("αισώπειος", "adj"),
]
FIXTURE_KEYS = ("word", "pos", "lang_code", "senses", "forms")
SENSE_KEYS = ("glosses", "tags", "form_of", "alt_of")
FORM_KEYS = ("form", "tags", "source")


def make_fixture() -> int:
    """Write the fixture: the FIXTURE_PAGES lines of the pinned subset, cut
    to the keys the step reads, in subset order."""
    wanted = set(FIXTURE_PAGES)
    out = []
    with gzip.open(inputs.committed(subset_key()), "rt", encoding="utf-8") as lines:
        for raw in lines:
            entry = json.loads(raw)
            if (entry.get("word"), entry.get("pos")) not in wanted:
                continue
            entry = {k: entry[k] for k in FIXTURE_KEYS if k in entry}
            entry["senses"] = [{k: s[k] for k in SENSE_KEYS if k in s} for s in entry.get("senses", [])]
            entry["forms"] = [{k: f[k] for k in FORM_KEYS if k in f} for f in entry.get("forms", [])]
            out.append(json.dumps(entry, ensure_ascii=False, separators=(",", ":")))
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"Wrote {len(out)} lines to {FIXTURE.relative_to(REPO)}")
    return 0


def synthetic_checks() -> list[tuple[str, bool]]:
    """Each rule on its own, on made-up pages: the edge cases the real
    fixture does not isolate (empty input, link depth, every cell rule, the
    allowlist file format, the table test, line order)."""
    def page(word, pos, forms=(), senses=({"glosses": ["a meaning"]},), lang="el"):
        return json.dumps({"word": word, "pos": pos, "lang_code": lang, "senses": list(senses),
                           "forms": [{"form": f, "tags": list(t), "source": "conjugation"} for f, t in forms]},
                          ensure_ascii=False)

    def form_of(target):
        return {"glosses": [f"form of {target}"], "form_of": [{"word": target}], "tags": ["form-of"]}

    present1 = ("active", "first-person", "imperfective", "indicative", "present", "singular")
    imperative = ("active", "imperative", "perfective", "second-person", "singular")
    lines = [
        page("λύνω", "verb", [
            ("λύνω", present1), ("λύνω", present1),            # a repeat is stored once
            ("-", ("plural",)), ("λύνoυμε", ("plural",)),      # placeholder; Latin o
            ("θα λύσω", ("future",)), ("λύσω", ("future", "singular")),  # multi-word; single-word future
            ("έλυνα", ("error-unknown-tag",)),                 # error-*
            ("Ο", ("singular",)),                              # stoplisted, compared lowercased
            ("el-conjug-1st", ("inflection-template",)),       # meta row
            ("λύσε", imperative)]),
        page("μετά", "adv", [("μετά", ("positive",))]),        # a stoplisted lemma keeps its own headword
        page("λύνει", "verb", senses=[{"glosses": ["third-person singular present of λύνω"]}]),
        page("λύσεις", "verb", senses=[{"glosses": ["θα λύσεις: second-person singular perfective future of λύνω"]}]),
        page("λυνάκι", "noun", senses=[{"glosses": ["a small thing of λύνω"]}]),  # no grammar word: a lemma
        # Form pages followed for up to 2 steps: λυα → λυβ → λυγ → λύνω resolves,
        # λυδ → λυε → λυζ → λυη → λύνω does not (λυε is then unresolved).
        page("λυα", "verb", senses=[form_of("λυβ")]), page("λυβ", "verb", senses=[form_of("λυγ")]),
        page("λυγ", "verb", senses=[form_of("λύνω")]),
        page("λυδ", "verb", senses=[form_of("λυε")]), page("λυε", "verb", senses=[form_of("λυζ")]),
        page("λυζ", "verb", senses=[form_of("λυη")]), page("λυη", "verb", senses=[form_of("λύνω")]),
        page("λυθ", "verb", senses=[form_of("ανύπαρκτο")]),   # a target with no page
        page("καλή μέρα", "intj"),                             # multi-word lemma
        page("λύνω", "verb", [("λύνομε", present1)], lang="en"),  # another language's line
    ]

    def lemma_words(forms):
        return {word for _, word, _, _ in forms.lemmas}

    def cells_of(forms, word):
        ids = [i for i, w, _, _ in forms.lemmas if w == word]
        return [cell for i in ids for cell in forms.cells.get(i, [])]

    def lookup_targets(forms, form):
        words = {i: w for i, w, _, _ in forms.lemmas}
        return {words[i]: tags for (norm, i), (_, tags) in forms.lookup.items() if norm == normalize_greek(form)}

    forms = collect(lines, set())
    allowed = collect(lines, {("Ο", "λύνω", "verb")})
    shuffled = collect(list(reversed(lines)), set())
    empty = collect([], set())

    with tempfile.TemporaryDirectory() as folder:
        allowlist = Path(folder) / "allowlist.tsv"
        allowlist.write_text("# form\tlemma\tpos\n\n"
                             + unicodedata.normalize("NFD", "παρά") + "\tπαράς\tnoun  # reviewed\n", encoding="utf-8")
        parsed = read_allowlist(allowlist)

    return [
        ("synthetic: empty input gives empty tables", not empty.lemmas and not empty.lookup and not empty.cells),
        ("synthetic: lines of another language are skipped", forms.pages == len(lines) - 1
         and ("λύνομε", present1) not in cells_of(forms, "λύνω")),
        ("synthetic: λύνω keeps only its real cells, a repeat once",
         cells_of(forms, "λύνω") == [("λύνω", present1), ("λύσε", imperative)]),
        ("synthetic: every cell rule counts what it caught",
         forms.junk["placeholder or non-Greek cell"] == 2 and forms.junk["multi-word cell"] == 1
         and forms.junk["single-word future cell"] == 1 and forms.junk["cell tagged error-*"] == 1
         and forms.junk["stoplisted form"] == 1 and forms.stop_hits == ["Ο in the table of λύνω (verb)"]),
        ("synthetic: the allowlist re-admits a reviewed stoplist hit",
         ("Ο", ("singular",)) in cells_of(allowed, "λύνω") and allowed.allowed == {("Ο", "λύνω", "verb")}
         and not allowed.stop_hits),
        ("synthetic: a stoplisted lemma keeps its own headword", cells_of(forms, "μετά") == [("μετά", ("positive",))]),
        ("synthetic: a gloss without markup links with its tags",
         lookup_targets(forms, "λύνει") == {"λύνω": ("present", "singular", "third-person")}),
        ("synthetic: a periphrastic sense is no lemma and no link",
         "λύσεις" not in lemma_words(forms) and not lookup_targets(forms, "λύσεις")),
        ("synthetic: a gloss without a grammar word is a lemma", "λυνάκι" in lemma_words(forms)),
        ("synthetic: form pages are followed for 2 steps, not 3",
         "λύνω" in lookup_targets(forms, "λυα") and not lookup_targets(forms, "λυδ")
         and all("λύνω" in lookup_targets(forms, w) for w in ("λυε", "λυζ", "λυη"))),
        ("synthetic: unresolved targets are counted", forms.unresolved == {"λυε": 1, "ανύπαρκτο": 1}),
        ("synthetic: a multi-word lemma is dropped and counted",
         "καλή μέρα" not in lemma_words(forms) and forms.junk["multi-word or non-Greek lemma"] == 1),
        ("synthetic: lemma ids do not depend on line order",
         forms.lemmas == shuffled.lemmas and forms.cells == shuffled.cells),
        ("synthetic: is_greek_word", is_greek_word("δω") and is_greek_word("ΐ") and is_greek_word("Ἀθῆναι")
         and not any(is_greek_word(s) for s in ("", "Αναξιμένoυς", "γράφ'", "θα γράψω", "‑η", "➤", "λύσω²"))),
        ("synthetic: a table needs a shown finite cell or two shown case cells",
         has_table("verb", [("λύνω", present1)])
         and not has_table("verb", [("λύνω", ("first-person", "present", "rare", "singular"))])
         and not has_table("verb", [("λύνοντας", ("participle", "present"))])
         and has_table("noun", [("x", ("nominative", "singular")), ("y", ("genitive", "singular"))])
         and not has_table("noun", [("x", ("nominative", "singular")), ("y", ("archaic", "genitive", "singular"))])),
        ("synthetic: the allowlist file skips comments and blank lines and NFCs its words",
         parsed == {("παρά", "παράς", "noun")}),
    ]


def synthetic_template_checks() -> list[tuple[str, bool]]:
    """The rules for Wiktionary template errors and links, on made-up pages:
    notes and ' - ' variants, misspellings, another word's table, bare
    endings, link tags."""
    def page(word, pos, forms=(), senses=({"glosses": ["a meaning"]},)):
        return json.dumps({"word": word, "pos": pos, "lang_code": "el", "senses": list(senses),
                           "forms": [{"form": f, "tags": list(t), "source": "conjugation"} for f, t in forms]},
                          ensure_ascii=False)

    def link(gloss, target, *tags):
        return {"glosses": [gloss], "form_of": [{"word": target}], "tags": ["form-of", *tags]}

    present1 = ("active", "first-person", "imperfective", "indicative", "present", "singular")
    present2 = ("active", "imperfective", "indicative", "present", "second-person", "singular")
    aorist1 = ("active", "first-person", "indicative", "past", "perfective", "singular")
    aorist2 = ("active", "indicative", "past", "perfective", "second-person", "singular")
    dependent1 = ("active", "dependent", "first-person", "indicative", "perfective", "singular")
    passive1pl = ("first-person", "imperfective", "indicative", "passive", "plural", "present")
    passive2 = ("imperfective", "indicative", "passive", "present", "second-person", "singular")
    imperative = ("active", "imperative", "perfective", "second-person", "singular")
    participle = ("participle", "present")
    nominative, genitive = ("masculine", "nominative", "singular"), ("genitive", "masculine", "singular")
    lines = [
        page("δένω", "verb", [
            ("δένω (δέω →)", present1), ("δένεις - δένες", present2),   # a note; two variants
            ("δέσε²", imperative), ("(δέσες (déses))", aorist2),         # a footnote mark; only a note
            ("δενόμαστε", passive1pl), ("δένοντας", participle)]),        # endings όμαστε, οντας
        page("πλένω", "verb", [("πλένω", present1), ("όμαστε", passive1pl)]),        # a bare ending
        page("είμαι", "verb", [("είμαι", present1), ("όντας", participle)]),         # a one-letter stem
        page("αντιδρώ", "verb", [("αντιδρώ", present1), ("αντίδρασε", imperative)]),  # ending ασε
        page("αφήνω", "verb", [("αφήνω", present1), ("άσε", imperative)]),           # begins like αφήνω
        page("τρώω", "verb", [("τρώω", present1), ("έφαγα", aorist1), ("φάω", dependent1)]),
        page("φοβάμαι", "verb", [("φοβάσαι", passive2)]),                            # no headword, its stem
        page("κρεατομηχανή", "noun", [("μηχανή", nominative), ("μηχανής", genitive)]),
        page("αισώπειος", "adj", [("ος", nominative), ("ου", genitive)]),
        page("γόνιμος", "adj", [("γόνιμος", nominative), ("γόνιμός", nominative), ("γόνιμοςου", genitive)]),
        page("δεμένο", "verb", senses=[link("masculine form of of δένω", "δένω", "error-lua-exec")]),
        page("δέσει", "verb", senses=[link("third-person singular perfective future of δένω", "δένω",
                                            "future", "perfective", "singular", "third-person")]),
        page("έδεσα", "verb", senses=[link("first-person singular simple past of δένω", "δένω",
                                            "first-person", "past", "singular")]),
        page("έδενα", "verb", senses=[link("first-person singular imperfect of δένω", "δένω",
                                            "first-person", "imperfect", "singular")]),
        page("δέστε", "verb", senses=[link("second-person plural imperfect active perfective imperative of δένω",
                                            "δένω", "imperative", "perfective", "plural", "second-person")]),
        page("δέσατε", "verb", senses=[link("second-person plural simple past of δένω", "δένω",   # the tag wins
                                             "imperfective", "plural", "second-person")]),
    ]
    forms = collect(lines, set())
    words = {i: w for i, w, _, _ in forms.lemmas}

    def cells_of(word):
        return [cell for i, w in words.items() if w == word for cell in forms.cells.get(i, [])]

    def lookup(form):
        return {words[i]: tags for (norm, i), (_, tags) in forms.lookup.items() if norm == normalize_greek(form)}

    return [
        ("synthetic: a note or footnote mark is stripped, ' - ' variants are cells of their own",
         cells_of("δένω")[:4] == [("δένω", present1), ("δένεις", present2), ("δένες", present2), ("δέσε", imperative)]
         and forms.junk["note or footnote mark stripped (kept)"] == 2
         and forms.junk["cell split into its ' - ' variants (kept)"] == 1
         and forms.junk["multi-word cell"] == 1),
        ("synthetic: two accents or a final sigma inside the word is no Greek word",
         cells_of("γόνιμος") == [("γόνιμος", nominative)] and forms.junk["misspelt cell: two accents"] == 1
         and forms.junk["misspelt cell: final sigma inside the word"] == 1
         and misspelling("εκστρατεύόμαστε") == "two accents"
         and misspelling("άφυλλοςος") == "final sigma inside the word"
         and not any(misspelling(word) for word in ("Ἀθῆναι", "ΐ", "δω", "γράφω", "ταὐτός"))),
        ("synthetic: a table without its headword or stem is dropped (another word's, bare endings)",
         not cells_of("κρεατομηχανή") and not cells_of("αισώπειος") and "κρεατομηχανή" not in lookup("μηχανή")
         and forms.junk["cell of a table declined from another word"] == 4),
        ("synthetic: a suppletive table and a table with only its stem stay",
         len(cells_of("τρώω")) == 3 and cells_of("φοβάμαι") == [("φοβάσαι", passive2)]),
        ("synthetic: a bare ending is dropped; a one-letter stem and a form that begins like its headword are not",
         cells_of("πλένω") == [("πλένω", present1)] and ("όντας", participle) in cells_of("είμαι")
         and ("άσε", imperative) in cells_of("αφήνω") and forms.junk["bare ending"] == 1),
        ("synthetic: links tagged error-* or future are dropped",
         not lookup("δεμένο") and not lookup("δέσει") and forms.junk["link tagged error-* or future"] == 2),
        ("synthetic: a link without an aspect takes its gloss's, a link with one keeps it",
         lookup("έδεσα") == {"δένω": ("first-person", "past", "perfective", "singular")}
         and lookup("έδενα") == {"δένω": ("first-person", "imperfect", "imperfective", "singular")}
         and lookup("δέστε") == {"δένω": ("imperative", "perfective", "plural", "second-person")}
         and lookup("δέσατε") == {"δένω": ("imperfective", "plural", "second-person")}
         and forms.link_aspects == 2),
    ]


def self_check() -> int:
    """Build the fixture twice, compare the table hashes, check the cases."""
    lines = FIXTURE.read_text(encoding="utf-8").splitlines()
    allowlist = read_allowlist()
    runs = []
    for _ in range(2):
        conn = new_database(":memory:")
        forms = collect(lines, allowlist)
        write_tables(conn, forms, "self-check")
        runs.append((conn, forms, table_hashes(conn)))
    conn, forms, hashes = runs[0]
    assert hashes == runs[1][2], "two builds of the fixture differ"
    for table, (rows, digest) in hashes.items():
        print(f"  {table:<12} {rows:>5} rows  {digest}")

    def lemmas_of(form: str, pos: str | None = None) -> set[str]:
        rows = conn.execute("SELECT l.word, l.pos FROM form_lookup f JOIN lemma l ON l.id = f.lemma_id "
                            "WHERE f.form_norm = ?", (normalize_greek(form),))
        return {word for word, p in rows if pos is None or p == pos}

    def caption(form: str, lemma: str) -> str:
        return conn.execute("SELECT t.tags FROM form_lookup f JOIN lemma l ON l.id = f.lemma_id "
                            "JOIN tagset t ON t.id = f.tagset_id WHERE f.form_norm = ? AND l.word = ?",
                            (normalize_greek(form), lemma)).fetchone()[0]

    def cells(lemma: str, pos: str) -> list[str]:
        return [form for (form,) in conn.execute(
            "SELECT p.form FROM paradigm p JOIN lemma l ON l.id = p.lemma_id WHERE l.word = ? AND l.pos = ? "
            "ORDER BY p.ord", (lemma, pos))]

    checks = [
        ("ο is not a cell or form of καλύπτω", "ο" not in cells("καλύπτω", "verb") and "καλύπτω" not in lemmas_of("ο")),
        ("αν is not a form of διαβαίνω", "αν" not in cells("διαβαίνω", "verb") and "διαβαίνω" not in lemmas_of("αν")),
        ("όταν and είτε are not forms of σαλπάρω",
         not {"όταν", "είτε"} & set(cells("σαλπάρω", "verb")) and "σαλπάρω" not in lemmas_of("όταν") | lemmas_of("είτε")),
        ("θα does not map to έχω", "έχω" not in lemmas_of("θα")),
        ("no stoplisted form maps to a verb", not stop_violations(forms, allowlist)),
        ("δω (2 letters) is kept: δω → βλέπω", "βλέπω" in lemmas_of("δω", "verb")),
        ("κάνεις → κάνω is kept", "κάνω" in lemmas_of("κάνεις", "verb")),
        ("έγραψα, εγραψα → γράφω, aorist 1sg active",
         "γράφω" in lemmas_of("εγραψα") and caption("έγραψα", "γράφω") == "active first-person indicative past perfective singular"),
        ("no future, multi-word or non-Greek cell (γραφώ, θα γράψω, γράφ')",
         not {"γράφ'", "θα γράψω", "‑η"} & set(cells("γράφω", "verb")) and not conn.execute(
             "SELECT 1 FROM paradigm p JOIN tagset t ON t.id = p.tagset_id WHERE ' ' || t.tags || ' ' LIKE '% future %'"
         ).fetchall()),
        ("ξέρεις → ξέρω (form_of)", "ξέρω" in lemmas_of("ξέρεις", "verb")),
        ("πάω → πηγαίνω (alt_of, and a gloss link without markup)", "πηγαίνω" in lemmas_of("πάω", "verb")),
        ("gloss words map to tags, unknown words are dropped",
         gloss_tags("first-person singular dependent active") == ("active", "dependent", "first-person", "singular")
         and gloss_tags("third-person singular simple past") == ("past", "perfective", "singular", "third-person")
         and gloss_tags("accusative/vocative singular") == ("accusative", "singular", "vocative")
         and gloss_tags("a less formal variant") == ()),
        ("αγαπώ → αγαπάω (alt_of); its cell there sets the caption",
         caption("αγαπώ", "αγαπάω") == "active first-person imperfective indicative present singular"),
        ("σας does not map to the pronoun τα (template guard)", "τα" not in lemmas_of("σας") and not cells("τα", "pron")),
        ("σπιτιού → σπίτι, genitive singular", caption("σπιτιού", "σπίτι") == "genitive singular"),
        ("καλός has 24 cells", len(cells("καλός", "adj")) == 24),
        ("παρά → παράς through the allowlist", "παράς" in lemmas_of("παρά", "noun")),
        ("the data_source row", conn.execute("SELECT id, kind, license FROM data_source").fetchall()
         == [("wiktionary-ell-forms", "word_forms", "CC BY-SA 4.0")]),
        ("κάνω (κάμνω →) is κάνω's present 1sg; θυμάμαι - θυμούμαι gives both",
         caption("κάνω", "κάνω") == "active first-person imperfective indicative present singular"
         and {"θυμάμαι", "θυμούμαι"} <= set(cells("θυμάμαι", "verb"))),
        ("γόνιμος keeps no two-accent cell (γόνιμός), its comparatives stay",
         "γόνιμός" not in cells("γόνιμος", "adj") and "γονιμότερος" in cells("γόνιμος", "adj")),
        ("κρεατομηχανή (μηχανή's forms) and αισώπειος (bare endings) keep no table",
         not cells("κρεατομηχανή", "noun") and not cells("αισώπειος", "adj")
         and "κρεατομηχανή" not in lemmas_of("μηχανή") and "αισώπειος" not in lemmas_of("ου")),
        ("suppletive tables stay: βλέπω (είδα, δω), πηγαίνω (πήγα, πάω)",
         {"είδα", "δω"} <= set(cells("βλέπω", "verb")) and {"πήγα", "πάω"} <= set(cells("πηγαίνω", "verb"))),
        ("σαλπάρω and διαβαίνω keep no bare ending (όμαστε, όμουν, ηκα; ανε)",
         not {"όμαστε", "όμουν", "ηκα"} & set(cells("σαλπάρω", "verb")) and "σάλπαρα" in cells("σαλπάρω", "verb")
         and "ανε" not in cells("διαβαίνω", "verb") and "διάβηκαν" in cells("διαβαίνω", "verb")
         and "σαλπάρω" not in lemmas_of("όμαστε")),
        ("μετέθεσα → μεταθέτω takes perfective from its gloss",
         caption("μετέθεσα", "μεταθέτω") == "first-person past perfective singular"),
    ]
    checks += synthetic_checks()
    checks += synthetic_template_checks()
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")

    # A subset whose sha256 differs from its pin fails the step.
    real_pins = inputs.pins
    key = "Scripts/fixtures/kaikki-el-sample.jsonl"
    try:
        inputs.pins = lambda: {key: {"sha256": "0" * 64}}
        try:
            inputs.committed(key)
            failed.append("a tampered subset is refused")
            print("  FAIL a tampered subset is refused")
        except RuntimeError:
            print("  ok   a tampered subset is refused")
        inputs.pins = lambda: {key: {"sha256": inputs.sha256(FIXTURE)}}
        inputs.committed(key)
    finally:
        inputs.pins = real_pins

    if failed:
        print("FAILED: " + "; ".join(failed))
        return 1
    print("OK: forms self-check passed.")
    return 0


# ---------------------------------------------------------------------------
# Refresh: a new pinned subset from the current dump
# ---------------------------------------------------------------------------

class _HashingReader(io.RawIOBase):
    """Passes a response through, hashing and counting every byte."""

    def __init__(self, raw):
        self.raw, self.digest, self.size = raw, hashlib.sha256(), 0

    def readable(self) -> bool:
        return True

    def readinto(self, buffer) -> int:
        data = self.raw.read(len(buffer))
        buffer[:len(data)] = data
        self.digest.update(data)
        self.size += len(data)
        return len(data)


def refresh() -> int:
    """Stream the current dump and write its Greek lines, byte for byte and
    in dump order, to a new dated subset; then point inputs.json at it."""
    page = urllib.request.urlopen(DUMP_PAGE, timeout=60).read().decode("utf-8")
    found = re.search(r"enwiktionary\s+dump\s+dated\s+(\d{4})-(\d{2})-(\d{2})",
                      re.sub(r"<[^>]+>", " ", page))
    if not found:
        sys.exit(f"No dump date found on {DUMP_PAGE}")
    date = "-".join(found.groups())
    key = f"{SUBSET_PREFIX}{''.join(found.groups())}.jsonl.gz"
    target = REPO / key
    partial = target.with_name(target.name + ".part")
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"Streaming {DUMP_URL} (enwiktionary {date})")

    lines = kept = 0
    with urllib.request.urlopen(DUMP_URL, timeout=600) as resp:
        expected_size = int(resp.headers.get("Content-Length") or 0)
        hashing = _HashingReader(resp)
        with gzip.GzipFile(fileobj=io.BufferedReader(hashing, 1 << 20)) as dump, \
                open(partial, "wb") as raw_out, \
                gzip.GzipFile(filename="", mode="wb", fileobj=raw_out, mtime=0) as out:
            for line in dump:
                lines += 1
                if (b'"lang_code": "el"' in line or b'"lang_code":"el"' in line) \
                        and json.loads(line).get("lang_code") == "el":
                    out.write(line)
                    kept += 1
        while hashing.read(1 << 20):  # anything after the last gzip member
            pass
    if expected_size and hashing.size != expected_size:
        partial.unlink()
        sys.exit(f"Read {hashing.size:,} bytes, the server announced {expected_size:,}")
    os.replace(partial, target)

    pins = inputs.pins()
    for old in [k for k in pins if k.startswith(SUBSET_PREFIX)]:
        del pins[old]
        if old != key and (REPO / old).exists():
            (REPO / old).unlink()
            print(f"Removed {old}")
    pins[key] = {
        "sha256": inputs.sha256(target),
        "dump_url": DUMP_URL,
        "dump_date": date,
        "dump_bytes": hashing.size,
        "dump_sha256": hashing.digest.hexdigest(),
        "dump_lines": lines,
        "lines": kept,
    }
    inputs.write_pins(pins)
    print(f"{lines:,} lines, {kept:,} Greek; dump sha256 {hashing.digest.hexdigest()}")
    print(f"Wrote {key} ({target.stat().st_size:,} bytes, sha256 {pins[key]['sha256']})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-check", action="store_true", help="Offline check on the fixture.")
    mode.add_argument("--standalone", type=Path, metavar="OUT",
                      help="Build the forms tables alone into OUT, with the QA report.")
    mode.add_argument("--refresh", action="store_true",
                      help="Stream the current dump and write a new dated subset.")
    mode.add_argument("--make-fixture", action="store_true",
                      help="Rewrite the self-check fixture from the pinned subset.")
    parser.add_argument("--headwords", type=Path, default=REPO / "DictApp/DictApp/Resources/dictionaries.sqlite",
                        help="With --standalone: the dictionary file whose Greek headwords the QA report uses.")
    parser.add_argument("--cache-dir", type=Path, default=inputs.DEFAULT_CACHE_DIR,
                        help="Where the frequency list is downloaded (default: Scripts/.cache).")
    args = parser.parse_args()
    if args.self_check:
        return self_check()
    if args.refresh:
        return refresh()
    if args.make_fixture:
        return make_fixture()
    return standalone(args.standalone.resolve(), args.headwords, args.cache_dir.resolve())


if __name__ == "__main__":
    sys.exit(main())
