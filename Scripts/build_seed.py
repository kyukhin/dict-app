#!/usr/bin/env python3
"""
build_seed.py
Downloads WordNet (En-En), OpenRussian (Ru-En), FreeDict eng-spa
(En-Es) and Spanish WordNet (Es-En) dictionaries, then builds a single
seed.sqlite containing all four sources, an FTS5 index, and a metadata
table.

Sources:
  - WordNet 3.0 via NLTK   (BSD license, Princeton University)
  - OpenRussian.org         (CC-BY-SA 4.0, community-maintained)
  - FreeDict eng-spa        (GPL-3.0, freedict.org — TEI/XML)
  - Spanish WordNet         (CC BY 3.0, MCR / OMW via NLTK)

Source-identifier convention used by this builder:
  - single-monolingual / unambiguous → bare provider name
        e.g. "wordnet", "openrussian".
  - bilingual / multi-direction → "provider-srclang-tgtlang" with
    ISO-639-3 codes, e.g. "freedict-eng-spa", "wordnet-spa-eng".

Requirements:
    pip install nltk requests defusedxml

Usage (from project root):
    source .venv/bin/activate
    python Scripts/build_seed.py
    python Scripts/build_seed.py --output DictApp/DictApp/Resources/seed.sqlite
    python Scripts/build_seed.py --skip-russian          # skip OpenRussian
    python Scripts/build_seed.py --skip-spanish          # skip FreeDict eng-spa
    python Scripts/build_seed.py --skip-spanish-wordnet  # skip Spanish WordNet
    python Scripts/build_seed.py --limit 5000            # subset WordNet (testing)
"""

import argparse
import csv
import io
import os
import sqlite3
import sys
import zipfile
from datetime import datetime

# ---------------------------------------------------------------------------
# NLTK bootstrap
# ---------------------------------------------------------------------------

def ensure_nltk():
    try:
        import nltk
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "nltk"])
        import nltk
    for corpus in ("wordnet", "omw-1.4"):
        try:
            nltk.data.find(f"corpora/{corpus}")
        except LookupError:
            print(f"  Downloading NLTK corpus: {corpus}...")
            nltk.download(corpus, quiet=True)
    return nltk

def ensure_requests():
    try:
        import requests
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "requests"])
        import requests
    return requests


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word        TEXT    NOT NULL,
    definition  TEXT    NOT NULL,
    phonetic    TEXT    DEFAULT '',
    pos         TEXT    DEFAULT '',
    source      TEXT    DEFAULT 'default',
    created_at  TEXT    DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_word_source
    ON entries(word COLLATE NOCASE, source);

CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    word, definition,
    content='entries', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
    INSERT INTO entries_fts(rowid, word, definition)
        VALUES (new.id, new.word, new.definition);
END;
CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, word, definition)
        VALUES ('delete', old.id, old.word, old.definition);
END;
CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, word, definition)
        VALUES ('delete', old.id, old.word, old.definition);
    INSERT INTO entries_fts(rowid, word, definition)
        VALUES (new.id, new.word, new.definition);
END;

CREATE TABLE IF NOT EXISTS history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word        TEXT    NOT NULL UNIQUE,
    looked_at   TEXT    DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS bookmarks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id    INTEGER NOT NULL UNIQUE REFERENCES entries(id) ON DELETE CASCADE,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- Metadata table: stores info about each dictionary source.
CREATE TABLE IF NOT EXISTS dict_metadata (
    source      TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    version     TEXT NOT NULL DEFAULT '',
    license     TEXT NOT NULL DEFAULT '',
    url         TEXT NOT NULL DEFAULT '',
    word_count  INTEGER NOT NULL DEFAULT 0,
    built_at    TEXT NOT NULL DEFAULT (datetime('now')),
    description TEXT NOT NULL DEFAULT ''
);
"""


# ---------------------------------------------------------------------------
# WordNet
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


def insert_wordnet(cur: sqlite3.Cursor, conn: sqlite3.Connection,
                   limit: int | None = None) -> int:
    print("\n[1/4] WordNet (En-En)")
    nltk = ensure_nltk()
    from nltk.corpus import wordnet as wn

    all_lemmas = sorted(set(wn.all_lemma_names()))
    if limit:
        all_lemmas = all_lemmas[:limit]
    total = len(all_lemmas)
    print(f"  Processing {total} lemmas...")

    batch, inserted = [], 0
    for i, lemma in enumerate(all_lemmas):
        synsets = wn.synsets(lemma)
        if not synsets:
            continue
        display_word = lemma.replace("_", " ")
        definition = build_definition(synsets)
        pos = extract_pos_tags(synsets)
        batch.append((display_word, definition, "", pos, "wordnet"))
        if len(batch) >= 500:
            cur.executemany(
                "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
                "VALUES (?, ?, ?, ?, ?)", batch)
            conn.commit()
            inserted += len(batch)
            batch.clear()
            pct = int((i + 1) / total * 100)
            print(f"\r  [{pct:3d}%] {inserted} entries...", end="", flush=True)
    if batch:
        cur.executemany(
            "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
            "VALUES (?, ?, ?, ?, ?)", batch)
        conn.commit()
        inserted += len(batch)

    count = cur.execute(
        "SELECT COUNT(*) FROM entries WHERE source='wordnet'").fetchone()[0]
    wordnet_license = (
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
    wordnet_description = (
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
    cur.execute(
        "INSERT OR REPLACE INTO dict_metadata(source, display_name, version, license, url, word_count, built_at, description) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        ("wordnet", "WordNet", "3.0",
         wordnet_license,
         "https://wordnet.princeton.edu/",
         count, datetime.now(tz=None).isoformat(),
         wordnet_description))
    conn.commit()
    print(f"\n  WordNet: {count} entries")
    return count


# ---------------------------------------------------------------------------
# OpenRussian (Ru-En)
# ---------------------------------------------------------------------------

OPENRUSSIAN_BASE = "https://raw.githubusercontent.com/Badestrand/russian-dictionary/master"
OPENRUSSIAN_FILES = {
    "nouns.csv":      "noun",
    "verbs.csv":      "verb",
    "adjectives.csv": "adjective",
    "others.csv":     "",
}


def download_openrussian_csvs(requests_mod) -> dict[str, str]:
    """Download individual CSV files from the Badestrand/russian-dictionary repo."""
    files = {}
    for filename in OPENRUSSIAN_FILES:
        url = f"{OPENRUSSIAN_BASE}/{filename}"
        print(f"  Downloading {filename}...")
        resp = requests_mod.get(url, timeout=60)
        resp.raise_for_status()
        files[filename] = resp.text
    return files


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


def insert_openrussian(cur: sqlite3.Cursor, conn: sqlite3.Connection) -> int:
    print("\n[2/4] OpenRussian (Ru-En)")
    requests_mod = ensure_requests()

    try:
        csv_files = download_openrussian_csvs(requests_mod)
    except Exception as e:
        print(f"  WARNING: Could not download OpenRussian: {e}")
        print("  Skipping Russian dictionary.")
        return 0

    entries = parse_openrussian(csv_files)
    print(f"  Parsed {len(entries)} Ru-En entries with translations.")

    batch, inserted = [], 0
    total = len(entries)
    for i, row in enumerate(entries):
        batch.append(row)
        if len(batch) >= 500:
            cur.executemany(
                "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
                "VALUES (?, ?, ?, ?, ?)", batch)
            conn.commit()
            inserted += len(batch)
            batch.clear()
            if total > 0:
                pct = int((i + 1) / total * 100)
                print(f"\r  [{pct:3d}%] {inserted} entries...", end="", flush=True)
    if batch:
        cur.executemany(
            "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
            "VALUES (?, ?, ?, ?, ?)", batch)
        conn.commit()
        inserted += len(batch)

    count = cur.execute(
        "SELECT COUNT(*) FROM entries WHERE source='openrussian'").fetchone()[0]
    openrussian_license = (
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
    openrussian_description = (
        "OpenRussian is a free, community-maintained Russian-English dictionary. "
        "It provides translations, stress marks, and grammatical information for Russian "
        "nouns, verbs, adjectives, and other parts of speech.\n\n"
        "The data is crowd-sourced and continuously improved by volunteers. "
        "The dictionary focuses on modern, everyday Russian vocabulary and is "
        "particularly useful for language learners.\n\n"
        "Data sourced from the Badestrand/russian-dictionary GitHub repository."
    )
    cur.execute(
        "INSERT OR REPLACE INTO dict_metadata(source, display_name, version, license, url, word_count, built_at, description) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        ("openrussian", "OpenRussian", "2024",
         openrussian_license,
         "https://openrussian.org/",
         count, datetime.now(tz=None).isoformat(),
         openrussian_description))
    conn.commit()
    print(f"\n  OpenRussian: {count} entries")
    return count


# ---------------------------------------------------------------------------
# FreeDict English-Spanish (En-Es)
# ---------------------------------------------------------------------------

def insert_freedict_eng_spa(cur: sqlite3.Cursor, conn: sqlite3.Connection) -> int:
    print("\n[3/4] FreeDict (En-Es)")
    # Imported lazily so a `--skip-spanish` run doesn't need the module
    # (and so a tools-checkout with an old build_seed.py won't crash on
    # a missing sibling file).
    from build_freedict_eng_spa import (
        download_and_parse,
        DESCRIPTION_TEXT,
        DISPLAY_NAME,
        LICENSE_TEXT,
        SOURCE,
        URL as METADATA_URL,
    )

    # No try/except here: this function only runs when the caller did
    # NOT pass --skip-spanish, i.e. Spanish was explicitly requested. A
    # download/parse failure must surface (non-zero exit) instead of
    # silently shipping a seed without the dictionary the user asked for.
    # Use --skip-spanish to build without it on purpose.
    entries, version = download_and_parse()

    print(f"  Parsed {len(entries)} En-Es entries.")

    batch, inserted = [], 0
    total = len(entries)
    for i, row in enumerate(entries):
        batch.append(row)
        if len(batch) >= 500:
            cur.executemany(
                "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
                "VALUES (?, ?, ?, ?, ?)", batch)
            conn.commit()
            inserted += len(batch)
            batch.clear()
            if total > 0:
                pct = int((i + 1) / total * 100)
                print(f"\r  [{pct:3d}%] {inserted} entries...", end="", flush=True)
    if batch:
        cur.executemany(
            "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
            "VALUES (?, ?, ?, ?, ?)", batch)
        conn.commit()
        inserted += len(batch)

    count = cur.execute(
        "SELECT COUNT(*) FROM entries WHERE source=?", (SOURCE,)).fetchone()[0]
    cur.execute(
        "INSERT OR REPLACE INTO dict_metadata(source, display_name, version, license, url, word_count, built_at, description) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (SOURCE, DISPLAY_NAME, version,
         LICENSE_TEXT,
         METADATA_URL,
         count, datetime.now(tz=None).isoformat(),
         DESCRIPTION_TEXT))
    conn.commit()
    print(f"\n  FreeDict: {count} entries")
    return count


# ---------------------------------------------------------------------------
# Spanish WordNet (Es-En)
# ---------------------------------------------------------------------------

def insert_spanish_wordnet(cur: sqlite3.Cursor, conn: sqlite3.Connection) -> int:
    print("\n[4/4] Spanish WordNet (Es-En)")
    # Imported lazily so a `--skip-spanish-wordnet` run doesn't need the
    # module (and so an old tools-checkout won't crash on a missing
    # sibling file).
    from build_spanish_wordnet import (
        build_and_collect,
        DESCRIPTION_TEXT,
        DISPLAY_NAME,
        LICENSE_TEXT,
        SOURCE,
        URL as METADATA_URL,
    )

    # No try/except: this runs only when --skip-spanish-wordnet was not
    # passed, so a failure must surface rather than silently shipping a
    # seed without the requested dictionary.
    entries, version = build_and_collect()

    print(f"  Built {len(entries)} Es-En entries.")

    batch, inserted = [], 0
    total = len(entries)
    for i, row in enumerate(entries):
        batch.append(row)
        if len(batch) >= 500:
            cur.executemany(
                "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
                "VALUES (?, ?, ?, ?, ?)", batch)
            conn.commit()
            inserted += len(batch)
            batch.clear()
            if total > 0:
                pct = int((i + 1) / total * 100)
                print(f"\r  [{pct:3d}%] {inserted} entries...", end="", flush=True)
    if batch:
        cur.executemany(
            "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
            "VALUES (?, ?, ?, ?, ?)", batch)
        conn.commit()
        inserted += len(batch)

    count = cur.execute(
        "SELECT COUNT(*) FROM entries WHERE source=?", (SOURCE,)).fetchone()[0]
    cur.execute(
        "INSERT OR REPLACE INTO dict_metadata(source, display_name, version, license, url, word_count, built_at, description) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (SOURCE, DISPLAY_NAME, version,
         LICENSE_TEXT,
         METADATA_URL,
         count, datetime.now(tz=None).isoformat(),
         DESCRIPTION_TEXT))
    conn.commit()
    print(f"\n  Spanish WordNet: {count} entries")
    return count


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Build a multi-dictionary seed.sqlite for DictApp.")
    parser.add_argument("--output", "-o",
                        default="DictApp/DictApp/Resources/seed.sqlite")
    parser.add_argument("--limit", "-l", type=int, default=None,
                        help="Limit WordNet to first N lemmas (for testing).")
    parser.add_argument("--skip-russian", action="store_true",
                        help="Skip the OpenRussian dictionary.")
    parser.add_argument("--skip-spanish", action="store_true",
                        help="Skip the FreeDict English-Spanish dictionary.")
    parser.add_argument("--skip-spanish-wordnet", action="store_true",
                        help="Skip the Spanish WordNet (Spanish-English) dictionary.")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    if os.path.exists(args.output):
        os.remove(args.output)

    # Allow `build_freedict_eng_spa` to be imported when this script is
    # run from any working directory.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

    conn = sqlite3.connect(args.output)
    cur = conn.cursor()
    cur.executescript(SCHEMA_SQL)

    wn_count = insert_wordnet(cur, conn, args.limit)
    ru_count = 0
    if not args.skip_russian:
        ru_count = insert_openrussian(cur, conn)
    es_count = 0
    if not args.skip_spanish:
        es_count = insert_freedict_eng_spa(cur, conn)
    spa_wn_count = 0
    if not args.skip_spanish_wordnet:
        spa_wn_count = insert_spanish_wordnet(cur, conn)

    # Rebuild FTS index in bulk. Per-row triggers already kept it in sync
    # during the inserts, but a final rebuild produces a smaller,
    # read-optimised index for the shipped seed.
    print("\nRebuilding FTS index...")
    cur.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")
    conn.commit()

    total = cur.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    size_mb = os.path.getsize(args.output) / (1024 * 1024)
    conn.close()

    print(f"\n{'='*50}")
    print(f"seed.sqlite built successfully!")
    print(f"  Location : {args.output}")
    print(f"  Size     : {size_mb:.1f} MB")
    print(f"  WordNet  : {wn_count:,} entries")
    print(f"  OpenRus  : {ru_count:,} entries")
    print(f"  FreeDict : {es_count:,} entries")
    print(f"  Spa-WN   : {spa_wn_count:,} entries")
    print(f"  Total    : {total:,} entries")
    print(f"{'='*50}")


if __name__ == "__main__":
    main()
