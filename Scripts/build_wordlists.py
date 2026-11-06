#!/usr/bin/env python3
"""
build_wordlists.py
The word lists, a static data step of `build_dictionaries.py`
(docs/specs/0130-word-lists.md, "List data"): the built-in lists, their
words linked to the dictionaries, and frequency ranks, in the tables of
`wordlists_schema.sql`. `cut_packs.py` puts each language's rows into its
pack (0237): the Greek lists into `ell`.

#152: Kirill's Greek lists A1, A2 and B1 (`ky-ell`), committed as
`Scripts/data/wordlists/ky-ell-*.csv` and pinned in `inputs.json`, and the
Greek frequency ranks from FrequencyWords 2018 (`word_rank`, `ell`). #153
adds the English lists (`cefr-eng`) and the English ranks.

The step, per series:
  1. reads the rows (NFC, trimmed); a Latin letter in a Greek term or
     ending, or a Greek letter inside a Latin word of a translation
     (Εnglish), fails the build;
  2. merges a capitalised term into its lowercase twin of the series
     (Δύση into δύση), then rows with the same term (SQLite NOCASE): the
     lowest level, translations joined with "; " and endings with " / " in
     file order (a repeated value once), the first row's `seq`;
  3. links each word to a headword of the language's dictionaries with the
     rules of the app's `ListLinking` (exact, cleaned, near, form), then
     applies `Scripts/data/wordlists/links.tsv`, the reviewed overrides;
  4. ranks it: the `word_rank` of its headword, or when unlinked of the
     first of its term and cleaned spellings that has one;
  5. writes `wordlist` and `wordlist_item`, checks the gates and writes the
     QA report `Scripts/reports/wordlists-qa.md`.

`word_rank` sums each FrequencyWords token's count into its own key (the
folded word) and into the key of each lemma it is a form of (`form_lookup`,
#141), then ranks the keys by count, ties by key.

Gates (the build fails): a Latin letter in a Greek term or ending; a Greek
letter inside a Latin word of a translation; an input row that becomes no word; the Greek series linked below 84%; a
`wordlist.word_count` that differs from its rows; an empty list; an
override whose term is not in the series or whose headword is none of the
language's; the E3 tables above 4 MB.

Usage (from the repository root):
    python3 Scripts/build_wordlists.py --full Scripts/.cache/dictionaries-full.sqlite
        the step alone on a copy of a built full file: rewrites the report
        (after editing links.tsv, say) without the full build
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputs  # noqa: E402
from build_greek import normalize_greek  # noqa: E402  (Search.foldGreek's twin)

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO = SCRIPTS_DIR.parent
DATA_DIR = SCRIPTS_DIR / "data" / "wordlists"
LINKS = DATA_DIR / "links.tsv"
REPORT = SCRIPTS_DIR / "reports" / "wordlists-qa.md"

# The DDL lives in one file, which the app's unit tests read too.
SCHEMA = (SCRIPTS_DIR / "wordlists_schema.sql").read_text(encoding="utf-8")
TABLES = ("wordlist", "wordlist_item", "word_rank")

LEVELS = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
SIZE_BUDGET = 4_000_000  # bytes, the three tables with their indexes

DATA_SOURCES = [
    {"id": "ky-ell-lists", "kind": "word_list", "display_name": "Greek word lists by Kirill Yukhin",
     "version": "2026-11-06", "license": "CC BY-SA 4.0", "url": "https://github.com/kyukhin/dict-app"},
    {"id": "frequencywords-2018", "kind": "word_frequency",
     "display_name": "FrequencyWords by Hermit Dave, from OpenSubtitles 2018",
     "version": "2018", "license": "CC BY-SA 4.0", "url": "https://github.com/hermitdave/FrequencyWords"},
]


@dataclass(frozen=True)
class Series:
    """A built-in series: one list per level, the files in level order."""
    id: str
    lang: str
    data_source: str
    translation_lang: str
    files: tuple[tuple[str, str], ...]  # (level, inputs.json key)
    link_gate: float
    frequency: str  # inputs.json key of the FrequencyWords list


GREEK = Series(
    id="ky-ell", lang="ell", data_source="ky-ell-lists", translation_lang="eng",
    files=tuple((level, f"Scripts/data/wordlists/ky-ell-{level.lower()}.csv") for level in ("A1", "A2", "B1")),
    link_gate=0.84, frequency="frequencywords/el_50k.txt")
SERIES = [GREEK]


@dataclass
class Row:
    """One input row."""
    level: str
    line: int
    term: str
    endings: str
    translation: str
    seq: int


@dataclass
class Word:
    """One word of a series: its rows merged, linked and ranked."""
    term: str
    rows: list[Row]
    level: str = ""
    headword: str | None = None
    rule: str = ""  # exact, cleaned, near, form, override; "" when unlinked
    computed: str | None = None  # the rules' headword, before an override
    rank: int | None = None
    sort_key: str = ""

    @property
    def seq(self) -> int:
        return self.rows[0].seq

    @property
    def translation(self) -> str:
        return joined((r.translation for r in self.rows), "; ")

    @property
    def endings(self) -> str:
        return joined((r.endings for r in self.rows), " / ")


@dataclass
class Built:
    """What the report needs of one series."""
    series: Series
    rows: list[Row]
    words: list[Word]
    case_pairs: list[tuple[str, str]] = field(default_factory=list)


def joined(values, separator: str) -> str:
    """The non-empty values in order, a repeated one once."""
    return separator.join(dict.fromkeys(v for v in values if v))


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def nocase(s: str) -> str:
    """SQLite NOCASE and the app's `WordKey`: only A–Z fold."""
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)


def latin_letters(s: str) -> list[str]:
    return [c for c in s if unicodedata.category(c).startswith("L") and "LATIN" in unicodedata.name(c, "")]


WORD = re.compile(r"[^\W\d_]+")


def greek_in_latin_words(s: str) -> list[str]:
    """The words of `s` that mix Greek letters into Latin ones, lookalikes
    such as Εnglish; a whole Greek word (see also μέρα) is fine."""
    def scripts(word: str) -> set[str]:
        return {unicodedata.name(c, "").split(" ")[0] for c in word}
    return [w for w in WORD.findall(s) if {"LATIN", "GREEK"} <= scripts(w)]


# ---------------------------------------------------------------------------
# Reading and merging
# ---------------------------------------------------------------------------

def read_greek(series: Series, failures: list[str]) -> list[Row]:
    """Kirill's files: `level,greek,endings,english`, one per level."""
    rows: list[Row] = []
    for level, key in series.files:
        text = inputs.committed(key).read_text(encoding="utf-8-sig")
        records = list(csv.reader(io.StringIO(text, newline="")))
        if not records or records[0] != ["level", "greek", "endings", "english"]:
            failures.append(f"{key}: the header is not level,greek,endings,english")
            continue
        for line, record in enumerate(records[1:], start=2):
            if len(record) != 4 or record[0].strip() != level:
                failures.append(f"{key}:{line}: not a row of level {level}: {record}")
                continue
            term, endings, translation = (nfc(v).strip() for v in record[1:])
            for name, value in (("term", term), ("endings", endings)):
                if latin_letters(value):
                    failures.append(f"{key}:{line}: Latin letters {''.join(latin_letters(value))} "
                                    f"in the Greek {name} {value!r}")
            if greek_in_latin_words(translation):
                failures.append(f"{key}:{line}: Greek letters in the Latin words "
                                f"{', '.join(greek_in_latin_words(translation))} of the translation {translation!r}")
            rows.append(Row(level, line, term, endings, translation, len(rows)))
    return rows


def merge(rows: list[Row], failures: list[str]) -> tuple[list[Word], list[tuple[str, str]]]:
    """The words of a series (spec, "List data"): a capitalised term merges
    into its lowercase twin, then rows with the same NOCASE term merge.
    Words in the order of their first row."""
    terms = {r.term for r in rows}
    pairs = sorted({(r.term, r.term.lower()) for r in rows
                    if r.term != r.term.lower() and r.term.lower() in terms})
    twin = dict(pairs)
    words: dict[str, Word] = {}
    for r in rows:
        if not r.term:
            failures.append(f"{r.level} line {r.line}: an empty term becomes no word")
            continue
        term = twin.get(r.term, r.term)
        word = words.setdefault(nocase(term), Word(term, []))
        word.rows.append(r)
    for word in words.values():
        word.level = min((r.level for r in word.rows), key=LEVELS.__getitem__)
    return list(words.values()), pairs


# ---------------------------------------------------------------------------
# Linking: the app's ListLinking (Models.swift), in Python
# ---------------------------------------------------------------------------

TRAILING_MARKS = set("!?;.")
QUOTES = set('"“”„«»‹›')
SINGLE_QUOTES = set("'‘’")


def stripping_punctuation(term: str) -> str:
    """The term without trailing `! ? ; .`, without the double quotes and
    guillemets at either end, and without single quotes that wrap it."""
    text = term
    while True:
        before = text
        while text and (text[-1].isspace() or text[-1] in TRAILING_MARKS or text[-1] in QUOTES):
            text = text[:-1]
        while text and (text[0].isspace() or text[0] in QUOTES):
            text = text[1:]
        if len(text) > 1 and text[0] in SINGLE_QUOTES and text[-1] in SINGLE_QUOTES:
            text = text[1:-1]
        if text == before:
            return text


def without_parentheses(text: str) -> str:
    """The text without its parenthesised parts; an unclosed one runs to the end."""
    depth, out = 0, []
    for c in text:
        if c == "(":
            depth += 1
        elif c == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(c)
    return "".join(out)


def collapsing_whitespace(text: str) -> str:
    return " ".join(text.split())


def cleaned_variants(term: str) -> list[str]:
    """Rule 2's spellings, in order, without the term, empty ones and repeats."""
    stripped = stripping_punctuation(term)
    candidates = [stripped, collapsing_whitespace(without_parentheses(stripped)),
                  collapsing_whitespace(stripped.replace("(", "").replace(")", ""))]
    variants: list[str] = []
    for v in candidates:
        if v and v != term and v not in variants:
            variants.append(v)
    return variants


def _all_caps(word: str) -> bool:
    return any(c.isalpha() for c in word) and not any(c.islower() for c in word)


def _near_key(word: str) -> str:
    """Lowercase, without diaeresis, σ for the final sigma (`nearKey`)."""
    decomposed = unicodedata.normalize("NFD", word.lower())
    return nfc("".join("σ" if c == "ς" else c for c in decomposed if c != "̈"))


def is_near(headword: str, spelling: str) -> bool:
    """`InflectionLookup.match`: the same but for case or a diaeresis; in
    capitals, the same folded."""
    if nfc(headword) == nfc(spelling):
        return True
    if _all_caps(headword) or _all_caps(spelling):
        return normalize_greek(headword) == normalize_greek(spelling)
    return _near_key(headword) == _near_key(spelling)


class Dictionaries:
    """The reads linking needs, over the dictionaries with headwords in one
    language (`dict_metadata.from_lang`), as the app's `linkLookup` reads them."""

    def __init__(self, conn: sqlite3.Connection, lang: str):
        self.conn, self.lang = conn, lang
        self.sources = [r[0] for r in conn.execute(
            "SELECT source FROM dict_metadata WHERE from_lang = ? ORDER BY source", (lang,))]
        if not self.sources:
            raise RuntimeError(f"No dictionary has {lang} headwords: the step runs after the dictionaries")
        self.in_sources = "source IN (" + ", ".join("?" * len(self.sources)) + ")"
        self.by_fold: dict[str, list[str]] = {}
        for (word,) in conn.execute(f"SELECT word FROM entries WHERE {self.in_sources} ORDER BY id", self.sources):
            self.by_fold.setdefault(normalize_greek(word), []).append(word)

    def headwords(self, spelling: str) -> list[str]:
        return [r[0] for r in self.conn.execute(
            f"SELECT word FROM entries WHERE word = ? COLLATE NOCASE AND {self.in_sources}",
            [spelling, *self.sources])]

    def near_candidates(self, spelling: str) -> list[str]:
        """The headwords that fold like the spelling, with as many scalars."""
        n = len(nfc(spelling))
        return [w for w in self.by_fold.get(normalize_greek(spelling), []) if len(w) == n]

    def form_lemmas(self, spelling: str) -> list[str]:
        """Greek: the lemmas whose table holds the spelling exactly
        (`greekFormLemmasSQL`)."""
        if self.lang != "ell":
            return []  # English (#153): morphy's bases
        form = nfc(spelling)
        return [r[0] for r in self.conn.execute("""
            SELECT DISTINCT l.word FROM form_lookup f JOIN lemma l ON l.id = f.lemma_id
            WHERE f.form_norm = ?
              AND EXISTS (SELECT 1 FROM paradigm p WHERE p.lemma_id = l.id AND p.form = ?)
            ORDER BY l.word""", (normalize_greek(form), form))]


def _headword(among: list[str], spelling: str) -> str | None:
    """The one spelled as `spelling`, else the first in code point order."""
    if spelling in among:
        return spelling
    return min(among) if among else None


def _near(spelling: str, candidates: list[str]) -> str | None:
    near: list[str] = []
    for c in candidates:
        if is_near(c, spelling) and c not in near:
            near.append(c)
    if len(near) == 1:
        return near[0]
    lowered = spelling.lower()
    return next((c for c in near if c == lowered), None)


def link(term: str, lang: str, d: Dictionaries) -> tuple[str, str] | None:
    """`ListLinking.link`: (headword, rule) or None for a standalone word."""
    found = _headword(d.headwords(term), term)
    if found:
        return found, "exact"
    variants = cleaned_variants(term)
    for v in variants:
        found = _headword(d.headwords(v), v)
        if found:
            return found, "cleaned"
    spellings = [s for s in [term, *variants] if any(c.isalpha() for c in s)]
    if lang == "ell":
        for s in spellings:
            found = _near(s, d.near_candidates(s))
            if found:
                return found, "near"
    if lang not in ("ell", "eng"):
        return None
    for s in spellings:
        if not s or any(c.isspace() for c in s):
            continue
        headwords: list[str] = []
        for lemma in d.form_lemmas(s):
            h = _headword(d.headwords(lemma), lemma)
            if h is None or any(nocase(h) == nocase(x) for x in headwords):
                continue
            headwords.append(h)
            if lang == "eng":
                break  # English takes the first; Greek needs exactly one
        if len(headwords) == 1:
            return headwords[0], "form"
    return None


def read_overrides(failures: list[str]) -> dict[tuple[str, str], str | None]:
    """links.tsv: `series`, `term`, `headword` (`-` for none); `#` comments."""
    overrides: dict[tuple[str, str], str | None] = {}
    if not LINKS.is_file():
        return overrides
    for number, line in enumerate(LINKS.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.startswith("#") or line == "series\tterm\theadword":
            continue
        fields = line.split("\t")
        if len(fields) != 3:
            failures.append(f"links.tsv:{number}: not three tab-separated fields")
            continue
        series, term, headword = (nfc(f).strip() for f in fields)
        overrides[(series, term)] = None if headword == "-" else headword
    return overrides


# ---------------------------------------------------------------------------
# Frequency ranks
# ---------------------------------------------------------------------------

def greek_ranks(conn: sqlite3.Connection, cache_dir: Path, series: Series) -> tuple[dict[str, int], int]:
    """`word_rank` keys of Greek: each token's count into its folded key
    and into the key of each lemma it is a form of. Returns key → rank and
    the number of tokens read."""
    counts: dict[str, int] = {}
    path = inputs.fetch(series.frequency, cache_dir)
    lines = path.read_text(encoding="utf-8").splitlines()
    for line in lines:
        token, count = line.split()
        own = normalize_greek(nfc(token))
        keys = {own} | {r[0] for r in conn.execute(
            "SELECT DISTINCT l.word_normalized FROM form_lookup f JOIN lemma l ON l.id = f.lemma_id "
            "WHERE f.form_norm = ?", (own,))}
        for key in keys:
            counts[key] = counts.get(key, 0) + int(count)
    ordered = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return {key: rank for rank, (key, _) in enumerate(ordered, start=1)}, len(lines)


def rank_of(word: Word, ranks: dict[str, int]) -> int | None:
    if word.headword is not None:
        return ranks.get(normalize_greek(word.headword))
    for spelling in [word.term, *cleaned_variants(word.term)]:
        rank = ranks.get(normalize_greek(spelling))
        if rank is not None:
            return rank
    return None


# ---------------------------------------------------------------------------
# Sort key: the app's `WordListItem.sortKey(of:)`
# ---------------------------------------------------------------------------

PUNCTUATION = {"Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po"}


def sort_key(term: str) -> str:
    """Without parenthesised parts and punctuation, Greek folded, other
    scripts lowercased without diacritics, whitespace collapsed."""
    text = "".join(c for c in without_parentheses(term) if unicodedata.category(c) not in PUNCTUATION)
    folded = normalize_greek(text)
    folded = nfc("".join(c for c in unicodedata.normalize("NFD", folded)
                         if unicodedata.category(c) != "Mn").lower())
    return collapsing_whitespace(folded)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build_series(conn: sqlite3.Connection, series: Series, ranks: dict[str, int],
                 overrides: dict[tuple[str, str], str | None], failures: list[str]) -> Built:
    rows = read_greek(series, failures)
    words, pairs = merge(rows, failures)
    d = Dictionaries(conn, series.lang)
    by_term = {w.term: w for w in words}
    for (s, term), headword in overrides.items():
        if s != series.id:
            continue
        if term not in by_term:
            failures.append(f"links.tsv: {term!r} is not a term of {s}")
        elif headword is not None and headword not in d.headwords(headword):
            failures.append(f"links.tsv: {headword!r} is not a {series.lang} headword")
    for w in words:
        found = link(w.term, series.lang, d)
        w.computed = found[0] if found else None
        w.headword, w.rule = found if found else (None, "")
        if (series.id, w.term) in overrides:
            w.headword, w.rule = overrides[(series.id, w.term)], "override"
        w.rank = rank_of(w, ranks)
        w.sort_key = sort_key(w.term)

    levels = [level for level, _ in series.files]
    with conn:
        for level in levels:
            count = sum(1 for w in words if w.level == level)
            conn.execute("INSERT INTO wordlist(id, lang, series, level, level_ord, word_count, data_source, "
                         "translation_lang) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (f"{series.id}-{level.lower()}", series.lang, series.id, level, LEVELS[level], count,
                          series.data_source, series.translation_lang))
        conn.executemany(
            "INSERT INTO wordlist_item(series, term, headword, translation, endings, pos, tags, level, level_ord, "
            "rank, seq, sort_key) VALUES (?, ?, ?, ?, ?, '', '', ?, ?, ?, ?, ?)",
            [(series.id, w.term, w.headword, w.translation, w.endings, w.level, LEVELS[w.level], w.rank, w.seq,
              w.sort_key) for w in words])
    return Built(series, rows, words, pairs)


def check(conn: sqlite3.Connection, built: list[Built], failures: list[str]) -> list[tuple[str, str, str, bool]]:
    """The gates that read the written tables; returns the report's rows."""
    gates = []
    for b in built:
        linked = sum(1 for w in b.words if w.headword is not None)
        rate = linked / len(b.words) if b.words else 0
        gates.append((f"{b.series.id} linked", f"{rate:.1%} ({linked:,} of {len(b.words):,})",
                      f"≥ {b.series.link_gate:.0%}", rate >= b.series.link_gate))
    mismatched = [f"{i} {n} ≠ {m}" for i, n, m in conn.execute("""
        SELECT l.id, l.word_count, (SELECT COUNT(*) FROM wordlist_item i
                                    WHERE i.series = l.series AND i.level_ord = l.level_ord)
        FROM wordlist l ORDER BY l.id""") if n != m]
    gates.append(("word_count equals rows", ", ".join(mismatched) or "all", "all", not mismatched))
    empty = [r[0] for r in conn.execute("SELECT id FROM wordlist WHERE word_count = 0 ORDER BY id")]
    gates.append(("Empty lists", ", ".join(empty) or "0", "0", not empty))
    for name, measured, needed, ok in gates:
        if not ok:
            failures.append(f"{name}: {measured} (needs {needed})")
    return gates


def sizes(conn: sqlite3.Connection) -> dict[str, int]:
    """The E3 tables as they ship: copied into a new file and VACUUMed."""
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "sizing.sqlite"
        sizing = sqlite3.connect(path)
        try:
            sizing.executescript(SCHEMA)
            source = conn.execute("PRAGMA database_list").fetchone()[2]
            sizing.execute("ATTACH DATABASE ? AS f", (source,))
            with sizing:
                for table in TABLES:
                    sizing.execute(f"INSERT INTO main.{table} SELECT * FROM f.{table}")
            sizing.execute("DETACH DATABASE f")
            sizing.execute("VACUUM")
            result = {table: 0 for table in TABLES}
            for name, size in sizing.execute("""
                    SELECT COALESCE(m.tbl_name, d.name), SUM(d.pgsize)
                    FROM dbstat AS d LEFT JOIN sqlite_master AS m ON m.name = d.name GROUP BY 1"""):
                if name in result:
                    result[name] += size
            return result
        finally:
            sizing.close()


def build(conn: sqlite3.Connection, cache_dir: Path, report_path: Path = REPORT) -> None:
    """The `STEPS` entry point of build_dictionaries.py: runs after the
    dictionaries and the forms, whose tables linking and ranking read."""
    failures: list[str] = []
    with conn:
        conn.executemany("INSERT INTO data_source(id, kind, display_name, version, license, url) "
                         "VALUES (:id, :kind, :display_name, :version, :license, :url)", DATA_SOURCES)
    overrides = read_overrides(failures)
    built, rank_stats = [], []
    for series in SERIES:
        ranks, tokens = greek_ranks(conn, Path(cache_dir), series)
        with conn:
            conn.executemany("INSERT INTO word_rank(lang, key, rank) VALUES (?, ?, ?)",
                             [(series.lang, key, rank) for key, rank in sorted(ranks.items())])
        rank_stats.append((series.lang, series.frequency, tokens, len(ranks)))
        built.append(build_series(conn, series, ranks, overrides, failures))
    input_problems = len(failures)
    gates = check(conn, built, failures)
    table_sizes = sizes(conn)
    total = sum(table_sizes.values())
    gates.append(("E3 tables", f"{total / 1e6:.2f} MB", f"≤ {SIZE_BUDGET / 1e6:.0f} MB", total <= SIZE_BUDGET))
    if total > SIZE_BUDGET:
        failures.append(f"E3 tables: {total:,} bytes, the budget is {SIZE_BUDGET:,}")
    gates.insert(0, ("Input problems (Latin letters in Greek, Greek letters in Latin words, rows that become "
                     "no word, bad rows, overrides)",
                     str(input_problems), "0", not input_problems))

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report(built, gates, failures, table_sizes, rank_stats), encoding="utf-8")
    for b in built:
        for level, _ in b.series.files:
            words = [w for w in b.words if w.level == level]
            linked = sum(1 for w in words if w.headword is not None)
            print(f"  {b.series.id}-{level.lower()}: {len(words):,} words, {percent(linked, len(words))} linked, "
                  f"{sum(1 for w in words if w.rank is None):,} unranked")
    for name, measured, needed, ok in gates:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {measured} (needs {needed})")
    print(f"  QA report: {report_path}")
    if failures:
        raise RuntimeError("Word list gates failed:\n  - " + "\n  - ".join(failures))


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def cell(text: str) -> str:
    return text.replace("|", "\\|") if text else "—"


def percent(part: int, whole: int) -> str:
    return f"{part / whole:.1%}" if whole else "—"


def report(built: list[Built], gates, failures: list[str], table_sizes: dict[str, int], rank_stats) -> str:
    pins = inputs.pins()
    out = ["# Word lists QA report", "",
           "Written by `Scripts/build_wordlists.py` on every dictionary build (docs/specs/0130-word-lists.md, "
           "\"List data\"); do not edit by hand.", "", "## Inputs", "", "| Input | sha256 |", "|---|---|"]
    for b in built:
        for _, key in b.series.files:
            out.append(f"| `{key}` | `{pins[key]['sha256']}` |")
    for _, key, _, _ in rank_stats:
        out.append(f"| `{key}` | `{pins[key]['sha256']}` |")
    out += ["", "## Gates", "", "| Gate | Measured | Needed | |", "|---|---|---|---|"]
    out += [f"| {name} | {measured} | {needed} | {'ok' if ok else 'FAIL'} |" for name, measured, needed, ok in gates]
    if failures:
        out += ["", "Failures:", ""] + [f"- {cell(f)}" for f in failures]

    for b in built:
        levels = [level for level, _ in b.series.files]
        rules = ["exact", "cleaned", "near", "form", "override"]
        out += ["", f"## {b.series.id}", "", "### Counts", "",
                "| Level | Rows | Words | Linked | Ranked |", "|---|---|---|---|---|"]
        for level in levels + ["all"]:
            words = [w for w in b.words if level in (w.level, "all")]
            rows = [r for r in b.rows if level in (r.level, "all")]
            linked = sum(1 for w in words if w.headword is not None)
            ranked = sum(1 for w in words if w.rank is not None)
            out.append(f"| {level} | {len(rows):,} | {len(words):,} | {percent(linked, len(words))} | "
                       f"{percent(ranked, len(words))} |")
        out += ["", f"{len(b.rows) - len(b.words):,} rows merged into other rows' words (below).", "",
                "### Link classes", "", "| Level | " + " | ".join(rules) + " | unlinked |",
                "|---" * (len(rules) + 2) + "|"]
        for level in levels + ["all"]:
            words = [w for w in b.words if level in (w.level, "all")]
            counts = [sum(1 for w in words if w.rule == rule and w.headword is not None) for rule in rules]
            out.append(f"| {level} | " + " | ".join(f"{n:,}" for n in counts)
                       + f" | {sum(1 for w in words if w.headword is None):,} |")

        first = sorted((w for w in b.words if w.level == levels[0] and w.rank is not None), key=lambda w: w.rank)[:20]
        out += ["", f"### {levels[0]}: the 20 most frequent words, before the shuffle", "",
                ", ".join(w.term for w in first)]

        def ordered(words):
            return sorted(words, key=lambda w: (LEVELS[w.level], w.sort_key, w.term))

        shown = ordered(w for w in b.words if w.rule in ("cleaned", "near", "form", "override"))
        out += ["", f"### Links to review: cleaned, near, form and override ({len(shown):,})", "",
                "| Level | Term | Headword | Rule | The rules' link |", "|---|---|---|---|---|"]
        out += [f"| {w.level} | {cell(w.term)} | {cell(w.headword or '')} | {w.rule} | "
                f"{cell(w.computed or '') if w.rule == 'override' else ''} |" for w in shown]

        unlinked = ordered(w for w in b.words if w.headword is None)
        out += ["", f"### Unlinked words ({len(unlinked):,})", "", "| Level | Term | Translation |", "|---|---|---|"]
        out += [f"| {w.level} | {cell(w.term)} | {cell(w.translation)} |" for w in unlinked]

        unranked = ordered(w for w in b.words if w.rank is None)
        out += ["", f"### Unranked words ({len(unranked):,})", "", "| Level | Term |", "|---|---|"]
        out += [f"| {w.level} | {cell(w.term)} |" for w in unranked]

        merged = ordered(w for w in b.words if len(w.rows) > 1)
        out += ["", f"### Merged rows ({len(merged):,} words of {sum(len(w.rows) for w in merged):,} rows)", "",
                "| Level | Word | Rows (level:line term) | Translation | Endings |", "|---|---|---|---|---|"]
        out += [f"| {w.level} | {cell(w.term)} | "
                + ", ".join(f"{r.level}:{r.line} {cell(r.term)}" for r in w.rows)
                + f" | {cell(w.translation)} | {cell(w.endings)} |" for w in merged]

        out += ["", f"### Case pairs ({len(b.case_pairs)})", "", "| Capitalised | Merged into |", "|---|---|"]
        out += [f"| {cell(a)} | {cell(z)} |" for a, z in b.case_pairs]

    out += ["", "## Frequency ranks", "", "| Language | Input | Tokens | Keys |", "|---|---|---|---|"]
    out += [f"| {lang} | `{key}` | {tokens:,} | {keys:,} |" for lang, key, tokens, keys in rank_stats]
    out += ["", "## Table sizes", "", "Copied into a new file and VACUUMed, as they ship.", "",
            "| Table | Bytes |", "|---|---|"]
    out += [f"| {table} | {size:,} |" for table, size in table_sizes.items()]
    out.append(f"| total | {sum(table_sizes.values()):,} |")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Main: the step alone on a copy of a full file
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Run the word lists step alone on a copy of a built full file.")
    parser.add_argument("--full", type=Path, required=True, help="A dictionaries-full.sqlite of build_dictionaries.py.")
    parser.add_argument("--cache-dir", type=Path, default=inputs.DEFAULT_CACHE_DIR,
                        help="Where the pinned inputs are downloaded (default: Scripts/.cache).")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        copy = Path(folder) / "full.sqlite"
        shutil.copyfile(args.full, copy)
        conn = sqlite3.connect(copy)
        try:
            with conn:  # the tables as SCHEMA has them now, empty
                for table in TABLES:
                    conn.execute(f"DROP TABLE IF EXISTS {table}")
                conn.executescript(SCHEMA)
                conn.executemany("DELETE FROM data_source WHERE id = ?", [(s["id"],) for s in DATA_SOURCES])
            build(conn, args.cache_dir.resolve())
        finally:
            conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
