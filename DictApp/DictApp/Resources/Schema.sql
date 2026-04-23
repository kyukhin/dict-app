-- Schema.sql
-- Dictionary database schema with FTS5 for fast full-text search.

-- Main entries table: stores the canonical data.
CREATE TABLE IF NOT EXISTS entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word        TEXT    NOT NULL,
    definition  TEXT    NOT NULL,
    phonetic    TEXT    DEFAULT '',
    pos         TEXT    DEFAULT '',          -- part of speech
    source      TEXT    DEFAULT 'default',   -- which dictionary file it came from
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- Unique constraint: no duplicate word+source pairs.
CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_word_source
    ON entries(word COLLATE NOCASE, source);

-- FTS5 virtual table for sub-millisecond prefix search.
-- unicode61 tokenizer handles both Latin and Cyrillic characters.
CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    word,
    definition,
    content='entries',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

-- Triggers to keep the FTS index in sync with the main table.
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

-- History table: tracks recently looked-up words (no duplicates).
CREATE TABLE IF NOT EXISTS history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word        TEXT    NOT NULL UNIQUE,
    looked_at   TEXT    DEFAULT (datetime('now'))
);

-- Bookmarks table.
CREATE TABLE IF NOT EXISTS bookmarks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id    INTEGER NOT NULL UNIQUE REFERENCES entries(id) ON DELETE CASCADE,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- Metadata table: stores info about each loaded dictionary.
CREATE TABLE IF NOT EXISTS dict_metadata (
    source       TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    version      TEXT NOT NULL DEFAULT '',
    license      TEXT NOT NULL DEFAULT '',
    url          TEXT NOT NULL DEFAULT '',
    word_count   INTEGER NOT NULL DEFAULT 0,
    built_at     TEXT NOT NULL DEFAULT (datetime('now')),
    description  TEXT NOT NULL DEFAULT ''
);
