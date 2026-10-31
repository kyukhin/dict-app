#!/usr/bin/env python3
"""
build_dictionaries.py
Builds `dictionaries.sqlite`, the read-only dictionary file the app attaches
as `dict` (docs/specs/0129-dictionary-file.md, "Dictionary file" and
"Build (#140)"):

  1. writes the schema (`SCHEMA`, then the `SCHEMA` of every static step);
  2. runs the dictionary builders: WordNet (En-En), OpenRussian (Ru-En),
     FreeDict eng-spa (En-Es), Spanish WordNet (Es-En), Arabic WordNet
     (Ar-En) and the four Greek sources (El-En, En-El);
  3. runs the static data steps (`STEPS`);
  4. rebuilds the `entries_fts` index;
  5. runs the checks; any failure fails the build;
  6. VACUUMs, then prints the size of every table (dbstat) and the total.

Every input is pinned in `Scripts/inputs.json` and verified before use
(`inputs.py`), rows go in in a fixed order and nothing stores a timestamp,
so the same inputs and the same SQLite version give a byte-identical file.
`--verify` rebuilds into a temp file and compares it with the committed one.

Every row carries a `word_normalized` search key: `word` for the en, ru and
es sources, the harakat-stripped form for Arabic, and the accent-, case- and
final-sigma-folded form for Greek (`build_greek.normalize_greek`). FTS5
indexes `word_normalized`. Greek inside the definitions of the Greek sources
is stored decomposed (NFD), so the tokenizer indexes it accent-free too.

Source-identifier convention:
  - single-monolingual / unambiguous → bare provider name,
        e.g. "wordnet", "openrussian";
  - bilingual → "provider-srclang-tgtlang" with ISO 639-3 codes,
        e.g. "freedict-eng-spa", "wordnet-spa-eng".

Requirements (from the repository root):
    python3 -m venv .venv
    .venv/bin/pip install -r Scripts/requirements.txt

Usage:
    .venv/bin/python Scripts/build_dictionaries.py
    .venv/bin/python Scripts/build_dictionaries.py --output path/to/dictionaries.sqlite
    .venv/bin/python Scripts/build_dictionaries.py --verify
    .venv/bin/python Scripts/build_dictionaries.py --cache-dir /path/to/cache
"""

from __future__ import annotations

import argparse
import csv
import importlib
import io
import os
import re
import sqlite3
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputs  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = REPO / "DictApp/DictApp/Resources/dictionaries.sqlite"

# `PRAGMA user_version`. The app's `DictionaryFile.formatVersion` must match
# (a unit test checks it). A changed table shape bumps both in the same PR.
FORMAT_VERSION = 2

# Static data steps (spec, "Adding static data"): module names in Scripts/,
# run in this order after the dictionaries. Each module has `SCHEMA` (DDL,
# applied after the core schema) and `build(conn, cache_dir)`, which fills
# its own tables, may read `entries` and pins its inputs in inputs.json.
STEPS: list[str] = [
    "build_forms",   # Greek word forms from Wiktionary (#141, 0136-word-forms.md)
]


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA = """
-- Ids stay AUTOINCREMENT, as in the 1.4.0 seed: an ignored repeated
-- headword uses up an id, so the ids are the seed's.
CREATE TABLE entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    word            TEXT    NOT NULL,
    word_normalized TEXT    NOT NULL DEFAULT '',   -- search key
    definition      TEXT    NOT NULL,
    phonetic        TEXT    NOT NULL DEFAULT '',
    pos             TEXT    NOT NULL DEFAULT '',
    source          TEXT    NOT NULL
);
CREATE UNIQUE INDEX idx_entries_word_source
    ON entries(word COLLATE NOCASE, source);

-- FTS5 indexes word_normalized (not word): a bare query matches a
-- vocalized Arabic or accented Greek headword. No triggers: the file
-- never changes after the build, which rebuilds the index once.
CREATE VIRTUAL TABLE entries_fts USING fts5(
    word_normalized, definition,
    content='entries', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

-- One row per dictionary, each a Dictionary Order source. from_lang and
-- to_lang are ISO 639-3 (#208).
CREATE TABLE dict_metadata (
    source       TEXT PRIMARY KEY,
    display_name TEXT    NOT NULL,
    version      TEXT    NOT NULL DEFAULT '',
    license      TEXT    NOT NULL DEFAULT '',
    url          TEXT    NOT NULL DEFAULT '',
    word_count   INTEGER NOT NULL DEFAULT 0,
    description  TEXT    NOT NULL DEFAULT '',
    from_lang    TEXT    NOT NULL,
    to_lang      TEXT    NOT NULL
);

-- One row per non-dictionary data set (word forms, examples, word lists),
-- for Credits. Never a dict_metadata row.
CREATE TABLE data_source (
    id           TEXT PRIMARY KEY,
    kind         TEXT NOT NULL,
    display_name TEXT NOT NULL,
    version      TEXT NOT NULL DEFAULT '',
    license      TEXT NOT NULL DEFAULT '',
    url          TEXT NOT NULL DEFAULT ''
);
"""

INSERT_ROW = ("INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source) "
              "VALUES (?, ?, ?, ?, ?, ?)")
# A 5-column row `(word, definition, phonetic, pos, source)`: the search
# key is the word itself.
INSERT_ROW_PLAIN = ("INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source) "
                    "VALUES (?1, ?1, ?2, ?3, ?4, ?5)")


@dataclass(frozen=True)
class Dictionary:
    """One source's rows plus its `dict_metadata` fields (the shape of
    `build_greek.GreekSource`)."""
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
# WordNet (En-En)
# ---------------------------------------------------------------------------

def pos_tag_to_label(pos: str) -> str:
    return {"n": "noun", "v": "verb", "a": "adjective",
            "r": "adverb", "s": "adjective satellite"}.get(pos, pos)


def build_definition(synsets) -> str:
    by_pos: dict[str, list] = {}
    for ss in synsets:
        label = pos_tag_to_label(ss.pos())
        by_pos.setdefault(label, []).append(ss)
    parts = []
    for pos_label, senses in by_pos.items():
        parts.append(f"**{pos_label}**")
        for i, ss in enumerate(senses, 1):
            line = f"{i}. {ss.definition()}"
            examples = ss.examples()
            if examples:
                quoted = "; ".join(f'"{ex}"' for ex in examples)
                line += f"  \n   *{quoted}*"
            parts.append(line)
        parts.append("")
    return "\n".join(parts).strip()


def extract_pos_tags(synsets) -> str:
    tags = dict.fromkeys(pos_tag_to_label(ss.pos()) for ss in synsets)
    return ", ".join(tags)


WORDNET_LICENSE = (
    "WordNet 3.0 License (BSD-style)\n\n"
    "Copyright 2006 by Princeton University. All rights reserved.\n\n"
    "THIS SOFTWARE AND DATABASE IS PROVIDED \"AS IS\" AND PRINCETON "
    "UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES, EXPRESS OR "
    "IMPLIED. BY WAY OF EXAMPLE, BUT NOT LIMITATION, PRINCETON "
    "UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES OF MERCHANT- "
    "ABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE "
    "OF THE LICENSED SOFTWARE, DATABASE OR DOCUMENTATION WILL NOT "
    "INFRINGE ANY THIRD PARTY PATENTS, COPYRIGHTS, TRADEMARKS OR "
    "OTHER RIGHTS.\n\n"
    "Permission to use, copy, modify and distribute this software and "
    "database and its documentation for any purpose and without fee or "
    "royalty is hereby granted, provided that you agree to comply with "
    "the above copyright notice and statements, including the disclaimer, "
    "and that the same appear on ALL copies of the software, database "
    "and documentation, including modifications that you make for "
    "internal use or for distribution."
)

WORDNET_DESCRIPTION = (
    "WordNet is a large lexical database of English developed at Princeton University. "
    "Nouns, verbs, adjectives and adverbs are grouped into sets of cognitive synonyms "
    "(synsets), each expressing a distinct concept. Synsets are interlinked by means of "
    "conceptual-semantic and lexical relations.\n\n"
    "WordNet superficially resembles a thesaurus, in that it groups words together based "
    "on their meanings. However, there are some important distinctions: WordNet interlinks "
    "not just word forms (strings of letters) but specific senses of words, and labels "
    "the semantic relations among them.\n\n"
    "Maintained by the Cognitive Science Laboratory at Princeton University under the "
    "direction of George A. Miller (1920–2012)."
)


def wordnet(cache_dir: Path) -> list[Dictionary]:
    wn = inputs.wordnet(cache_dir)

    rows = []
    for lemma in sorted(set(wn.all_lemma_names())):
        synsets = wn.synsets(lemma)
        if not synsets:
            continue
        rows.append((lemma.replace("_", " "), build_definition(synsets), "",
                     extract_pos_tags(synsets), "wordnet"))
    return [Dictionary("wordnet", "WordNet", "3.0", WORDNET_LICENSE,
                       "https://wordnet.princeton.edu/", WORDNET_DESCRIPTION,
                       "eng", "eng", rows)]


# ---------------------------------------------------------------------------
# OpenRussian (Ru-En)
# ---------------------------------------------------------------------------

# The Badestrand/russian-dictionary export, pinned to a commit in inputs.json.
OPENRUSSIAN_FILES = {
    "nouns.csv":      "noun",
    "verbs.csv":      "verb",
    "adjectives.csv": "adjective",
    "others.csv":     "",
}

OPENRUSSIAN_LICENSE = (
    "Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\n\n"
    "You are free to:\n"
    "  • Share — copy and redistribute the material in any medium or format\n"
    "  • Adapt — remix, transform, and build upon the material for any purpose, "
    "even commercially\n\n"
    "Under the following terms:\n"
    "  • Attribution — You must give appropriate credit, provide a link to the license, "
    "and indicate if changes were made.\n"
    "  • ShareAlike — If you remix, transform, or build upon the material, you must "
    "distribute your contributions under the same license.\n\n"
    "Full license text: https://creativecommons.org/licenses/by-sa/4.0/legalcode"
)

OPENRUSSIAN_DESCRIPTION = (
    "OpenRussian is a free, community-maintained Russian-English dictionary. "
    "It provides translations, stress marks, and grammatical information for Russian "
    "nouns, verbs, adjectives, and other parts of speech.\n\n"
    "The data is crowd-sourced and continuously improved by volunteers. "
    "The dictionary focuses on modern, everyday Russian vocabulary and is "
    "particularly useful for language learners.\n\n"
    "Data sourced from the Badestrand/russian-dictionary GitHub repository."
)


def parse_openrussian(csv_files: dict[str, str]) -> list[tuple]:
    """
    Parse nouns.csv, verbs.csv, adjectives.csv, others.csv into
    (word, definition, phonetic, pos, source) tuples.
    Each CSV has columns: bare, accented, translations_en, translations_de, ...
    """
    entries = []
    for filename, pos_label in OPENRUSSIAN_FILES.items():
        if filename not in csv_files:
            continue
        # These CSVs are tab-separated.
        reader = csv.DictReader(io.StringIO(csv_files[filename]), delimiter="\t")
        for row in reader:
            bare = row.get("bare", "").strip()
            accented = row.get("accented", "").strip()
            translations_en = row.get("translations_en", "").strip()
            if not bare or not translations_en:
                continue
            phonetic = accented if accented and accented != bare else ""
            entries.append((bare, translations_en, phonetic, pos_label, "openrussian"))
    return entries


def openrussian(cache_dir: Path) -> list[Dictionary]:
    csv_files = {name: inputs.fetch(f"openrussian/{name}", cache_dir).read_bytes().decode("utf-8")
                 for name in OPENRUSSIAN_FILES}
    return [Dictionary("openrussian", "OpenRussian", "2024", OPENRUSSIAN_LICENSE,
                       "https://openrussian.org/", OPENRUSSIAN_DESCRIPTION,
                       "rus", "eng", parse_openrussian(csv_files))]


# ---------------------------------------------------------------------------
# The other builders (their own modules)
# ---------------------------------------------------------------------------

def freedict_eng_spa(cache_dir: Path) -> list[Dictionary]:
    import build_freedict_eng_spa as m
    rows, version = m.download_and_parse("eng-spa", cache_dir)
    return [Dictionary(m.SOURCE, m.DISPLAY_NAME, version, m.LICENSE_TEXT, m.URL,
                       m.DESCRIPTION_TEXT, m.FROM_LANG, m.TO_LANG, rows)]


def spanish_wordnet(cache_dir: Path) -> list[Dictionary]:
    import build_spanish_wordnet as m
    rows, version = m.build_and_collect(cache_dir)
    return [Dictionary(m.SOURCE, m.DISPLAY_NAME, version, m.LICENSE_TEXT, m.URL,
                       m.DESCRIPTION_TEXT, m.FROM_LANG, m.TO_LANG, rows)]


def arabic_wordnet(cache_dir: Path) -> list[Dictionary]:
    import build_arabic_wordnet as m
    rows, version = m.build_and_collect(cache_dir)
    return [Dictionary(m.SOURCE, m.DISPLAY_NAME, version, m.LICENSE_TEXT, m.URL,
                       m.DESCRIPTION_TEXT, m.FROM_LANG, m.TO_LANG, rows)]


def greek(cache_dir: Path) -> list:
    from build_greek import build_all
    return build_all(cache_dir)


# In insertion order: it fixes the row ids and the dict_metadata order.
DICTIONARY_BUILDERS = [wordnet, openrussian, freedict_eng_spa, spanish_wordnet,
                       arabic_wordnet, greek]


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def insert_dictionary(conn: sqlite3.Connection, d) -> int:
    """Insert one dictionary's rows in their order, then its `dict_metadata`
    row. `INSERT OR IGNORE`: a repeated headword (`word COLLATE NOCASE`,
    `source`) keeps its first row, as in 1.4.0. Returns how many rows were
    dropped that way."""
    if not d.rows:
        raise RuntimeError(f"{d.source}: the builder returned no rows")
    if any(row[-1] != d.source for row in d.rows):
        raise RuntimeError(f"{d.source}: a row names another source")
    sql = INSERT_ROW_PLAIN if len(d.rows[0]) == 5 else INSERT_ROW
    with conn:
        before = conn.total_changes
        conn.executemany(sql, d.rows)
        inserted = conn.total_changes - before
        conn.execute(
            "INSERT INTO dict_metadata(source, display_name, version, license, url, word_count, "
            "description, from_lang, to_lang) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (d.source, d.display_name, d.version, d.license, d.url, inserted,
             d.description, d.from_lang, d.to_lang))
    dropped = len(d.rows) - inserted
    print(f"  {d.source}: {inserted:,} rows, {dropped:,} dropped as repeated headwords ({d.version})")
    return dropped


ISO_639_3 = re.compile(r"[a-z]{3}")


def check(conn: sqlite3.Connection) -> None:
    """The checks of the spec's Build section. Any failure fails the build."""
    failures = []

    integrity = [row[0] for row in conn.execute("PRAGMA integrity_check")]
    if integrity != ["ok"]:
        failures.append("integrity_check: " + "; ".join(integrity[:5]))
    try:
        # rank = 1 also compares the index with the `entries` content.
        with conn:
            conn.execute("INSERT INTO entries_fts(entries_fts, rank) VALUES('integrity-check', 1)")
    except sqlite3.DatabaseError as err:
        failures.append(f"entries_fts integrity-check: {err}")

    counts = dict(conn.execute("SELECT source, COUNT(*) FROM entries GROUP BY source"))
    metadata = {source: (word_count, from_lang, to_lang) for source, word_count, from_lang, to_lang
                in conn.execute("SELECT source, word_count, from_lang, to_lang FROM dict_metadata")}
    if set(counts) != set(metadata):
        failures.append(f"entries sources {sorted(counts)} differ from "
                        f"dict_metadata sources {sorted(metadata)}")
    for source, (word_count, from_lang, to_lang) in metadata.items():
        if word_count != counts.get(source, 0):
            failures.append(f"{source}: word_count {word_count} but {counts.get(source, 0)} rows")
        if not (ISO_639_3.fullmatch(from_lang) and ISO_639_3.fullmatch(to_lang)):
            failures.append(f"{source}: from_lang {from_lang!r} and to_lang {to_lang!r} "
                            "must be ISO 639-3 codes")

    max_id = conn.execute("SELECT COALESCE(MAX(id), 0) FROM entries").fetchone()[0]
    if max_id >= 2 ** 40:
        failures.append(f"max(entries.id) = {max_id}, not below 2^40 (imported ids start there)")

    journal = conn.execute("PRAGMA journal_mode").fetchone()[0]
    if journal.lower() != "delete":
        failures.append(f"journal mode {journal}, not DELETE")
    user_version = conn.execute("PRAGMA user_version").fetchone()[0]
    if user_version != FORMAT_VERSION:
        failures.append(f"user_version {user_version}, not {FORMAT_VERSION}")

    if failures:
        sys.exit("Build checks failed:\n  - " + "\n  - ".join(failures))
    print(f"Checks passed: integrity, FTS, {len(metadata)} sources' word_count and "
          f"languages, max id {max_id:,}, journal mode DELETE, user_version {user_version}.")


def table_sizes(conn: sqlite3.Connection) -> list[tuple[str, int]]:
    """Bytes per table (dbstat), each with its indexes; an FTS table with
    its shadow tables."""
    virtual = [name for (name,) in conn.execute(
        "SELECT name FROM sqlite_master WHERE sql LIKE 'CREATE VIRTUAL TABLE%'")]
    sizes: dict[str, int] = {}
    for name, size in conn.execute("""
            SELECT COALESCE(m.tbl_name, d.name), SUM(d.pgsize)
            FROM dbstat AS d LEFT JOIN sqlite_master AS m ON m.name = d.name
            GROUP BY 1"""):
        owner = next((v for v in virtual if name.startswith(v + "_")), name)
        sizes[owner] = sizes.get(owner, 0) + size
    return sorted(sizes.items(), key=lambda item: (-item[1], item[0]))


def build(output: Path, cache_dir: Path) -> None:
    """Build the dictionary file at `output`. A failed build leaves the
    file that was there."""
    print(f"Building {output} (SQLite {sqlite3.sqlite_version}, cache {cache_dir})")
    steps = [importlib.import_module(name) for name in STEPS]
    partial = output.with_name(output.name + ".part")
    for leftover in (partial, partial.with_name(partial.name + "-journal")):
        leftover.unlink(missing_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(partial)
    try:
        conn.execute("PRAGMA page_size = 4096")
        conn.execute("PRAGMA journal_mode = DELETE")
        conn.executescript(SCHEMA)
        for step in steps:
            conn.executescript(step.SCHEMA)
        conn.execute(f"PRAGMA user_version = {FORMAT_VERSION}")

        print("\nDictionaries")
        dropped: dict[str, int] = {}
        for builder in DICTIONARY_BUILDERS:
            for d in builder(cache_dir):
                dropped[d.source] = insert_dictionary(conn, d)

        for name, step in zip(STEPS, steps):
            print(f"\nStep {name}")
            step.build(conn, cache_dir)
            conn.commit()

        print("\nRebuilding the FTS index...")
        with conn:
            conn.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")
        check(conn)
        print("Vacuuming...")
        conn.execute("VACUUM")

        total = conn.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        print(f"\nRows: {total:,}; dropped as repeated headwords: "
              + ", ".join(f"{source} {n:,}" for source, n in dropped.items()))
        try:
            sizes = table_sizes(conn)
        except sqlite3.OperationalError as error:  # SQLite built without dbstat
            sizes = []
            print(f"Sizes skipped: {error}")
        if sizes:
            print("Sizes (dbstat):")
        for name, size in sizes:
            print(f"  {name:<24} {size / 1e6:9.1f} MB  {size:>13,} B")
    finally:
        conn.close()
    os.replace(partial, output)
    size = output.stat().st_size
    print(f"  {'total':<24} {size / 1e6:9.1f} MB  {size:>13,} B")
    print(f"sha256 {inputs.sha256(output)}  {output}")


def sqlite_version_of(path: Path) -> str:
    """The SQLite version that last wrote `path` (header offset 96)."""
    with open(path, "rb") as f:
        n = int.from_bytes(f.read(100)[96:100], "big")
    return f"{n // 1000000}.{n // 1000 % 1000}.{n % 1000}"


def verify(committed: Path, cache_dir: Path) -> int:
    """Rebuild into a temp file and compare its sha256 with `committed`."""
    if not committed.is_file():
        sys.exit(f"{committed} does not exist")
    with open(committed, "rb") as f:
        if f.read(16) != b"SQLite format 3\0":
            sys.exit(f"{committed} is not an SQLite file (a Git LFS pointer? git lfs pull)")
    with tempfile.TemporaryDirectory() as folder:
        built = Path(folder) / committed.name
        build(built, cache_dir)
        expected, actual = inputs.sha256(committed), inputs.sha256(built)
    print(f"\ncommitted {expected}  {committed}")
    print(f"rebuilt   {actual}")
    if actual != expected:
        print(f"MISMATCH. The committed file was written by SQLite {sqlite_version_of(committed)}, "
              f"this build used {sqlite3.sqlite_version}.")
        return 1
    print("OK: the rebuilt file is byte-identical to the committed one.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build dictionaries.sqlite, the app's read-only dictionary file.")
    parser.add_argument("--output", "-o", type=Path, default=DEFAULT_OUTPUT,
                        help=f"The file to write, or with --verify the file to compare "
                             f"(default: {DEFAULT_OUTPUT.relative_to(REPO)}).")
    parser.add_argument("--cache-dir", type=Path, default=inputs.DEFAULT_CACHE_DIR,
                        help="Where the pinned inputs are downloaded (default: Scripts/.cache).")
    parser.add_argument("--verify", action="store_true",
                        help="Rebuild into a temp file and compare its sha256 with --output.")
    args = parser.parse_args()
    if args.verify:
        return verify(args.output.resolve(), args.cache_dir.resolve())
    build(args.output.resolve(), args.cache_dir.resolve())
    return 0


if __name__ == "__main__":
    sys.exit(main())
