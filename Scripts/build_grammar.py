#!/usr/bin/env python3
"""
build_grammar.py
The grammar reference, a static data step of `build_dictionaries.py`
(docs/specs/0133-grammar.md, "Build step"). Its DDL is `grammar_schema.sql`.

#240 lands the three tables, empty, in format 4, so adding grammar later
never forces users to download their packs again (0237, "Format rule").
Until #171 adds the build (parse, render, gates, review document),
`build()` writes nothing.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

SCHEMA = (Path(__file__).resolve().parent / "grammar_schema.sql").read_text(encoding="utf-8")
TABLES = ("grammar_topic", "grammar_text", "grammar_link")


def build(conn: sqlite3.Connection, cache_dir: Path) -> None:
    """Fills the grammar tables: nothing yet, #171 adds the build."""
    print("  " + ", ".join(TABLES) + ": empty until #171")
