#!/usr/bin/env python3
"""
build_wordlists.py
The word lists, a static data step of `build_dictionaries.py`
(docs/specs/0130-word-lists.md, "List data"): the built-in lists, their
words linked to the dictionaries, and frequency ranks, in the tables of
`wordlists_schema.sql`.

#240 registers the step and lands the three tables, empty, in format 4, so
every file has them (0237, one schema everywhere) and #152's and #153's
rows later change only the `ell` and `eng-lists` pack versions, never the
format (0237, "Format rule"). Until #152 (Kirill's Greek lists) and #153
(the English CEFR lists) fill it, `build()` writes nothing.
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
    print("  " + ", ".join(TABLES) + ": empty until #152 and #153")
