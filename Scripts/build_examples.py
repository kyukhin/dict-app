#!/usr/bin/env python3
"""
build_examples.py
Example sentences from Tatoeba, a static data step of `build_dictionaries.py`
(docs/specs/0134-example-sentences.md, "Data: tables"). Greek rows go into
the Greek pack, English rows into the English lists pack (`Scripts/packs.json`);
the bundle and the stub have the tables, empty (0237, one schema everywhere).

#240 lands the three tables, empty, in format 4, so #177's rows later change
only the `ell` and `eng-lists` pack versions, never the format (0237, "Format
rule"). Until #177 adds the pipeline, `build()` writes nothing.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

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


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """Fills the example tables: nothing yet, #177 adds the pipeline."""
    print("  " + ", ".join(TABLES) + ": empty until #177")
