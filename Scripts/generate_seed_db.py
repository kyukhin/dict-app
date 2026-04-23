#!/usr/bin/env python3
"""
generate_seed_db.py
Creates a sample SQLite dictionary database with FTS5 index.

Usage:
    python3 Scripts/generate_seed_db.py              # writes seed.sqlite (1000 words)
    python3 Scripts/generate_seed_db.py --count 100000 --output big.sqlite
    python3 Scripts/generate_seed_db.py --json seed.json  # export as JSON
"""

import argparse
import json
import sqlite3
import sys

SAMPLE_WORDS = [
    ("aardvark", "/ˈɑːrd.vɑːrk/", "noun",
     "A nocturnal burrowing mammal with a long snout, native to Africa."),
    ("aberration", "/ˌæb.əˈreɪ.ʃən/", "noun",
     "A departure from what is normal or expected."),
    ("benevolent", "/bəˈnev.əl.ənt/", "adjective",
     "Well-meaning and kindly."),
    ("cacophony", "/kəˈkɒf.ən.i/", "noun",
     "A harsh, discordant mixture of sounds."),
    ("diligent", "/ˈdɪl.ɪ.dʒənt/", "adjective",
     "Having or showing care in one's work or duties."),
    ("ephemeral", "/ɪˈfem.ər.əl/", "adjective",
     "Lasting for a very short time."),
    ("facetious", "/fəˈsiː.ʃəs/", "adjective",
     "Treating serious issues with deliberately inappropriate humor."),
    ("gregarious", "/ɡrɪˈɡeə.ri.əs/", "adjective",
     "Fond of company; sociable."),
    ("harbinger", "/ˈhɑːr.bɪn.dʒər/", "noun",
     "A person or thing that announces or signals the approach of another."),
    ("idiosyncratic", "/ˌɪd.i.əˌsɪŋˈkræt.ɪk/", "adjective",
     "Relating to the distinctive or peculiar character of a person or thing."),
]


def create_schema(cur: sqlite3.Cursor):
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
    """)


def generate_entries(count: int):
    """Yield (word, phonetic, pos, definition) tuples."""
    for i in range(count):
        idx = i % len(SAMPLE_WORDS)
        base = SAMPLE_WORDS[idx]
        if i < len(SAMPLE_WORDS):
            yield base
        else:
            suffix = f"_{i}"
            yield (
                base[0] + suffix,
                base[1],
                base[2],
                f"{base[3]} (variant {i})",
            )


def write_sqlite(path: str, count: int):
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    create_schema(cur)
    for word, phonetic, pos, definition in generate_entries(count):
        cur.execute(
            "INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source) "
            "VALUES (?, ?, ?, ?, ?)",
            (word, definition, phonetic, pos, "seed"),
        )
    conn.commit()
    final_count = cur.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    conn.close()
    print(f"Wrote {final_count} entries to {path}")


def write_json(path: str, count: int):
    entries = []
    for word, phonetic, pos, definition in generate_entries(count):
        entries.append({
            "word": word,
            "definition": definition,
            "phonetic": phonetic,
            "pos": pos,
        })
    with open(path, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)
    print(f"Wrote {len(entries)} entries to {path}")


def main():
    parser = argparse.ArgumentParser(description="Generate a sample dictionary database.")
    parser.add_argument("--count", type=int, default=1000, help="Number of entries (default: 1000)")
    parser.add_argument("--output", type=str, default="seed.sqlite", help="Output .sqlite file")
    parser.add_argument("--json", type=str, default=None, help="Also export as JSON file")
    args = parser.parse_args()

    write_sqlite(args.output, args.count)
    if args.json:
        write_json(args.json, args.count)


if __name__ == "__main__":
    main()
