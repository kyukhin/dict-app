-- The grammar reference (docs/specs/0133-grammar.md, "Build step"), applied
-- by `build_grammar.py` and read by the unit tests. Greek rows go into the
-- Greek pack, English rows (2.1.0) into the English lists pack; every other
-- file has the tables, empty (0237, one schema everywhere).

-- One row per topic. Ids are permanent.
CREATE TABLE grammar_topic (
    id     TEXT PRIMARY KEY,   -- 'ell-aorist-regular'
    lang   TEXT NOT NULL,      -- the language taught, ISO 639-3 (the issue's target_lang)
    level  TEXT NOT NULL,      -- 'A1' … 'C2'; sorts as text
    ord    INTEGER NOT NULL,   -- order within the language and level
    UNIQUE (lang, level, ord)
);

-- One row per topic and explanation language.
CREATE TABLE grammar_text (
    topic_id     TEXT NOT NULL,  -- grammar_topic.id
    explain_lang TEXT NOT NULL,  -- ISO 639-3: 'eng'
    title        TEXT NOT NULL,
    body         TEXT NOT NULL,  -- the Markdown after the title, forms tables rendered
    PRIMARY KEY (topic_id, explain_lang)
) WITHOUT ROWID;

-- The front matter's links, in their order.
CREATE TABLE grammar_link (
    topic_id TEXT NOT NULL,
    kind     TEXT NOT NULL,      -- 'word' | 'topic' | 'tense' | 'class'
    key      TEXT NOT NULL,      -- a Greek headword (NFC), a topic id, a ConjugationTense raw value, a class
    ord      INTEGER NOT NULL,
    PRIMARY KEY (topic_id, kind, key)
) WITHOUT ROWID;
