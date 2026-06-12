-- Schema.sql
-- Dictionary database schema with FTS5 for fast full-text search.

-- Main entries table: stores the canonical data.
CREATE TABLE IF NOT EXISTS entries (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    word            TEXT    NOT NULL,
    word_normalized TEXT    NOT NULL DEFAULT '',   -- search key (Arabic harakat-stripped; == word elsewhere)
    definition      TEXT    NOT NULL,
    phonetic        TEXT    DEFAULT '',
    pos             TEXT    DEFAULT '',          -- part of speech
    source          TEXT    DEFAULT 'default',   -- which dictionary file it came from
    created_at      TEXT    DEFAULT (datetime('now'))
);

-- Unique constraint: no duplicate word+source pairs.
CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_word_source
    ON entries(word COLLATE NOCASE, source);

-- FTS5 virtual table for sub-millisecond prefix search.
-- Indexes word_normalized (not word) so a de-vocalized query matches a
-- vocalized Arabic headword. unicode61 handles Latin, Cyrillic and Arabic.
CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    word_normalized,
    definition,
    content='entries',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

-- Triggers to keep the FTS index in sync with the main table.
CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
    INSERT INTO entries_fts(rowid, word_normalized, definition)
        VALUES (new.id, new.word_normalized, new.definition);
END;

CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, word_normalized, definition)
        VALUES ('delete', old.id, old.word_normalized, old.definition);
END;

CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, word_normalized, definition)
        VALUES ('delete', old.id, old.word_normalized, old.definition);
    INSERT INTO entries_fts(rowid, word_normalized, definition)
        VALUES (new.id, new.word_normalized, new.definition);
END;

-- History table: tracks recently looked-up words (no duplicates).
-- `source` (Issue #6) records the dictionary of the entry last viewed for the
-- word, so the History row can show the same per-source colour stripe as Search.
CREATE TABLE IF NOT EXISTS history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word        TEXT    NOT NULL UNIQUE,
    source      TEXT    NOT NULL DEFAULT '',
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
