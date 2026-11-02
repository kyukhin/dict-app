#!/usr/bin/env python3
"""
build_morphy.py
WordNet's morphy data, a static data step of `build_dictionaries.py`
(docs/specs/0136-word-forms.md, "Morphy (#143)"). The app's `Morphy` port
maps an inflected English query to its lemmas (went → go, dogs → dog) with
two tables:

  - `morphy_exception`: WordNet's exception lists (`noun.exc`, `verb.exc`,
    `adj.exc`, `adv.exc`), one row per (form, pos, base);
  - `morphy_lemma`: the single-word lemmas of `index.noun`, `index.verb`,
    `index.adj` and `index.adv` with their parts of speech, which a
    detachment rule's result must be.

Input: WordNet 3.0 inside the pinned `nltk_data` `wordnet.zip`
(`inputs.json`), read through the shared reader of `inputs.wordnet()`, whose
root is `corpora/wordnet.zip/wordnet/`, never an extracted copy. The data is
the `wordnet` dictionary's, already credited, so the step adds no
`data_source` row. It reads no `entries`.
"""

from __future__ import annotations

import os
import sqlite3
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputs  # noqa: E402

SCHEMA = """
-- WordNet morphy (#143). Every lookup is a primary-key search.
CREATE TABLE morphy_exception (
    form TEXT NOT NULL,   -- an irregular form, as WordNet lists it (went)
    pos  TEXT NOT NULL,   -- n, v, a, r
    base TEXT NOT NULL,   -- a lemma it is a form of (go)
    PRIMARY KEY (form, pos, base)
) WITHOUT ROWID;

CREATE TABLE morphy_lemma (
    word     TEXT PRIMARY KEY,   -- a single-word WordNet lemma, lowercase
    pos_mask INTEGER NOT NULL    -- 1 noun, 2 verb, 4 adj, 8 adv
) WITHOUT ROWID;
"""
TABLES = ("morphy_exception", "morphy_lemma")

# WordNet's file names and the pos letter `morphy_exception` stores.
PARTS_OF_SPEECH = {"noun": "n", "verb": "v", "adj": "a", "adv": "r"}
# `morphy_lemma.pos_mask` bits. Adjective satellites (`s`) are adjectives.
POS_BITS = {"n": 1, "v": 2, "a": 4, "s": 4, "r": 8}
SIZE_BUDGET = 1_500_000  # bytes, the two tables as shipped


def read_lines(wn, name: str) -> list[str]:
    """The lines of one WordNet file, read inside the pinned zip."""
    stream = wn.open(name)
    try:
        return stream.read().splitlines()
    finally:
        stream.close()


def exceptions(wn) -> list[tuple[str, str, str]]:
    """(form, pos, base) of every exception line and base, sorted and
    unique: `noun.exc` repeats three lines."""
    rows = set()
    for name, pos in PARTS_OF_SPEECH.items():
        for line in read_lines(wn, f"{name}.exc"):
            form, *bases = line.split()
            rows.update((form, pos, base) for base in bases)
    return sorted(rows)


def lemmas(wn) -> list[tuple[str, int]]:
    """(word, pos_mask) of every single-word lemma: no `_` (several words)
    and no `-` (words joined), sorted. The license header's lines start
    with two spaces."""
    masks: dict[str, int] = {}
    for name in PARTS_OF_SPEECH:
        for line in read_lines(wn, f"index.{name}"):
            if line.startswith("  "):
                continue
            word, pos = line.split()[:2]
            if "_" in word or "-" in word:
                continue
            masks[word] = masks.get(word, 0) | POS_BITS[pos]
    return sorted(masks.items())


def insert(conn: sqlite3.Connection, exception_rows: list, lemma_rows: list) -> None:
    with conn:
        conn.executemany("INSERT INTO morphy_exception(form, pos, base) VALUES (?, ?, ?)", exception_rows)
        conn.executemany("INSERT INTO morphy_lemma(word, pos_mask) VALUES (?, ?)", lemma_rows)


def shipped_size(exception_rows: list, lemma_rows: list) -> dict[str, int]:
    """Bytes per table as the file ships: the same rows in a file of their
    own, packed by `VACUUM` as the dictionary build packs its file. Pages
    hold one table each, so the size does not depend on the other tables."""
    with tempfile.TemporaryDirectory() as folder:
        conn = sqlite3.connect(Path(folder) / "morphy.sqlite")
        try:
            conn.execute("PRAGMA page_size = 4096")
            conn.executescript(SCHEMA)
            insert(conn, exception_rows, lemma_rows)
            conn.execute("VACUUM")
            sizes = dict.fromkeys(TABLES, 0)
            for table, size in conn.execute(f"""
                    SELECT m.tbl_name, SUM(d.pgsize) FROM dbstat AS d JOIN sqlite_master AS m ON m.name = d.name
                    WHERE m.tbl_name IN ({",".join("?" * len(TABLES))}) GROUP BY m.tbl_name""", TABLES):
                sizes[table] = size
            return sizes
        finally:
            conn.close()


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """The `STEPS` entry point of build_dictionaries.py: fills the two
    tables in key order, then raises if they exceed the spec's budget."""
    wn = inputs.wordnet(Path(cache_dir))
    exception_rows, lemma_rows = exceptions(wn), lemmas(wn)
    insert(conn, exception_rows, lemma_rows)
    try:
        sizes = shipped_size(exception_rows, lemma_rows)
    except sqlite3.OperationalError as error:
        raise RuntimeError(f"The morphy size gate needs SQLite with dbstat: {error}") from error
    total = sum(sizes.values())
    print(f"  {len(exception_rows):,} exception rows, {len(lemma_rows):,} lemmas; "
          + ", ".join(f"{table} {size:,} B" for table, size in sizes.items())
          + f", {total / 1e6:.2f} MB (budget {SIZE_BUDGET / 1e6:.1f} MB)")
    if total > SIZE_BUDGET:
        raise RuntimeError(f"Morphy tables take {total:,} bytes, over the {SIZE_BUDGET:,}-byte budget")
