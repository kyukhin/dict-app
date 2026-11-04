#!/usr/bin/env python3
"""
build_wordlists.py
The word lists, a static data step of `build_dictionaries.py`
(docs/specs/0130-word-lists.md, "List data"): the built-in lists, their
words linked to the dictionaries, and frequency ranks, in the tables of
`wordlists_schema.sql`.

Empty until #152 (Kirill's Greek lists) and #153 (the English CEFR lists)
fill it. The first of them registers the step in `STEPS`, after
`build_forms` and `build_morphy`, whose tables it reads, and bumps
`FORMAT_VERSION`: the new tables change the file's shape (0129, "Adding
static data"). Until then nothing runs it, and the dictionary file is
unchanged.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

# The DDL lives in one file, which the app's unit tests read too.
SCHEMA = (Path(__file__).resolve().parent / "wordlists_schema.sql").read_text(encoding="utf-8")
TABLES = ("wordlist", "wordlist_item", "word_rank")


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """The `STEPS` entry point of build_dictionaries.py. Fills nothing yet
    (#152, #153)."""
