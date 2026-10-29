#!/usr/bin/env python3
"""
make_search_probe.py
Writes the search probe golden file (docs/specs/0129-dictionary-file.md,
Test plan): the top 50 (source, word) of every probe query as LibreDict
1.4.0 ranks them. `SearchProbeTests` runs the same queries through the
app's `DatabaseService` and compares the lists.

How the 1.4.0 results are made:
  1. The tag's `Schema.sql` and `seed.sqlite` are read from git (the seed
     through `git lfs smudge`, so the LFS object must be in .git/lfs).
  2. A 1.4.0 database is built the way a fresh English-UI install copied
     the seed into its own database (#111): `wordnet` first, then the other
     sources in seed order, each copied with 1.4.0's `INSERT OR IGNORE … ORDER BY id`, the
     triggers filling `entries_fts`.
  3. Each query runs through 1.4.0's `sanitizeFTS`, `Search.ftsQuery` and
     search SQL, copied verbatim from the tag's DatabaseService.swift.

Any PR that changes the bundled entries regenerates this file, and the
change is reviewed.

Usage:
    python3 Scripts/make_search_probe.py
    python3 Scripts/make_search_probe.py --tag v1.4.0 \\
        --output DictApp/DictAppTests/search-probe-1.4.0.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_greek import normalize_greek  # noqa: E402  (Search.foldGreek's twin)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Paths inside the tag's tree: 1.4.0 names (#140 removed Schema.sql and
# renamed the seed to dictionaries.sqlite).
SCHEMA_PATH = "DictApp/DictApp/Resources/Schema.sql"
SEED_PATH = "DictApp/DictApp/Resources/seed.sqlite"
DEFAULT_OUTPUT = "DictApp/DictAppTests/search-probe-1.4.0.json"

LIMIT = 50
TOP_N = 4  # Search.preferredDictionaryTopN

# en, ru, es, ar, el. `entry` matches the import fixtures' definitions.
RELEVANCE_QUERIES = [
    "house", "a", "the", "ice cream", "dog", "water", "run", "entry", "light",
    "дом", "вод", "говорить",
    "casa", "comer", "agua", "perro",
    "كتاب", "ماء", "بيت",
    "γράφω", "γραφω", "νερο", "σκυλος",
]
PREFERRED_QUERIES = ["house", "casa", "νερο"]

# The pair groups of a fresh English install's Dictionary Order
# (DictionaryDefaults.defaultOrder for "en", then DictionaryGrouping.sourceGroups).
ENGLISH_GROUPS = [
    ["wordnet"],
    ["freedict-eng-spa", "wordnet-spa-eng"],
    ["openrussian"],
    ["freedict-ell-eng", "wordnet-eng-ell", "freedict-eng-ell", "wordnet-ell-eng"],
    ["wordnet-arb-eng"],
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


def build_140_database(tag: str, folder: str) -> tuple[str, str]:
    """The 1.4.0 database of a fresh English install, and the seed's sha256."""
    seed = seed_bytes(tag)
    seed_path = os.path.join(folder, "seed.sqlite")
    with open(seed_path, "wb") as f:
        f.write(seed)
    db_path = os.path.join(folder, "dict.sqlite")
    conn = sqlite3.connect(db_path, isolation_level=None)
    conn.executescript(git("show", f"{tag}:{SCHEMA_PATH}").decode())
    conn.execute("ATTACH DATABASE ? AS bundled", (seed_path,))
    sources = [r[0] for r in conn.execute("SELECT source FROM bundled.dict_metadata ORDER BY rowid")]
    # 1.4.0's copy order for English: wordnet, then preferredSources["en"]
    # (wordnet again), then the rest in seed order.
    order = [s for s in ["wordnet"] if s in sources] + [s for s in sources if s != "wordnet"]
    for source in order:
        conn.execute("BEGIN")
        conn.execute("""
            INSERT OR IGNORE INTO main.entries(word, word_normalized, definition, phonetic, pos, source)
            SELECT word, word_normalized, definition, phonetic, pos, source
            FROM bundled.entries WHERE source = ? ORDER BY id
            """, (source,))
        conn.execute("COMMIT")
    copied, expected = conn.execute(
        "SELECT (SELECT COUNT(*) FROM main.entries), (SELECT SUM(word_count) FROM bundled.dict_metadata)").fetchone()
    if copied != expected:
        sys.exit(f"the 1.4.0 database has {copied} rows, the seed's metadata {expected}")
    conn.execute("INSERT INTO entries_fts(entries_fts) VALUES('integrity-check')")
    conn.execute("DETACH DATABASE bundled")
    conn.close()
    return db_path, hashlib.sha256(seed).hexdigest()


def sanitize_fts(query: str) -> str:
    """`sanitizeFTS`: Unicode letters, marks and digits plus whitespace, trimmed."""
    kept = "".join(ch for ch in query
                   if unicodedata.category(ch)[0] in "LMN" or ch in " \t")
    return kept.strip(" \t")


def fts_query(sanitized: str) -> tuple[str, str, str]:
    """`Search.ftsQuery`: (match, rankKey, rawKey)."""
    folded = normalize_greek(sanitized)
    if folded == sanitized:
        return sanitized + "*", sanitized, sanitized
    return f"({sanitized}*) OR ({folded}*)", folded, sanitized


def relevance(conn: sqlite3.Connection, query: str, limit: int = LIMIT) -> list[list[str]]:
    match, rank_key, raw_key = fts_query(sanitize_fts(query))
    rows = conn.execute("""
        SELECT e.*
        FROM entries_fts fts
        JOIN entries e ON e.id = fts.rowid
        WHERE entries_fts MATCH ?
        ORDER BY
            (e.word_normalized = ? COLLATE NOCASE OR e.word_normalized = ? COLLATE NOCASE) DESC,
            (e.word_normalized LIKE ? COLLATE NOCASE OR e.word_normalized LIKE ? COLLATE NOCASE) DESC,
            rank
        LIMIT ?
        """, (match, rank_key, raw_key, rank_key + "%", raw_key + "%", limit)).fetchall()
    return [[r["source"], r["word"]] for r in rows]


def preferred(conn: sqlite3.Connection, query: str, groups: list[list[str]]) -> list[list[str]]:
    match, rank_key, raw_key = fts_query(sanitize_fts(query))
    enabled = sorted({s for g in groups for s in g})
    result: list[sqlite3.Row] = []
    taken: list[int] = []
    for members in groups:
        marks = ", ".join("?" for _ in members)
        rows = conn.execute(f"""
            SELECT e.*
            FROM entries_fts fts JOIN entries e ON e.id = fts.rowid
            WHERE entries_fts MATCH ? AND e.source IN ({marks})
            ORDER BY (e.word_normalized = ? COLLATE NOCASE OR e.word_normalized = ? COLLATE NOCASE) DESC,
                     (e.word_normalized LIKE ? COLLATE NOCASE OR e.word_normalized LIKE ? COLLATE NOCASE) DESC,
                     rank
            LIMIT ?
            """, (match, *members, rank_key, raw_key, rank_key + "%", raw_key + "%", TOP_N)).fetchall()
        result += rows
        taken += [r["id"] for r in rows]
    remaining = LIMIT - len(taken)
    if remaining > 0:
        marks = ", ".join("?" for _ in enabled)
        not_in = (" AND e.id NOT IN (" + ", ".join("?" for _ in taken) + ")") if taken else ""
        result += conn.execute(f"""
            SELECT e.*
            FROM entries_fts fts JOIN entries e ON e.id = fts.rowid
            WHERE entries_fts MATCH ? AND e.source IN ({marks}){not_in}
            ORDER BY rank
            LIMIT ?
            """, (match, *enabled, *taken, remaining)).fetchall()
    return [[r["source"], r["word"]] for r in result]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--tag", default="v1.4.0", help="the release whose seed and SQL make the golden lists")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="path of the golden file, from the repo root")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as folder:
        db_path, seed_sha = build_140_database(args.tag, folder)
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        probe = {
            "about": "Top 50 (source, word) per query as LibreDict 1.4.0 ranks them. "
                     "Written by Scripts/make_search_probe.py; do not edit by hand.",
            "tag": args.tag,
            "seedSha256": seed_sha,
            "sqliteVersion": sqlite3.sqlite_version,
            "limit": LIMIT,
            "topN": TOP_N,
            "relevance": [{"query": q, "results": relevance(conn, q)} for q in RELEVANCE_QUERIES],
            "preferred": [{"query": q, "groups": ENGLISH_GROUPS, "results": preferred(conn, q, ENGLISH_GROUPS)}
                          for q in PREFERRED_QUERIES],
        }
        conn.close()

    for kind in ("relevance", "preferred"):
        for item in probe[kind]:
            if not item["results"]:
                sys.exit(f"{kind} '{item['query']}' returned nothing: not a useful probe")
    output = os.path.join(REPO, args.output)
    with open(output, "w", encoding="utf-8") as f:
        json.dump(probe, f, ensure_ascii=False, indent=1)
        f.write("\n")
    lists = len(probe["relevance"]) + len(probe["preferred"])
    print(f"Wrote {lists} lists to {args.output}")


if __name__ == "__main__":
    main()
