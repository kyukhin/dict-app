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

`--packs` writes the 2.0 golden file instead, `search-probe-2.0.json`
(docs/specs/0237-downloads.md, "Search ranking"): the same queries on the
committed English bundle with every language pack attached under its schema
name, as the app attaches them, through the app's 2.0 SQL: one branch per
file that holds an enabled source, each with its own `ORDER BY … LIMIT`,
and one `ORDER BY … LIMIT` over the union. The packs are the committed
assets in `Packs/`, decompressed and checked against the catalog. Any PR
that changes a dictionary's rows regenerates it.

Usage:
    python3 Scripts/make_search_probe.py
    python3 Scripts/make_search_probe.py --tag v1.4.0 \\
        --output DictApp/DictAppTests/search-probe-1.4.0.json
    python3 Scripts/make_search_probe.py --packs
"""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
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
PACKS_OUTPUT = "DictApp/DictAppTests/search-probe-2.0.json"
BUNDLE = "DictApp/DictApp/Resources/dictionaries.sqlite"
# DictionarySchemas.all: the bundle, then the packs in `ord` order.
SCHEMAS = ["dict", "spa", "rus", "arb", "ell", "eng_lists"]

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


# ---------------------------------------------------------------------------
# 2.0: the bundle and the packs (#237)
# ---------------------------------------------------------------------------

def attach_packs(folder: str) -> tuple[sqlite3.Connection, dict[str, str], dict]:
    """An in-memory connection with the committed bundle as `dict` and every
    catalog pack, decompressed from its committed asset, under its schema
    name; the map source → schema (the bundle first) and the files' sha256s."""
    bundle = os.path.join(REPO, BUNDLE)
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.execute("ATTACH DATABASE ? AS dict", ("file:" + bundle + "?mode=ro&immutable=1",))
    files = {"bundle": hashlib.sha256(open(bundle, "rb").read()).hexdigest()}
    for pack in conn.execute("SELECT id, version, file_sha256 FROM dict.catalog_pack ORDER BY ord").fetchall():
        asset = os.path.join(REPO, "Packs", f"{pack['id']}-{pack['version']}.sqlite.xz")
        data = lzma.decompress(open(asset, "rb").read(), format=lzma.FORMAT_XZ)
        if hashlib.sha256(data).hexdigest() != pack["file_sha256"]:
            sys.exit(f"{asset} does not decompress to the catalog's file (git lfs pull?)")
        path = os.path.join(folder, f"{pack['id']}.sqlite")
        with open(path, "wb") as f:
            f.write(data)
        schema = pack["id"].replace("-", "_")
        conn.execute(f"ATTACH DATABASE ? AS {schema}", ("file:" + path + "?mode=ro&immutable=1",))
        files[pack["id"]] = pack["file_sha256"]
    schema_of: dict[str, str] = {}
    for schema in SCHEMAS:
        for (source,) in conn.execute(f"SELECT source FROM {schema}.dict_metadata ORDER BY rowid"):
            schema_of.setdefault(source, schema)
    return conn, schema_of, files


def files_holding(schema_of: dict[str, str], sources: list[str] | None) -> list[str]:
    """`DictionarySchemas.files(holding:)`: the files that hold one of the
    sources (`None`: any source), in `SCHEMAS` order."""
    wanted = set(schema_of.values()) if sources is None else {schema_of[s] for s in sources if s in schema_of}
    return [s for s in SCHEMAS if s in wanted]


def ranked_20(conn: sqlite3.Connection, query: str, sources: list[str] | None, schema_of: dict[str, str],
              relevance_order: bool, limit: int, excluding: list[int] = ()) -> list[sqlite3.Row]:
    """`DatabaseService.rankedEntries` with packs: one branch per file, each
    ordered and cut to `limit`, then one ORDER BY and LIMIT over the union."""
    match, rank_key, raw_key = fts_query(sanitize_fts(query))
    branches, args = [], []
    for schema in files_holding(schema_of, sources):
        branch = f"""SELECT e.id, e.word, e.word_normalized, e.definition, e.phonetic, e.pos, e.source,
                   NULL AS created_at, fts.rank AS rank,
                   (e.word_normalized = ? COLLATE NOCASE OR e.word_normalized = ? COLLATE NOCASE) AS is_exact
            FROM {schema}.entries_fts fts JOIN {schema}.entries e ON e.id = fts.rowid
            WHERE entries_fts MATCH ?"""
        args += [rank_key, raw_key, match]
        if sources is not None:
            branch += " AND e.source IN (" + ", ".join("?" for _ in sources) + ")"
            args += sources
        if excluding:
            branch += " AND e.id NOT IN (" + ", ".join("?" for _ in excluding) + ")"
            args += list(excluding)
        if relevance_order:
            branch += ("\nORDER BY is_exact DESC, (e.word_normalized LIKE ? COLLATE NOCASE "
                       "OR e.word_normalized LIKE ? COLLATE NOCASE) DESC, rank")
            args += [rank_key + "%", raw_key + "%"]
        else:
            branch += "\nORDER BY rank"
        branch += "\nLIMIT ?"
        args.append(limit)
        branches.append("SELECT * FROM (" + branch + ")")
    if not branches:
        return []
    order = ("is_exact DESC, (word_normalized LIKE ? COLLATE NOCASE OR word_normalized LIKE ? COLLATE NOCASE) "
             "DESC, rank") if relevance_order else "rank"
    if relevance_order:
        args += [rank_key + "%", raw_key + "%"]
    return conn.execute("SELECT * FROM (" + "\nUNION ALL\n".join(branches) + f") ORDER BY {order} LIMIT ?",
                        args + [limit]).fetchall()


def relevance_20(conn: sqlite3.Connection, schema_of: dict[str, str], query: str) -> list[list[str]]:
    return [[r["source"], r["word"]] for r in ranked_20(conn, query, None, schema_of, True, LIMIT)]


def preferred_20(conn: sqlite3.Connection, schema_of: dict[str, str], query: str,
                 groups: list[list[str]]) -> list[list[str]]:
    enabled = sorted({s for g in groups for s in g})
    result: list[sqlite3.Row] = []
    taken: list[int] = []
    for members in groups:
        rows = ranked_20(conn, query, members, schema_of, True, TOP_N)
        result += rows
        taken += [r["id"] for r in rows]
    remaining = LIMIT - len(taken)
    if remaining > 0:
        result += ranked_20(conn, query, enabled, schema_of, False, remaining, taken)
    return [[r["source"], r["word"]] for r in result]


def main_packs(output: str) -> None:
    with tempfile.TemporaryDirectory() as folder:
        conn, schema_of, files = attach_packs(folder)
        probe = {
            "about": "Top 50 (source, word) per query as LibreDict 2.0 ranks them, on the English bundle "
                     "with every language pack attached (0237). Written by Scripts/make_search_probe.py "
                     "--packs; do not edit by hand.",
            "tag": "2.0",
            "files": files,
            "sqliteVersion": sqlite3.sqlite_version,
            "limit": LIMIT,
            "topN": TOP_N,
            "relevance": [{"query": q, "results": relevance_20(conn, schema_of, q)} for q in RELEVANCE_QUERIES],
            "preferred": [{"query": q, "groups": ENGLISH_GROUPS,
                           "results": preferred_20(conn, schema_of, q, ENGLISH_GROUPS)}
                          for q in PREFERRED_QUERIES],
        }
        conn.close()
    write(probe, output)


def write(probe: dict, output_path: str) -> None:
    for kind in ("relevance", "preferred"):
        for item in probe[kind]:
            if not item["results"]:
                sys.exit(f"{kind} '{item['query']}' returned nothing: not a useful probe")
    output = os.path.join(REPO, output_path)
    with open(output, "w", encoding="utf-8") as f:
        json.dump(probe, f, ensure_ascii=False, indent=1)
        f.write("\n")
    lists = len(probe["relevance"]) + len(probe["preferred"])
    print(f"Wrote {lists} lists to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--tag", default="v1.4.0", help="the release whose seed and SQL make the golden lists")
    parser.add_argument("--output", help="path of the golden file, from the repo root "
                                         f"(default: {DEFAULT_OUTPUT}, with --packs {PACKS_OUTPUT})")
    parser.add_argument("--packs", action="store_true",
                        help="write the 2.0 golden lists: the bundle with every pack attached")
    args = parser.parse_args()
    if args.packs:
        main_packs(args.output or PACKS_OUTPUT)
        return

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
    write(probe, args.output or DEFAULT_OUTPUT)


if __name__ == "__main__":
    main()
