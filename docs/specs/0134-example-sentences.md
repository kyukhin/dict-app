# Example sentences

> Spec written by Claude (AI) for LibreDict.
> Status: Implemented (approved by Kirill on 2026-11-04) · Epic: #134 · Tickets: #177, #178 · Updated: 2026-11-08

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
  - English headwords (WordNet, En–El · FD, En–El · WN, En–Es · FD) that are words of the English lists (CEFR-J and Octanove, 0130), from the English lists pack. That pack is downloaded only when the user starts learning English (0237, Kirill 2026-11-04: nothing unneeded on the phone), so a user who only looks up English words sees no English examples.
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

#178 asked for "the first example on the new-word card". E4 has no such card: a new word is introduced by its first question, which carries the "New word" badge (Kirill, 2026-11-03, 0131 Open question 5). Examples come in a sheet instead (Kirill, 2026-11-04):

- **A new word.** The first answer to a new word's first question is graded as today (the options' colours, the haptic, the sound, the VoiceOver announcement). Then a sheet slides up over the run with:
  - the result line, as the bar has it: "Right!" or "Right answer: γράφω";
  - the word, as the question shows it (with its endings, `αγάπη η`);
  - 1–3 examples, each with the form highlighted, its translation in the via language (below) and the byline;
  - **Continue**, which closes the sheet and goes to the next question, as the bar's Continue does.
- **Every other question.** The feedback bar gets an **Example** button beside Continue when the word has examples. It opens the same sheet, whose Continue also goes to the next question. The button is on the new word's first bar too, so a sheet swiped down can be opened again; swiping it down returns to the bar.
- **A word without examples**: no sheet and no button; the bar is as today.
- Match the pairs has no feedback bar, so no button. Learning data does not change: no setting, card or log field, and a question's time (`duration_ms`) still ends at the answer.
- iPhone: the sheet opens at half height and can be pulled up; at accessibility text sizes it opens at full height and scrolls, Continue pinned at the bottom. iPad: a form sheet. Arabic: it mirrors as the Definition section does.
- **Translation in learning** (Kirill, 2026-11-04: learning is chosen as a pair, 0131). In the sheet, an example's translation is the one in the via language of the word's language, a direct Tatoeba translation only, never one through English. In a limited pair (0131: Greek via Russian, whose word meanings are English), a sentence without a translation in the via shows its translation in the meanings language instead (Kirill, 2026-11-04):

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

### Decisions

- 2026-10-22 (Kirill, #134): example sentences ship in 2.0.0. Acceptance: at least 85% of the top-500 Greek verbs show 3+ examples; each example has a translation, the highlighted form and its author; a Russian translation with the Russian UI when Tatoeba has one; offensive sentences filtered out; added size ≤ 10 MB; Tatoeba (CC BY 2.0 FR) credited.
- 2026-10-22 (Kirill, #177): Tatoeba from a pinned export; el–en, el–ru and en–ru pairs with authors; sentences linked to lemmas through word forms (#141 for Greek, morphy #143 for English); up to 5 per word; a stoplist.
- 2026-10-22 (Kirill, #178): an "Examples" section, 3 visible and the rest on tap; the form highlighted; the translation in the UI language when Tatoeba has it, else English; the author in small print; the first example in learning; Tatoeba in Credits.
- 2026-11-03 (Kirill, 0131): no introduction screen for a new word (Open question 2).
- 2026-11-03 (Kirill, 0237): the bundle holds English only; every other language's data comes in its pack. This replaces #177's "store in the read-only dictionary file".
- 2026-11-04 (Kirill): code complete 11-27, submission to Apple 12-04. If the release is behind, E7 and #160 move to 2.0.x first. Keep E7 small and say what a minimal version is.
- 2026-11-04 (Kirill, Open question 3): the three empty example tables land in format 4 with #240 (T1), whatever happens to E7.
- 2026-11-04 (Kirill): nothing is cut from 2.0 if it runs late, E7 included: the release date moves instead. E7 ships in full; the first draft's minimal version is no longer a plan.
- 2026-11-04 (Kirill, Open question 1): English examples ship in 2.0 (+1.25 days), in the `eng-lists` pack, which is downloaded only when the user starts learning English: nothing unneeded lies on the phone. Greek examples stay in the Greek pack.
- 2026-11-04 (Kirill, Open question 2): examples in learning come in a popup: after the first answer to a new word's first question, a sheet shows the word with 1–3 example sentences and their translations, closed with "Continue"; in every other question the feedback bar has an "Example" button that opens the same sheet; a word without examples shows no sheet and no button.
- 2026-11-04 (Kirill, Open question 4): direct Tatoeba translations only. Learning is chosen as a language pair (0131); a pair without a dictionary, such as Greek via Russian, is not offered in 2.0, so no note about limited Russian is needed.
- 2026-11-04 (Kirill): learning is chosen as a language pair (0131), "Greek via English", "English via Spanish". Applied here: in learning, an example's translation is in the via language, a direct Tatoeba translation or none.
- 2026-11-04 (Kirill): Greek via Russian is offered as a limited pair (0131), although there is no Greek–Russian dictionary. Applied here: in learning, its examples show the Russian translation when Tatoeba has a direct one, else the English one; examples with a Russian translation come first. Direct translations only, as before.
- 2026-11-04 (Kirill, Open question 5): the 85% gate counts all 500 verbs; a data refresh that falls below asks Kirill in its PR with the list of misses.
- 2026-11-04 (Kirill, Open question 6): the examples section sits above the inflection table on the Definition screen.
- 2026-11-08 (Kirill): no stoplist; only Tatoeba's own tags filter the sentences. Replaces #177's "a stoplist".

Design choices of this spec, for review:
- Greek examples ship in the Greek pack, English examples in the English lists pack; the bundle gains only empty tables.
- Examples are keyed by `WordKey` text, so the Definition screen and learning read the same rows, and nothing is stored in the user database.
- Up to 5 per word, chosen and ordered by the build; the app does no ranking.
- Only Tatoeba's direct translations, never a translation of a translation (Open question 4).
- A sentence is linked by its exact forms (accents kept), not by folded keys.
- The pin is a committed subset of the export, since Tatoeba keeps only the latest one (as kaikki.org, 0136).
- The section sits above the inflection table (Open question 6).
- The Definition screen translates examples into the UI language and learning into the via language: the dictionary has no pair, learning always has one.

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

- Measured on the prototype's tables (`dbstat`; `lzma` preset 6, as 0237 compresses). The Greek pack (0237: 55.1 MB installed, 10.7 MB to download, before E3's lists) grows by 2.34 and 0.68 MB; the English lists pack (0237: about 1.9 MB installed, 0.6 MB to download) by 6.90 and 2.31 MB. The App Store download does not change, and the English examples reach only users who learn English (Kirill, 2026-11-04).
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
    word        TEXT NOT NULL,     -- WordKey.word: a lemma or headword as stored (NFC; A–Z lowercased)
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
- **Format** (Kirill, 2026-11-04). The three tables land empty in format 4 with #240 (0237 T1): #240 adds `build_examples.py` with its `SCHEMA` and a `build()` that writes nothing, registers it in `STEPS`, and puts the filters above in `packs.json`. #177 then fills the rows, which changes only the `ell` and `eng-lists` versions: an update of those packs, never a format bump that would make every user download every pack again (0237, "Format rule").

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
   - Exact, not folded: folding finds one more top verb (429), but makes πότε (when) an example of ποτέ (never). Measured: 5,980 keys with an example, 2,958 of them with 3 or more; 5,511 of the 51,230 Greek headwords have examples.
   - English: the keys are the one-word terms of the English lists (`wordlist_item` of series `cefr-eng`, #153), lowercased; 8,431 words (the one-word terms of #153's lists, the build of 2026-11-08). A token of a–z letters, lowercased, keys every morphy lemma of it (the rules of 0136's `Morphy` on `morphy_exception` and `morphy_lemma`, mirrored in Python) and itself, when that is a list word: went, going, goes and gone key go. Measured: 7,496 list words have an example, 6,662 have 3 or more.
5. **Choice**, per key. Rank the sentences that contain it by:
   1. the author declares the sentence's language native (Tatoeba level 5; 26,815 of the Greek sentences);
   2. more of eng, rus, spa, arb translated;
   3. 3 to 10 words before others;
   4. lower Tatoeba id.

   English ranks the number of translations first, then the native author: nearly every English candidate has a native author, and the vias of English (Spanish, Greek) are the rarer translations.

   Then take, in that order, one sentence per new form first, then the rest, up to 5. So γράφω shows έγραψε, έγραψα, γράψω, γράψε, γράφω, and go shows go, going, went, goes, gone. The highlight is the first token of the sentence that gave the key.
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

**Report** `Scripts/reports/examples-qa.md`, rewritten by every build and committed: the export date and hashes; counts per filter; candidates and translations per language; the coverage gate with the missing verbs listed; the blocking tags hit; samples (γράφω, είμαι, σπίτι, καλός, μέρα; go, house, write, good); table sizes and a sha256 of each table's rows in key order.

**Reproducibility.** Sorted inserts, no timestamps; `build_dictionaries.py --verify` and `cut_packs.py --verify` (0237) prove the files byte-identical. `build_examples.py --self-check` runs offline on `Scripts/fixtures/tatoeba-sample/` (about 30 lines in the subset's format, with a small forms fixture): a tagged sentence and a tagged translation, an orphan, a 16-word sentence, a Greek sentence without English, γράφω in six forms (five kept, the new forms first), μέρα, πότε and ποτέ, two Russian translations by a native and a non-native author; went, going and gone keying go, an English sentence without any translation (dropped), an English word not in the lists fixture (no key). It builds twice and requires equal table hashes, as `build_forms.py --self-check` does.

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

### Identifiers

| Element | Identifier |
|---|---|
| Section, its title | `examples_section`, `examples_title` |
| Example `n` (1…5, display order): container, sentence, translation, byline | `example_<n>`, `example_sentence_<n>`, `example_translation_<n>`, `example_byline_<n>` |
| More / Fewer | `examples_more_button` |
| Learning: the sheet, its word, its Continue | `example_sheet`, `example_sheet_word`, `example_sheet_continue`; its examples use `example_<n>` and the ids above (n 1…3) |
| Learning: the feedback bar's Example button | `exercise_example_button` |
| Credits line | `credits_tatoeba` |

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

No new Swift file and no Xcode step. No network code, entitlement, Info.plist key or dependency; the display name stays "LibreDict" (`INFOPLIST_KEY_CFBundleDisplayName`).

### Tickets, order and sizes

Sizes are pipeline days: development, QA on the four simulators, review and the daily merge. Streams as of 2026-11-04: two UI, two data.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| #240 (0237 T1), the E7 part | `build_examples.py` with `SCHEMA` and an empty `build()` in `STEPS`; the three tables in format 4; the `packs.json` filters | — | +0.25 | Data |
| #177 Pipeline | `build_examples.py` (filters, keys, choice, gates, report, `--refresh`, `--self-check`) for Greek (2) and English (1); both subsets and the pins; rebuilt `ell` and `eng-lists` assets; `--verify` | Approval; #240; E3 #153 (the English key set) and #152, or a rebase after them (one rebuilt file per data PR, 0129) | L, 3 | Data, whichever is free |
| #178 Definition and learning | Model, read, Definition section, More, byline, VoiceOver, Arabic, Credits, the strings in five languages, `ExampleSentencesTests` on the matrix with a Greek and an English word (1.75); the learning sheet, the bar's Example button and their tests (1.0); the via translation (0.25) | #177 for the data (unit tests start on made-up rows); E3 #151 (`wordKey(for:)`; if absent, add exactly it, as 0131 allows #157); 0237 T2 #241 (`-installPacks`). The learning part: E4 #157 (`LearningPairs.via`), #159 and #161 | L, 3 | UI |

- 6 stream-days, plus 0.25 inside #240. Against the first draft's 4.25: English +1.25 (Kirill, 2026-11-04) and the sheet in place of a line in the feedback bar +0.5.
- #177 starts when #240 and E3's #153 have merged and blocks nothing else; #178 follows it, its learning part after E4's #161.
- Nothing is cut if the release runs late; the date moves instead (Kirill, 2026-11-04). The first draft's minimal version is no longer a plan.

## Test plan

Unit classes go in `DictAppTests.swift`; async tests are `@MainActor` (#229). Data tests read the committed Greek and English lists packs through 0237's `PackFixtures`; read tests use `TestDictionary.make(rows:metadata:examples:)` attached as the `ell` or `eng_lists` pack through 0237's `DictionaryFiles` seam. UI suites run on the four-simulator matrix, one suite per `xcodebuild` run with the app uninstalled before it, with `-skipWelcome -installPacks ell,eng-lists -packFixtures <path>` (0237) unless a test says otherwise.

| Acceptance criterion | Test |
|---|---|
| #134, #177: at least 85% of the top-500 Greek verbs show 3+ examples (all 500 counted, Kirill 2026-11-04) | Build gate (fails below 85% of the 500; measured 85.8%), figures and misses in `examples-qa.md`. Unit `ExampleDataTests.testFrequentVerbsHaveThreeExamples` (γράφω, είμαι, έχω, κάνω, θέλω, ξέρω, λέω, πάω: 3+ each in the Greek pack) |
| #134, #177, #178: each example has a translation, the highlighted form and its author | Build gates. Unit `ExampleDataTests.testEveryExampleIsComplete` (in both packs: every Greek sentence has an English translation, every English one a translation into rus, spa, arb or ell, every text an author, every span inside its text), `ExampleTextTests.testHighlightCoversTheForm` (bold and tinted exactly on the span; a span past the end gives the plain text), `testBylineNamesBothAuthors` (one name when they are equal or no translation shows). UI `ExampleSentencesTests.testGreekWordShowsExamples` (γράφω: `examples_section`, 3 examples, each with a sentence, a translation and a byline ending "Tatoeba"; More shows 5 and reads "Fewer examples") |
| #178: More is hidden with 3 or fewer examples | UI `ExampleSentencesTests.testThreeExamplesShowNoMoreButton` (λύπη has exactly 3: no More button) |
| #134, #178: a Russian translation with the Russian UI when Tatoeba has one | Unit `ExampleTextTests.testTranslationFollowsTheUILanguage` (ru present → ru; absent → eng; es; ar → arb; Greek UI and a Greek sentence → eng; an English sentence with the English UI → none, with the Greek UI → ell or none). UI `ExampleSentencesTests.testRussianUIShowsRussianTranslation` (`-AppleLanguages (ru)`: γράφω's first translation is Cyrillic; with the English UI it is Latin) |
| #134, #177: offensive sentences filtered by Tatoeba's tags | Build gate (re-scan of the output: no stored sentence or translation has a blocking tag). `--self-check` (the tagged sentence and the tagged translation are absent) |
| #134, #177: added size ≤ 10 MB | Build gate (measured 9.31 MB); table sizes in `examples-qa.md`. QA: both assets' and files' sizes, and App Size in TestFlight (unchanged), recorded in History |
| Kirill 2026-11-04: English examples ship, in the English lists pack only | Unit `ExampleDataTests.testEnglishListWordsHaveExamples` (go, house, write, good: 3+ each in `eng-lists`; went, going, gone highlighted for go), `testExamplesGoWithTheirLanguage` (Greek rows only in `ell`, English rows only in `eng-lists`, none in the bundle, the stub or the other packs). UI `ExampleSentencesTests.testEnglishWordShowsExamples` (house from WordNet with `-installPacks eng-lists`: the section; `-AppleLanguages (es)`: a Spanish translation), `testEnglishWordWithoutTheListsPackShowsNone` (`-installPacks ell` only: house shows no section) |
| Kirill 2026-11-04: the tables land in format 4 with #240 | Unit `ExampleDataTests.testEveryFileHasTheExampleTables` (bundle, stub and every committed asset: the three tables, empty in the bundle and the stub), with 0237's `PackFileTests.testEveryFileHasTheFormat` (format 4). Review: #177 changes no table shape and no `user_version` |
| #177: reproducible from the pinned snapshot | `inputs.committed()` checks every subset file; `build_examples.py --self-check` builds twice with equal hashes; `build_dictionaries.py --verify` and `cut_packs.py --verify` give the committed files |
| #134, #178: Tatoeba (CC BY 2.0 FR) credited | Unit `ExampleDataTests.testTatoebaDataSourceRow` (in the Greek and the English lists packs, CC BY 2.0 FR; no `dict_metadata` row). UI `ExampleSentencesTests.testCreditsListTatoeba` (`credits_tatoeba` through `settings_credits_link`) |
| Kirill 2026-11-04 (pairs): in learning, an example's translation is in the via, direct only | Unit `ExampleTextTests.testLearningTranslationFollowsTheVia` (a Greek sentence via English: English; an English sentence via Spanish: Spanish, and none when Tatoeba has no Spanish one, never the Greek or Russian one; via Greek: Greek; via English: none; a Greek sentence in Greek via Russian, the limited pair: Russian when it has a direct one, else English), `testLearningPrefersExamplesWithTheVia` (5 examples, 2 with Spanish: those 2 first, then 1 more in build order), `ExerciseRunViewModelTests.testExampleUsesTheLanguagesVia` (English via Spanish: the Spanish translation; Greek via Russian: Russian where Tatoeba has it, English otherwise, the Russian ones first) |
| #178: the new-word card shows an example when one exists (Kirill 2026-11-04: a sheet after the first answer, an Example button on every other bar, nothing for a word without examples) | Unit `ExerciseRunViewModelTests.testNewWordOpensTheExampleSheet` (the first answer to an `isNew` question of a word with examples sets `showsExampleSheet` with 1–3 examples; a later question of the same word does not), `testExampleButtonOnEveryBar` (a review, a trainer and a mistakes question of a word with examples offer it, and it opens the same examples; a word without examples: no sheet, no button), `testSheetContinueMovesOn` (Continue on the sheet goes to the next question, as the bar's does; a swipe down returns to the bar, whose Continue then moves on), `testExamplesReadOncePerWord` (two questions of one word, one read). UI `SessionFlowTests.testNewWordShowsTheExampleSheet` (`-learningFixture myWords5 -learningAnswerHints`: the first question has `exercise_new_badge`; after the answer `example_sheet` shows `example_sheet_word` and 1–3 `example_<n>` with English translations; `example_sheet_continue` shows the next question; all five fixture words have 5 examples, measured), `ExerciseFlowTests.testExampleButtonOpensTheSheet` (`-learningFixture due`: the bar's `exercise_example_button` opens `example_sheet`) |
| #178: localized UI; Arabic right to left | The catalog test. UI `ArabicLocalizationTests.testExamplesRightToLeft` (Arabic title; the byline starts with U+200F; the section's leading edge is on the right), `GreekLocalizationTests.testExamplesInGreek` (Greek title; the translation is English) |
| #178: iPhone and iPad, iOS 17.5 and 26.4 | `ExampleSentencesTests`, `SessionFlowTests` and the extended suites on the matrix; `ExampleSentencesTests.testExamplesFitAtTheLargestTextSize` (every line inside the window, More reachable), `SessionFlowTests.testExampleSheetAtTheLargestTextSize` (the sheet at full height on iPhone, `example_sheet_continue` hittable); `ArabicLocalizationTests.testExampleSheetRightToLeft` |
| Words without examples, packs not installed, other languages | Unit `ExampleReadTests.testWordWithoutExamplesReadsNone`, `testMissingPackReadsNone` (the stub attached), `testOtherLanguagesReadNothing` (`spa`, `und`: no SQL), `testExamplesComeInOrder` (`ord`, the limit, translations joined), `DefinitionViewModelExampleTests.testEntryUsesItsWordKey` (γράφω from El–En · FD and El–En · WN load the same rows). UI `ExampleSentencesTests.testWordWithoutExamplesShowsNoSection` (Αμβέρσα, which has none in the prototype) |
| 0129, 0237: reads go through the retry, no network | Unit `DictionaryReopenTests.testExampleReadRecoversAfterTheFileIsInvalidated`; 0237's `NetworkAuditTests` stays green |

QA records in History: the gate figures, the Greek and English lists assets' and files' sizes, `examples(for:)` time on the iPhone 15 Pro simulator (iOS 17.5, median of 3; expected under 5 ms) and the matrix results.

## Open questions

1. **English examples in 2.0.** Resolved 2026-11-04: yes, in the `eng-lists` pack, downloaded only when the user starts learning English (Decisions).
2. **Examples in learning.** Resolved 2026-11-04: an example popup (Decisions).
3. **Land the tables before 2.0, whatever happens to E7.** Resolved 2026-11-04: yes, with #240 (Decisions).
4. **Translations through English.** Resolved 2026-11-04: direct translations only (Decisions).
5. **The gate's margin.** Resolved 2026-11-04: all 500 verbs (Decisions).
6. **Where the section sits.** Resolved 2026-11-04: above the inflection table (Decisions).

## History

- 2026-11-04: First draft. Measured with a prototype of the pipeline on the Tatoeba export of 2026-10-31 (the 19 files above) and the dictionary file of master `e9997dd`: Greek candidates and drops per filter, keys with exact and folded matching, the top-500 verb gate under 12, 15, 20 and no word caps (423, 428, 429, 432), table and xz sizes for 3 and 5 examples, translation coverage per language, direct against indirect Russian, translation authors, the Wiktionary stoplist seed, the subset's size, and the English variants (CEFR-J and all lemmas, with all or Russian-only translations, and their pin).
- 2026-11-04: Learning is chosen as a language pair (Kirill, 0131): in learning, an example's translation is in the via language, a direct Tatoeba translation or none (`ExampleText.learningTranslation(for:via:)`, `forLearning(_:via:)`, examples with a via translation first); the Definition screen keeps the UI-language rule. #178 +0.25.
- 2026-11-04: Kirill's answers applied to the body: English examples for the 8,609 English list words in the English lists pack (measured 6.90 MB installed, 2.31 MB to download, an English subset of 24.8 MB, 22 export files pinned); examples in learning come in a sheet after the first answer to a new word, and through an Example button on every other feedback bar; the empty tables land in format 4 with #240; nothing is cut, and the minimal version goes. #177 L 3, #178 L 3, #240 +0.25.
- 2026-11-04: Approved by Kirill.
- 2026-11-04: Greek via Russian is offered as a limited pair (Kirill, 0131): in learning its examples show the direct Russian translation, else the English one (`learningTranslation(for:via:meanings:)`), Russian ones first. No size change.
- 2026-11-07: #177 as built: 428 of the top 500 Greek verbs have 3 or more examples (85.6%); 10,814 Greek and 28,997 English sentences; tables 9.29 MB (Greek 2.34, English 6.97). The `ell` pack grows by 0.68 MB to download, `eng-lists` by 2.33 MB. English keys are the 8,431 one-word terms of #153's lists, the Greek seed 185 lemmas.
- 2026-11-07: #177, Morphy over-generation (CodeRabbit, PR #249): a token keys no inferred lemma when two of its lemmas are list words (lives: live, life), and no suffix-guessed lemma when the token is itself a list word (evening ↛ even, hopes ↛ hop); WordNet's irregular forms stay (was → be). 6,651 English words keep 3 or more examples (−17).
- 2026-11-07: #177 filters as built: a Greek sentence drops when any linked English translation is stoplisted; stoplists also check the pieces of a word split at an apostrophe; tokens include combining marks (harakat, stress marks), so a prefix entry cannot be split off; a tag blocks when it starts with "@" (except audio and adoption tags) or is on the content-tag list. `inputs.json` pins the export's 22 files as one folder entry plus 8 file entries; the subset is 25.8 MB in LFS; `--refresh --export-dir --export-date` and `--standalone` are added. The stoplist awaits Kirill's review.
- 2026-11-08: #178 as built: each example is one VoiceOver element, so UI tests read `example_<n>`'s label (the sentence, translation and byline have no reachable ids); the byline keys are `examples.byline %@` and `examples.a11y.byline %@`; usernames sit in bidi isolates in every language, not only Arabic; the sheet opens once per word per run. QA: 18 deliberate breaks each failed their target test; `ExampleReadTests.testDecomposedWordFindsItsExamples` (an NFD word) added; `examples(for:)` takes 0.11–0.18 ms in Release on iPhone 17, iOS 26.4 (target under 5 ms). Unit 949 pass; `ExampleSentencesTests` 8/8 on iPhone and iPad. E7 is implemented.
- 2026-11-08: No stoplist (Kirill): `examples-stoplist.tsv`, its Wiktionary seed, its part of the output gate and `ExampleDataTests.testNoStoplistedWordInThePack` are gone; Tatoeba's tags are the only filter. As built: 429 of the top 500 Greek verbs have 3 or more examples (85.8%); 10,853 Greek and 29,040 English sentences; 6,662 English list words have 3 or more; tables 9.31 MB (Greek 2.34, English 6.98). The `ell` asset is 11,902,208 bytes (+31,528), `eng-lists` 2,826,948 (+5,336), both still under release `packs-20261107`.
- 2026-11-08: The measured figures follow the build's report (`examples-qa.md`, CodeRabbit, PR #278): 6,662 of the 8,431 English list words have 3 or more examples and 7,496 one; the example tables take 9.31 MB (English 6.98); 85.8% of the top-500 Greek verbs have 3 or more. The prototype's placement table keeps its own figures.
- 2026-11-09: #182 regression: `SessionFlowTests.testExampleSheetAtTheLargestTextSize` checks the full-height sheet on iPhone only; on iPad the sheet is a form sheet, as this spec says.
