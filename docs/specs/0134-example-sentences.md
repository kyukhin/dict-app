# Example sentences

> Status: Implemented (approved by kyukhin on 2026-11-04); the drill examples (#364, #365) approved by kyukhin on 2026-11-22 · Epic: #134 · Tickets: #177, #178, #339, #364, #365, #362, #378 · Updated: 2026-11-24

Read [0000-overview.md](0000-overview.md), [0129-dictionary-file.md](0129-dictionary-file.md) and [0136-word-forms.md](0136-word-forms.md) first, then the approved specs this epic builds on, still in open PRs: 0237 (downloads: the English bundle and the language packs), 0130 (word lists: `WordKey`) and 0131 (learning). Numbers marked "measured" come from a prototype of the pipeline, run on 2026-11-04 against the Tatoeba export of 2026-10-31 (pinned below) and the dictionary file of master `e9997dd` (151,674,880 bytes, sha256 `24a1494d…`), Python 3.14.0, SQLite 3.51.2.

## Why

- A definition says what a word means. A real sentence shows how it is used, in the form it takes there (έγραψα, θα γράψω; went, mice). Learners need both, and LibreDict 2.0 is for learning Greek and English.
- Tatoeba has 42,985 Greek sentences: 30,811 with an English translation, 5,812 with a Russian one, 2,780 with a Spanish one and 399 with an Arabic one, each written by a named contributor, under CC BY 2.0 FR (measured). It has 2,040,024 English sentences, 675,444 of them directly linked to a Russian, Spanish, Arabic or Greek one.
- Goal: up to five real sentences per Greek word and per word of the English lists, the word's form highlighted, with a translation and the authors, on the Definition screen and in learning. The app code is language-neutral, so other languages need only data.

## Behaviour

### Definition screen (#178)

- A word with examples shows an **Examples** section below the definition and above the inflection table (#144).
- Up to 5 examples, in the order the build chose. 3 show. "More examples" shows the rest and becomes "Fewer examples"; it is hidden with 3 or fewer. The state is not stored, as with "All forms".
- Each example has three lines:
  - the sentence, the word's form in it in bold and in the accent colour. It is selectable, like the definition;
  - its translation, in the secondary colour (rule below);
  - a byline in small print: the sentence's author, then the translation's author when that is someone else, then "Tatoeba": "Zeus, CH · Tatoeba".
- **Translation on the Definition screen** (#178): the one in the UI language when Tatoeba has it and the UI language is not the sentence's own; otherwise the English one, unless the sentence is English; otherwise none. In learning the via language decides instead (Learning, below).

| UI language | Greek sentence | English sentence |
|---|---|---|
| English | English | none |
| Russian | Russian, else English | Russian, else none |
| Spanish | Spanish, else English | Spanish, else none |
| Arabic | Arabic, else English | Arabic, else none |
| Greek | English | Greek, else none |

- **Which words**: an entry shows the examples of its `WordKey` (0130): its dictionary's language and its headword. γράφω from El–En · FD and from El–En · WN show the same examples.
  - Greek headwords (El–En · FD, El–En · WN), from the Greek pack.
  - English headwords (WordNet, En–El · FD, En–El · WN, En–Es · FD) that are words of the English lists (CEFR-J and Octanove, 0130), from the English lists pack. That pack is downloaded only when the user starts learning English (0237, kyukhin 2026-11-04: nothing unneeded on the phone), so a user who only looks up English words sees no English examples.
  - Russian, Spanish, Arabic and imported dictionaries: none.
- A word without examples shows no section and no empty state, like a word without a table.
- Greek examples come with the Greek pack (0237); without it there is no Greek entry to open. English examples come with the English lists pack; without it an English entry shows no section.

γράφω, as the prototype built it (the first three show):

| Sentence | English (en UI) | Russian (ru UI) | Byline in ru UI |
|---|---|---|---|
| **Έγραψε** ένα γράμμα. | She wrote a letter. | Она написала письмо. | Zeus, odexed · Tatoeba |
| **Έγραψα** ένα τραγούδι για σένα. | I wrote a song for you. | Я написал для тебя песню. | Zeus, marafon · Tatoeba |
| Θα **γράψω** ένα γράμμα στον Τομ. | I'm going to write Tom a letter. | Я напишу Тому письмо. | Zeus, Selena777 · Tatoeba |
| **Γράψε** το όνομα σου στον κατάλογο και δώστο σε αυτόν που είναι κοντά σου. | Write your name on the list … | Напиши свое имя … | glavkos, gleki · Tatoeba |
| **Γράφω** ποιήματα. | I write poems. | Я пишу стихи. | Zeus, marafon · Tatoeba |

go, from the English lists pack (the first three show; the build keeps one sentence per form first):

| Sentence | Spanish (es UI) | Greek (el UI) | Byline in es UI |
|---|---|---|---|
| I wish I could **go** to Japan. | Deseo poder ir a Japón. | Μακάρι να μπορούσα να πάω στην Ιαπωνία. | CK, Shishir · Tatoeba |
| What are you **going** to do? | ¿Qué vas a hacer? | Τι πας να κάνεις; | CK, alicia · Tatoeba |
| We **went** to London last year. | Fuimos a Londres el año pasado. | Την τελευταία χρονιά πήγαμε στο Λονδίνο. | CN, Shishir · Tatoeba |
| Which **goes** faster, a ship or a train? | ¿Qué viaja más rápido, un barco o un tren? | none: the line is left out | Dejo, kylecito · Tatoeba |
| For a moment there, I thought he had **gone** mad. | Por un momento yo pensé que él se había vuelto loco. | none | CK, marcelostockle · Tatoeba |

### Learning (#178)

#178 asked for "the first example on the new-word card". E4 has no such card: a new word is introduced by its first question, which carries the "New word" badge (kyukhin, 2026-11-03, 0131 Open question 5). Examples come in a sheet instead (kyukhin, 2026-11-04):

- **A new word.** The first answer to a new word's first question is graded as today (the options' colours, the haptic, the sound, the VoiceOver announcement). Then a sheet slides up over the run with:
  - the result line, as the bar has it: "Right!" or "Right answer: γράφω";
  - the word, as the question shows it (with its endings, `αγάπη η`);
  - 1–3 examples, each with the form highlighted, its translation in the via language (below) and the byline;
  - **Continue**, which closes the sheet and goes to the next question, as the bar's Continue does.
- **Every other question.** The feedback bar gets an **Example** button beside Continue when the word has examples. It opens the same sheet, whose Continue also goes to the next question. The button is on the new word's first bar too, so a sheet swiped down can be opened again; swiping it down returns to the bar.
- **A word without examples**: no sheet and no button; the bar is as today.
- Match the pairs has no feedback bar, so no button. Learning data does not change: no setting, card or log field, and a question's time (`duration_ms`) still ends at the answer.
- iPhone: the sheet opens at half height and can be pulled up; at accessibility text sizes it opens at full height and scrolls, Continue pinned at the bottom. iPad: a form sheet. Arabic: it mirrors as the Definition section does.
- **Translation in learning** (kyukhin, 2026-11-04: learning is chosen as a pair, 0131). In the sheet, an example's translation is the one in the via language of the word's language, a direct Tatoeba translation only, never one through English. In a limited pair (0131: Greek via Russian, whose word meanings are English), a sentence without a translation in the via shows its translation in the meanings language instead (kyukhin, 2026-11-04):

| Pair | Sentence | Translation shown |
|---|---|---|
| Greek via English | Greek | English (every stored Greek sentence has one) |
| Greek via Russian, limited | Greek | Russian when Tatoeba has a direct one, else English (every stored Greek sentence has one) |
| English via Spanish | English | Spanish when Tatoeba has a direct one, else none |
| English via Greek | English | Greek when Tatoeba has a direct one, else none |
| English via English | English | none: the sentence is already in the via |

- The sheet takes up to 3 of the word's examples, those with a translation in the via first, otherwise in the build's order. A sentence without one shows alone, with its byline.
- The Definition screen keeps the UI-language rule above: it belongs to the dictionary, not to a pair, and works for words of languages not learned.

### Credits (#178)

Credits gains "Example sentences: Tatoeba (tatoeba.org), CC BY 2.0 FR. Each example names its authors." in all five languages. The Greek pack and the English lists pack each store the source as a `data_source` row (0129).

### Offensive sentences (#177)

Filtered at build time, never at run time:
- Tatoeba's own tags: the sentence or translation carries a maintenance tag (`@change`, `@needs native check`, `@check translation`, `@delete`, …) or a content tag (`vulgar`, `offensive`, `rude`, `sexual`, `racist`, `slur`, `violence`, `drugs`, …). The full list is in `build_examples.py`.
- Measured (the build of 2026-11-08): tags drop 315 Greek sentences and 28 of their translations; for English, 486 sentences of the subset and 831 translations.
- A user who still finds a bad sentence reports it through "Report a bug"; we tag it on Tatoeba and the next data refresh drops it.

### Drill examples (#364, #365; approved by kyukhin on 2026-11-22)

After each drill answer, right or wrong, the answer panel shows one sentence with exactly the asked form: **Κάνε** αυτό που μπορείς! for κάνω · Imperative: simple form · εσύ (kyukhin, 2026-11-22). 0132 ("A question") has the panel; this spec has the data.

- **Which cells**: every cell the drill can ask: the verbs of the three Greek lists, every tense up to B2, both voices, impersonal verbs in αυτός only. That is 595 verbs and 57,000 cells (measured 2026-11-22, Design, "Drill examples").
- **Where the sentence comes from**, in this order: Tatoeba (#364), a Wiktionary usage example (#365), a sentence generated for LibreDict (#365). The sentences already in the pack hold the form for 5% of the cells, all of Tatoeba for 8%, and Wiktionary brings that to 9% (measured; Design, "Measured").
- **2.0** (kyukhin, 2026-11-22): every cell of the A1 and A2 verbs at tenses up to A2 gets a sentence, generated where none is found. Their B1 and B2 tenses and the B1 verbs come in 2.1; until then those cells show what Tatoeba and Wiktionary have.
- **Skipped cells** (kyukhin, 2026-11-22): a cell where no natural Greek sentence shows the form in the cell's meaning stays without an example, as a cell above the scope does. Most are passives of active verbs that Greeks do not use in that person (αναβόμαστε); some are forms not used in the list's sense (σήμανα for σημαίνω "mean") or an order nobody gives (μπόρεσε). They are listed with the reason (Design, "Data files").
- **Translations of the sentences LibreDict adds** (kyukhin, 2026-11-22): English and Russian only, the drill's two vias in 2.0. Spanish and Arabic come when a pair needs them. Tatoeba sentences keep their direct translations, as word examples do.
- **Byline**: every example names its source: the Tatoeba authors and "Tatoeba" as on the Definition screen, "Wiktionary", or "LibreDict, generated" (kyukhin, 2026-11-22; wording in Design, "Byline").
- Drill examples show only in the drill. The Definition screen and learning keep their word examples.
- A learner with an older Greek pack sees no drill example until the pack is updated (0237: "Update available").

### Decisions

- 2026-10-22 (kyukhin, #134): example sentences ship in 2.0.0. Acceptance: at least 85% of the top-500 Greek verbs show 3+ examples; each example has a translation, the highlighted form and its author; a Russian translation with the Russian UI when Tatoeba has one; offensive sentences filtered out; added size ≤ 10 MB; Tatoeba (CC BY 2.0 FR) credited.
- 2026-10-22 (kyukhin, #177): Tatoeba from a pinned export; el–en, el–ru and en–ru pairs with authors; sentences linked to lemmas through word forms (#141 for Greek, morphy #143 for English); up to 5 per word; a stoplist.
- 2026-10-22 (kyukhin, #178): an "Examples" section, 3 visible and the rest on tap; the form highlighted; the translation in the UI language when Tatoeba has it, else English; the author in small print; the first example in learning; Tatoeba in Credits.
- 2026-11-03 (kyukhin, 0131): no introduction screen for a new word (Open question 2).
- 2026-11-03 (kyukhin, 0237): the bundle holds English only; every other language's data comes in its pack. This replaces #177's "store in the read-only dictionary file".
- 2026-11-04 (kyukhin): code complete 11-27, submission to Apple 12-04. If the release is behind, E7 and #160 move to 2.0.x first. Keep E7 small and say what a minimal version is.
- 2026-11-04 (kyukhin, Open question 3): the three empty example tables land in format 4 with #240 (T1), whatever happens to E7.
- 2026-11-04 (kyukhin): nothing is cut from 2.0 if it runs late, E7 included: the release date moves instead. E7 ships in full; the first draft's minimal version is no longer a plan.
- 2026-11-04 (kyukhin, Open question 1): English examples ship in 2.0 (+1.25 days), in the `eng-lists` pack, which is downloaded only when the user starts learning English: nothing unneeded lies on the phone. Greek examples stay in the Greek pack.
- 2026-11-04 (kyukhin, Open question 2): examples in learning come in a popup: after the first answer to a new word's first question, a sheet shows the word with 1–3 example sentences and their translations, closed with "Continue"; in every other question the feedback bar has an "Example" button that opens the same sheet; a word without examples shows no sheet and no button.
- 2026-11-04 (kyukhin, Open question 4): direct Tatoeba translations only. Learning is chosen as a language pair (0131); a pair without a dictionary, such as Greek via Russian, is not offered in 2.0, so no note about limited Russian is needed.
- 2026-11-04 (kyukhin): learning is chosen as a language pair (0131), "Greek via English", "English via Spanish". Applied here: in learning, an example's translation is in the via language, a direct Tatoeba translation or none.
- 2026-11-04 (kyukhin): Greek via Russian is offered as a limited pair (0131), although there is no Greek–Russian dictionary. Applied here: in learning, its examples show the Russian translation when Tatoeba has a direct one, else the English one; examples with a Russian translation come first. Direct translations only, as before.
- 2026-11-04 (kyukhin, Open question 5): the 85% gate counts all 500 verbs; a data refresh that falls below asks kyukhin in its PR with the list of misses.
- 2026-11-04 (kyukhin, Open question 6): the examples section sits above the inflection table on the Definition screen.
- 2026-11-08 (kyukhin): no stoplist; only Tatoeba's own tags filter the sentences. Replaces #177's "a stoplist".
- 2026-11-22 (kyukhin, #364): after a drill answer, show a real sentence with exactly the asked form, in 2.0. Release/2.0 is frozen; this is kyukhin's exception: it lands on master, then is cherry-picked into release/2.0.
- 2026-11-22 (kyukhin, #364): for every cell the drill can ask, keep one Tatoeba sentence with the cell's whole form. Compound tenses need θα, να or έχω before the verb, with clitics allowed between. The filters and translations are the word examples'. Only the `ell` pack and its catalog pin change; its release is published only after kyukhin's yes.
- 2026-11-22 (kyukhin, #365): fill the cells Tatoeba lacks. Use only sources whose licence allows shipping (CC0, CC BY, CC BY-SA), first the Wiktionary usage examples of the pinned kaikki dump. No NC licences, nothing copied from learning sites. Generate the rest: one short sentence at the verb's list level, with the exact form, translated into English, Russian, Spanish and Arabic, committed as a data file under `Scripts/data`.
- 2026-11-22 (kyukhin, #365): the checks are the form gate, a second model pass and kyukhin's review of a random sample of 50 before the pack ships. The byline names the source, Wiktionary or "LibreDict, generated". In 2.0: the A1 and A2 verbs (about 4,500 sentences); B1 moves to 2.1.
- 2026-11-22 (kyukhin, Open question 7): in 2.0 the A1 and A2 verbs get a sentence for every cell at tenses up to A2; their B1 and B2 tenses come in 2.1, with the B1 verbs.
- 2026-11-22 (kyukhin, Open question 8): a homograph of another reading takes a found sentence only with a model-checked reading.
- 2026-11-22 (kyukhin, Open question 9): the 10 MB budget counts word examples only; the drill examples have their own 3.5 MB installed.
- 2026-11-22 (kyukhin, Open question 10): cell keys in `example_word`, sources by id range; the format stays 4.
- 2026-11-22 (kyukhin, Open question 11): the bylines as the byline table has them.
- 2026-11-22 (kyukhin, Open question 12, against the recommendation): generated translations are English and Russian only in 2.0, the only ones the drill shows; a Wiktionary sentence gets a generated Russian one only. Spanish and Arabic come when a pair needs them. This narrows #365's "English, Russian, Spanish and Arabic".
- 2026-11-22 (kyukhin): no date moves for #364 and #365: build 11 and the App Store submission stay on 2026-11-26.
- 2026-11-22 (kyukhin, #365, after approval): a cell where no natural Greek sentence shows the form in the cell's meaning stays without an example. Such cells are listed in `ell-skipped.tsv` with the reason and the checker; the 2.0 gate counts a listed cell as done, and the report lists the skips with their reasons. Mostly passives of active verbs with no real use (the generator's brief, rule 5).
- 2026-11-22 (kyukhin, #365, after approval): besides the spec's filters, Wiktionary usage examples are dropped for content: broken text, violence, offensive, politics, smoking, religion, quotations and brands (196 of 597; "Sources and licences").
- 2026-11-22 (kyukhin, #365, after approval; CodeRabbit on #366): attribution per row. The Wiktionary rows keep the entry they come from (`page`), and Credits names Wiktionary contributors with the source and the licence, as for the word forms (0136).
- 2026-11-22 (kyukhin, #365, after approval): `ell-readings.tsv` keeps the second pass's reason in a `reason` column, after `checked_by`.
- 2026-11-23 (kyukhin, #365): every Tatoeba sentence a drill cell uses is checked by a model too (its Greek, the form's reading, the Wiktionary rows' content filter, the English and Russian translations); a failure is a `no` verdict and the cell moves on to its next sentence (Checks, 4).
- 2026-11-23 (kyukhin, #365, sample review): the cause of the sample's three bad rows is fixed across the rows it could touch: the generated rows of passive cells of active verbs and of -μαι verbs, checked again (Checks, 3).

Design choices of this spec, for review:
- Greek examples ship in the Greek pack, English examples in the English lists pack; the bundle gains only empty tables.
- Examples are keyed by `WordKey` text, so the Definition screen and learning read the same rows, and nothing is stored in the user database. Drill cell keys (#364) are the one exception: they keep their capitals and are read with `examples(lang:word:limit:)`.
- Up to 5 per word, chosen and ordered by the build; the app does no ranking.
- Only Tatoeba's direct translations, never a translation of a translation (Open question 4).
- A sentence is linked by its exact forms (accents kept), not by folded keys.
- The pin is a committed subset of the export, since Tatoeba keeps only the latest one (as kaikki.org, 0136).
- The section sits above the inflection table (Open question 6).
- The Definition screen translates examples into the UI language and learning into the via language: the dictionary has no pair, learning always has one.
- Drill examples (#364, #365, approved by kyukhin on 2026-11-22):
  - the cell rows go into `example_word` under a cell key, and the source follows from the sentence id, so the format stays 4 and only `ell` changes (Open question 10, resolved);
  - the build's cell list is a Python port of 0132's rules, guarded by a Swift test on the committed pack;
  - a homograph whose other reading differs needs a checked reading (Open question 8, resolved);
  - real sentences come before generated ones;
  - the drill examples get a size budget of their own (Open question 9, resolved).

### Out of scope

Examples for Russian, Spanish and Arabic words (no lemmatizer for them in the app). Tatoeba audio (each recording has its own license) and speaking a sentence aloud. Searching sentences, or sentences in Search results. Reporting a sentence from the app. Translations through a third language. Exercises built from sentences (cloze, build-a-sentence, 2.1.0 #147–#150). Examples for imported dictionaries without a language. Examples for English words outside the English lists: every English lemma at 3 examples each would take 12.5 MB, over the budget (measured).

## Design

### Depends on

| Spec | What E7 uses |
|---|---|
| 0129 | "Adding static data": a static step `Scripts/build_examples.py` with `SCHEMA` and `build(conn, cache_dir)` in `STEPS`; plain tables; a `data_source` row, never a `dict_metadata` row; inputs pinned in `Scripts/inputs.json`; sorted inserts, no timestamps; the size budget printed through `dbstat`. #213's `read` helper (one retry after an I/O error) for every read |
| 0136 | The Greek forms tables (`lemma`, `paradigm`, `form_link`) to link a token to its lemma; morphy (`morphy_exception`, `morphy_lemma`, and the rules of `Morphy`) for English; the top-500 verb ranking from FrequencyWords `el_50k.txt` (already pinned) for the gate |
| 0237 | Every file has every table; a file fills only its own rows. `Scripts/packs.json` row filters put the Greek rows in `ell` and the English rows in `eng-lists`. A new table bumps the format of every file, so the tables land with #240's format 4. `DictionarySchemas` maps a language to its pack schema. Tests install packs with `PackFixtures` (unit) and `-installPacks` (UI) |
| 0130 | `WordKey (lang, word)`: ISO 639-3 and the term as stored with only A–Z lowercased. `wordKey(for: EntryKey)` (#151) gives an entry's key. The English lists' terms (`wordlist_item`, series `cefr-eng`, #153) are the English words that get examples |
| 0131 | `ExerciseRunViewModel` builds each question just before it shows, with `isNew`; the feedback bar and its Continue are in `ExerciseView.swift`; `LearningPairs.via` gives a learned language's via |

### Placement and size

| Data | Where | Installed | Download (xz) |
|---|---|---|---|
| Greek examples: 10,810 sentences, 17,335 word links, translations in en, ru, es, ar | Greek pack `ell` | 2.34 MB | 0.68 MB |
| English examples: 28,718 sentences, 33,485 word links for 7,458 list words, translations in ru (24,450), es (20,970), ar (5,294), el (3,876) | English lists pack `eng-lists` | 6.90 MB | 2.31 MB |
| The three tables, empty | Bundle and `empty-pack.sqlite` | 12 KB each (one page per table) | — |
| All examples | | 9.24 MB | 2.99 MB |

- Measured on the prototype's tables (`dbstat`; `lzma` preset 6, as 0237 compresses). The Greek pack (0237: 55.1 MB installed, 10.7 MB to download, before E3's lists) grows by 2.34 and 0.68 MB; the English lists pack (0237: about 1.9 MB installed, 0.6 MB to download) by 6.90 and 2.31 MB. The App Store download does not change, and the English examples reach only users who learn English (kyukhin, 2026-11-04).
- Budget (#134): the example tables of all files together ≤ 10 MB installed: 9.24 MB, 0.76 MB to spare. If a refresh goes over, its PR keeps 4 English examples per word (5.78 MB, measured) and says so.

### Data: tables

DDL in `SCHEMA` of `Scripts/build_examples.py`. Every file gets them (0237), so the unit tests' `TestDictionary.make` copies them with the rest of the schema.

```sql
-- One row per Tatoeba sentence used as an example.
CREATE TABLE example_sentence (
    id      INTEGER PRIMARY KEY,   -- the Tatoeba sentence id (stable across exports)
    lang    TEXT NOT NULL,         -- ISO 639-3 of the sentence: 'ell' or 'eng' (the pack filter)
    text    TEXT NOT NULL,         -- NFC, otherwise as Tatoeba has it
    author  TEXT NOT NULL          -- Tatoeba username
);
-- Its direct translations: at most one per language.
CREATE TABLE example_translation (
    sentence_id INTEGER NOT NULL,  -- example_sentence.id
    lang        TEXT NOT NULL,     -- 'eng', 'rus', 'spa', 'arb' (Tatoeba's 'ara'); 'ell' for English sentences
    id          INTEGER NOT NULL,  -- the translation's Tatoeba id
    text        TEXT NOT NULL,
    author      TEXT NOT NULL,
    PRIMARY KEY (sentence_id, lang)
) WITHOUT ROWID;
-- A word's examples, in display order.
CREATE TABLE example_word (
    lang        TEXT NOT NULL,     -- WordKey.lang
    word        TEXT NOT NULL,     -- WordKey.word: a lemma or headword as stored (NFC; A–Z lowercased); a drill cell key (#364), not lowercased
    ord         INTEGER NOT NULL,  -- 1…5
    sentence_id INTEGER NOT NULL,
    form_start  INTEGER NOT NULL,  -- the highlighted form: offset in Unicode scalars of the NFC text
    form_length INTEGER NOT NULL,
    PRIMARY KEY (lang, word, ord)
) WITHOUT ROWID;
```

- A word's examples are one primary-key prefix read of `example_word`, then the sentences by `id` and their translations by `(sentence_id, lang)`. No other index, no `ANALYZE` (0129).
- `data_source` row: `tatoeba`, kind `example_sentences`, "Tatoeba (example sentences)", version `export 2026-10-31`, license `CC BY 2.0 FR`, url `https://tatoeba.org`. It goes with the rows into both packs (0237 lets a `data_source` row sit in several files).
- `Scripts/packs.json`: `example_sentence` and `example_word` where `lang = 'ell'` → `ell`, where `lang = 'eng'` → `eng-lists`; `example_translation` by its sentence's language (`sentence_id IN (SELECT id FROM example_sentence WHERE lang = …)`), to the same packs; the `tatoeba` `data_source` row → both. If T1's filter format takes only `column = value`, `example_translation` gets a `sentence_lang` column instead, with a History line. The cut's check that every row lands in exactly one file covers the three tables.
- **Format** (kyukhin, 2026-11-04). The three tables land empty in format 4 with #240 (0237 T1): #240 adds `build_examples.py` with its `SCHEMA` and a `build()` that writes nothing, registers it in `STEPS`, and puts the filters above in `packs.json`. #177 then fills the rows, which changes only the `ell` and `eng-lists` versions: an update of those packs, never a format bump that would make every user download every pack again (0237, "Format rule").

### Pipeline (#177)

**Source and pin.**
- Tatoeba publishes its exports every Saturday at 06:30 UTC and keeps only the latest (downloads.tatoeba.org/exports). As with kaikki.org (0136), a URL plus hash cannot pin it, so the committed subset is the pin.
- Subset: `Scripts/data/tatoeba-20261031/` in Git LFS (`.gitattributes` gains `Scripts/data/tatoeba-*/*.xz`). Two projections of the export with no quality filter, so a filter change needs no new subset. Each has `sentences.tsv.xz` (`id`, `lang`, `text`, `author`), `links.tsv.xz`, `tags.tsv.xz` (the tags of its sentences) and `natives.tsv.xz` (its authors who declare level 5 in a sentence's language):
  - `ell-*`: every Greek sentence and every eng, rus, spa and ara sentence directly linked to one: 75,127 sentences, 42,276 links, 31,113 tags; 1.39 MB (xz preset 9, measured with every native speaker of ell, eng and rus, an upper bound);
  - `eng-*`: every English sentence directly linked to a rus, spa, ara or ell one, and those translations: 1,728,400 sentences, 1,198,407 links, 596,390 tags, 2,598 natives; 24.8 MB (sentences 19.2, links 4.4, tags 1.2).
  - 26.2 MB in all, once per snapshot (0136's kaikki subset is 19.1 MB).
- `Scripts/inputs.json` records the export (date 2026-10-31, every file's URL, size and sha256, below) and each subset file's sha256, checked by `inputs.committed()` before use. The step works offline.
- `build_examples.py --refresh` downloads the current export files, writes a new dated subset and its `inputs.json` entry. A refresh is a reviewed PR of its own, and the report's diff shows what changed.

Export of 2026-10-31 (`Last-Modified` Sat, 31 Oct 2026 06:39–06:59 GMT), 22 files, under `https://downloads.tatoeba.org/exports/per_language/`:

| File | Bytes | sha256 |
|---|---|---|
| `ell/ell_sentences_detailed.tsv.bz2` | 817,801 | `9e724855f0c0fc44e2a46762f628fe4ee8849ac54e9a4043f6e86b50e7d7ae44` |
| `ell/ell-eng_links.tsv.bz2` | 192,619 | `c4220bfa0c57d852716aa090eb995374cbcd36a65bdb42f2e281ade31579af46` |
| `ell/ell-rus_links.tsv.bz2` | 39,818 | `e28cfbc546802c3a50d845f183e83609ad217e744abda86d89a7ab0534f9680a` |
| `ell/ell-spa_links.tsv.bz2` | 19,423 | `9d8b26ffdb97b7e0399fbbc2d975ced5bf113c46ac9bbd15be5f174af30dd1b0` |
| `ell/ell-ara_links.tsv.bz2` | 2,383 | `544a8a75b7e04d43c7df37de72c4981174896e3eba012262a18fbd44c4b74f83` |
| `eng/eng-rus_links.tsv.bz2` | 5,011,078 | `a732da5398ea5026aca8aabe2a0d588f42a2139a17347fc7b6ec8e16f528467b` |
| `eng/eng-spa_links.tsv.bz2` | 1,761,958 | `13bcf23b8890f9666d30c0e1c03ab4fc3e6be9fa5f8dbb587a4cd5f61e167b8f` |
| `eng/eng-ara_links.tsv.bz2` | 299,441 | `20f4671b42bbbcb037fb7498519096d8a90053d34274c58aae9d3c103fcada93` |
| `eng/eng_sentences_detailed.tsv.bz2` | 34,969,370 | `7d8a98a1322c63eb62199b0e928efc5b9afbf8f4bb9bc4b60ebde1ea99a30cda` |
| `rus/rus_sentences_detailed.tsv.bz2` | 23,620,785 | `16e6147510b4f09f97636940aaf674dee68a47910276c9a122e81453527eb329` |
| `spa/spa_sentences_detailed.tsv.bz2` | 9,521,526 | `8ebe95f5a71651c9407606e898fa59efe43295c461d24d32c1804a5dd908e67e` |
| `ara/ara_sentences_detailed.tsv.bz2` | 1,213,294 | `d6f188e382e437d0632f2bdcad23941acd9bf7eba984069327977b84837f411d` |
| `ell/ell_tags.tsv.bz2` | 4,633 | `c85217922d10ecf4d171a69e78b8965908317104a126b10f6f3310b73f882a0e` |
| `eng/eng_tags.tsv.bz2` | 2,338,387 | `b681bd2a38453765464a69e3da61f1adb1e2e54914b571a7960e4f5cf7c9751d` |
| `rus/rus_tags.tsv.bz2` | 254,344 | `a16d7ad9f873d528b0061547a2ff7fed8a80da5dc63ca425e9159f811aab0413` |
| `spa/spa_tags.tsv.bz2` | 70,726 | `27753b89b9b74e1f4ebc0d8fe676386dd4f32e496852dfebdb859fa9394900a4` |
| `ara/ara_tags.tsv.bz2` | 4,435 | `f31a67a0ac99762c3a4bf657d84c6cff5a095d0e4bc5f34526ce0f13054a5115` |
| `ell/ell_user_languages.tsv.bz2` | 3,641 | `9db1d182ffe506e4d8612c3f1195d8d1ddda169428a7f15646809aff769db422` |
| `eng/eng_user_languages.tsv.bz2` | 291,815 | `8fe1e08ec64e4ff76a9b642e5a77db950ae09513c6a72af78de290c81c6c323e` |
| `rus/rus_user_languages.tsv.bz2` | 28,027 | `4a344119972443d01b1270b065a265b5d04f6548a58286f06b98f857a049c012` |
| `spa/spa_user_languages.tsv.bz2` | 39,725 | `1324a9a46e1469b3dfcee91244b23f93be830147acef921ba8d86b7eb8ed1cba` |
| `ara/ara_user_languages.tsv.bz2` | 15,552 | `9975fabe921f3033ad135e5954a900b2c6f3141f82a41b35643cbb5c978124d9` |

**Steps** (`build(conn, cache_dir)`, after `build_forms`, `build_morphy` and `build_wordlists`, whose tables it reads):

1. **Sentences.** A Greek sentence is a candidate when, in this order (drops measured on the build of 2026-11-08):
   - it has an author: an orphan has no one to credit (476);
   - it has no blocking tag (315);
   - it has at most 15 words (911);
   - it has a usable English translation (11,413: most link only to other languages; 297 English translations have no author, 15 are tagged).
   - 29,870 candidates remain.

   An English sentence is a candidate when it has an author (44,402 of 2,040,024 have none, most of them Tanaka corpus sentences), no blocking tag (1,037), at most 15 words (73,557) and at least one usable direct translation into rus, spa, arb or ell: an example for learners whose UI or via is one of those.
2. **Translations.** Tatoeba's direct links only, both directions. Per language the first usable one (author, no blocking tag), by: author declares that language native, then lowest id. Candidates with Russian: 3,172, Spanish 1,865, Arabic 264 (the build of 2026-11-08).
3. **Tokens.** Runs of letters and marks, an inner apostrophe kept (`[^\W\d_]+(?:['’][^\W\d_]+)*`), each with its start and length in Unicode scalars.
4. **Keys.** A token, lowercased (Python `str.lower()`) and NFC, gives:
   - the `word` of every lemma it is a cell of (`paradigm`), the lemma's own word, or one of its link pages (`form_link`): έγραψα → γράφω, πάει → πάω;
   - the token itself, as written or lowercased, when it is a headword of El–En · FD or El–En · WN: μέρα keys μέρα as well as its lemma's forms.
   - **A Greek list word** (#339, kyukhin 2026-11-17): a token that is, as written or lowercased, a one-word term of the Greek lists (`wordlist_item` of series `ky-ell`) keys that term, itself when it is a headword, and of its lemmas only the verbs. So αυτό keys αυτό, not αυτός, and ο no longer shows sentences with η, τον or τα, which are list words of their own; πάω keys πάω and πηγαίνω, γράφω keeps έγραψα (no list word), and είμαι keeps είναι. A list word's examples are keyed by its term (`WordKey`, 0130), so learning shows them in the word's own form. A term's spellings are the term and its cleaned spellings (0130, linking rule 2) that are one token: στη(ν) is στη and στην, Γεια! is Γεια; a term with a space, (ένα) σωρό, has none. Tokens that are no list word key as above. English is unchanged.
   - Exact, not folded: folding finds one more top verb (429), but makes πότε (when) an example of ποτέ (never). Measured: 5,980 keys with an example, 2,958 of them with 3 or more; 5,511 of the 51,230 Greek headwords have examples.
   - English: the keys are the one-word terms of the English lists (`wordlist_item` of series `cefr-eng`, #153), lowercased; 8,431 words (the one-word terms of #153's lists, the build of 2026-11-08). A token of a–z letters, lowercased, keys every morphy lemma of it (the rules of 0136's `Morphy` on `morphy_exception` and `morphy_lemma`, mirrored in Python) and itself, when that is a list word: went, going, goes and gone key go. Measured: 7,496 list words have an example, 6,662 have 3 or more.
5. **Choice**, per key. Rank the sentences that contain it by:
   1. the author declares the sentence's language native (Tatoeba level 5; 26,815 of the Greek sentences);
   2. more of eng, rus, spa, arb translated;
   3. 3 to 10 words before others;
   4. lower Tatoeba id.

   English ranks the number of translations first, then the native author: nearly every English candidate has a native author, and the vias of English (Spanish, Greek) are the rarer translations.

   Then take, in that order, one sentence per new form first, then the rest, up to 5. So γράφω shows έγραψε, έγραψα, γράψω, γράψε, γράφω, and go shows go, going, went, goes, gone. The highlight is the first token of the sentence that gave the key. A Greek list word that is no verb shows its own forms (its term's spellings) first, in that order, and other forms only fill up to 5 (#339): ο shows ο, not των, τη, τες. A list word that is a verb keeps one sentence per form; when that pass leaves its own form out, its best own-form sentence leads and the last pick drops: λέω shows λέω, then είπε, πω ….
6. **Credit.** The `data_source` row.

**Gates** (`build()` raises, so the build fails):

| Gate | Measured |
|---|---|
| Top-500 Greek verbs (0136's ranking) with 3+ examples ≥ 85% | 429 of 500, 85.8% (the build of 2026-11-08). Many of the 71 misses are participles tagged as verbs (καλεσμένος, δεμένος) or rare in Tatoeba (ερευνάω, κανονίζω). 476 have at least one. Top-500 nouns with 3+: 434 (reported, not gated) |
| Every Greek sentence stored has an English translation; every English one has a translation into rus, spa, arb or ell; every stored text has an author | holds |
| English list words with 3+ examples (reported, not gated) | 6,662 of 8,431; 7,496 have at least one |
| Every span lies inside its text, and its token gives its key | holds |
| No stored sentence or translation has a blocking tag (checked again on the output) | 0 |
| Example tables ≤ 10 MB in the full file | 9.31 MB (Greek 2.34, English 6.98) |
| Every translation and word row points at a stored sentence | holds |

**Report** `Scripts/reports/examples-qa.md`, rewritten by every build and committed: the export date and hashes; counts per filter; candidates and translations per language; the coverage gate with the missing verbs listed; the list-word rule against the keys without it, on the same candidates (keys that gain, lose or change examples, the 20 that lose the most sentences) and #339's cornerstone words with how many of their examples show their own form; the blocking tags hit; samples (γράφω, είμαι, σπίτι, καλός, μέρα; go, house, write, good); table sizes and a sha256 of each table's rows in key order.

**Reproducibility.** Sorted inserts, no timestamps; `build_dictionaries.py --verify` and `cut_packs.py --verify` (0237) prove the files byte-identical. `build_examples.py --self-check` runs offline on `Scripts/fixtures/tatoeba-sample/` (about 30 lines in the subset's format, with a small forms fixture): a tagged sentence and a tagged translation, an orphan, a 16-word sentence, a Greek sentence without English, γράφω in six forms (five kept, the new forms first), μέρα, πότε and ποτέ, the list words η, γράφω, πάω and στη(ν) (#339: Η keys η, not ο; πάω keys πηγαίνω too; στην keys στη(ν)), two Russian translations by a native and a non-native author; went, going and gone keying go, an English sentence without any translation (dropped), an English word not in the lists fixture (no key). It builds twice and requires equal table hashes, as `build_forms.py --self-check` does.

### Reading (#178)

- `DatabaseService.examples(for key: WordKey, limit: Int = 5) async throws -> [ExampleSentence]`:
  - the schema is `DictionarySchemas.examplesSchema(for: key.lang)`: `ell` → `ell`, `eng` → `eng_lists`, nil for every other language → `[]` without a read;
  - one `read` (with #213's retry): the `example_word` rows by `(lang, word)` in `ord` order up to `limit`, joined with `example_sentence`; then the translations of those ids;
  - a missing pack reads its stub (0237), so the result is `[]` with no special code.
- Models (`Models.swift`, pure):
  - `ExampleSentence { id, lang, text, author, form: Range<Int>, translations: [ExampleTranslation] }`, `ExampleTranslation { lang, text, author }`;
  - `ExampleText.translation(for:uiLanguage:)`: the Definition screen's rule in Behaviour; the UI language as ISO 639-3 (en → eng, ru → rus, es → spa, ar → arb, el → ell, the inverse of `SettingsViewModel.languageNameKeys`);
  - `ExampleText.learningTranslation(for:via:meanings:) -> ExampleTranslation?`: the translation whose `lang` is the via; else, when `meanings` differs from the via (a limited pair), the one in `meanings`; nil when there is none or the sentence is in the via itself; `ExampleText.forLearning(_ examples:, via:, limit: 3)`: those with a via translation first, in the build's order otherwise;
  - `ExampleText.sentence(_:)`: an `AttributedString`, the form bold and tinted; the sentence's runs carry its language (`el` for Greek), so VoiceOver reads them with the Greek voice, as #144's cells do. A span that does not fit the text (never, per the gates) gives the plain sentence;
  - `ExampleText.byline(_:translation:bundle:)` and `accessibilityLabel(_:translation:bundle:)`, resolved through the in-app language's bundle (`LocalizationManager.localizedBundle`), as `FormCaption` does.
- Layering: SQL only in `DatabaseService`; the choice of translation, the highlight and the byline are pure and unit-tested; views render what they are given.

### Definition screen (#178)

- `DefinitionViewModel` gains `@Published private(set) var examples: [ExampleSentence]` and `loadExamples()`: `wordKey(for: EntryKey(entry))` (E3 #151), then `examples(for:)`. It runs in the view's `.task`, as `loadInflection` does. A failed read leaves the screen without examples, as for tables.
- `DefinitionView.swift` gains `ExamplesSection` (title, rows, the More button) and `ExampleSentenceView` (one example), which learning's sheet reuses. Both are shared from this file, as `ReadingModeToolbarButton` is. The UI language comes from the view's `\.locale`, which the app root sets.
- **VoiceOver**: each example is one element, read as "Έγραψα ένα τραγούδι για σένα. I wrote a song for you. From Tatoeba: Zeus and Shishir." The section title is a header; More is a button.
- **Arabic**: the section mirrors. A Greek or English sentence keeps its own direction; the byline is a composed string, so it starts with U+200F and the usernames are wrapped in FSI…PDI (#119).
- **iPad, Dynamic Type**: the same column inside the screen's scroll view; every line wraps, nothing is truncated.

### Learning (#178)

- `ExerciseRunViewModel` (`LearnViewModel.swift`): when it builds a question, it reads the word's examples once per run and word (`examples(for: card's WordKey, limit: 5)`, kept by `WordKey` for the run) and publishes `sheetExamples = ExampleText.forLearning(_:via: pair.via, limit: 3)` for the language's `LearningPair` (0131), with `learningTranslation(for:via:meanings:)` for each. The read is one primary-key lookup and ends before the question shows, so the bar never changes after it appears.
- After grading the first answer to a question with `isNew`, it sets `showsExampleSheet` when `sheetExamples` is not empty. The bar's Example button sets it too. Continue on the sheet calls the same `continue()` as the bar's; a swipe down only clears `showsExampleSheet`.
- `ExerciseView.swift`: `ExampleSheet` (the result line, the word, `ExampleSentenceView` for each example, Continue), presented with `.sheet`, detents `.medium` and `.large` (`.large` at accessibility text sizes, Continue in a bottom bar); the bar's Example button when `sheetExamples` is not empty.
- E4's data does not change: no new setting, table or log field.

### Licenses

- Tatoeba sentences are CC BY 2.0 FR. Tatoeba's terms of use: reuse "is only allowed if the name of the author is cited" (6.2), and "it is your responsibility to quote the author of the sentence" (6.5). Some sentences are also CC0; the app treats all as CC BY.
- So each example names the author of every text it shows: the sentence and the translation. Translation authors differ from the sentence's in 83% of the English translations (measured), hence the two names in the byline.
- Orphan sentences and translations (no author in the export) are never used.
- Texts are shown unchanged (only NFC), so no notice of changes is needed.
- Credits names Tatoeba, the license and tatoeba.org; the `data_source` row records the same. The committed subset keeps every author.
- The dictionaries already ship CC BY-SA 3.0 and 4.0 data with attribution in Credits; CC BY 2.0 FR asks no more than that.
- Build input only, nothing shipped: FrequencyWords for the gate (CC BY-SA 4.0, as in 0136).

### Drill examples (#364, #365; approved by kyukhin on 2026-11-22)

Figures marked "measured" come from a prototype run on 2026-11-22 (scratchpad, not committed). It used:
- the Greek pack of master `63e7bda` (`ell-a94e8f99ecb8`);
- the Tatoeba subset of 2026-10-31: 29,870 Greek candidates after this spec's filters, 11,259 of them already in the pack;
- the kaikki subset of 2026-10-01 (0136);
- Python 3.15.2 and SQLite 3.54.1.

**Cells.** A cell is what one drill question asks: a verb, a facet and a person (0132).
- The build's cell list is exactly the drill's:
  - the verbs are 0132's session pool over the three Greek lists, `droppingSharedPassives` included;
  - the cells of each verb are every (facet, person) that `ConjugationQuestionBuilder.questions(verb:level: .b2)` lists. That means every tense up to B2 in both voices, an impersonal verb in αυτός only, never the cited cell, and never a question without three distractors.
- A cell's forms are `DrillVerb.forms(facet, person)`: the table's own forms (γράφτηκα, γράφηκα) and the generated ones (θα γράψω, να γράψω, έχω γράψει, είχα γράψει, θα έχω γράψει, and θα είμαι from the θα/να fallback).
- Measured: 595 verbs (196 A1, 66 A2, 333 B1, as 0132 counts them) and 57,000 cells.
- **Key**: `<word>|<facet>|<person>`, in NFC. `<word>` is the card's word (0132: πηγαίνω for πάω, ντύνομαι for a passive link), `<facet>` is `ConjugationFacet.rawValue` and `<person>` is `Person.rawValue`. Example: `κάνω|imperativeSimple.active|2sg`. No Greek word has a `|`. The key keeps its capitals (`imperativeSimple`): it is not a `WordKey`, so the app reads it with `examples(lang:word:limit:)`, never lowercased. Elsewhere `example_word.word` stays `WordKey.word` (A-Z lowercased).
- **Port**: `Scripts/drill_cells.py` ports 0132's rules to Python, with the Swift names: the pool (`drillVerbs` with its link rule), `DrillVerb.make`, `ParadigmLayout.verbSlot` and `VoiceForms`, `ConjugationTense.forms`, `DrillLevel.facets` and the ask rule of `questions`. The prototype port gives the counts above. The Swift tests `testCellKeysAreDrillCells` and `testEveryCellInScopeHasASentence` catch drift (Test plan).
- Practise on a verb outside the pool shows no sentence (0132, Practise on any Greek verb). So does a voice the pool drills under another word: ντύνω's passive, drilled as ντύνομαι.

**Match rule** (does a sentence hold a cell?). The build tokenizes as in step 3, lowercased and in NFC. An elided clitic glued to its word is split off: σ'αγαπώ is σ' and αγαπώ. An elided θ' or ν' (either apostrophe, glued or before a space) only blocks (rule 3): it is never the θα or να of a compound form, which needs the whole word (kyukhin: exactly the asked form). So ν' ανεβαίνουν is no present and θ' ακούσετε no future. A cell form is the verb alone, or the verb with θα, να, an auxiliary (έχω … έχουν, είχα … είχαν) or θα with an auxiliary before it. A sentence holds the cell when it holds one of the cell's forms whole:
1. **Exact words.** Accents are kept, as for word examples. Only case is ignored, so a sentence may start with Θα or Κάνε.
2. **Compound forms.** Each word of the form comes in order, with only clitics between: μου, σου, του, της, μας, σας, τους, τον, την, τη, το, τα, τις, τες, με, σε, μ', σ', τ'. After να, μη and μην may come too. So θα σου γράψω, να μην το κάνεις and το έχω γράψει match. An adverb between does not: έχω ήδη γράψει.
3. **Particles.** A simple tense (present, imperfect, aorist, imperatives), a perfect or a pluperfect does not match after θα, να, an elided θ' or ν', ας or μη(ν), skipping clitics. μη(ν) blocks after να and as a prohibitive (decided 2026-11-22 after QA, as kyukhin's homograph rule keeps a found sentence only in the asked reading). θα έγραφα is no imperfect, να γράφω no present, θα έχω γράψει no perfect, Μην ανησυχείς and ας γράφει no present.
4. **Auxiliaries.** έχω or είχα with an aorist infinitive in the next 3 words, only clitics or one other word between, is an auxiliary. In έχει γράψει and έχει ήδη γράψει, έχει is not έχω's present αυτός, and θα έχω γράψει is not έχω's future; in έχει ένα γράμμα it is. The perfect itself still needs its words in order with only clitics between (rule 2).
5. **Homographs.** One spelling can fill several cells of a verb, or of two verbs, that rules 2 to 4 cannot tell apart. There are two kinds:
   - **Aspect only.** The two cells have the same person, voice and mood; only the continuous and simple forms share a spelling: κάνε, θα κάνουν, να κάνουν. One sentence serves both cells. Measured: 317 cells.
     - A simple-imperative cell takes no sentence whose form is the continuous imperative, unless both imperatives are one word (#365, the Tatoeba check, 2026-11-23). Wiktionary's table also lists μίλα and κράτα as simple imperatives, but **Μίλα** is no sentence for μίλησε, nor **Κράτα** for κράτησε; κάνε, both imperatives of κάνω, serves both cells. The check applies the rule with `no` verdicts (Checks, 4), not the match rule. "One word" means the two cells' asked forms are spelt alike: κάνε, and since #362 (kyukhin, 2026-11-23) σταμάτα, ξύπνα, παράτα, προχώρα and χαμογέλα, which 0136's `first` rows make the asked simple imperative. So the 13 `no` verdicts "Tatoeba check, form: … is the continuous imperative" on those five verbs' simple-imperative εσύ cells go, their sentences become usable there, and the sentence each cell then takes gets the rest of the Tatoeba check (Checks, 4). The two older `no` verdicts on σταμάτησε and ξύπνησε read as an aorist stay.
   - **Another reading.** The spelling also has another person, tense or mood:
     - γράφετε: present and imperative εσείς;
     - μίλησε: aorist αυτός and imperative εσύ;
     - διάβαζε: imperfect αυτός and imperative εσύ;
     - είναι: αυτός and αυτοί;
     - γραφόμαστε: present and imperfect εμείς;
     - πέστε: λέω and πέφτω.

     A found sentence counts for such a cell only with an `ok` reading verdict from the second model pass (#365, "Data files"). Otherwise the cell stays open, and #365 generates a sentence written for that reading. A Wiktionary or generated row's `check` `ok` is the verdict for its own cell, since the second pass checked it in that reading; a verdict in `ell-readings.tsv` for the same cell and sentence decides instead. For any other cell its spelling holds, the row needs a verdict like any found sentence. A `no` verdict keeps its sentence out of its cell whatever the cell is, homograph or not: the second pass also refused πείνα (the noun) for πεινάω's imperative (#365, after QA). Measured: 4,578 cells; 950 of them in the 2.0 scope, 396 of those with a found sentence to check. Without the rule the prototype gave the imperative μίλησε the sentence "Αυτός **μίλησε** για δέκα λεπτά χωρίς σταματημό."
6. **Highlight.** The highlight covers the form as the sentence writes it, from its first word to the verb, clitics included: Δε χρειάζεται **να μου το πεις** αυτό. Word examples highlight one token; a cell row may highlight several words.

**Choice** (one sentence per cell). Of the sentences that hold the cell:
1. Tatoeba first, then Wiktionary, then generated: real sentences come first.
2. A sentence with the cell's first form (the option the question shows as right) comes before one with another form: κάνε before κάμε.
3. Tatoeba sentences are ranked by step 5's rank: native author, more of eng, rus, spa and arb, 3 to 10 words, lower id. Wiktionary and generated sentences: the row written or translated for the cell (its `cell`) first, then 3 to 10 words, then fewer words, then the id (for Wiktionary the dump's order).
4. The highlight is the first occurrence in the sentence.

A sentence can serve several cells and is one `example_sentence` row. One that is already a word example is reused.

**Where it lives** (no new table). The cell rows go into the existing `example_word` table: `lang` 'ell', `word` the cell key, `ord` 1, `sentence_id` and the span. Sentences and translations are `example_sentence` and `example_translation` rows, as today.
- The table shapes do not change, so the format stays 4 (0237's format rule). `packs.json`'s `lang = 'ell'` filters put the rows in the Greek pack, and only the `ell` asset and its catalog row change (#364).
- The Definition screen and learning read headwords and list words, which never hold a `|`, so they never read a cell row.
- **Source by sentence id**, since a source column would need a new format:

  | Source | Sentence ids |
  |---|---|
  | Tatoeba | below 1,000,000,000 (the export's highest is 14,087,789) |
  | Wiktionary | 1,000,000,000 + n |
  | generated | 2,000,000,000 + n |

  n numbers each source's rows in the data file (below) in the order they were added. It is given once and never reused, so a row dropped later leaves a gap: the second pass dropped 50 of the 401 Wiktionary rows.
- A translation has its sentence's source, with one exception: a Wiktionary sentence's English is Wiktionary's, and its Russian is generated. The translations of a Wiktionary or generated sentence take its id as their `id`.
- `author` is "Wiktionary" or "LibreDict" for the texts not from Tatoeba, so every text keeps an author (the step's gate).
- Swift's `ExampleSource` reads the same ranges.
- Rejected for 2.0: a new `example_cell` table with a `source` column. It is cleaner, but it is format 5: the bundle, the stub and all five packs change, and every installed pack is downloaded again (0237). It can come in 2.x with the next format bump (Open question 10).

**Sources and licences** (kyukhin, 2026-11-22: CC0, CC BY or CC BY-SA only).
1. **Tatoeba** (#364), as above: CC BY 2.0 FR. Each text names its author. The candidates pass the same filters (an author, no blocking tag, at most 15 words, an English translation) and keep their direct translations.
2. **Wiktionary usage examples** (#365), from the senses' `examples` in the pinned subset `Scripts/data/kaikki-el-20261001.jsonl.gz` (0136). Nothing new is downloaded.
   - Taken: `type` "example" without a `ref`, with an English translation, on one line, in Greek letters, at most 15 words. Measured: 6,027 of the subset's 8,907 examples.
   - Never taken:
     - quotations (`type` "quotation" or any `ref`): third-party text from books and press, quoted as citations, which Wiktionary's licence cannot grant;
     - untyped entries, which are notes ("See related expressions").
   - **Content filter** (kyukhin, 2026-11-22): besides the filters above, an example is dropped for its content, as the generator's brief keeps generated ones neutral. Of the 597 usage examples that held a cell Tatoeba lacks, 196 were dropped before any translation: broken text 86 (a fragment, a misspelling, a lost accent), violence 41, offensive 33, politics 25, smoking 4, religion 4, quotation 2 (a citation typed as an example), brand 1. The second pass then dropped 50 of the 401 kept: 21 for content, 18 whose form has another reading than the cell's (a prohibition with μη(ν), an imperative, a homograph with no subject), 7 with broken Greek and 4 whose Russian it could not make right. 351 rows ship.
   - Licence: Wiktionary's text, and so kaikki.org's data, is under CC BY-SA 4.0 (also GFDL; we use CC BY-SA 4.0).
     - Attribution (kyukhin, 2026-11-22; CodeRabbit on #366): as for the word forms (0136). Credits names "Wiktionary contributors" with the source (via kaikki.org) and the licence; the `data_source` row records the source, its version and the licence (the table under "Credits and `data_source`"). The data file keeps each row's entry (`page`, the Wiktionary page the example is on in the pinned subset), so every sentence leads back to its page and that page's history of authors; the build checks the page against the pin.
     - Share-alike: the rows, with our translations of them, ship under CC BY-SA 4.0 in the Greek pack, as the word forms do (0136).
     - The Greek text and its English are Wiktionary's, unchanged but for NFC. Our Russian translation is marked as generated in the byline, as CC BY-SA 4.0 asks of changes.
3. **Generated** (#365): a model writes one sentence for one cell and translates it into eng and rus (kyukhin, 2026-11-22: the drill's two vias in 2.0; spa and arb come when a pair needs them). It is LibreDict's own data under CC BY-SA 4.0, like the grammar notes (0133). The model gets the cell and the list words, and no web content, so nothing comes from learning sites.

Other licensed corpora wait for 2.1, each with its licence checked first.

**Data files** (#365), plain text in Git (not LFS), so a PR shows every sentence:
- **`Scripts/data/drill-examples/ell.tsv`**: one row per Wiktionary or generated sentence. UTF-8, tab-separated, a header line, rows sorted by `id`. 1.5 MB for the 2.0 scope (#365 as built, 2026-11-23: 351 Wiktionary and 4,436 generated rows; the estimate was about 1.3 MB and 5,600 rows).

  | Column | Content |
  |---|---|
  | `id` | 1,000,000,001… (Wiktionary), 2,000,000,001… (generated) |
  | `source` | `wiktionary` or `generated` |
  | `page` | A Wiktionary row's entry in the pinned subset (the page it is on, checked against the pin); empty for a generated row (kyukhin, 2026-11-22) |
  | `cell` | The cell key it was written or translated for |
  | `text` | Greek, NFC. A Wiktionary row repeats the pinned text, which the build checks, so it cannot be edited by hand |
  | `eng`, `rus` | Translations. A Wiktionary row's `eng` is Wiktionary's own (checked against the pin). `spa` and `arb` columns are added when a pair needs them |
  | `model` | The generator's id and the date |
  | `check` | `ok`, or the second pass's reason |
  | `checked_by` | The checking model's id and the date |

- **`Scripts/data/drill-examples/ell-readings.tsv`**: the second pass's verdicts on found sentences of homograph cells, and the Tatoeba check's `no` verdicts on any cell (Checks, 4). Columns `cell`, `sentence_id` (a Tatoeba id, or a Wiktionary or generated row's id), `verdict` (`ok` or `no`), `checked_by` and `reason`, the second pass's reason (kyukhin, 2026-11-22).
- **`Scripts/data/drill-examples/ell-skipped.tsv`** (kyukhin, 2026-11-22): the cells with no natural sentence. Columns `cell`, `reason` (the generator's, confirmed by the second pass) and `checked_by`. A cell listed here counts as done for the 2.0 gate and stays without an example, even when a sentence holds its form another way (#365, after QA: 3 such cells, "Αν χρειαστείτε κάτι" is a subjunctive after αν, not χρειάζομαι's imperative εσείς). Lines of cells the drill no longer asks are stale: reported, never used.
- **`Scripts/drill_examples.py`** is the tool around them. The build never runs it and stays offline:
  - `--todo [--scope A2/A2] [--source FILE] [--out DIR]` lists the open cells of a scope (verb lists up to / tenses up to; A2/A2 is 2.0's): no row in a built file and not skipped, with what the generator needs: the cell, its form and spellings, the verb, its list term, meaning and level, the tense title, voice and person, its homographs and their other readings; with `--out` also the allowed words, one file per list level;
  - `--add <file>` appends generated or checked rows and gives them ids, the next of their source; a Wiktionary row without a `page` gets it from the pin;
  - `--sample 50` writes `Scripts/reports/drill-examples-sample.md`: 50 rows that did not come from Tatoeba, drawn with a seed taken from the data file's sha256, so nobody picks the sample.
- **The generator's brief**:
  - one sentence of 3 to 10 words, with the cell's form exactly once, in the cell's reading (tense, voice, person);
  - its other words from the Greek lists up to the verb's level (A1 for an A1 verb, A1 and A2 for an A2 verb), plus function words;
  - everyday, neutral content, with no real people, brands, politics or violence;
  - modern monotonic spelling;
  - faithful translations in English and Russian that keep the tense and person;
  - a cell with no sentence a Greek would really say in the cell's meaning is skipped with its reason, not forced (kyukhin, 2026-11-22): above all a passive of an active verb with no real use in that person.

  The rows record the model ids; this spec does not fix them.

**Checks** (#365):
1. **Form gate.** The build fails unless every Wiktionary and generated row:
   - holds its cell by the match rule (the build finds the span);
   - has at most 15 words, is in NFC and has both translations, eng and rus;
   - has `check` `ok` and an id in its range, the ids unique and ascending, and a text no other row has;
   - for a Wiktionary row, has the pinned text, English and page; a generated row has no page;
   - and every reading verdict is `ok` or `no` with its checker, every skip has its reason and checker.
2. **Second model pass.** A separate run, in a fresh context, checks each row:
   - the Greek's grammar and naturalness;
   - that the highlighted form has the cell's reading;
   - that each translation is faithful;
   - the vocabulary level and the content.

   A row that fails is generated again and checked again. The same pass writes the reading verdicts and confirms each skip.
3. **kyukhin's sample of 50**, in the data PR. He reads the Greek, English and Russian: every language the rows hold. If the sample has a wrong form or a wrong meaning, the cause is fixed, the rows it touched are generated again and a new sample is drawn. The `ell` release waits for his ok (0237, "Release").
   - First sample (kyukhin, 2026-11-23): every form matched its cell. Two rows were unnatural, a passive where a Greek says an active third person plural (φέρνονται) and a figurative aorist (αστράψατε), and one translation was wrong (παρουσιαστήκαμε is "we reported to", not "we introduced ourselves").
   - The cause fixed: the second pass checked again, with those patterns, all 828 generated rows of passive cells of active verbs and of -μαι verbs. 163 rows changed in place, keeping their ids (kyukhin's three among them); 19 were removed and their cells skipped. A new sample was drawn.
4. **Tatoeba check** (kyukhin, 2026-11-23). Every pair of a cell and the Tatoeba sentence it uses is checked by a model too, as a Wiktionary row is:
   - its Greek: errors and spelling (a sweep for δε μπορώ, μη ξεχάσεις, ΄ for ’);
   - the reading of its form, the cell's;
   - the content filter of the Wiktionary rows ("Sources and licences");
   - both translations the drill shows, English and Russian.

   A failure is a `no` verdict in `ell-readings.tsv` (the reason starts "Tatoeba check"). A Greek, content, English or Russian failure is the sentence's own, so it gets a `no` verdict for every cell the sentence serves; a form failure holds for its cell only. The cell then takes its next Tatoeba sentence, and that pair is checked in turn; this repeats until no unchecked pair comes up (#365, after QA: a check keyed by the sentence alone missed the cells that took a checked sentence later). A 2.0 cell left without one is generated or skipped like any open cell. As run: 996 `no` verdicts on 897 sentences. 646 sentences fail for themselves, in 708 pairs: content 293, Greek 244, English 87, Russian 22. 288 pairs fail on the form: mostly χώρα the noun in χωράω's imperative, and continuous imperatives in simple-imperative cells (rule 5). Drill rows from Tatoeba: 3,958 before the check, 3,602 after (3,429 sentences); in the 2.0 scope 2,284 before and 2,140 after. The 2.0 cells left without a sentence got 114 generated rows and 3 skips, and 2 more took generated rows already in the data file. 94 of the verdicts name a Tatoeba sentence that is no candidate (the build's filters drop it), so they are stale: reported, never used.

**Byline** (kyukhin, 2026-11-22). Every example names its source. Wiktionary is named as Credits names it in each language: Wiktionary, Викисловарь, Wikcionario, ويكاموس, Βικιλεξικό.

| Sentence | Translation shown | Byline (en) | VoiceOver (en) |
|---|---|---|---|
| Tatoeba | Tatoeba's | Zeus, CH · Tatoeba (as today) | From Tatoeba: Zeus and CH |
| Wiktionary | its English | Wiktionary | From Wiktionary |
| Wiktionary | a generated one (rus) | Wiktionary · translation: LibreDict, generated | From Wiktionary; translation generated by LibreDict |
| Generated | generated | LibreDict, generated | Generated by LibreDict |

**Credits and `data_source`** (#365).
- The Wiktionary line becomes "Word forms and usage examples: Wiktionary contributors, via kaikki.org (CC BY-SA 4.0)". It credits both Wiktionary rows.
- A new line: "Generated conjugation examples: written with an AI model for LibreDict and checked (CC BY-SA 4.0). Each is marked “LibreDict, generated”."
- Two new `data_source` rows in the Greek pack, also listed under `ell` in `packs.json`:

  | id | kind | Name | Version | Licence | URL |
  |---|---|---|---|---|---|
  | `wiktionary-ell-examples` | `example_sentences` | Wiktionary (Greek usage examples) | `enwiktionary 2026-10-01` | CC BY-SA 4.0 | `https://kaikki.org/dictionary/` |
  | `libredict-drill-ell` | `example_sentences` | Drill examples (LibreDict, generated) | the data file's date: the latest in its generated rows' `model` and `checked_by` | CC BY-SA 4.0 | `https://github.com/kyukhin/dict-app/tree/master/Scripts/data/drill-examples` |

**Report and gates.** `examples-qa.md` gains a "Drill cells" section:
- the pool: verbs per list;
- cells by list and tense level, and by tense and voice, each split into covered by Tatoeba, by Wiktionary, generated, skipped and none;
- the data files: rows per source and how many ship, verdicts, skips, stale lines, and the 2.0 scope's open cells;
- homograph cells of both kinds, with their verdicts, and the spellings shared by two verbs;
- samples: κάνω imperative εσύ, γράφω aorist εγώ, γράφω future εγώ, λέω simple subjunctive εσύ, βλέπω perfect εγώ, έχω present αυτός;
- the open cells of the 20 most frequent verbs;
- stale data rows: cells the drill no longer asks, which the build skips;
- the share of each generated row's words that are list words up to its verb's level;
- the skipped cells with their reasons (kyukhin, 2026-11-22);
- the size of the drill rows and a hash of them.

| Gate | Ticket |
|---|---|
| Every cell row's span holds its cell's form by the match rule, checked again on the output | #364 |
| Every cell key is in the build's cell list; one row per cell (`ord` 1); every Tatoeba id below 10^9 | #364 |
| The word examples do not change: the rows of word keys keep their hash | #364 |
| Every cell of the 2.0 scope (the A1 and A2 verbs, tenses up to A2) has a sentence, or is listed in `ell-skipped.tsv` (kyukhin, 2026-11-22); no listed cell has a row | #365 |
| The data files pass the form gate (Checks, 1) | #365 |
| Size: the 10 MB budget counts word examples only (9.36 MB now). The drill rows and the sentences only they use stay within 3.5 MB installed (kyukhin, 2026-11-22) | #364, #365 |

**Measured** (2026-11-22). Cells per verb list and tense level. The coverage columns count cells with at least one matching sentence:
- **Pack**: a sentence already in the Greek pack;
- **Tatoeba**: any candidate after the filters;
- **+ Wiktionary**: Tatoeba or a Wiktionary usage example;
- **Homographs**: of the found cells, those of another reading that wait for a reading verdict;
- **To generate**: the cells without a found sentence, counting every homograph cell as open (an upper bound).

| Verbs, tenses | Cells | Pack | Tatoeba | + Wiktionary | Homographs | To generate |
|---|---|---|---|---|---|---|
| A1 verbs, A1 tenses | 4,319 | 1,221 (28%) | 1,874 (43%) | 2,006 (46%) | 304 | 2,617 |
| A1 verbs, A2 tenses | 1,156 | 148 (13%) | 242 (21%) | 281 (24%) | 23 | 898 |
| A1 verbs, B1 tenses | 5,124 | 390 (8%) | 672 (13%) | 738 (14%) | 202 | 4,588 |
| A1 verbs, B2 tenses | 8,450 | 109 (1%) | 262 (3%) | 316 (4%) | 8 | 8,142 |
| A2 verbs, A1 tenses | 1,465 | 205 (14%) | 273 (19%) | 317 (22%) | 65 | 1,213 |
| A2 verbs, A2 tenses | 394 | 32 (8%) | 54 (14%) | 64 (16%) | 4 | 334 |
| A2 verbs, B1 tenses | 1,722 | 48 (3%) | 72 (4%) | 88 (5%) | 35 | 1,669 |
| A2 verbs, B2 tenses | 2,786 | 20 (1%) | 32 (1%) | 45 (2%) | 0 | 2,741 |
| B1 verbs, all tenses | 31,584 | 840 (3%) | 1,039 (3%) | 1,294 (4%) | 265 | 30,555 |
| All | 57,000 | 3,013 (5%) | 4,520 (8%) | 5,149 (9%) | 906 | 52,757 |

The A1 and A2 verbs by tense, all tense levels. Each cell gives cells / Tatoeba / + Wiktionary:

| Tense | Main voice | Passive of a verb with both voices |
|---|---|---|
| Present | 1,295 / 598 (46%) / 643 (50%) | 902 / 47 (5%) / 77 (9%) |
| Imperfect | 1,555 / 260 (17%) / 299 (19%) | 868 / 4 / 7 (1%) |
| Aorist | 1,526 / 640 (42%) / 688 (45%) | 887 / 40 (5%) / 65 (7%) |
| Future: simple form | 1,556 / 351 (23%) / 392 (25%) | 903 / 8 / 12 (1%) |
| Imperative: continuous form | 465 / 154 (33%) / 166 (36%) | 149 / 1 / 2 (1%) |
| Imperative: simple form | 499 / 247 (49%) / 268 (54%) | 284 / 5 / 5 (2%) |
| Future: continuous form | 1,526 / 44 (3%) / 50 (3%) | 887 / 1 / 1 |
| Perfect | 1,526 / 173 (11%) / 191 (13%) | 888 / 9 / 13 (1%) |
| Pluperfect | 1,526 / 30 (2%) / 34 (2%) | 888 / 0 / 0 |
| Future perfect | 1,526 / 2 / 5 | 888 / 0 / 0 |
| Subjunctive: continuous form | 1,526 / 280 (18%) / 304 (20%) | 887 / 5 / 6 (1%) |
| Subjunctive: simple form | 1,556 / 560 (36%) / 600 (39%) | 903 / 22 (2%) / 27 (3%) |

- κάνω · Imperative: simple form · εσύ (κάνε, κάμε) gets "**Κάνε** αυτό που μπορείς!" from Tatoeba. It is an aspect-only homograph of the continuous imperative, so it is no reading to check.
- The 50 verbs ranked highest, tenses up to A2: 1,334 cells, 42% covered by the pack, 62% by Tatoeba, 65% with Wiktionary. The issue's 13% and 23% (41% and 67% for those 50 verbs) came from a rough script (active voice, approximate cells); the figures above replace them.

Scopes and size. "Installed" is measured: the pack rebuilt with the rows, then `VACUUM`. Generated rows were stood in by real sentences of the same languages, each with an English and a Russian translation; a Wiktionary row has a Russian one added. "Download" adds xz as measured for the found rows (+0.14 MB), plus the generated rows' bytes at today's Greek example ratio (0.68 / 2.34). It is an estimate, since xz compresses the stand-ins, which repeat stored text, too well.

| Scope | Cells | Found, homographs excluded | To generate | `ell` installed | `ell` download |
|---|---|---|---|---|---|
| Found sentences only, every cell (#364 and the Wiktionary part of #365) | 57,000 | 4,243 | — | +0.59 MB | +0.14 MB |
| A1 and A2 verbs, tenses up to A2 (2.0, kyukhin 2026-11-22) | 7,334 | 2,272 | 4,666 to 5,062 | +1.9 MB | about +0.5 MB |
| A1 and A2 verbs, every tense (2.1) | 25,416 | 3,214 | 21,561 to 22,202 | +6.6 MB | about +1.9 MB |
| Every cell (with the B1 verbs, 2.1) | 57,000 | 4,243 | 51,851 to 52,757 | +14.8 MB | about +4.3 MB |

The `ell` pack is 60.6 MB installed and 11.9 MB to download today. The low bound of "To generate" assumes every found homograph sentence passes its reading check. "About 4,500" in #365 matches the tenses up to A2: what the drill asks with Greek A1 and A2 checked, until "Tenses up to" is raised.

**Reading in the app.** 0132 ("Example in the answer panel") reads a cell's sentence with `examples(lang: "ell", word: <cell key>, limit: 1)`, the read that `examples(for:limit:)` calls, so the key is never lowercased as a `WordKey` would be (Key, above). `ExampleSentence.source` (`ExampleSource`: `.tatoeba`, `.wiktionary`, `.generated`, from the id) chooses the byline. `ExampleText.byline` and `accessibilityLabel` keep the Tatoeba text and add the other three rows of the byline table. `ExampleText.sourceOfTranslation` gives a translation's source. Everything stays pure and unit-tested.

### Identifiers

| Element | Identifier |
|---|---|
| Section, its title | `examples_section`, `examples_title` |
| Example `n` (1…5, display order): container, sentence, translation, byline | `example_<n>`, `example_sentence_<n>`, `example_translation_<n>`, `example_byline_<n>` |
| More / Fewer | `examples_more_button` |
| Learning: the sheet, its word, its Continue | `example_sheet`, `example_sheet_word`, `example_sheet_continue`; its examples use `example_<n>` and the ids above (n 1…3) |
| Learning: the feedback bar's Example button | `exercise_example_button` |
| Credits line | `credits_tatoeba` |
| The drill's answer panel (#364): the example | `drill_example` (0132) |
| Credits line of the generated drill examples (#365) | `credits_drill_examples` |

Numbered identifiers avoid the `firstMatch`-in-another-cell gotcha (#143).

### Strings

Seven keys. The implementing agent checks these texts and enters them in the catalog; composed Arabic strings start with U+200F, and usernames inside them are wrapped in FSI…PDI (#119):

| Key | en | ru | es | ar | el |
|---|---|---|---|---|---|
| `examples.title` | Examples | Примеры | Ejemplos | أمثلة | Παραδείγματα |
| `examples.more` | More examples | Ещё примеры | Más ejemplos | مزيد من الأمثلة | Περισσότερα παραδείγματα |
| `examples.fewer` | Fewer examples | Меньше примеров | Menos ejemplos | أمثلة أقل | Λιγότερα παραδείγματα |
| `examples.byline` | %@ · Tatoeba | %@ · Tatoeba | %@ · Tatoeba | %@ · Tatoeba | %@ · Tatoeba |
| `examples.a11y.byline` | From Tatoeba: %@ | Из Tatoeba: %@ | De Tatoeba: %@ | من Tatoeba: %@ | Από το Tatoeba: %@ |
| `examples.button` | Example | Пример | Ejemplo | مثال | Παράδειγμα |
| `credits.dataSources.tatoeba` | Example sentences: Tatoeba (tatoeba.org), CC BY 2.0 FR. Each example names its authors. | Примеры предложений: Tatoeba (tatoeba.org), CC BY 2.0 FR. У каждого примера указаны его авторы. | Frases de ejemplo: Tatoeba (tatoeba.org), CC BY 2.0 FR. Cada ejemplo indica sus autores. | جمل الأمثلة: Tatoeba (tatoeba.org)، CC BY 2.0 FR. يذكر كل مثال أسماء مؤلفيه. | Παραδείγματα προτάσεων: Tatoeba (tatoeba.org), CC BY 2.0 FR. Κάθε παράδειγμα αναφέρει τους συγγραφείς του. |

- In `examples.byline` the authors are joined with ", "; in `examples.a11y.byline` with the locale's "and" (`ListFormatter`).
- The sheet's Continue and result line reuse E4's keys (#159). Sentences, translations and usernames are never translated.
- `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage` covers the keys. 0237's Languages row and remove alert keep their text; the packs' sizes grow by themselves through the catalog.

#365 adds seven keys and changes one (the implementing agent checks the texts, Arabic values start with U+200F):

| Key | en | ru | es | ar | el |
|---|---|---|---|---|---|
| `examples.byline.wiktionary` | Wiktionary | Викисловарь | Wikcionario | ويكاموس | Βικιλεξικό |
| `examples.byline.wiktionaryGenerated` | Wiktionary · translation: LibreDict, generated | Викисловарь · перевод: LibreDict, сгенерирован | Wikcionario · traducción: LibreDict, generada | ويكاموس · الترجمة: LibreDict، مولَّدة | Βικιλεξικό · μετάφραση: LibreDict, παραγόμενη |
| `examples.byline.generated` | LibreDict, generated | LibreDict, сгенерировано | LibreDict, generado | LibreDict، مولَّد | LibreDict, παραγόμενο |
| `examples.a11y.byline.wiktionary` | From Wiktionary | Из Викисловаря | De Wikcionario | من ويكاموس | Από το Βικιλεξικό |
| `examples.a11y.byline.wiktionaryGenerated` | From Wiktionary; translation generated by LibreDict | Из Викисловаря; перевод сгенерирован LibreDict | De Wikcionario; traducción generada por LibreDict | من ويكاموس؛ الترجمة مولَّدة بواسطة LibreDict | Από το Βικιλεξικό· μετάφραση από το LibreDict, παραγόμενη |
| `examples.a11y.byline.generated` | Generated by LibreDict | Сгенерировано LibreDict | Generado por LibreDict | مولَّد بواسطة LibreDict | Παράχθηκε από το LibreDict |
| `credits.dataSources.drillExamples` | Generated conjugation examples: written with an AI model for LibreDict and checked (CC BY-SA 4.0). Each is marked “LibreDict, generated”. | Сгенерированные примеры спряжения: написаны с помощью ИИ-модели для LibreDict и проверены (CC BY-SA 4.0). Каждый помечен «LibreDict, сгенерировано». | Ejemplos de conjugación generados: escritos con un modelo de IA para LibreDict y revisados (CC BY-SA 4.0). Cada uno lleva «LibreDict, generado». | أمثلة التصريف المولَّدة: كُتبت بنموذج ذكاء اصطناعي لـ LibreDict ورُوجعت (CC BY-SA 4.0). يحمل كل منها «LibreDict، مولَّد». | Παραγόμενα παραδείγματα κλίσης: γράφτηκαν με μοντέλο ΤΝ για το LibreDict και ελέγχθηκαν (CC BY-SA 4.0). Το καθένα σημειώνεται «LibreDict, παραγόμενο». |
| `credits.dataSources.wiktionary` (changed) | Word forms and usage examples: Wiktionary contributors, via kaikki.org (CC BY-SA 4.0) | Словоформы и примеры употребления: … | Formas de las palabras y ejemplos de uso: … | صيغ الكلمات وأمثلة الاستخدام: … | Κλιτοί τύποι και παραδείγματα χρήσης: … |

"LibreDict" and the Wiktionary names are not translated beyond Credits' own wording. #364 adds no key: Tatoeba's byline is as today.

### Code map

| Path | Change | Ticket |
|---|---|---|
| `Scripts/build_examples.py` | New step in `STEPS`: `SCHEMA` and an empty `build()` (#240); the pipeline, `--refresh` and `--self-check` (#177) | #240, #177 |
| `Scripts/data/tatoeba-20261031/*.tsv.xz` (LFS), `Scripts/fixtures/tatoeba-sample/`, `Scripts/reports/examples-qa.md`; `.gitattributes` | New | #177 |
| `Scripts/packs.json`, `Scripts/build_dictionaries.py` | The row filters; the step in `STEPS`, within format 4 | #240 |
| `Scripts/inputs.json` | The export and subset pins | #177 |
| `DictApp/DictApp/Resources/dictionaries.sqlite`, `empty-pack.sqlite` | The empty tables, in format 4 | #240 |
| `Packs/ell-*.sqlite.xz`, `Packs/eng-lists-*.sqlite.xz` | Rebuilt with the Greek and the English rows; new pack versions, same format | #177 |
| `Models/Models.swift` | `ExampleSentence`, `ExampleTranslation`, `ExampleText`, `DictionarySchemas.examplesSchema(for:)` | #178 |
| `Services/DatabaseService.swift` | `examples(for:limit:)` | #178 |
| `ViewModels/DefinitionViewModel.swift`, `Views/DefinitionView.swift` | `examples`, `ExamplesSection`, `ExampleSentenceView` | #178 |
| `ViewModels/LearnViewModel.swift`, `Views/ExerciseView.swift` | The examples of a run's words, `ExampleSheet`, the bar's Example button | #178 |
| `Views/CreditsView.swift`, `Resources/Localizable.xcstrings` | The Tatoeba line; seven keys | #178 |
| `DictAppTests/DictAppTests.swift` | The unit classes below; `TestDictionary.make` gains `examples:` | #177, #178 |
| `DictAppUITests/TestCases/ExampleSentencesTests.swift`, `PageObjects/DefinitionPage.swift`, `TestHelpers/AccessibilityIdentifiers.swift`, `TestData.swift` | New suite and helpers (synchronized folder, no Xcode step) | #178 |
| `docs/specs/0000-overview.md`, `0129-dictionary-file.md`, `0237-downloads.md`, `0131-learning.md` | Definition screen and Credits; the example tables and their owner; the Greek and English lists packs' sizes and contents; the example sheet in a run | #240, #177, #178 |

Drill examples (#364, #365; approved by kyukhin on 2026-11-22):

| Path | Change | Ticket |
|---|---|---|
| `Scripts/drill_cells.py` | New: the drill's cells, a port of 0132's rules | #364 |
| `Scripts/build_examples.py` | The match rule, the choice, the cell rows, the report section and the gates (#364); the Wiktionary rows, the data files, their gate and the two `data_source` rows (#365); `--self-check` cases for both | #364, #365 |
| `Scripts/fixtures/tatoeba-sample/` | The match cases (Test plan) (#364); `drill-examples/` (the three data files) and `kaikki-examples.jsonl` (entries of the pinned subset) for the data cases, and αγάπησε in `lexicon.tsv` (#365) | #364, #365 |
| `Scripts/drill_examples.py`, `Scripts/data/drill-examples/ell.tsv`, `ell-readings.tsv`, `ell-skipped.tsv`, `Scripts/reports/drill-examples-sample.md` | New | #365 |
| `Scripts/packs.json` | The two `data_source` ids under `ell` | #365 |
| `Packs/ell-*.sqlite.xz`, the bundle's `catalog_pack` row | Rebuilt `ell`, a new version and its pin; no other asset | #364, #365 |
| `Models/Models.swift` | `ExampleSource`, the source bylines and VoiceOver labels; the Credits line | #365 |
| `Resources/Localizable.xcstrings`, `Views/CreditsView.swift` | The keys above | #365 |
| `DictAppTests/DictAppTests.swift` | `DrillExampleDataTests`; `ExampleDataTests.testEveryExampleIsComplete` amended; `ExampleTextTests` for the bylines | #364, #365 |
| The app side of #364 | In 0132's code map | #364 |
| `docs/specs/0000-overview.md`, `0237-downloads.md` | The drill panel; the Greek pack's size | #364, #365 |

No new Swift file and no Xcode step. No network code, entitlement, Info.plist key or dependency; the display name stays "LibreDict" (`INFOPLIST_KEY_CFBundleDisplayName`).

### Tickets, order and sizes

Sizes are pipeline days: development, QA on the four simulators, review and the daily merge. Streams as of 2026-11-04: two UI, two data.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| #240 (0237 T1), the E7 part | `build_examples.py` with `SCHEMA` and an empty `build()` in `STEPS`; the three tables in format 4; the `packs.json` filters | — | +0.25 | Data |
| #177 Pipeline | `build_examples.py` (filters, keys, choice, gates, report, `--refresh`, `--self-check`) for Greek (2) and English (1); both subsets and the pins; rebuilt `ell` and `eng-lists` assets; `--verify` | Approval; #240; E3 #153 (the English key set) and #152, or a rebase after them (one rebuilt file per data PR, 0129) | L, 3 | Data, whichever is free |
| #178 Definition and learning | Model, read, Definition section, More, byline, VoiceOver, Arabic, Credits, the strings in five languages, `ExampleSentencesTests` on the matrix with a Greek and an English word (1.75); the learning sheet, the bar's Example button and their tests (1.0); the via translation (0.25) | #177 for the data (unit tests start on made-up rows); E3 #151 (`wordKey(for:)`; if absent, add exactly it, as 0131 allows #157); 0237 T2 #241 (`-installPacks`). The learning part: E4 #157 (`LearningPairs.via`), #159 and #161 | L, 3 | UI |

- 6 stream-days, plus 0.25 inside #240. Against the first draft's 4.25: English +1.25 (kyukhin, 2026-11-04) and the sheet in place of a line in the feedback bar +0.5.
- #177 starts when #240 and E3's #153 have merged and blocks nothing else; #178 follows it, its learning part after E4's #161.
- Nothing is cut if the release runs late; the date moves instead (kyukhin, 2026-11-04). The first draft's minimal version is no longer a plan.

Drill examples (#364, #365; approved by kyukhin on 2026-11-22). Both land on master and are cherry-picked into release/2.0 (backport-2.0). Each rebuilds `ell` once, and its `packs-YYYYMMDD` release follows kyukhin's yes.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| #364 Drill examples from Tatoeba | Data (1.5): `drill_cells.py`, the match rule, the choice, the cell rows, the report, the gates, `--self-check`, the rebuilt `ell`. App (1.0): the panel, the read, `-drillPlan` and the tests in 0132 | Approval of this spec and 0132's part | M, 2.5 | One data and one UI stream in parallel; the UI part starts on a fixture pack |
| #365 Fill the cells Tatoeba lacks | Wiktionary rows (0.5); the data files and `drill_examples.py` (0.5); generation and the second pass for the 2.0 scope (1.0 for about 5,000 rows); the bylines, Credits and strings in five languages (0.5); the sample, then the rebuilt `ell` | #364 merged; kyukhin's sample review | M, 2.5 | Data |

## Test plan

Unit classes go in `DictAppTests.swift`; async tests are `@MainActor` (#229). Data tests read the committed Greek and English lists packs through 0237's `PackFixtures`; read tests use `TestDictionary.make(rows:metadata:examples:)` attached as the `ell` or `eng_lists` pack through 0237's `DictionaryFiles` seam. UI suites run on the four-simulator matrix, one suite per `xcodebuild` run with the app uninstalled before it, with `-skipWelcome -installPacks ell,eng-lists -packFixtures <path>` (0237) unless a test says otherwise.

| Acceptance criterion | Test |
|---|---|
| #134, #177: at least 85% of the top-500 Greek verbs show 3+ examples (all 500 counted, kyukhin 2026-11-04) | Build gate (fails below 85% of the 500; measured 85.8%), figures and misses in `examples-qa.md`. Unit `ExampleDataTests.testFrequentVerbsHaveThreeExamples` (γράφω, είμαι, έχω, κάνω, θέλω, ξέρω, λέω, πάω: 3+ each in the Greek pack) |
| #134, #177, #178: each example has a translation, the highlighted form and its author | Build gates. Unit `ExampleDataTests.testEveryExampleIsComplete` (in both packs: every Greek sentence has an English translation, every English one a translation into rus, spa, arb or ell, every text an author, every span inside its text), `ExampleTextTests.testHighlightCoversTheForm` (bold and tinted exactly on the span; a span past the end gives the plain text), `testBylineNamesBothAuthors` (one name when they are equal or no translation shows). UI `ExampleSentencesTests.testGreekWordShowsExamples` (γράφω: `examples_section`, 3 examples, each with a sentence, a translation and a byline ending "Tatoeba"; More shows 5 and reads "Fewer examples") |
| #178: More is hidden with 3 or fewer examples | UI `ExampleSentencesTests.testThreeExamplesShowNoMoreButton` (λύπη has exactly 3: no More button) |
| #134, #178: a Russian translation with the Russian UI when Tatoeba has one | Unit `ExampleTextTests.testTranslationFollowsTheUILanguage` (ru present → ru; absent → eng; es; ar → arb; Greek UI and a Greek sentence → eng; an English sentence with the English UI → none, with the Greek UI → ell or none). UI `ExampleSentencesTests.testRussianUIShowsRussianTranslation` (`-AppleLanguages (ru)`: γράφω's first translation is Cyrillic; with the English UI it is Latin) |
| #134, #177: offensive sentences filtered by Tatoeba's tags | Build gate (re-scan of the output: no stored sentence or translation has a blocking tag). `--self-check` (the tagged sentence and the tagged translation are absent) |
| #134, #177: added size ≤ 10 MB | Build gate (measured 9.31 MB); table sizes in `examples-qa.md`. QA: both assets' and files' sizes, and App Size in TestFlight (unchanged), recorded in History |
| kyukhin 2026-11-04: English examples ship, in the English lists pack only | Unit `ExampleDataTests.testEnglishListWordsHaveExamples` (go, house, write, good: 3+ each in `eng-lists`; went, going, gone highlighted for go), `testExamplesGoWithTheirLanguage` (Greek rows only in `ell`, English rows only in `eng-lists`, none in the bundle, the stub or the other packs). UI `ExampleSentencesTests.testEnglishWordShowsExamples` (house from WordNet with `-installPacks eng-lists`: the section; `-AppleLanguages (es)`: a Spanish translation), `testEnglishWordWithoutTheListsPackShowsNone` (`-installPacks ell` only: house shows no section) |
| kyukhin 2026-11-04: the tables land in format 4 with #240 | Unit `ExampleDataTests.testEveryFileHasTheExampleTables` (bundle, stub and every committed asset: the three tables, empty in the bundle and the stub), with 0237's `PackFileTests.testEveryFileHasTheFormat` (format 4). Review: #177 changes no table shape and no `user_version` |
| #177: reproducible from the pinned snapshot | `inputs.committed()` checks every subset file; `build_examples.py --self-check` builds twice with equal hashes; `build_dictionaries.py --verify` and `cut_packs.py --verify` give the committed files |
| #134, #178: Tatoeba (CC BY 2.0 FR) credited | Unit `ExampleDataTests.testTatoebaDataSourceRow` (in the Greek and the English lists packs, CC BY 2.0 FR; no `dict_metadata` row). UI `ExampleSentencesTests.testCreditsListTatoeba` (`credits_tatoeba` through `settings_credits_link`) |
| kyukhin 2026-11-04 (pairs): in learning, an example's translation is in the via, direct only | Unit `ExampleTextTests.testLearningTranslationFollowsTheVia` (a Greek sentence via English: English; an English sentence via Spanish: Spanish, and none when Tatoeba has no Spanish one, never the Greek or Russian one; via Greek: Greek; via English: none; a Greek sentence in Greek via Russian, the limited pair: Russian when it has a direct one, else English), `testLearningPrefersExamplesWithTheVia` (5 examples, 2 with Spanish: those 2 first, then 1 more in build order), `ExerciseRunViewModelTests.testExampleUsesTheLanguagesVia` (English via Spanish: the Spanish translation; Greek via Russian: Russian where Tatoeba has it, English otherwise, the Russian ones first) |
| #178: the new-word card shows an example when one exists (kyukhin 2026-11-04: a sheet after the first answer, an Example button on every other bar, nothing for a word without examples) | Unit `ExerciseRunViewModelTests.testNewWordOpensTheExampleSheet` (the first answer to an `isNew` question of a word with examples sets `showsExampleSheet` with 1–3 examples; a later question of the same word does not), `testExampleButtonOnEveryBar` (a review, a trainer and a mistakes question of a word with examples offer it, and it opens the same examples; a word without examples: no sheet, no button), `testSheetContinueMovesOn` (Continue on the sheet goes to the next question, as the bar's does; a swipe down returns to the bar, whose Continue then moves on), `testExamplesReadOncePerWord` (two questions of one word, one read). UI `SessionFlowTests.testNewWordShowsTheExampleSheet` (`-learningFixture myWords5 -learningAnswerHints`: the first question has `exercise_new_badge`; after the answer `example_sheet` shows `example_sheet_word` and 1–3 `example_<n>` with English translations; `example_sheet_continue` shows the next question; all five fixture words have 5 examples, measured), `ExerciseFlowTests.testExampleButtonOpensTheSheet` (`-learningFixture due`: the bar's `exercise_example_button` opens `example_sheet`) |
| #178: localized UI; Arabic right to left | The catalog test. UI `ArabicLocalizationTests.testExamplesRightToLeft` (Arabic title; the byline starts with U+200F; the section's leading edge is on the right), `GreekLocalizationTests.testExamplesInGreek` (Greek title; the translation is English) |
| #178: iPhone and iPad, iOS 17.5 and 26.4 | `ExampleSentencesTests`, `SessionFlowTests` and the extended suites on the matrix; `ExampleSentencesTests.testExamplesFitAtTheLargestTextSize` (every line inside the window, More reachable), `SessionFlowTests.testExampleSheetAtTheLargestTextSize` (the sheet at full height on iPhone, `example_sheet_continue` hittable); `ArabicLocalizationTests.testExampleSheetRightToLeft` |
| Words without examples, packs not installed, other languages | Unit `ExampleReadTests.testWordWithoutExamplesReadsNone`, `testMissingPackReadsNone` (the stub attached), `testOtherLanguagesReadNothing` (`spa`, `und`: no SQL), `testExamplesComeInOrder` (`ord`, the limit, translations joined), `DefinitionViewModelExampleTests.testEntryUsesItsWordKey` (γράφω from El–En · FD and El–En · WN load the same rows). UI `ExampleSentencesTests.testWordWithoutExamplesShowsNoSection` (Αμβέρσα, which has none in the prototype) |
| 0129, 0237: reads go through the retry, no network | Unit `DictionaryReopenTests.testExampleReadRecoversAfterTheFileIsInvalidated`; 0237's `NetworkAuditTests` stays green |

QA records in History: the gate figures, the Greek and English lists assets' and files' sizes, `examples(for:)` time on the iPhone 15 Pro simulator (iOS 17.5, median of 3; expected under 5 ms) and the matrix results.

Drill examples (#364, #365; approved by kyukhin on 2026-11-22). Data tests read the committed Greek pack through `PackFixtures`. The panel's tests are in 0132's test plan.

| Acceptance criterion | Test |
|---|---|
| #364: unit tests for the cell match (compound tenses, clitics) | `build_examples.py --self-check`, on drill cases added to `Scripts/fixtures/tatoeba-sample/`:<br>- θα γράψω; Θα σου το γράψω (clitics, a capital); να μην το γράψεις (μην after να); το έχω γράψει (perfect);<br>- θα έχω γράψει: the future perfect only, never the perfect; έχει γράψει and έχει ήδη γράψει: never έχω's present αυτός, έχει ένα γράμμα is; θα έγραφα: never the imperfect; να γράφω: never the present;<br>- ν' αγαπάς, ν'αγαπάει, θ' αγαπούσα, θ' αγαπήσεις (an elided ν' or θ' blocks the present and the imperfect, and is no να or θα: no subjunctive, no future); μη μου μιλάς, ας μιλάνε (no present after a prohibitive or ας);<br>- Δε μ' αγαπάς (an elided clitic); έχω ήδη γράψει (an adverb: no match); γραψε without its accent (no match);<br>- Κάνε … (κάνω imperative εσύ, both aspects, no verdict needed); μίλησε without a reading verdict (no row) and with one (a row);<br>- a span from θα to the verb, clitics included; two forms of one cell (the first wins); a Tatoeba and a Wiktionary sentence for one cell (Tatoeba wins).<br>It builds twice with equal table hashes. Unit `DrillExampleDataTests.testSpansHoldTheCellsForm` checks the shipped spans on their own: every cell row's span, lowercased NFC, is one of the cell's forms with only clitics, and μη(ν) after να, between its words. `testCellKeysAreDrillCells`: every cell key (one with a `\|`) in `example_word` is a cell of the app's pool (`drillVerbs` over the three lists, `questions(verb:level: .b2)`), one row each with `ord` 1 |
| #364: κάνω, imperative εσύ, has a sentence with κάνε | Unit `DrillExampleDataTests.testKanoImperativeHasKane`: the `κάνω\|imperativeSimple.active\|2sg` row's span reads Κάνε, with an English translation and a Tatoeba author. The panel is in 0132 |
| #364: the build reports covered cells per tense; only the `ell` pack and its catalog pin change | `examples-qa.md`, "Drill cells" (per tense and voice). Review: the PR changes `Packs/ell-*.sqlite.xz` and the bundle's `catalog_pack` row, and no other asset; `cut_packs.py --verify`. Unit `ExampleDataTests.testExamplesGoWithTheirLanguage` (cell rows only in `ell`) and 0237's `PackFileTests.testEveryFileHasTheFormat` (still format 4). The gate "word examples do not change" |
| #364, #177: every example is complete | Unit `ExampleDataTests.testEveryExampleIsComplete`, amended: a cell row has `ord` 1, and its span may cover several words (from the form's first word to the verb). A generated sentence has eng and rus; a Wiktionary one has Wiktionary's eng and a generated rus; neither has spa or arb |
| #365: every drill cell of the Greek A1 and A2 verbs has a sentence (tenses up to A2, kyukhin 2026-11-22), or is listed as a cell with no natural one (kyukhin 2026-11-22) | Build gate. Unit `DrillExampleDataTests.testEveryCellInScopeHasASentence`: the app's own pool from the committed pack, every cell of the A1 and A2 lists' verbs in scope (`questions(verb:level: .a2)`) has a row or is in `ell-skipped.tsv`, and every skipped cell is in scope. This also catches drift in `drill_cells.py`. `--self-check`: a skipped cell is done, any other open cell fails the gate, cells above the scope do not count |
| #365: every sentence names its source; generated ones say so | Unit `ExampleTextTests.testBylineNamesTheSource`: the four rows of the byline table in five languages; Arabic starts with U+200F; the VoiceOver labels. `DrillExampleDataTests.testEverySentenceHasASource`: every sentence id is in one of the three ranges. A generated sentence has eng and rus only, author "LibreDict"; a Wiktionary sentence has the English from the pin and a generated Russian, author "Wiktionary". `CreditsTests` (both new `data_source` rows credited); `DrillExampleDataTests.testDrillDataSourceRows` (both rows in the Greek pack only, CC BY-SA 4.0). UI `ConjugationDrillFlowTests.testGeneratedExampleSaysSo` (0132). `--self-check`: a Wiktionary sentence by Wiktionary with the pin's English and a Russian by LibreDict; a generated one by LibreDict with eng and rus only; the three id ranges |
| #365: the licences allow shipping; nothing from learning sites | Review of the sources above and of `Scripts/drill_examples.py`: the generator gets no web content. The `data_source` rows and the Credits lines name CC BY-SA 4.0 |
| #365: the form gate, the second pass, kyukhin's ok on the sample | Build gate (Checks, 1); the `check` column is `ok` on every row. `--self-check` on `Scripts/fixtures/tatoeba-sample/drill-examples/`: the form gate catches each kind of bad row, verdict and skip; Tatoeba comes before a generated row; a row counts for its own cell of another reading (γράφετε, έκανα, αγάπησε) and never for the other; the readings file's `ok` and `no`; a row first for its own cell; stale lines reported and never used; the pin takes no quotation, and a text met twice keeps its first page; the two `data_source` rows; two builds with equal hashes; `Scripts/reports/drill-examples-sample.md` in the PR. kyukhin's ok is recorded in History, and the `ell` release follows it. The Tatoeba check (Checks, 4): its `no` verdicts are applied, `DrillExampleDataTests.testReadingVerdictsDecide` |
| Size | Build gate (drill rows ≤ 3.5 MB installed, kyukhin 2026-11-22). QA records the `ell` asset's and file's sizes in History |

## Open questions

1. **English examples in 2.0.** Resolved 2026-11-04: yes, in the `eng-lists` pack, downloaded only when the user starts learning English (Decisions).
2. **Examples in learning.** Resolved 2026-11-04: an example popup (Decisions).
3. **Land the tables before 2.0, whatever happens to E7.** Resolved 2026-11-04: yes, with #240 (Decisions).
4. **Translations through English.** Resolved 2026-11-04: direct translations only (Decisions).
5. **The gate's margin.** Resolved 2026-11-04: all 500 verbs (Decisions).
6. **Where the section sits.** Resolved 2026-11-04: above the inflection table (Decisions).

Drill examples (#364, #365):

7. **Which tenses of the A1 and A2 verbs in 2.0?** Resolved 2026-11-22: the tenses up to A2 (7,334 cells, 4,666 to 5,062 sentences to generate); their B1 and B2 tenses come in 2.1, with the B1 verbs (Decisions).
8. **Homographs of another reading** (μίλησε, γράφετε, είναι). Resolved 2026-11-22: such a cell takes a found sentence only with a model-checked reading (Decisions).
9. **Size budget.** Resolved 2026-11-22: the 10 MB budget counts word examples only; the drill examples have their own 3.5 MB installed (Decisions).
10. **Where the rows live.** Resolved 2026-11-22: cell keys in `example_word`, sources by id range; the format stays 4 (Decisions).
11. **Bylines.** Resolved 2026-11-22: as the byline table has them (Decisions).
12. **The translations of added sentences.** Resolved 2026-11-22, against the recommendation to keep four: English and Russian only in 2.0, the drill's two vias; a Wiktionary sentence gets a generated Russian one only. Spanish and Arabic come when a pair needs them (Decisions).

## History

- 2026-11-04: First draft. Measured with a prototype of the pipeline on the Tatoeba export of 2026-10-31 (the 19 files above) and the dictionary file of master `e9997dd`: Greek candidates and drops per filter, keys with exact and folded matching, the top-500 verb gate under 12, 15, 20 and no word caps (423, 428, 429, 432), table and xz sizes for 3 and 5 examples, translation coverage per language, direct against indirect Russian, translation authors, the Wiktionary stoplist seed, the subset's size, and the English variants (CEFR-J and all lemmas, with all or Russian-only translations, and their pin).
- 2026-11-04: Learning is chosen as a language pair (kyukhin, 0131): in learning, an example's translation is in the via language, a direct Tatoeba translation or none (`ExampleText.learningTranslation(for:via:)`, `forLearning(_:via:)`, examples with a via translation first); the Definition screen keeps the UI-language rule. #178 +0.25.
- 2026-11-04: kyukhin's answers applied to the body: English examples for the 8,609 English list words in the English lists pack (measured 6.90 MB installed, 2.31 MB to download, an English subset of 24.8 MB, 22 export files pinned); examples in learning come in a sheet after the first answer to a new word, and through an Example button on every other feedback bar; the empty tables land in format 4 with #240; nothing is cut, and the minimal version goes. #177 L 3, #178 L 3, #240 +0.25.
- 2026-11-04: Approved by kyukhin.
- 2026-11-04: Greek via Russian is offered as a limited pair (kyukhin, 0131): in learning its examples show the direct Russian translation, else the English one (`learningTranslation(for:via:meanings:)`), Russian ones first. No size change.
- 2026-11-07: #177 as built: 428 of the top 500 Greek verbs have 3 or more examples (85.6%); 10,814 Greek and 28,997 English sentences; tables 9.29 MB (Greek 2.34, English 6.97). The `ell` pack grows by 0.68 MB to download, `eng-lists` by 2.33 MB. English keys are the 8,431 one-word terms of #153's lists, the Greek seed 185 lemmas.
- 2026-11-07: #177, Morphy over-generation (CodeRabbit, PR #249): a token keys no inferred lemma when two of its lemmas are list words (lives: live, life), and no suffix-guessed lemma when the token is itself a list word (evening ↛ even, hopes ↛ hop); WordNet's irregular forms stay (was → be). 6,651 English words keep 3 or more examples (−17).
- 2026-11-07: #177 filters as built: a Greek sentence drops when any linked English translation is stoplisted; stoplists also check the pieces of a word split at an apostrophe; tokens include combining marks (harakat, stress marks), so a prefix entry cannot be split off; a tag blocks when it starts with "@" (except audio and adoption tags) or is on the content-tag list. `inputs.json` pins the export's 22 files as one folder entry plus 8 file entries; the subset is 25.8 MB in LFS; `--refresh --export-dir --export-date` and `--standalone` are added. The stoplist awaits kyukhin's review.
- 2026-11-08: #178 as built: each example is one VoiceOver element, so UI tests read `example_<n>`'s label (the sentence, translation and byline have no reachable ids); the byline keys are `examples.byline %@` and `examples.a11y.byline %@`; usernames sit in bidi isolates in every language, not only Arabic; the sheet opens once per word per run. QA: 18 deliberate breaks each failed their target test; `ExampleReadTests.testDecomposedWordFindsItsExamples` (an NFD word) added; `examples(for:)` takes 0.11–0.18 ms in Release on iPhone 17, iOS 26.4 (target under 5 ms). Unit 949 pass; `ExampleSentencesTests` 8/8 on iPhone and iPad. E7 is implemented.
- 2026-11-08: No stoplist (kyukhin): `examples-stoplist.tsv`, its Wiktionary seed, its part of the output gate and `ExampleDataTests.testNoStoplistedWordInThePack` are gone; Tatoeba's tags are the only filter. As built: 429 of the top 500 Greek verbs have 3 or more examples (85.8%); 10,853 Greek and 29,040 English sentences; 6,662 English list words have 3 or more; tables 9.31 MB (Greek 2.34, English 6.98). The `ell` asset is 11,902,208 bytes (+31,528), `eng-lists` 2,826,948 (+5,336), both still under release `packs-20261107`.
- 2026-11-08: The measured figures follow the build's report (`examples-qa.md`, CodeRabbit, PR #278): 6,662 of the 8,431 English list words have 3 or more examples and 7,496 one; the example tables take 9.31 MB (English 6.98); 85.8% of the top-500 Greek verbs have 3 or more. The prototype's placement table keeps its own figures.
- 2026-11-09: #182 regression: `SessionFlowTests.testExampleSheetAtTheLargestTextSize` checks the full-height sheet on iPhone only; on iPad the sheet is a form sheet, as this spec says.
- 2026-11-17 (kyukhin, #339): a Greek list word's examples show its own form. A token that is a one-word term of the Greek lists keys that term, itself as a headword, and of its lemmas only the verbs (Pipeline step 4); a list word whose own form the per-form pass leaves out leads with its best own-form sentence (step 5: 58 words, 51 verbs such as λέω and μιλάω and 7 others such as όλος and πολύς). Against the keys without the rule, on the same candidates: 6,018 keys before, 6,015 now; 59 gain examples (αυτό, οι, στο, στη(ν) …), 62 lose them all (the letter Η, the archaic τίς, adjectives whose Tatoeba forms are list words of their own: σχετικός, ξαφνικός …), 258 change; ο keeps 5,831 of its 16,935 candidate sentences, αυτός 681 of 5,339. Every cornerstone word shows its own form, as many of its examples as: 5 of 5 for 45 words, ο, ένας, αυτός, δικός, ποιος, πόσος, εκείνος, κανένας and όλος 1 (their other forms come first), του 2, δεν 3 (δε), σε, τρεις, τέσσερις, τέσσερα 4, τρία 3; δεκατρείς 2 of 3, δεκατρία, δεκατέσσερις and δεκατέσσερα 2 of 2. Greek headwords with an example 5,402 (−37); top-500 nouns with 3 or more 422 (−12, reported); the verb gate keeps 429 of 500. Example tables 9.32 MB (Greek 2.36, English 6.98, unchanged); 10,993 Greek sentences, 17,297 word rows. `--self-check` gains the list words η, γράφω, πάω, στη(ν) and the own-form choice. The `ell` asset is `ell-b308efefbce4`, 11,908,908 bytes (release `packs-20261120`, 0237); `eng-lists` rows are unchanged (re-cut with SQLite 3.54.1, 0237).
- 2026-11-17 (kyukhin, #339, after QA): a Greek list word that is no verb shows its own forms first, other forms only fill up (Pipeline step 5); verbs keep one sentence per form, with a dropped own form leading. 849 keys change their examples (17 of the cornerstone words, 832 other list words); every cornerstone word now shows its own form in all its examples but πόσος (2 of 5) and δεκατρείς (2 of 3), where Tatoeba has no more. Example tables 9.36 MB; the verb gate keeps 429 of 500.
- 2026-11-17 (kyukhin, #346): the one-word Greek lists (0130) change the keys: the one-word terms of `ky-ell` are 4,525 (2,820 with an example, 1,946 with 3 or more, 1,463 with every example in their own form); 6,016 keys against 6,015 (προϊσταμένη gains one), 3 keys reorder (παίκτρια, τραγουδίστρια, ψεύτρα), and of the 64 new list terms 19 have examples. Against the keys without the rule: 60 gain, 62 lose them all, 1,032 change. Example tables 9.36 MB.
- 2026-11-22: Drill examples drafted for #364 and #365 (Draft, waiting for kyukhin's review), measured with a prototype on the `ell` pack of master `63e7bda`:
  - the drill has 57,000 cells (595 verbs);
  - Tatoeba covers 8% of them, 5% from sentences already in the pack, and Wiktionary's usage examples bring that to 9%;
  - the 2.0 scope, the A1 and A2 verbs at tenses up to A2, has 7,334 cells and 4,666 to 5,062 sentences to generate, for +2.6 MB installed and about +0.7 MB to download;
  - at every tense, 25,416 cells and about 22,000 to generate.

  The cell rows go into `example_word` under a cell key, so the format stays 4. Sources by id range; homographs; bylines by source; the data files and checks. Six open questions (7 to 12).
- 2026-11-22: Drill examples approved by kyukhin, with his answers to open questions 7 to 12 (Decisions): tenses up to A2 for the A1 and A2 verbs in 2.0; a model-checked reading for homographs of another reading; their own 3.5 MB budget; cell keys in `example_word`, format 4; the bylines as proposed; and, against the recommendation, English and Russian only for the sentences LibreDict adds (a Wiktionary sentence gets a generated Russian one only). No date moves: build 11 and the App Store submission stay on 2026-11-26. Sizes measured again with two translations: the 2.0 scope adds 1.9 MB installed and about 0.5 MB to download (was 2.6 and 0.7 with four); every tense of the A1 and A2 verbs 6.6 and 1.9; every cell 14.8 and 4.3; found sentences only 0.59 and 0.14. The data file shrinks to about 1.3 MB.
- 2026-11-22 (#364, after QA): rule 3 also blocks after an elided θ' or ν' (glued or before a space; `Οι τιμές εξακολουθούν ν' ανεβαίνουν` was a present), ας and a prohibitive μη(ν) (`Μην ανησυχείς`). An elided θ' or ν' is never the θα or να of a compound form (kyukhin: exactly the asked form), so `Θ' ακούσετε` is no sentence for θα ακούσετε. `--self-check` gains these cases.
- 2026-11-22 (#364, review): rule 4 takes έχω or είχα as an auxiliary when an aorist infinitive follows within 3 words, with only clitics or one other word between (έχει ήδη γράψει), not only right after it; the drill's read of a cell key is `examples(lang:word:limit:)` here too.
- 2026-11-22 (kyukhin, #365, after approval): four decisions written in (Decisions): cells with no natural sentence are listed in `ell-skipped.tsv` and count as done for the 2.0 gate; Wiktionary usage examples are filtered for content (196 of 597, with the counts in "Sources and licences"); each Wiktionary row keeps its entry (`page`), the attribution basis being the word forms' (0136); `ell-readings.tsv` keeps the second pass's `reason`.
- 2026-11-22 (#365, as built): `Scripts/data/drill-examples/` holds 351 Wiktionary rows (the second pass dropped 50 of the 401 left after the content filter) and 4,329 generated rows, all `ok`; 383 reading verdicts (210 ok, 173 no; a Wiktionary sentence by its row's id, and the 7 verdicts on dropped rows left out); 603 skipped cells, all in the 2.0 scope. The 2.0 scope's 7,334 cells: Tatoeba 2,284, Wiktionary 141, generated 4,306, skipped 603, open 0. All 351 Wiktionary rows and 4,305 generated rows ship; all 57,000 cells: 8,722 with a sentence. The drill rows take 2.06 MB installed (budget 3.5 MB); the word examples keep their hash (9.36 MB). Of #364's 3,768 cell rows, 5 take another Tatoeba sentence, which an `ok` verdict on the cell's first form now allows; υπογράφω's aorist αυτός takes a generated one, its Tatoeba sentence having a `no` verdict; γελάω's and πεινάω's imperative εσύ lose theirs (skipped cells; πεινάω's sentence also has a `no` verdict). Implementation details, no change of behaviour: a data row's `check` `ok` is its own cell's reading verdict, a verdict in `ell-readings.tsv` decides on top of it; a Wiktionary or generated row comes first for the cell it was written for; a data row's translations take its sentence's id; ids keep the gaps of dropped rows; `libredict-drill-ell`'s version is the latest date in the generated rows; `drill_examples.py --todo` takes `--scope A2/A2`, `--source` and `--out`. 11 present cells that the prep counted as covered by Tatoeba (Μην του το δίνεις, θέλουν ν' ακούν) fail #364's rule 3 and were generated too. `--self-check` gains the data cases (Test plan).
- 2026-11-22 (#365, after QA): a `no` verdict keeps its sentence out of its cell for every cell, not only one whose form is a homograph of another reading (3 of the 173 `no` verdicts were ignored: πεινάω's and φυσάω's imperative εσύ, υπογράφω's aorist αυτός); a cell in `ell-skipped.tsv` stays without an example even when a sentence holds it (3 cells took one, 2 of them wrongly), and the 2.0 gate also fails on a listed cell with a row. `--self-check` and `DrillExampleDataTests.testEveryCellInScopeHasASentence` cover both. The `ell` asset is `ell-353d52a673b0` (0237).
- 2026-11-23 (kyukhin, #365, sample review): kyukhin read the first sample of 50. Every form matched its cell; φέρνονται (a passive where a Greek says an active third person plural) and αστράψατε (a figurative aorist) were unnatural, and παρουσιαστήκαμε was mistranslated ("we introduced ourselves" for "we reported to"). The cause fixed (Checks, 3): the 828 generated rows of passive cells of active verbs and of -μαι verbs were checked again with those patterns; 163 changed in place, keeping their ids (his three among them), and 19 were removed and their cells skipped. A new sample of the new data file is in `drill-examples-sample.md`, for his review.
- 2026-11-23 (kyukhin, #365, Tatoeba check): every Tatoeba sentence the drill cells used was checked like a Wiktionary row, and a cell whose sentence failed took its next one until none was new (Checks, 4). 834 sentences failed, with 877 `no` verdicts (20 of them on cells whose `ok` verdict they replace): content 277, Greek 242, form 208, English 87, Russian 20. A simple-imperative cell takes no continuous imperative unless both are one word (Match rule 5). Drill rows from Tatoeba: 3,958 before, 3,617 after. The 2.0 cells left without a sentence got 114 generated rows; 3 were skipped. As built: `ell.tsv` 4,775 rows (351 Wiktionary, 4,424 generated; 351 and 4,417 ship); `ell-readings.tsv` 1,240 verdicts (190 ok, 1,050 no; 71 stale, on sentences the filters drop); `ell-skipped.tsv` 625 cells. The 2.0 scope's 7,334 cells: Tatoeba 2,141, Wiktionary 142, generated 4,426, skipped 625, open 0. All 57,000 cells: 8,509 with a sentence (Tatoeba 3,617, Wiktionary 369, generated 4,523). The drill rows take 2.07 MB installed (budget 3.5 MB); the word examples keep their hash (9.36 MB). The `ell` asset is `ell-df66bea2d079` (0237).
- 2026-11-23 (kyukhin, #365): kyukhin's ok on the second sample (`drill-examples-sample.md` as drawn above): no wrong row. On his word, two rows change, keeping their ids, with `checked_by` "kyukhin 2026-11-23": ξεναγό for οδηγό in one row (2000000930; ξεναγός is no list word), and one Russian translation made closer (2000000022). The sample is not drawn again.
- 2026-11-23 (kyukhin, #365, table fixes): 0136's table fixes change the forms of six verbs, so 13 skips go: θυμίζω's present εσύ, αυτός, εμείς, εσείς and αυτοί, συμμετέχω's aorist αυτός and imperative εσείς (their only reason was the typo), and μαλώνω's future and simple subjunctive εσύ, αυτός and εσείς (μαλώσεις, μαλώσει, μαλώσετε are standard, not misspelt); four skips keep their cell but lose the typo from their reason (μαλώνω's and νυστάζω's imperatives, υπάρχω's aorist εμείς and εσείς); 612 skips stay. μάλωσε and συμμετείχε are now homographs of another reading, so their found sentences wait for a verdict: μαλώνω's aorist αυτός and the 11 other open cells take 12 checked generated rows, and συμμετέχω's imperfect αυτός, above the 2.0 scope, loses its Tatoeba sentence. θυμίζω's present αυτός and αυτοί take Tatoeba sentences (7818625, 5538461), which then passed the Tatoeba check (Checks, 4). θυμίζω's word examples change: its two sentences spelt θυμήζει go and five spelt right come. As built: `ell.tsv` 4,787 rows (351 Wiktionary, 4,436 generated); the 2.0 scope's 7,334 cells: Tatoeba 2,142, Wiktionary 142, generated 4,438, skipped 612, open 0; all 57,000 cells: 8,521 with a sentence. The drill rows take 2.08 MB installed. The `ell` asset is `ell-0a5563e78fd8` (0237), with kyukhin's two edits.
- 2026-11-23 (#365, after QA): the Tatoeba check was keyed by the sentence, so a sentence checked for one cell was never checked for a cell that took it later: 29 pairs, 13 of them in the 2.0 scope (Πήγαινε μίλα … in μιλάω's simple imperative). Now every (cell, sentence) pair the drill uses is checked, a Greek, content, English or Russian failure applies to every cell the sentence serves, and the loop ran until no unchecked pair came up: 119 more `no` verdicts (1,359 in all: 190 ok, 1,169 no). 12 cells above the 2.0 scope lose their Tatoeba sentence, and 6 take another one (3 from Tatoeba, 2 generated, 1 from Wiktionary). The 2.0 scope's 7,334 cells: Tatoeba 2,140, Wiktionary 142, generated 4,440, skipped 612, open 0; all 57,000 cells: 8,509 with a sentence (Tatoeba 3,602, Wiktionary 370, generated 4,537). Drill rows 2.08 MB installed. The `ell` asset is `ell-9ddc96d088d1` (0237).
- 2026-11-23 (kyukhin, #362): Match rule 5's "one word" now covers the five -άω verbs whose short form 0136 puts first (σταμάτα, ξύπνα, παράτα, προχώρα, χαμογέλα); their 13 "form" `no` verdicts in simple-imperative cells go, and the cells' new sentences get the Tatoeba check. 0132's no-imperative list takes 309 cells out of the drill's 57,000 (65 of the 2.0 scope); the implementing PR records the new counts.
- 2026-11-23 (#362, as built): the five short-form cells lose 48 "form" `no` verdicts, not 13: the after-QA loop above had added 35 more while σταματάω and προχωράω took one Σταμάτα or Προχώρα sentence after another. Leaving cells: 309 of the no-imperative list and 4 that 0136's drops empty. Cells whose spelling was a homograph of an imperative that left (ανήκετε, ανάρρωσε, άξιζε) take their found sentence without a reading verdict. 19 (cell, Tatoeba sentence) pairs were new against `ell-9ddc96d088d1`, 3 of them in the 2.0 scope (θέλω's present εσείς, σταματάω's and ξυπνάω's simple imperative). The Tatoeba check (Checks, 4) failed 4 (content 2: ανήκω's and βρομάω's present εσείς; Greek 2: θέλω's γι΄αυτό, κοστίζω's δολλάρια), and θέλω's present εσείς then took another Tatoeba sentence, which passed: 16 new pairs ship. As built: `ell.tsv` 4,787 rows (2 stale, the two generated rows above; 351 and 4,426 ship); `ell-readings.tsv` 1,315 verdicts (190 ok, 1,125 no; 176 stale); `ell-skipped.tsv` 612 cells, 549 in the 2.0 scope, 63 stale. The 2.0 scope's 7,269 cells: Tatoeba 2,143, Wiktionary 142, generated 4,435, skipped 549, open 0; all 56,687 cells: 8,518 with a sentence (Tatoeba 3,617, Wiktionary 369, generated 4,532). Drill rows 2.08 MB installed. The `ell` asset is `ell-31c23f304940` (0237).
- 2026-11-24 (#378; Draft, its Open questions 5 to 9 answered by kyukhin the same day): 0136's "Three tables" changes the cells of επιμένω, προβάλλω and τεμπελιάζω, all B1 verbs. 7 cells join (επιμένω's aorist, προβάλλω's simple imperative εσύ) and προβάλλω's passive simple imperative εσύ leaves (προβάλου, rare): 56,687 → 56,693 cells. The asked form of 47 cells changes. No data-file row, verdict or skip is on a changed cell, so nothing goes stale. επιμένω's aorist αυτός can take a Tatoeba sentence with επέμεινε (5443068 or 5457560), which gets the Tatoeba check (Checks, 4) before the PR; the other new and changed cells stay open for #371. The 2.0 scope does not change (7,269 cells, open 0). The implementing PR records the counts.
- 2026-11-24 (#378, "More tables"; Draft, waiting for kyukhin's review): the draft extension adds 15 cells (56,693 → 56,708): περιμένω's aorist and simple imperative, απέχω's aorist, συλλέγω's simple imperative εσύ. 9 of them are in the 2.0 scope (7,269 → 7,278), so the gate's "open 0" needs them filled before the PR: περιμένω's 8 are homographs of another reading (its aorist is spelt as its imperfect), so each takes a Tatoeba sentence with an `ok` reading verdict and the Tatoeba check (candidates: 1 to 28 per cell), or a generated row or a skip; συλλέγω's σύλλεξε has no candidate. περιμένω's 5 imperfect rows become homograph cells too and keep their sentences only with an `ok` reading. No line goes stale.
- 2026-11-24 (kyukhin, #378): approved with "More tables". Its answers add περιμένω's dependent, spelt as the present: its continuous future and subjunctive join the drill (B1 tenses) and share their sentences with the simple ones (homographs of aspect only, Match rule 5), so the 2.0 scope keeps its 9 new cells. For περιμένω's aorist and imperfect, the reading pass follows Claude's reviewer (2026-11-24): a bounded stretch of time (Περίμενα δύο ώρες, μέχρι τις έξι) reads as the aorist, a background or habitual frame (Ενώ περίμενα…, Κάθε μέρα περίμενα…) as the imperfect, and a bare Τον περίμενα with no context serves neither.
- 2026-11-24 (#378, as built, before the reading pass, which the next line closes): 56,738 cells (56,693 after "Three tables"); the 2.0 scope 7,278, open 9: περιμένω's aorist (6) and simple imperative (2), συλλέγω's σύλλεξε (no candidate). Drill rows 8,518 → 8,527: 14 new Tatoeba pairs (επιμένω's aorist αυτός 5443068; περιμένω's perfect εγώ 2509011; its 12 continuous future and subjunctive cells, each with the sentence its simple cell has), and περιμένω's 5 imperfect rows leave until read. Candidates by the build's match rule: Tatoeba εγώ 22, εσύ 3, αυτός 27, εμείς 8, εσείς 3, αυτοί 1, imperative εσύ 27, εσείς 12, and generated rows of other cells with the same spelling. απέχω's 12907617 (απείχαν) has no English translation, so its aorist has no candidate and stays open (B1). No data-file line is stale.
- 2026-11-24 (#378, as built): the reading pass, by the rule above, and the Tatoeba check of the new pairs. `ell-readings.tsv` gains 15 verdicts (12 `ok`: περιμένω's aorist εγώ to εσείς, both simple imperatives, its imperfect εγώ to εσείς; 3 `no`: 7796633 Όλοι περίμεναν, bare, for the aorist and the imperfect αυτοί, and 2509011 for the perfect εγώ, which fails the Tatoeba check on its Greek): 1,330 verdicts (202 ok, 1,128 no; 176 stale). `ell.tsv` gains 2 generated rows, both checked `ok`: 2000004456 for περιμένω's aorist αυτοί and 2000004457 for συλλέγω's σύλλεξε (4,789 rows: 351 Wiktionary and 4,438 generated, 4,428 of them ship; 2 stale). The other new pairs pass: επιμένω's 5443068, and the 12 continuous future and subjunctive cells with their simple cell's sentence. Open outside the 2.0 scope: περιμένω's imperfect αυτοί and perfect εγώ, απέχω's aorist (#371). The 2.0 scope's 7,278 cells: Tatoeba 2,150, Wiktionary 142, generated 4,437, skipped 549, open 0; all 56,738 cells: 8,540 with a sentence (Tatoeba 3,637, Wiktionary 369, generated 4,534). Drill rows 8,518 → 8,540 (23 added, 1 removed, 1 changed: περιμένω's imperfect εγώ takes 3017158, as 1503112 reads as the aorist). Drill rows 2.08 MB installed. The `ell` asset is `ell-0b5108ee6753` (0237).
