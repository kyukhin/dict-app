-- Word lists (#130, docs/specs/0130-word-lists.md, "List data"): the DDL of
-- `build_wordlists.py`. The step applies it, and the unit tests read this
-- file through `#filePath` to build test dictionaries, so it exists once.
-- Every dictionary file has these tables (0237, "The catalog"); a language's
-- pack fills them with its lists.

-- One row per built-in list. Ids are permanent, like source IDs.
CREATE TABLE wordlist (
    id          TEXT PRIMARY KEY,        -- 'ky-ell-a1', …, 'cefr-eng-c2'
    lang        TEXT NOT NULL,           -- ISO 639-3
    series      TEXT NOT NULL,           -- 'ky-ell', 'cefr-eng'
    level       TEXT NOT NULL,           -- 'A1' … 'C2'
    level_ord   INTEGER NOT NULL,        -- 1 … 6; the list holds the words of this level only
    word_count  INTEGER NOT NULL,        -- checked by the build
    data_source TEXT NOT NULL            -- data_source.id, for Credits
);

-- One row per word of a series, with the level that introduces it.
CREATE TABLE wordlist_item (
    series      TEXT NOT NULL,
    term        TEXT NOT NULL COLLATE NOCASE,  -- NFC, trimmed, as the list writes it
    headword    TEXT,                          -- the linked headword; NULL = standalone
    translation TEXT NOT NULL DEFAULT '',
    endings     TEXT NOT NULL DEFAULT '',
    pos         TEXT NOT NULL DEFAULT '',
    tags        TEXT NOT NULL DEFAULT '',
    level       TEXT NOT NULL DEFAULT '',
    level_ord   INTEGER NOT NULL DEFAULT 0,
    rank        INTEGER,                       -- frequency rank; NULL = unranked
    seq         INTEGER NOT NULL,              -- order in the source files
    sort_key    TEXT NOT NULL,                 -- alphabetical key
    PRIMARY KEY (series, term)
) WITHOUT ROWID;

-- Frequency ranks for imports: key = folded word (Greek) or lowercase (English).
CREATE TABLE word_rank (
    lang TEXT NOT NULL, key TEXT NOT NULL, rank INTEGER NOT NULL,
    PRIMARY KEY (lang, key)
) WITHOUT ROWID;
