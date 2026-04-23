#!/usr/bin/env python3
"""
download_wordnet.py
Downloads the WordNet 3.1 English dictionary via NLTK and converts it into
a SQLite database that matches the DictApp schema (entries table + FTS5 index).

WordNet is released under a BSD-style license and is public domain for all
practical purposes.

Requirements:
    pip3 install nltk

Usage:
    python3 Scripts/download_wordnet.py
    python3 Scripts/download_wordnet.py --output path/to/seed.sqlite
    python3 Scripts/download_wordnet.py --limit 5000   # subset for testing
"""

import argparse
import os
import sqlite3
import sys
import textwrap

def ensure_nltk():
    """Install nltk if missing, then download WordNet data."""
    try:
        import nltk
    except ImportError:
        print("Installing nltk...")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "nltk"])
        import nltk

    # Download only what we need (small ~30 MB).
    for corpus in ("wordnet", "omw-1.4"):
        try:
            nltk.data.find(f"corpora/{corpus}")
        except LookupError:
            print(f"Downloading NLTK corpus: {corpus}...")
            nltk.download(corpus, quiet=True)

    return nltk

def pos_tag_to_label(pos: str) -> str:
    """Convert WordNet POS tag to human-readable label."""
    return {
        "n": "noun",
        "v": "verb",
        "a": "adjective",
        "r": "adverb",
        "s": "adjective satellite",
    }.get(pos, pos)

def build_definition(synsets) -> str:
    """
    Build a Markdown-formatted definition string from a list of synsets.
    Groups by part-of-speech, numbers each sense, and includes examples.
    """
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
        parts.append("")  # blank line between POS groups

    return "\n".join(parts).strip()

def extract_pos_tags(synsets) -> str:
    """Return deduplicated, comma-separated POS labels."""
    tags = dict.fromkeys(pos_tag_to_label(ss.pos()) for ss in synsets)
    return ", ".join(tags)

def create_database(path: str, limit: int | None = None):
    """Download WordNet and write a fully indexed SQLite database."""
    nltk = ensure_nltk()
    from nltk.corpus import wordnet as wn

    # Collect all lemma names (unique words).
    all_lemmas = sorted(set(wn.all_lemma_names()))
    if limit:
        all_lemmas = all_lemmas[:limit]

    total = len(all_lemmas)
    print(f"Processing {total} words from WordNet...")

    # Remove existing file so we start fresh.
    if os.path.exists(path):
        os.remove(path)

    conn = sqlite3.connect(path)
    cur = conn.cursor()

    # Apply the same schema used by DictApp.
    cur.executescript("""
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
            word,
            definition,
            content='entries',
            content_rowid='id',
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
    """)

    # Batch insert for speed.
    batch_size = 500
    batch = []
    inserted = 0

    for i, lemma in enumerate(all_lemmas):
        synsets = wn.synsets(lemma)
        if not synsets:
            continue

        # Use underscore-free display form.
        display_word = lemma.replace("_", " ")
        definition = build_definition(synsets)
        pos = extract_pos_tags(synsets)

        batch.append((display_word, definition, "", pos, "wordnet"))

        if len(batch) >= batch_size:
            cur.executemany(
                "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
                "VALUES (?, ?, ?, ?, ?)",
                batch,
            )
            conn.commit()
            inserted += len(batch)
            batch.clear()
            pct = int((i + 1) / total * 100)
            print(f"\r  [{pct:3d}%] {inserted} entries written...", end="", flush=True)

    # Flush remaining.
    if batch:
        cur.executemany(
            "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
            "VALUES (?, ?, ?, ?, ?)",
            batch,
        )
        conn.commit()
        inserted += len(batch)

    final_count = cur.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    conn.close()

    size_mb = os.path.getsize(path) / (1024 * 1024)
    print(f"\n\nDone! {final_count} entries written to {path} ({size_mb:.1f} MB)")
    print(f"Schema: entries (id, word, definition, phonetic, pos, source, created_at)")
    print(f"        entries_fts (FTS5 index on word + definition)")
    print(f"        history, bookmarks")

def main():
    parser = argparse.ArgumentParser(
        description="Download WordNet and build a DictApp-compatible SQLite dictionary."
    )
    parser.add_argument(
        "--output", "-o",
        default="DictApp/DictApp/Resources/seed.sqlite",
        help="Output path (default: DictApp/DictApp/Resources/seed.sqlite)",
    )
    parser.add_argument(
        "--limit", "-l",
        type=int,
        default=None,
        help="Limit to first N words (for testing). Omit for full ~147k word dictionary.",
    )
    args = parser.parse_args()

    # Ensure output directory exists.
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    create_database(args.output, args.limit)

if __name__ == "__main__":
    main()
