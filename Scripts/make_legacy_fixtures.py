#!/usr/bin/env python3
"""
make_legacy_fixtures.py
Writes the 1.x database fixtures of the #139 migration tests
(docs/specs/0129-dictionary-file.md, Test plan): what a LibreDict 1.x
install keeps in `Application Support/DictApp/dict.sqlite`, small enough to
commit. `LegacyMigrationTests` moves them into a user database.

Each fixture is built from its release tag:
  1. The tag's `Schema.sql` in WAL mode, as 1.x opened its database, then
     the tag's launch migrations (`user_version = 1` from 1.3.0 on).
  2. A subset of the tag's `seed.sqlite` (read through `git lfs smudge`, so
     the LFS object must be in .git/lfs): the first rows of every source plus
     the words the user data below needs, copied the way 1.x unpacked them
     (`INSERT OR IGNORE`, source by source, with the `dict_metadata` rows).
  3. Fixed user data with fixed timestamps: two imports, `my_glossary` and
     one named like a bundled source whose first word the bundle already has
     (so 1.x's `INSERT OR IGNORE` skipped it), bookmarks on bundled and
     imported entries, and History rows, one of them without a source.

  legacy-1.2.0.sqlite  v1.2.0  the 1.1/1.2 shape: no `word_normalized`, no
                               `history.source`; WordNet and OpenRussian
  legacy-1.3.0.sqlite  v1.3.0  five sources
  legacy-1.4.0.sqlite  v1.4.0  nine sources (Greek)

`--full PATH` writes a full-size 1.4.0 database instead: every seed row,
2,003 imported rows, 100 History rows and 50 bookmarks. It is for timing the
move locally (`LIBREDICT_LEGACY_DB`) and is never committed.

Usage:
    python3 Scripts/make_legacy_fixtures.py
    python3 Scripts/make_legacy_fixtures.py --full /tmp/dict-1.4.0-full.sqlite
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_PATH = "DictApp/DictApp/Resources/Schema.sql"
SEED_PATH = "DictApp/DictApp/Resources/seed.sqlite"
OUTPUT_DIR = "DictApp/DictAppTests"
FIXTURES = {"v1.2.0": "legacy-1.2.0.sqlite", "v1.3.0": "legacy-1.3.0.sqlite", "v1.4.0": "legacy-1.4.0.sqlite"}
MAX_BYTES = 1_000_000

SUBSET = 40  # first rows of every bundled source
UNPACKED_AT = "2026-04-01 00:00:00"  # created_at of the copied seed rows

GLOSSARY = "my_glossary"
GLOSSARY_AT = "2026-05-10 12:00:00"
GLOSSARY_ROWS = [
    ("house", "My note: a building to live in."),
    ("housesitter", "Someone who looks after a home while its owners are away."),
    ("zorblat", "A made-up word of the legacy fixture."),
    ("quindle", "A second made-up word."),
    ("flumox", "A third made-up word."),
    ("brantoor", "A fourth made-up word."),
    ("wexley", "A fifth made-up word."),
]
# Imported under a bundled source ID: `freedict-eng-spa`, or `wordnet` where
# the tag has no Spanish. "dog" is a bundled word, so 1.x kept the bundled row.
NAMED_AT = "2026-05-20 19:30:00"
NAMED_ROWS = [
    ("dog", "perro (imported)"),
    ("doomscroll", "hacer scroll sin fin"),
    ("photobomb", "colarse en una foto"),
    ("dogsitter", "cuidador de perros"),
]
NAMED = "<named like a bundled source>"

# (source, word), dated BOOKMARKED_AT + i hours. Rows of a source the tag
# lacks are left out.
BOOKMARKED_AT = "2026-06-01 09:00:00"
BOOKMARKS = [
    ("wordnet", "dog"),
    ("freedict-eng-spa", "house"),
    ("openrussian", "дом"),
    ("wordnet-arb-eng", "كِتاب"),
    ("freedict-ell-eng", "σπίτι"),
    (GLOSSARY, "zorblat"),
    (NAMED, "dogsitter"),
]
# (word, source), looked at LOOKED_AT + i hours. `''` is a row from before
# 1.3.0, when History had no source.
LOOKED_AT = "2026-06-02 08:00:00"
HISTORY = [
    ("dog", "wordnet"),
    ("house", "freedict-eng-spa"),
    ("дом", "openrussian"),
    ("كِتاب", "wordnet-arb-eng"),
    ("σπίτι", "freedict-ell-eng"),
    ("zorblat", GLOSSARY),
    ("dogsitter", NAMED),
    ("casa", ""),
]


def git(*args: str, stdin: bytes | None = None) -> bytes:
    return subprocess.run(["git", *args], cwd=REPO, input=stdin, check=True,
                          stdout=subprocess.PIPE).stdout


def seed_bytes(tag: str) -> bytes:
    blob = git("show", f"{tag}:{SEED_PATH}")
    if blob.startswith(b"version https://git-lfs"):
        blob = git("lfs", "smudge", stdin=blob)
    if not blob.startswith(b"SQLite format 3\0"):
        sys.exit(f"{tag}:{SEED_PATH} did not resolve to an SQLite file (git lfs fetch?)")
    return blob


def columns(conn: sqlite3.Connection, table: str, schema: str = "main") -> list[str]:
    return [r[1] for r in conn.execute(f"PRAGMA {schema}.table_info({table})")]


def build(tag: str, output: str, folder: str, full: bool = False) -> None:
    seed_path = os.path.join(folder, f"seed-{tag}.sqlite")
    with open(seed_path, "wb") as f:
        f.write(seed_bytes(tag))
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(output + suffix):
            os.remove(output + suffix)

    conn = sqlite3.connect(output, isolation_level=None)
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(git("show", f"{tag}:{SCHEMA_PATH}").decode())
    has_normalized = "word_normalized" in columns(conn, "entries")
    has_history_source = "source" in columns(conn, "history")
    if has_normalized:
        conn.execute("PRAGMA user_version = 1")  # 1.3.0's `migrate`, a no-op on this schema

    conn.execute("ATTACH DATABASE ? AS bundled", (seed_path,))
    sources = [r[0] for r in conn.execute("SELECT source FROM bundled.dict_metadata ORDER BY rowid")]
    named = "freedict-eng-spa" if "freedict-eng-spa" in sources else "wordnet"
    imported = {GLOSSARY, named}

    def source_of(source: str) -> str:
        return named if source == NAMED else source

    bookmarks = [(source_of(s), w) for s, w in BOOKMARKS if source_of(s) in set(sources) | imported]
    history = [(w, source_of(s)) for w, s in HISTORY if s == "" or source_of(s) in set(sources) | imported]

    # The bundled rows, as 1.x unpacked them (1.4.0: wordnet first for an English UI).
    entry_columns = ["word"] + (["word_normalized"] if has_normalized else []) + [
        "definition", "phonetic", "pos", "source"]
    names = ", ".join(entry_columns)
    conn.execute("BEGIN")
    for source in sorted(sources, key=lambda s: s != "wordnet"):
        words = {w for s, w in bookmarks if s == source} | {w for w, s in history if s == source}
        if source == named:
            words.add(NAMED_ROWS[0][0])
        marks = ", ".join("?" for _ in words) or "NULL"
        subset = "" if full else f"""
            AND (id IN (SELECT id FROM bundled.entries WHERE source = ? ORDER BY id LIMIT {SUBSET})
                 OR word IN ({marks}))"""
        conn.execute(f"""
            INSERT OR IGNORE INTO main.entries({names}, created_at)
            SELECT {names}, ? FROM bundled.entries
            WHERE source = ? {subset}
            ORDER BY id
            """, (UNPACKED_AT, source) + (() if full else (source, *sorted(words))))
    shared = [c for c in columns(conn, "dict_metadata") if c in columns(conn, "dict_metadata", "bundled")]
    conn.execute(f"""
        INSERT OR REPLACE INTO main.dict_metadata({", ".join(shared)})
        SELECT {", ".join(shared)} FROM bundled.dict_metadata ORDER BY rowid
        """)
    conn.execute("COMMIT")
    conn.execute("DETACH DATABASE bundled")

    # Imports, as 1.x's importJSON wrote them: `INSERT OR IGNORE`, the
    # search key is the word.
    glossary = list(GLOSSARY_ROWS)
    if full:
        glossary += [(f"glossword{i}", f"custom gloss {i}") for i in range(2000 - len(glossary))]
    conn.execute("BEGIN")
    for source, at, rows in ((GLOSSARY, GLOSSARY_AT, glossary), (named, NAMED_AT, NAMED_ROWS)):
        for word, definition in rows:
            values = [word] + ([word] if has_normalized else []) + [definition, "", "", source, at]
            conn.execute(f"""
                INSERT OR IGNORE INTO entries({names}, created_at)
                VALUES ({", ".join("?" for _ in values)})
                """, values)

    if full:
        more = conn.execute("SELECT source, word FROM entries WHERE id % 4000 = 7 ORDER BY id").fetchall()
        bookmarks += [k for k in more if k not in bookmarks][:50 - len(bookmarks)]
        words = {w for w, _ in history}
        history += [(w, s) for s, w in more if w not in words][:100 - len(history)]
    for i, (source, word) in enumerate(bookmarks):
        ids = [r[0] for r in conn.execute("SELECT id FROM entries WHERE source = ? AND word = ?", (source, word))]
        if len(ids) != 1:
            sys.exit(f"{tag}: bookmark {source}/{word} matches {len(ids)} entries")
        conn.execute("INSERT INTO bookmarks(entry_id, created_at) VALUES (?, datetime(?, ?))",
                     (ids[0], BOOKMARKED_AT, f"+{i} hours"))
    for i, (word, source) in enumerate(history):
        if has_history_source:
            conn.execute("INSERT INTO history(word, source, looked_at) VALUES (?, ?, datetime(?, ?))",
                         (word, source, LOOKED_AT, f"+{i} hours"))
        else:
            conn.execute("INSERT INTO history(word, looked_at) VALUES (?, datetime(?, ?))",
                         (word, LOOKED_AT, f"+{i} hours"))
    conn.execute("COMMIT")

    conn.execute("INSERT INTO entries_fts(entries_fts) VALUES('integrity-check')")
    if not full:
        conn.execute("VACUUM")
    conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    counts = conn.execute("""
        SELECT (SELECT COUNT(*) FROM entries), (SELECT COUNT(*) FROM history), (SELECT COUNT(*) FROM bookmarks)
        """).fetchone()
    conn.close()
    for suffix in ("-wal", "-shm"):
        if os.path.exists(output + suffix):
            os.remove(output + suffix)

    size = os.path.getsize(output)
    if not full and size >= MAX_BYTES:
        sys.exit(f"{output} is {size:,} bytes; fixtures stay under {MAX_BYTES:,}")
    print(f"{os.path.relpath(output, REPO)}: {tag}, {counts[0]} entries, {counts[1]} History rows, "
          f"{counts[2]} bookmarks, imports {GLOSSARY} and {named}, {size:,} bytes")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--full", metavar="PATH",
                        help="write a full-size 1.4.0 database to PATH for local timing, instead of the fixtures")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as folder:
        if args.full:
            build("v1.4.0", os.path.abspath(args.full), folder, full=True)
            return
        for tag, name in FIXTURES.items():
            build(tag, os.path.join(REPO, OUTPUT_DIR, name), folder)


if __name__ == "__main__":
    main()
