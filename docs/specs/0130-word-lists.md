# Word lists by level and list import

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-11-04 · Epic: #130 · Tickets: #151, #152, #153, #154, #155 · Updated: 2026-11-06

Read [0000-overview.md](0000-overview.md), [0129-dictionary-file.md](0129-dictionary-file.md) and [0136-word-forms.md](0136-word-forms.md) first, and 0237 (#237, downloads), written in parallel. E3 adds static list data, which ships in each language's pack (0237's install of the language's lists), one migration to the user database, a Lists screen in the Learn tab and list import. E4 (#131, learning, spec 0131) and E10 (#166, statistics, spec 0166) are drafted in parallel and build on the interface in "For E4 and E10". Numbers marked "measured" come from a prototype run on 2026-11-03 against master `7df5f05` (`dictionaries.sqlite` format 3), Kirill's three CSVs of 2026-10-22, CEFR-J and Octanove at the pinned commit, and FrequencyWords 2018.

## Why

Learning (E4) needs words to learn. A learner checks the levels they want and gets their words in a useful order: frequent words first, not alphabetical. Kirill's own Greek A1–B1 lists and the free English CEFR lists cover the two languages the app teaches in 2.0. Learners who already have lists in a spreadsheet, Anki or Quizlet bring them in. "My words" (the former bookmarks, #139) becomes one list among the others.

## Behaviour

### Lists screen (#154)

The Learn tab (#158, E4) links to "Lists". The screen shows only the lists of learned languages (0131, Kirill 2026-11-03), built-in and imported. A language's built-in lists appear once 0237 has installed them. With Greek and English learned, the sections are:

| Section | Rows |
|---|---|
| Greek | Greek A1 · 1,457 words, Greek A2 · 756, Greek B1 · 2,435 |
| English | English A1 · 1,063, A2 · 1,241, B1 · 2,139, B2 · 2,417, C1 · 913, C2 · 875 (measured; the build reports the final counts) |
| My lists | My words (always first), then imported lists of learned languages, newest first |

- A level list holds only its own level's words (Kirill, 2026-11-03). Greek A1 + A2 + B1 is 4,648 words. To learn from scratch to B1, check A1, A2 and B1 in New words from (below).
- The section in the UI language goes last (an English UI shows Greek first; a Greek UI shows English first). Otherwise Greek, then English.
- Each row shows the title, the word count and, once E10 provides it, a progress bar (new / learning / learned). Each checked list (New words from) carries a "Learning" badge.
- Swipe to delete an imported list, after an alert: “Delete “Greek verbs”? Progress on its words is kept.” Built-in lists and My words cannot be deleted.
- A "+" button opens Import (below).

### List screen (#154)

- Title and count at the top, then a "Learn this list" button. Tapping it checks this list in New words from: its words join the new words of the daily session (E4). The button then reads "Learning this list", with a checkmark. A second tap unchecks the list.
- Words are alphabetical (Kirill, 2026-10-22). A list with several levels (an import) has one section per level, A1 first. Sorting ignores accents, case and parenthesised parts, so "(ένα) σωρό" sorts under σ.
- A row shows the term as the list writes it, its endings in the secondary colour (`αγαπημένος -η, -ο`, `αγάπη η`), and below it the word's meaning in the meanings language of the list's language's pair, which is its via except in the limited Greek via Russian (0131, "Languages and pairs" and "Meanings"; Kirill, 2026-11-04):
  - the list's translation when it is in that language: Kirill's English translations for Greek via English and for the limited Greek via Russian, whose meanings are English (Kirill, 2026-11-04);
  - an imported list's own translations, in every pair;
  - otherwise the first sense of the word in the pair's dictionary: English A1's "house" reads "casalicio, casa" for English via Spanish, "σπίτι (το χτίριο), οίκος, στεγάζω" via Greek, and WordNet's first sense via English;
  - the part of speech (`noun, verb`) when there is none.
- My words rows show a one-line snippet of their entry, newest first, with swipe to delete, as the Bookmarks tab does today.
- A word linked to a dictionary has a disclosure chevron; tapping it opens its Definition. A word without a dictionary entry shows only its translation and does not open anything.
- The Definition opened from a list is the word's entry in the first of the pair's dictionaries in Dictionary Order, enabled ones first, else in the first dictionary of its language. English list words therefore open En–Es · FD for English via Spanish and WordNet for English via English, whatever the UI language.

### New words from (#154)

New words come from every list the user checks here (Kirill, 2026-11-03).

- Opens from the Learn home ("Choose lists" while nothing is checked, then a "New words from" row) and from Settings → Learning (E4, #162).
- At the top: "Lower levels come first: A1, then A2 and up. Lists without levels come last."
- Rows: every list of a learned language but My words, in the Lists screen's sections and order: Greek A1, A2, B1; English A1 … C2; imported lists, newest first. A language whose learning stopped (0131) hides its lists here too; their checkmarks are kept for when it resumes. A row shows the title, the word count and a checkmark when checked. A tap checks or unchecks it; the change applies to the next new word picked.
- My words is not on it: a word added to My words (Learn) is learned at once (E4).
- Lists of several languages can be checked, but learning never mixes languages (Kirill, 2026-11-03): new words come from the checked lists of the language chosen on the Learn home (E4).
- Nothing checked: the footer reads "No list checked. New words come only from words you add with Learn." There is no default (Decisions).
- From scratch to B1: check Greek A1, A2 and B1. Upper English only: check English C1 and C2.

### Import (#155)

- "+" → "Import a file" (CSV, TSV or TXT through the system file picker) or "Paste text" (a text box with a Paste button, for Quizlet's export). The Learn home of a language without lists opens the same screen ("Import a list", 0131).
- A "Formats" link on the import screen opens a short help screen (Kirill, 2026-11-03) with three examples: a CSV with the header `term,translation,level`, an Anki plain-text export, and text pasted from Quizlet. The examples stay as they are; the text around them is in the five UI languages.
- Formats, read without edits:
  - Kirill's files: `level,greek,endings,english`;
  - any CSV or TSV whose header names the columns (term, translation, level, endings, tags, part of speech, or a language name for the term and translation columns), or with no header: column 1 is the term, column 2 the translation;
  - Anki "Notes in Plain Text" exports, with their `#separator`, `#html`, `#columns`, `#tags column`, `#guid column`, `#notetype column` and `#deck column` headers; HTML is stripped;
  - Quizlet's export pasted as text: tab between term and definition, one card per line.
- A preview shows before anything is saved:
  - the list name (the file name, or "Pasted list"), editable;
  - the language, guessed from the terms' script (Greek, Cyrillic, Arabic; Latin guesses English), changeable: Greek, English, Spanish, Russian, Arabic or Other;
  - the delimiter, detected as tab, then semicolon, then comma, changeable;
  - the columns found ("Term · Translation · Level · Endings");
  - "1,457 words · 39 merged · 2 rows with errors", the first 50 words, and every broken row with its line number, its text and the reason.
- Broken rows (no term, a quote never closed, a field over 1,000 characters) are skipped; the rest import. Rows with the same term are merged into one word, and so is a capitalised term whose lowercase twin is in the list (Decisions), compared with Swift's Unicode `lowercased()` before anything is stored. Merged rows combine as built-in rows do (Dictionary file): the lowest level, translations joined with "; " and endings with " / " in file order, the first row's `seq`, `pos` and `rank`, tags joined without repeats; `testImportMergesDuplicateFields` checks it. A word without a translation is fine.
- "Import" saves the list and links its words to the dictionaries with the same rules as the built-in lists. The result reads "Imported %d words, %d found in the dictionaries" (Kirill's A1 file: 1,457 words). The new list appears under My lists.
- A list in a language not learned yet asks "Learn Spanish via English?" on Import, with the language's default pair, as Learn on a word does (0131): Yes adds the pair; No saves the list, hidden until the language is learned.
- An imported list's translations are shown as they are in every pair of its language: the app does not know their language, and the user chose them.
- Other (`und`) can be learned like any language. Its alert reads "Learn lists in other languages?"; Yes adds `und` to `learning_languages`, and the Learn home's switch names it "Other" (0131). Settings → Learning → Languages stops it like any other. All Other lists share `und`, so they are one language for learning.
- Limits: 20,000 rows and 10 MB per import. UTF-8 (with or without BOM) and UTF-16 with BOM; anything else shows "Save the file as UTF-8 and try again".

### Linking a word to the dictionaries (#151)

A list word links to a headword of a dictionary in the list's language (bundled and installed ones by `dict_metadata.from_lang`, imported ones by `imported_sources.from_lang`). The first rule that finds exactly one headword wins:

1. **Exact**: the term is a headword (SQLite `NOCASE`, which folds only A–Z).
2. **Cleaned**: the term without trailing `! ? ; .`, quotes and guillemets; then without its parenthesised part; then with the parentheses removed (`(Σαουδική) Αραβία` → `Αραβία`, `Σαουδική Αραβία`).
3. **Near** (Greek): equal but for case and diaeresis, accents kept, as in #144 (`Ευχαριστώ!` → ευχαριστώ, `Μάϊος` → Μάιος). Several near headwords: the one equal to the lowercased term, else none.
4. **Form**, one word only. Greek: the lemmas whose table holds the term's exact spelling (`paradigm.form`), when exactly one of them is a headword (`λίγοι` → λίγος, `σπουδές` → σπουδή). English: the bases of `morphy_exception` in Morphy's order (verb, noun, adj, adv) that are headwords, the first one.

An accent-folded match alone never links: νομός (prefecture) is not νόμος (law), μονός is not μόνος (#144, Kirill 2026-11-02). Words that link nowhere stay as standalone words with the list's own translation (#151).

Measured on Kirill's lists: 4,090 of 4,648 words link (88.0%): A1 94.1%, A2 78.7%, B1 87.2%. Exact 3,947, cleaned 10, near 24, form 106, overridden 3. Unlinked (558): 155 multi-word expressions, 70 capitalised words (mostly names), 333 other words that the dictionaries lack (αντιηλιακό, γιουβέτσι), 2 of them forms of two lemmas each (αυτοί, εξετάσεις). Near also links three names to common nouns (Αγγελική → αγγελική "angelic", Αλεξία, Αθανασία); the build's override file corrects such links (Design). English: 98.6% link to a dictionary with English headwords, 96.7% to WordNet alone.

### Order of new words (for E4)

New words come from the checked lists of one language, the one chosen on the Learn home (E4), by level across them: A1 first, then A2 … C2 (Kirill, 2026-11-03). Each language has its own order. Words of imported lists without a level come after all levelled words. A word in two checked lists is one word (`WordKey`), at its lowest level.

Within each level (Kirill, 2026-10-22):
- **By frequency** (the default): words ordered by frequency rank, then unranked words in their lists' order. Then a light shuffle: each run of 10 consecutive places is shuffled. Then one pass over the places separates alphabetical neighbours: a word followed by the next word of its level in alphabetical order (`sort_key`, then `term`) swaps places with it; when the pair straddles two runs of 10, the first two words of the later run swap instead. A swap never creates such a pair behind the pass, so one pass is enough. The 10 most frequent words stay in the first 10, the 20 most frequent in the first 20, and no word is followed by its alphabetical neighbour, except into a last run of one word.
- **Random**: the level shuffled.
- The shuffle is fixed per install and set of checked lists, so the order is the same every session while the checked lists stay the same, and only words already learned drop out. The neighbour pass then runs again on what remains, so a word that drops out never leaves two neighbours side by side.
- The setting "by frequency / random" and its UI are E4's.

Greek A1, the first 20 by frequency before the shuffle (measured): αυτός, σε, και, πού, που, θα, έχω, με, για, κάνω, λέω, τι, πώς, από, μπορώ, άλλος, ξέρω, θέλω, όχι, εδώ. είμαι was in Kirill's A2 file; moved to A1 (Decisions), it should head this list, since its forms include είναι, and εδώ drops out.

Frequency rank: the word's count in FrequencyWords 2018 (OpenSubtitles, top 50,000), summed over its inflected forms: Greek through the word forms of #141, English through WordNet's exception lists (`went` counts for go). Ranked: Greek 3,697 of 4,657 terms, counted before the capital merge (A1 91.9%), English about 88.7%.

### Credits

Credits gains four lines in all five languages: "Greek word lists by Kirill Yukhin"; "The CEFR-J Wordlist Version 1.5. Compiled by Yukio Tono, Tokyo University of Foreign Studies. Retrieved from https://github.com/openlanguageprofiles/olp-en-cefrj on <the #153 date>"; "Octanove Vocabulary Profile C1/C2 1.0, Octanove Labs (CC BY-SA 4.0)"; "Word frequencies: FrequencyWords by Hermit Dave, from OpenSubtitles 2018 (CC BY-SA 4.0)". The citations stay in English; only the lead-in is translated.

### Decisions

- 2026-10-22 (Kirill): the Greek lists are Kirill's own (`KLIK - A1.csv`, `A2`, `B1`; columns `level, greek, endings, english`). Levels are disjoint increments; full B1 = A1 + A2 + B1 = 4,652 words, 84–92% of them Greek headwords. His word selection ships preinstalled.
- 2026-10-22 (Kirill): English lists are CEFR-J A1–B2 (free for commercial use with a citation) and Octanove C1/C2 (CC BY-SA 4.0).
- 2026-10-22 (Kirill): levels are real CEFR levels, not frequency bands.
- 2026-10-22 (Kirill): lists are alphabetical. New words come within a level by frequency with a light shuffle, behind a setting "by frequency / random". The setting belongs to E4.
- 2026-10-22 (Kirill): bookmarks are removed in 2.0. Tabs become Search · Learn · History · Settings. The Definition star becomes "Learn": it adds the word to My words and enrols it at once (E4). 1.x bookmarks are already in My words (#139, merged).
- 2026-10-22 (Kirill): list export (Anki TSV, #156) is in 2.1.0.
- 2026-10-22 (Kirill, #151): built-in lists live in the read-only dictionary file, user lists in the user database. Words link to their dictionary entry, also through word forms; unmatched words keep the list's translation.
- 2026-10-22 (Kirill, 0129): user data points at static data only by text keys, never by row ids.
- 2026-11-03 (Kirill, Open question 1): a capitalised word merges into its lowercase twin in the same list: Δύση into δύση, Ειρήνη into ειρήνη (5 pairs in Kirill's lists). Imports merge the same way.
- 2026-11-03 (Kirill, Open question 2): είμαι moves from A2 to A1 in the committed copy of his lists (its two rows), so the criterion "the first 20 A1 words hold είμαι, έχω, θέλω" stands. Greek A1 has 1,458 words, A2 758, B1 2,436.
- 2026-11-03 (Kirill, Open question 3): no default list. Until the user taps "Learn this list", the Learn home offers "Choose a list": other languages may have no list at all.
- 2026-11-03 (Kirill, Open question 4): his lists are committed under CC BY-SA 4.0 as `ky-ell-a1.csv`, `-a2.csv`, `-b1.csv`, titled "Greek A1/A2/B1", credited "Greek word lists by Kirill Yukhin", and never named "KLIK". Latin lookalike letters (11 terms, 16 endings) are fixed in the committed copy, and the build fails on any new one; the #152 PR lists the fixes.
- 2026-11-03 (Kirill, Open question 5): CEFR-J 1.5, pinned at the Open Language Profiles commit.
- 2026-11-03 (Kirill, Open question 7): "random" shuffles within each level, so A1 still comes before A2.
- 2026-11-03 (Kirill, Open question 8): English list words link through every English dictionary and open the first English dictionary in Dictionary Order.
- 2026-11-03 (Kirill, Open question 6): level lists are disjoint: each holds only its own level's words. New words come from the lists the user checks on a new screen, New words from (every built-in and imported list, not My words): by level across them, A1 first, within a level by frequency with the light shuffle, imported words without a level last, a word in two lists once. The preference `learning_lists` holds the set; empty means no default (Open question 3), and the Learn home offers "Choose lists". "Learn this list" checks its list.
- 2026-11-03 (Kirill): learning is per language: languages never mix. Lists of several languages may be checked; new words are ordered per language and come from the checked lists of the language chosen on the Learn home (E4, 0131).
- 2026-11-03 (Kirill): learning a language is explicit (`learning_languages`, 0131). The Lists screen and New words from show only the lists of learned languages, built-in and imported.
- 2026-11-03 (Kirill, #237): dictionaries and word lists are no longer bundled, except English WordNet. A language's built-in lists come with 0237's install of the language's lists: the Greek lists in the Greek pack, the English lists in an English lists pack. The table shapes stay. This replaces the 2026-10-22 placement in the read-only dictionary file.
- 2026-11-03 (Kirill): the import screen gets a "Formats" help with three examples: a CSV with `term,translation,level`, an Anki plain-text export, a Quizlet paste.
- 2026-11-03 (Kirill): the release date moves for #237. The dates in this spec are to be replanned with it; the order of the tickets stays.
- 2026-11-04 (Kirill): learning is chosen as a language pair (0131), "Greek via English", "English via Spanish". Lists stay per learned language; a list word's meaning is in the via: Kirill's English translations for Greek via English, otherwise the pair's dictionary. Greek–Russian data may come in 2.1.
- 2026-11-04 (Kirill): nothing is cut from 2.0 if it runs late: the release date moves instead (0131).
- 2026-11-04 (Kirill): Greek via Russian is offered as a limited pair (0131): word meanings and list translations stay in English (Kirill's lists are English), while grammar and notes are in Russian. Applied here: a list row shows its meaning in the pair's meanings language, so Greek lists read the same via English and via Russian.
- 2026-11-04 (Kirill, with 0133's topic 12): the committed copy writes είκοσι ένα, and επτά, οκτώ, εννέα carry the spoken εφτά, οχτώ, εννιά in `endings`.
- 2026-11-06 (Kirill): A2's εννέα/εννιά and B1's εφτά merge into A1's εννέα and επτά, so each number is learned once; the teens stay as he wrote them. Greek A1 1,457, A2 756, B1 2,435.

Design choices of this spec, for review:
- My words stays in 0129's `my_words` table, exposed as a list (answers 0129's Q3). No data moves, and #139's 1.x move and the #213 tests stay as they are.
- "Learn this list" is the list's checkmark: a second tap unchecks it, like a tap on New words from.
- An imported level named A1 … C2 orders with the built-in levels; other level names come after C2, in the list's order, before words without a level.
- A list word's identity is its language and its term (`WordKey`), not a dictionary entry, so one word learned from two lists, or from two dictionaries, is one word (For E4).
- A built-in list records the language of its translations (`wordlist.translation_lang`), so a pair with other meanings (a full Greek via Russian once a Greek–Russian dictionary exists) never shows Kirill's English as its meaning, while the limited Greek via Russian of 2.0, whose meanings language is English, does. Imported lists record none: their translations show in every pair.

### Out of scope

List export (#156, 2.1.0). Anki `.apkg` files. Editing words or renaming a list after import. Re-linking an imported list when a later dictionary update adds headwords. Frequency ranks for Spanish, Russian and Arabic lists (their words keep the list's order). Searching inside a list. Lists in Search results.

## Design

### Data placement

| Data | Where | Why |
|---|---|---|
| Built-in lists, their words, frequency ranks | The language's pack (0237): Greek in the Greek pack, English in an English lists pack. Tables `wordlist`, `wordlist_item`, `word_rank`, shapes as below | Static, installed with the language (Decisions); 0237 says how a pack is opened |
| Imported lists and their words | `user.sqlite`, tables `user_list`, `user_list_item` (migration `130-1-word-lists`) | User data |
| My words | `user.sqlite`, `my_words` (0129, unchanged) | Already holds the 1.x bookmarks |
| The lists new words come from | Preference `learning_lists` (`SettingsService`), a JSON array of list ids like `enabled_sources` | A preference, synced with the others in #73 |
| The shuffle seed | `user_meta` key `wordlists.seed`, a random `UInt64` written on first use | Install-level user data, kept by `-resetData` |

`wordlist_item` and `user_list_item` have the same columns, apart from the first, so one Swift record decodes both and one query template reads either.

### List data: `Scripts/build_wordlists.py` (#152, #153)

A static step (0129, "Adding static data"), registered in `STEPS` after `build_forms` and `build_morphy`, whose tables it reads. Its DDL is `Scripts/wordlists_schema.sql`, which the step applies and the unit tests read through `#filePath` to build test dictionaries, so the DDL exists once. The step builds the tables below; 0237 decides how they are packed and installed (Greek rows in the Greek pack, English rows in the English lists pack). Nothing here assumes the bundled file.

```sql
-- One row per built-in list. Ids are permanent, like source IDs.
CREATE TABLE wordlist (
    id          TEXT PRIMARY KEY,        -- 'ky-ell-a1', …, 'cefr-eng-c2'
    lang        TEXT NOT NULL,           -- ISO 639-3
    series      TEXT NOT NULL,           -- 'ky-ell', 'cefr-eng'
    level       TEXT NOT NULL,           -- 'A1' … 'C2'
    level_ord   INTEGER NOT NULL,        -- 1 … 6; the list holds the words of this level only
    word_count  INTEGER NOT NULL,        -- checked by the build
    data_source TEXT NOT NULL,           -- data_source.id, for Credits
    translation_lang TEXT NOT NULL DEFAULT '' -- ISO 639-3 of wordlist_item.translation: 'eng' for ky-ell; '' = no translations (cefr-eng)
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
    sort_key    TEXT NOT NULL,                 -- alphabetical key (below)
    PRIMARY KEY (series, term)
) WITHOUT ROWID;
-- Frequency ranks for imports: key = folded word (Greek) or lowercase (English).
CREATE TABLE word_rank (
    lang TEXT NOT NULL, key TEXT NOT NULL, rank INTEGER NOT NULL,
    PRIMARY KEY (lang, key)
) WITHOUT ROWID;
```

- A level list's words: `WHERE series = ? AND level_ord = ?` on the primary key prefix (`series`). Each word of a series sits in one level, so the lists of a series are disjoint.
- `sort_key`: the term without parenthesised parts and punctuation, folded with `normalize_greek` (which equals `Search.foldGreek`, #87); for other scripts lowercase with diacritics removed (NFD, combining marks dropped; Swift `folding(options: [.caseInsensitive, .diacriticInsensitive])`), so `árbol` sorts with `arbol`. Ties by `term`.
- First, a capitalised term whose Unicode lowercase (Python `str.lower()`; Swift `lowercased()` in imports) is also a term of the series merges into that lowercase term (Decisions). `NOCASE` folds only A–Z, so this runs in Python and Swift before the rows are stored, and stored terms never differ by a non-ASCII case only; `WordKey` needs no Unicode folding. `testImportLinksLikeTheBuild` also checks the five merges.
- Rows with the same term (SQLite `NOCASE`) in one series merge: the lowest level, translations joined with "; " and endings with " / " in file order, the first row's `seq`. Kirill's files have 60 such rows: second senses (σπίτι "house, residence; (family) home"), both genders (αστυνομικός η / ο) and 4 exact duplicates.
- Linking follows "Linking a word to the dictionaries", in Python, against `entries`, `paradigm`, `lemma`, `form_lookup` and `morphy_exception`. `Scripts/data/wordlists/links.tsv` (`series`, `term`, `headword`, where `-` means none) overrides single links after review; the build fails on an override whose term is not in the series.
- `rank`: `word_rank` of the headword, or of the cleaned term when unlinked. `word_rank` sums each FrequencyWords token's count into its own key and into the key of each lemma it is a form of (Greek `form_lookup`; English `morphy_exception`), then ranks the keys by count (ties by key). 47,749 Greek and 50,093 English keys (measured).
- `data_source` rows: `ky-ell-lists` (kind `word_list`), `cefrj-1.5` and `octanove-c1c2-1.0` (`word_list`), `frequencywords-2018` (`word_frequency`).
- `wordlist.translation_lang`: `eng` for Kirill's lists (his `english` column, #152), '' for CEFR-J and Octanove, which have no translations (#153). A later translation of the lists into another language would be a pair's dictionary (0237, "Pairs"), not a second column.
- **Gates** (the build fails): Latin letters in a Greek term or ending; a Greek letter inside an otherwise Latin word of a translation; an input row that becomes no word (each row is a word or merges into one); the Greek series (A1 + A2 + B1) linked below 84%, the English series below 95%; a `wordlist.word_count` that differs from its rows; an empty list; the E3 tables above 4 MB.
- **Report** `Scripts/reports/wordlists-qa.md`, committed: counts per level, link classes per level, every cleaned, near, form and override link (for review), every unlinked and every unranked word, merged rows, Greek case pairs, table sizes.
- **Size** (measured): 1.2 MB for `wordlist_item`, 2.2 MB for `word_rank`, 3.4 MB in all. Budget 4 MB.
- Every dictionary file shares one schema (0237, "The catalog"). #240 registers the step and puts E3's tables, empty, into format 4 of the bundle, the stub and every pack, so #152 and #153 add rows only, which changes only their pack's version, never the format. #152 and #153 still merge one after the other, since they share the step.

**Inputs** (`Scripts/inputs.json`, 0129):

| Input | Pin |
|---|---|
| Kirill's lists | Committed as plain text (small, diffable): `Scripts/data/wordlists/ky-ell-a1.csv`, `-a2.csv`, `-b1.csv`, keyed by path with their sha256 (`inputs.committed()`). Never named "KLIK" (Decisions) |
| CEFR-J Wordlist 1.5 | `https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/d4e45b75b38f27b30dfc5c44d8c571aec7e7092f/cefrj-vocabulary-profile-1.5.csv`, sha256 `b0dd3c635f1c9a4fdf1490c7e5b7c48e8bbe55b652ad0c9860a95f98e10ae498` (7,799 rows) |
| Octanove C1/C2 1.0 | Same commit, `octanove-vocabulary-profile-c1c2-1.0.csv`, sha256 `18c33a407f2f89f7b8de9671c6d45fe3ea0bce45e7d2d7dcaab48d73e0f7b380` (2,136 rows: C1 1,111, C2 1,025) |
| FrequencyWords Greek | Already pinned by #141: `frequencywords/el_50k.txt` (commit `072bbed`) |
| FrequencyWords English | Same commit, `content/2018/en/en_50k.txt`, sha256 `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458` |

**Licenses, verified 2026-11-03.**
- CEFR-J, cefr-j.org/download.html: "The copyright of this wordlist belongs to Tono Laboratory at TUFS, but the list can be used for both research and commercial purposes", with "a proper acknowledgement of the source". The Japanese text adds that commercial work asking the lab for supervision is arranged and charged separately; we ask for none. The Open Language Profiles README repeats the terms: "can be used for research and commercial purposes with no charge, provided that you cite the dataset properly."
- Octanove C1/C2: CC BY-SA 4.0, stated in the Open Language Profiles README (Octanove Labs' own distribution); there is no other source.
- FrequencyWords: "MIT License for code. CC-by-sa-4.0 for content" (README).
- CC BY-SA data already ships in the file (FreeDict, OpenRussian, Wiktionary), so the derived rows add no new obligation beyond Credits.
- cefr-j.org now serves version 1.6 (2020-03-24) only, as an `.xlsx` in a zip, with no older versions online. 1.6 differs from 1.5 in 17 rows, mostly spelling variants merged into one row (`yogurt/yoghurt/yoghourt`) plus `being`, `having` and `tonne`. Pinning 1.6 means committing a third-party file to the repository (Open question 5).

**English items.** A CEFR-J or Octanove row is `headword, pos, CEFR`. Variants separated by "/" (`a.m./A.M./am/AM`) are one word: the term is the first variant that links, else the first; the other variants go into `endings`, so the row reads "a.m. A.M., am, AM". A word listed at several levels (by part of speech, or in both CEFR-J and Octanove) takes the lowest; its parts of speech are joined in `pos`. Words per level, measured on 1.5 by the first variant: A1 1,063, A2 1,241, B1 2,139, B2 2,417, C1 913, C2 875; 8,648 in all. Octanove's 1,111 C1 and 1,025 C2 rows hold 1,009 and 972 words (one row per part of speech), of which 96 and 97 already sit at a lower level. The build reports the final counts, since a variant's term depends on linking.

### User database: migration `130-1-word-lists` (#151)

```sql
CREATE TABLE user_list (
    id          TEXT PRIMARY KEY,       -- 'user-' + lowercase UUID
    title       TEXT NOT NULL,
    lang        TEXT NOT NULL,          -- ISO 639-3; 'und' for Other
    origin      TEXT NOT NULL,          -- 'file', 'anki' or 'paste'
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE user_list_item (
    list_id     TEXT NOT NULL REFERENCES user_list(id) ON DELETE CASCADE,
    term        TEXT NOT NULL COLLATE NOCASE,
    headword    TEXT,
    translation TEXT NOT NULL DEFAULT '',
    endings     TEXT NOT NULL DEFAULT '',
    pos         TEXT NOT NULL DEFAULT '',
    tags        TEXT NOT NULL DEFAULT '',
    level       TEXT NOT NULL DEFAULT '',
    level_ord   INTEGER NOT NULL DEFAULT 0,  -- 1 … 6 = A1 … C2; other level names 7, 8, … in order of first appearance; 0 = none
    rank        INTEGER,
    seq         INTEGER NOT NULL,
    sort_key    TEXT NOT NULL,
    PRIMARY KEY (list_id, term)
) WITHOUT ROWID;
```

- GRDB enables foreign keys by default, so deleting a `user_list` row deletes its words.
- `my_words` is not touched. My words is the list `my-words`: each row is a word whose term and headword are the entry's word, in its source's language.
- `-resetData` (DEBUG) also deletes every user list and the `learning_lists` preference.
- Imports store `headword` and `rank` when saved; they are not recomputed later (Out of scope).

### Swift (#151)

Pure code goes into `Models.swift`, SQL into `DatabaseService.swift` (the only code that touches SQLite), as #142–#144 did.

**Model** (`Models.swift`):
- `WordListID` (`String` raw value): `ky-ell-a1` … `cefr-eng-c2`, `my-words`, `user-<uuid>`.
- `WordKey { lang, word }`: a word's learning identity. `lang` is ISO 639-3 (`und` when unknown); `word` is the word as stored with only A–Z lowercased, as SQLite's `lower()` and `NOCASE` do, so Swift equality matches SQL. No Unicode normalisation in the key: list terms are stored in NFC, but 1,402 Arabic WordNet headwords are not (measured), and SQL could not normalise them.
- `WordList { id, kind (builtIn, myWords, user), lang, level, title, count }`.
- `WordListItem { listID, key, term, headword?, translation, translationLang, endings, partOfSpeech, tags, level, levelOrder, rank?, seq, sortKey }`. `listID` is the list it was read from. `key` is `WordKey(lang: list lang, word: term)`; for My words, `WordKey(lang: source language, word: entry word)`. `translationLang` is the list's `translation_lang`; '' for imported lists and My words (0131's meaning rule shows an import's translations in every pair).
- `NewWordOrder` (`frequency`, `random`).
- `LearningOrder.arrange(_:order:seed:)`: the order of "Order of new words" over the items of one language's checked lists, given in Lists screen order. Keeps one item per key (the lowest `levelOrder`, then the first list), groups by `levelOrder` (0 last), sorts, then the window-of-10 shuffle and the neighbour pass, or the full shuffle, with SplitMix64. The seed is FNV-1a 64 of "\(installSeed)|\(that language's checked ids, sorted, comma-joined)|\(order)", so checking a list of another language leaves the order unchanged (Swift's `Hasher` changes per launch, so it cannot be used).
- `ListLinking`: the cleaned variants and the near key of "Linking", pure. `build_wordlists.py` implements the same rules in Python; `testImportLinksLikeTheBuild` compares the two on Kirill's 4,648 terms (Test plan).
- `ListText` (#155): the parser, pure. Detects the encoding (UTF-8 BOM, UTF-16 BOM, else UTF-8), the Anki headers, the delimiter (tab if any of the first 20 data lines has one outside quotes, else semicolon if every one has one outside quotes, else comma; an Anki `#separator` or a manual choice overrides), parses RFC 4180 records (quoted fields with the delimiter, `""` and newlines), maps the header, strips HTML when `#html:true` or when a field holds tags (tags removed, `<br>` and `<div>` to "; ", entities decoded, `[sound:…]` dropped), and returns rows, merged duplicates and broken rows with line numbers. A quote still open at the end of the input breaks its record. The broken record runs from its first line to the first later line that parses on its own as a complete record with the expected number of fields (the header's, Anki's `#columns`, or else the first good row's); parsing resumes on that line, or nothing follows when there is none. So the continuation lines of a broken multiline field never become words.

**Database** (`DatabaseService`):
- `wordLists() -> [WordList]`: built-ins from the `wordlist` tables of the installed packs (0237), My words with its count, user lists with theirs. The view models keep the lists of learned languages (`learning_languages`, 0131) and My words.
- `wordListItems(_ id: WordListID) -> [WordListItem]`: alphabetical (`sort_key`, `term`); My words newest first, one item per `WordKey`. When rows from two dictionaries share a key (γράφω from El–En · FD and El–En · WN), the row added first (`added_at`, then `source`) stands for the word, as in 0131's enrolment, and My words' count counts keys. Its swipe calls 0131's `stopLearning`, which must then delete every My words row of the key, not only the one shown.
- `nextNewWords(in:from:count:excluding:order:) -> [WordListItem]`: keeps the lists of the set whose language is `lang`, puts them in Lists screen order itself (a `Set` has none: built-in lists by `level_ord`, then imported lists newest first, by `created_at`, then id), fetches their items in that order and the seed, runs `LearningOrder.arrange`, drops the excluded keys, runs the neighbour pass again on the rest (`LearningOrder.separateNeighbours`), takes `count`. No list of that language gives no words; ids of lists that no longer exist are skipped. The arrangement is cached per language, set and order until a list changes.
- `entry(for item: WordListItem, sourceOrder: [String]) -> DictionaryEntry?`: the item's headword in the first source of the given order whose language is the list's (in the source's file, `DictionarySchemas.schema(ofSource:)` (0237), then `imported_entries`). The caller passes 0131's `LearningPairs.sourceOrder` for the language's pair: the pair's dictionaries first, then Dictionary Order's sources, enabled first. The signature does not change.
- **Meanings on the list screen** (#154): `WordListViewModel` gets each row's meaning in the pair's meanings language from 0131's `meanings(of:lang:meaningsLang:sourceOrder:)` (#159), one batch for the list after `wordListItems`; the rows show the part of speech while it loads and where there is no meaning.
- `wordKey(for: EntryKey) -> WordKey`.
- `prepareListImport(_ parse: ListText.Result, lang:) -> ListImportPreview` (links and ranks in one read; ranks come from the language's `word_rank` when its pack is installed, else the words stay unranked) and `saveUserList(_ preview:title:) -> WordListID` (one write); `deleteUserList(_:)`.
- My words keeps `addToMyWords`, `removeFromMyWords`, `isInMyWords` and `fetchMyWords` (0129).
- Every read goes through the #213 `read` helper; the save is a user-database write and is not retried (0129).

**Preference** (`SettingsService`): `learningListIDs: Set<WordListID>`, key `learning_lists`, a JSON array of list ids; absent or empty means nothing is checked. Deleting a list unchecks it. No migration from an earlier key: no shipped build has E3.

**View models and views** (#154, #155): `WordListsViewModel`, `WordListViewModel` and `ListImportViewModel` in `ViewModels/WordListsViewModel.swift`; `WordListsView`, `WordListView`, `NewWordsFromView`, `ListImportView` (the source choice, the paste box and the preview) and `ListImportHelpView` (Formats) in `Views/WordListsView.swift`. `ListImportViewModel` asks E4's "Learn %@ via %@?" (the default pair) for a language not learned (0131) before saving. `WordListsViewModel` holds the checked set (`checked`, `toggleChecked(_:)`) for the Lists screen's badges and New words from; `WordListViewModel`'s "Learn this list" toggles the same preference. E4 pushes `NewWordsFromView` from the Learn home and its Learning settings. Views render and call; they hold no SQL and no parsing.

**Xcode step (Kirill, in the Xcode GUI).** The app target lists its files, so the two new files need adding: `DictApp/DictApp/ViewModels/WordListsViewModel.swift` and `DictApp/DictApp/Views/WordListsView.swift`, both in the app target. Once, before #154 and #155 start; #151, #152 and #153 need no step. Unit tests stay in `DictAppTests.swift` and read their fixtures through `#filePath`; UI suites go into the synchronized `DictAppUITests` folder.

**Performance targets** (iPhone 15 Pro simulator, iOS 17.5, median of 3): `wordListItems` of English B2 (the largest list) and `nextNewWords` with all six English lists checked under 100 ms; English B2's meanings via Spanish under 200 ms more; Kirill's B1 file (2,444 rows) parsed and previewed in under 1 s, saved in under 3 s.

### Identifiers

| Element | Identifier |
|---|---|
| Lists screen | `word_lists` |
| A list row, its count, its badge | `word_list_row_<id>`, `word_list_count_<id>`, `word_list_active_<id>` (`word_list_row_ky-ell-b1`, `word_list_row_my-words`) |
| Import button | `word_list_import_button` |
| List screen, a word row, its meaning in the meanings language | `word_list_items`, `word_list_item` (label: the term), `word_list_item_translation` |
| Learn this list | `word_list_learn_button` |
| New words from: screen, a row (value `checked` when checked), the footer with nothing checked | `new_words_from`, `new_words_from_row_<id>`, `new_words_from_none` |
| Import source choice, Formats link, help screen | `list_import_file`, `list_import_paste`, `list_import_formats`, `list_import_help` |
| Paste box, Paste button | `list_import_text`, `list_import_paste_button` |
| Preview | `list_import_preview`, `list_import_name`, `list_import_language`, `list_import_delimiter`, `list_import_summary`, `list_import_error_row`, `list_import_confirm` |
| Result | `list_import_result` |

DEBUG launch argument `-importListFixture:<path>` skips the file picker and imports the file at `<path>` (the UI test passes a path from its `#filePath`; the app on the simulator reads the Mac's file system, as the unit tests do). The paste test puts text on the general pasteboard from the test runner and taps the SwiftUI `PasteButton`, which shows no paste alert.

### Strings

About 38 new keys, translated by the implementing agent into en, ru, es, ar and el (overview, Localization). The main ones:

| Key | en |
|---|---|
| `wordLists.title` | Lists |
| `wordLists.section.myLists` | My lists |
| `wordLists.myWords` | My words |
| `wordLists.count` | %lld words (plural variants) |
| `wordLists.listTitle` | %1$@ %2$@ ("Greek A1": language name, level) |
| `wordLists.level.A1` … `.C2` | A1 … C2. Greek uses the Greek certificate letters Α1, Α2, Β1, Β2, Γ1, Γ2 |
| `wordLists.learnThisList`, `wordLists.learningThisList`, `wordLists.learning` | Learn this list · Learning this list · Learning |
| `newWordsFrom.title`, `.header`, `.none` | New words from · Lower levels come first: A1, then A2 and up. Lists without levels come last. · No list checked. New words come only from words you add with Learn. |
| `wordLists.delete.title`, `.message` | Delete "%@"? · Progress on its words is kept. |
| `listImport.file`, `listImport.paste`, `listImport.pasteButton` | Import a file · Paste text · Paste |
| `listImport.summary` | %1$lld words · %2$lld merged · %3$lld rows with errors |
| `listImport.error.noTerm`, `.openQuote`, `.tooLong`, `.encoding` | No word in this row · A quote is never closed · A field is longer than 1,000 characters · Save the file as UTF-8 and try again |
| `listImport.result` | Imported %1$lld words, %2$lld found in the dictionaries |
| `listImport.language.other`, `listImport.learnOther` | Other · Learn lists in other languages? |
| `listImport.formats`, `listImport.help.title`, `.csv`, `.anki`, `.quizlet` | Formats · Formats you can import · A CSV file with a header row (`term,translation,level`) · An Anki deck exported as "Notes in Plain Text" · A Quizlet set exported and pasted as text |
| `credits.dataSources.greekLists`, `.cefrj`, `.octanove`, `.frequencyWords` | The Credits lines |

Composed Arabic strings start with U+200F (#119). Terms, translations and citations are never translated.

### Code map

| Path | Change | Ticket |
|---|---|---|
| `Scripts/wordlists_schema.sql`, `Scripts/build_wordlists.py` | New step and its DDL, in `STEPS` | #151 (schema), #152, #153 |
| `Scripts/data/wordlists/ky-ell-*.csv`, `links.tsv`; `Scripts/inputs.json`; `Scripts/reports/wordlists-qa.md` | Inputs, pins, report | #152, #153 |
| The Greek pack and the English lists pack (0237) | Their list tables | #152, #153 |
| `DictApp/DictApp/Models/Models.swift` | `WordListID`, `WordKey`, `WordList`, `WordListItem`, `NewWordOrder`, `LearningOrder`, `ListLinking`; `ListText`; `DictionaryFile.formatVersion` + 1 | #151; #155; the first of #152 and #153 |
| `DictApp/DictApp/Services/DatabaseService.swift` | Migration `130-1-word-lists`, the list queries, import save and delete | #151, #155 |
| `DictApp/DictApp/Services/SettingsService.swift` | `learning_lists` | #151 |
| `DictApp/DictApp/DictApp.swift` | `-resetData` clears user lists; `-importListFixture:` | #151, #155 |
| `DictApp/DictApp/ViewModels/WordListsViewModel.swift`, `DictApp/DictApp/Views/WordListsView.swift` | New (Xcode step) | #154, #155 |
| `DictApp/DictApp/Views/CreditsView.swift`, `Resources/Localizable.xcstrings` | Credits lines, strings | #152, #153, #154, #155 |
| `DictApp/DictAppTests/DictAppTests.swift`, fixtures next to it | Unit tests | all |
| `DictApp/DictAppUITests/TestCases/WordListsFlowTests.swift`, `WordListImportTests.swift`, `PageObjects/WordListsPage.swift`, `TestHelpers/AccessibilityIdentifiers.swift` | UI tests | #154, #155 |
| `docs/specs/0000-overview.md` | Screens, Code map, Bundled data, Database, Preferences, Localization, tests | each PR |

### Tickets, order and size

#151 lands first. Then two streams run in parallel:

| Ticket | Contents | Depends on | Size |
|---|---|---|---|
| #151 Data model | Migration, model, `LearningOrder`, `ListLinking`, queries, `learning_lists`, `wordlists_schema.sql` (with `wordlist.translation_lang`) and an empty `build_wordlists.py` (no rebuild) | — | M, 2.25 days |
| #152 Greek lists | Kirill's CSVs, linking in Python, overrides, Greek frequency and `word_rank`, gates, report, credits, the tables for the Greek pack (0237) | #151 | M, 2 days |
| #153 English lists | CEFR-J, Octanove, English frequency and `word_rank`, report, credits, the tables for the English lists pack (0237), after #152 or before it | #151 | S–M, 1.5 days |
| #154 Lists screen | Lists and list screens for learned languages (rows with the meaning in the meanings language), Learn this list, New words from, strings, UI tests | #151; #158's Learn tab (E4) for its entry; #159's `meanings` (E4); #152 for the Greek counts in its UI tests; 0237's install for the built-in lists in its UI tests | M, 3.5 days |
| #155 Import | `ListText`, preview, paste, save, delete, "Learn %@ via %@?" for a new language, the Formats help, UI tests | #151; #154's "+" for its UI tests | M–L, 3.25 days |

Data stream: #152, then #153 (they share the step, so they merge one after the other). UI stream: #154, then #155; #155's parser, linking and unit tests start with #154 and merge after it. About 12.5 developer days in all, 7.25 to 8.25 calendar days with two streams. Learning pairs (Kirill, 2026-11-04) add 0.75: #151 +0.25 (built: the column and the field), #154 +0.5 (the rows' meanings); #152, #153 and #155 only set a column value or reuse E4's alert. If late, nothing is cut: the release date moves (Decisions). The dates are to be replanned with #237 (Decisions); the order above stays. The risk is #158: if E4's Learn tab is not merged when #154 starts, #154 rebases onto its branch.

### For E4 and E10

E4 relies on these, and E3 keeps them stable:

1. **A list is an ordered set of words with levels.** `WordListItem.key: WordKey` is the word's identity: `(lang, word)`, ISO 639-3 and the term as stored with only A–Z lowercased. A key appears once per list. `listID` names the list the item came from. Linked words also carry `headword`, the dictionary word their Definition opens; standalone words carry only the list's term and translation.
2. **Why `WordKey`, not `EntryKey`.** 12% of Kirill's words have no entry and still need learning, and one word can sit in two lists or two dictionaries (σπίτι in Greek A1 and in My words from El–En · WN) and must be one card pair. For a My words row the key is `(source language, word)`; in SQL, in a write (the writer has every dictionary file attached, 0237): `COALESCE(d.from_lang, s.from_lang, 'und')` and `lower(m.word)` from `my_words m LEFT JOIN (<DictionarySchemas.sourceLanguageSQL>) d ON d.source = m.source LEFT JOIN imported_sources s ON s.source = m.source`. 0237's `sourceLanguageSQL` reads the bundle's `dict_metadata` and `dict.catalog_source`, so a row of a pack not yet downloaded keeps its language instead of `und`; `wordKey(for:)` reads the same in Swift. A card keyed by `WordKey` survives a dictionary switch or a deleted list.
3. **Queries** (`DatabaseService`, async):
   - `wordLists() -> [WordList]`;
   - `wordListItems(_ id:) -> [WordListItem]`;
   - `nextNewWords(in lang: String, from lists: Set<WordListID>, count: Int, excluding enrolled: Set<WordKey>, order: NewWordOrder) -> [WordListItem]`: only the lists of `lang`, levels in order across them, each key once. Deterministic for a given install, language, set of lists, order and exclusion set. E4 passes the chosen language, the checked lists and the keys it has cards for;
   - `entry(for item:sourceOrder:) -> DictionaryEntry?` for the Definition and for a card's answer;
   - `wordKey(for: EntryKey) -> WordKey`, for the Learn button and E4's enrolment of My words.
4. **Content for a card.** `term`, `translation` (may be empty), `translationLang`, `endings`, `partOfSpeech`. The card shows `translation` when it is not empty and `translationLang` is the pair's meanings language (English for the limited Greek via Russian) or '' (an import's translations, in every pair); otherwise E4 takes the meaning from the pair's dictionary (0131, Meanings).
5. **The sources of new words** are `SettingsService.learningListIDs` (`learning_lists`), the set checked on New words from or by "Learn this list" (#154). Empty until the user checks a list; there is no default (Decisions). E4 reads it, with the language chosen on its home (`learning_language`, 0131), when it builds a session or its home appears, and pushes `NewWordsFromView` from the Learn home ("Choose lists", then a "New words from" row) and from its Learning settings (#162).
6. **My words.** The Learn button (#158) calls `addToMyWords(EntryKey)` / `removeFromMyWords(EntryKey)` and does its own enrolment. `my_words` stays the table E4 enrols from when a language is chosen (0131).
7. **Owned by E4, not here:** cards, reviews, sessions, enrolment, the learned languages (`learning_languages`) and the language picker, the "by frequency / random" setting and its default, the Learn tab and its home. E3 reads `learning_languages` to filter its screens.
8. **E10:** a list's progress is E10's aggregate over `wordListItems(id).map(\.key)`. `WordListsView` rows take an optional `ListProgress` (new, learning, learned) and hide the bar while it is `nil`; #163 supplies it, and the progress half of #154's criterion is tested in E10's PR. Progress is per language (0166): a list has one language, and My words' bar counts only its words of the language chosen on the Learn home.

## Test plan

Unit classes go in `DictAppTests.swift`. Classes that read the built list tables read the built packs as 0237's tests do; tests with made-up rows use `TestDictionary.make(rows:)` plus the `wordlists_schema.sql` DDL. Async tests are `@MainActor` (#229). UI suites run on the four-simulator matrix (iPhone and iPad, iOS 17.5 and 26.4), one suite per `xcodebuild` run with the app uninstalled before it.

| Acceptance criterion | Test |
|---|---|
| #151: built-in and user lists share one model and one query API | Unit `WordListModelTests.testOneModelForEveryKind`: a test file with two built-in levels, My words with two rows and one saved user list; `wordLists()` returns the three kinds with counts, `wordListItems` decodes each into `WordListItem`; `testLevelListHoldsOnlyItsLevel` (`level_ord = ?`); `testUserListDeleteCascades`; `testMyWordsOneItemPerKey` (γράφω in My words from El–En · FD, then El–En · WN: one item, the FD row's, and a count of 1); `testMigrationLeavesMyWordsUntouched` (129-1 data, then 130-1: `my_words` rows and the #139 fixtures move as before) |
| #151: words link to entries, also through forms; unmatched words keep their translation | Unit `ListLinkingTests` (pure): every rule and its order on made-up data (exact, cleaned variants, near for case and diaeresis, never accent-folded: νομός ↛ νόμος, μονός ↛ μόνος; one-word forms only; ambiguous → none). `WordListModelTests.testLinkingOnTheFile` (real file): σπίτι, `Ευχαριστώ!` → ευχαριστώ, `Καλή όρεξη!` → καλή όρεξη, `λίγοι` → λίγος, `έχει αέρα` → none with "it is windy"; English `bought` → buy, `was` → be |
| #151: unit tests for level and rank queries | `LearningOrderTests` (pure): `testFrequencyKeepsTopTenInFirstTen` (and 20 in 20), `testUnrankedFollowRankedInListOrder`, `testLevelsInOrder`, `testRandomShufflesWithinLevel`, `testSameSeedSameOrder`, `testSeedDiffersPerSetAndInstall`, `testExcludedKeysDropOut` (the remaining order is unchanged but for the neighbour pass: with A, X, B, where B follows A alphabetically, and X excluded, A and B are not side by side), `testNoAlphabeticalRun` (Kendall tau between the first 100 places and alphabetical order below 0.2), `testNoWordFollowedByItsAlphabeticalNeighbour` (a level of unranked words in alphabetical list order and a ranked level, 50 seeds each: no word is followed by the next word of its level, except into a last run of one word; the top 10 and top 20 stay in place). `WordListModelTests.testNextNewWordsOnTheFile` (after #152), `testRankLookupUsesPrimaryKey` (`EXPLAIN QUERY PLAN` without `SCAN`) |
| #151 (Kirill, 2026-11-03): new words come from the checked lists of one language, by level across them | Unit `LearningOrderTests.testCheckedListsInLevelOrder` (made-up Greek A2, Greek A1 imported with A1 and "Lesson 1" levels, and a Greek import without levels: every A1 word before every A2 word, then "Lesson 1", then the unlevelled words; frequency and the window shuffle within each level), `testWordInTwoListsComesOnce` (at its lowest level, `listID` of that list). `WordListModelTests.testNextNewWordsInListsScreenOrder` (two imported lists without levels: the newer list's words come first, whatever order the set gives). `WordListModelTests.testNextNewWordsPerLanguage` on made-up lists, and `testNextNewWordsPerLanguageOnTheFile` on the packs after #152 and #153 (Greek A1, Greek A2 and English C2 checked: `in: ell` gives only Greek words, A1 before A2; `in: eng` only English C2; checking English C2 leaves the Greek order unchanged; an unknown id is skipped) |
| #130, #152: Greek A1, A2, B1 built in with their counts; B1 shows all words | Unit `WordListDataTests.testGreekListsAndCounts` (the Greek pack's `wordlist`: 1,457 / 756 / 2,435, 4,648 in all; `word_count` equals the rows; every row of the three committed CSVs is a word of its level and of no other list). UI `WordListsFlowTests.testBuiltInListsShowTheirCounts`, `testGreekB1ShowsAllItsWords` (one section; scroll to the last word; σπίτι, an A1 word, is not in it) |
| #130, #152: at least 84% of the words open a dictionary entry | Build gate. Unit `WordListDataTests.testGreekLinkRate` (≥ 84% of the 4,648 words of the three lists have a `headword`, and every headword resolves through `entry(for:sourceOrder:)`). UI `WordListsFlowTests.testTapOpensDefinition` (σπίτι opens its Definition) |
| #152: every word has a frequency rank or is reported unranked | Unit `testEveryUnrankedWordIsReported` (the unranked words of the file equal the report's list). `wordlists-qa.md` committed |
| #130: new words by frequency with a light shuffle; the first 20 A1 words hold the most frequent verbs; no alphabetical runs; "random" works | Unit `WordListDataTests.testGreekA1FirstTwentyHoldTheFrequentVerbs` (`nextNewWords(in: ell, from: [ky-ell-a1], count: 20, order: .frequency)` holds είμαι, έχω, θέλω for 20 seeds), `testGreekA1FirstHundredIsNotAlphabetical` (Kendall tau, and no word followed by its alphabetical neighbour in the whole level), `testRandomOrderDiffersFromFrequency` |
| #130, #153: English A1–C2 built in with word counts | Unit `WordListDataTests.testEnglishListsAndCounts` (six lists, each word in one of them, the report's counts, ≥ 95% of the series linked, `went`-style forms ranked with their lemma). UI `testBuiltInListsShowTheirCounts` |
| #153: CEFR-J license confirmed at the source and quoted in the PR | Review: the PR quotes this spec's Licenses paragraph with the date checked again |
| #130, #153: CEFR-J, Octanove, FrequencyWords and Kirill's list credited | Unit `WordListDataTests.testDataSourceRows` (four `data_source` rows, no `dict_metadata` row). UI `WordListsFlowTests.testCreditsListTheWordLists` (four ids in Credits) |
| #154: every built-in and imported list shown with its word count | UI `WordListsFlowTests.testBuiltInListsShowTheirCounts` (`-learningLanguages ell,eng`, both packs installed as 0237's tests do), `WordListImportTests.testImportedListAppearsWithItsCount`. Progress: E10's PR (For E4 and E10, item 8) |
| #154 (Kirill, 2026-11-03): only the lists of learned languages | Unit `WordListsViewModelTests.testOnlyLearnedLanguages` (Greek learned, English not: no English list on Lists or New words from, built-in or imported; English stopped: its checked lists stay in `learning_lists` but hidden). UI `WordListsFlowTests.testListsFollowLearnedLanguages` (`-learningLanguages ell`: Greek and My lists sections only) |
| #154: tapping a word opens its Definition; unmatched words show the list's translation | UI `testTapOpensDefinition`, `testStandaloneWordShowsItsTranslation` (`έχει αέρα` shows "it is windy" and has no chevron; tapping it pushes nothing). Unit `testEntryFollowsThePair` (an English word opens WordNet for English via English and En–Es · FD for English via Spanish, whatever the UI language; with the pair's dictionaries off, the first English dictionary of Dictionary Order) |
| Kirill 2026-11-04: a list word's meaning is in the via | Unit `WordListModelTests.testTranslationLanguage` (Greek lists `eng`, English lists '', user lists and My words ''), `WordListViewModelTests.testRowsShowTheMeaningInTheVia` (Greek A1 via English and via Russian, the limited pair: Kirill's English translations; English A1's "house" via Spanish "casalicio, casa", via English WordNet's first sense; an imported Greek list's translations in every pair; no meaning: the part of speech). UI `WordListsFlowTests.testEnglishListMeaningsFollowTheVia` (`-learningLanguages eng:spa`, `-installPacks eng-lists,spa`: English A1's "house" row reads "casalicio, casa"; after changing the via to English in Settings, WordNet's sense) |
| #154: "Learn this list" switches the source of new words | Unit `WordListsViewModelTests.testLearnThisListTogglesItsList` (a tap adds the id to `learning_lists`, a second tap removes it), `testDeletingACheckedListUnchecksIt`. UI `testLearnThisListAddsTheBadge` (Greek A1, then English B1: both rows carry the badge, the button reads "Learning this list"; a second tap on English B1 removes its badge; it survives a relaunch) |
| #154 (Kirill, 2026-11-03): New words from: the checked lists are the sources of new words | Unit `WordListsViewModelTests.testNewWordsFromRows` (every list but My words, in the Lists screen's order; a toggle writes the set; empty shows the footer). UI `WordListsFlowTests.testNewWordsFromCheckedLists` (`-learningLanguages ell,eng`, both packs installed: Learn home, "Choose lists", check Greek A1 and English C2, back; the language switch shows; with English chosen, Start's new words, with `exercise_new_badge`, are English; close, choose Greek, Start: they are Greek. It needs E4's Start, #161, so whichever of #154 and #161 merges second adds it) |
| #154: 5 UI languages, Arabic right to left | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`. UI `GreekLocalizationTests.testWordListsInGreek` ("Ελληνικά Α1", the English section first), `ArabicLocalizationTests.testWordListsAreRightToLeft`, `SpanishLocalizationTests.testWordListsInSpanish` |
| #154: UI tests on iPhone and iPad, iOS 17.5 and 26.4 | The matrix run of `WordListsFlowTests` and `WordListImportTests`; `iPadSpecificTests.testWordListsOnIPad` (both orientations; iPadOS 26 tab strip) |
| #130, #155: Kirill's three CSVs import without edits | Unit `ListImportTests.testKirillsFilesImport` (each committed CSV imported alone: 0 broken rows, 1,457 / 758 / 2,436 words, levels kept; alone, the A2 and B1 files keep the words that the built lists merge into A1). UI `WordListImportTests.testImportKirillsA1` (`-learningLanguages ell`, `-importListFixture:`: preview "1,457 words · 39 merged · 0 rows with errors", Import, the list row shows 1,457) |
| #130, #155: an Anki plain-text export imports without edits | Unit `ListTextTests.testAnkiHeaders` (every header, separator names and literal characters, `#html`, tags, guid, note type and deck columns ignored, HTML and `[sound:]` stripped), `ListImportTests.testAnkiExportImports` on `anki-notes-plain-text.txt`, a real export from Anki desktop (Fixtures, below) |
| #130, #155: a Quizlet paste imports without edits | Unit `ListTextTests.testQuizletPaste`. UI `WordListImportTests.testPasteFromQuizlet` (pasteboard set by the runner, Paste button, preview, Import) |
| #130, #155: a broken row shows in the preview and does not stop the import | Unit `ListTextTests.testBrokenRowsAreReportedAndSkipped` (an empty term, an unclosed quote in the middle and at the end, a 1,001-character field: each with its line number; the other rows parse), `testUnclosedMultilineQuote` (a two-column file whose row 5 opens a quote that never closes, followed by two one-field continuation lines, then good rows: one broken row at line 5, no word from the continuation lines, the good rows after them import), `testDelimiterDetection` (tab > semicolon > comma, override; a comma CSV with a quoted semicolon on every line stays comma), `testRFC4180Quotes`, `testEncodings` (UTF-8 with and without BOM, UTF-16 BOM, invalid bytes), `testDuplicatesMerge`, `testHeaderMapping` (Kirill's header, language names, no header), `testLimits`. UI `WordListImportTests.testBrokenRowShowsInPreview` (`broken-list.csv`: 2 `list_import_error_row`s with line numbers, Import, the count excludes them) |
| #155: imported words link like built-in lists | Unit `ListImportTests.testImportLinksLikeTheBuild`: Kirill's three files imported in the app link each word to the same headword as the Greek pack's `wordlist_item`, except the terms in `links.tsv`; ranks equal too. `testImportPreviewAndSaveTimes` (the targets above) |
| #155 (Kirill, 2026-11-03): a Formats help; a list of a language not learned asks first | UI `WordListImportTests.testFormatsHelp` (`list_import_formats` opens `list_import_help` with the three examples), `testImportInANewLanguageAsks` (`-learningLanguages ell`, English UI, an English file: "Learn English via English?"; No: saved, not on Lists; Yes on a second import: English joins the Learn home's switch and the list shows). Unit `ListImportViewModelTests.testAsksOnlyForANewLanguage` |
| No regression | `BookmarkFlowTests`, `LegacyMigrationTests`, `UserDatabaseTests`, `DictionaryReopenTests`, `SearchProbeTests` stay green unchanged; `DictionaryFileTests.testDictionaryFileFormat` and 0237's `PackFileTests.testEveryFileHasTheFormat` pass (every file has the E3 tables, empty or filled, since #240) |

QA records in History: the measured counts and link rates from the report, the size of the E3 tables, the performance targets, and the matrix results.

**Fixtures.** `Scripts/data/wordlists/ky-ell-*.csv` serve the unit and UI import tests directly. `broken-list.csv`, `quizlet-paste.txt` and `anki-notes-plain-text.txt` sit next to `DictAppTests.swift`. Kirill exports the Anki fixture from Anki desktop (any small deck, "Notes in Plain Text", with tags and HTML) during #155; until then a hand-made file in the documented format stands in.

## Open questions

1. **Greek capitals.** Resolved 2026-11-03: capitalised twins merge into the lowercase word (Decisions).
2. **είμαι in A2.** Resolved 2026-11-03: it moves to A1 in the committed copy (Decisions).
3. **No list chosen yet.** Resolved 2026-11-03: no default (Decisions).
4. **Your lists in the public repository.** Resolved 2026-11-03: yes to all three (Decisions).
5. **CEFR-J version.** Resolved 2026-11-03: 1.5 (Decisions).
6. **English levels cumulative.** Resolved 2026-11-03: replaced by checked lists (Decisions).
7. **"Random" order.** Resolved 2026-11-03: within each level (Decisions).
8. **English words open the user's dictionary.** Resolved 2026-11-03: every English dictionary, opened through Dictionary Order (Decisions).

## History

- 2026-11-03: First draft. Counts, link rates, frequency ranks and table sizes measured with a prototype of `build_wordlists.py` on the dictionary file of master `7df5f05`, Kirill's CSVs of 2026-10-22, CEFR-J 1.5 and 1.6, Octanove 1.0 and FrequencyWords 2018. Licenses checked at cefr-j.org and in the Open Language Profiles and FrequencyWords repositories.
- 2026-11-03: Kirill's decisions of the day: disjoint levels and checked lists (New words from), learning per language, and learning a language explicitly. The Lists screen and New words from show only learned languages' lists; built-in lists move from the bundled file to the languages' packs (0237), with the same tables; import gets a Formats help and asks before saving a list of a new language (#155 +0.25 day); dates are to be replanned with #237.
- 2026-11-04: Review fixes and alignment with 0237 (Draft): the frequency order ends with a pass that keeps alphabetical neighbours apart, with its tests; `nextNewWords` puts the checked lists in Lists screen order itself; a semicolon counts as the delimiter only outside quotes; E3's tables bump the format of every file, since 0237's files share one schema (free before 2.0 ships); `entry(for:sourceOrder:)` reads each source's file, and the My words key reads 0237's `DictionarySchemas.sourceLanguageSQL`, so a word of a pack not yet downloaded keeps its language.
- 2026-11-04: Approved by Kirill.
- 2026-11-04: Review fixes after approval: Other (`und`) can be learned, with its own import prompt and name; My words lists one item per `WordKey` (the row added first) and counts keys; a quote left open breaks its record up to the next line that parses as a full record, so continuation lines never become words; `nextNewWords` runs the neighbour pass again after dropping enrolled words. Tests added for each.
- 2026-11-04: Review fixes after approval: imports merge duplicate rows like the build; the sort key drops diacritics in every script.
- 2026-11-04: #151: `testLinkingOnTheFile` checks `bought` → buy and `was` → be, not `went` → go: FreeDict En–El has the headword `went`, so the exact rule wins.
- 2026-11-04: #151: until #241's `DictionarySchemas` helpers land, the list queries look for the list tables in every attached file, and source languages come from each file's `dict_metadata`.
- 2026-11-04: #151: the near and form rules also try the cleaned spellings (`Ευχαριστώ!` → ευχαριστώ). Cleaning drops double quotes and guillemets at either end, single quotes only when they wrap the term (σ' stays). `build_wordlists.py` follows.
- 2026-11-04: #151: My words' `WordList.lang` is `mul`.
- 2026-11-04: #151: the 100 ms new-words target holds in an optimized build (41 ms; `wordListItems` of B2 9 ms); the Debug test `testListQueriesAtFullSize` checks 150 and 500 ms.
- 2026-11-04: #151: `entry(for:sourceOrder:)` also tries the word's language's sources missing from `sourceOrder`, after the given ones.
- 2026-11-04: #151: the seed takes the checked lists that still exist, so deleting a checked list reorders the rest.
- 2026-11-04: #151: the second neighbour pass runs in frequency order only; random order has none.
- 2026-11-05: #151: `entry(for:sourceOrder:)` counts a source of no known language as `und`, as the My words key does, so a My words row of such an import opens its entry (CodeRabbit, PR #250).
- 2026-11-04: Learning is chosen as a language pair (Kirill, 0131): `wordlist.translation_lang` and `WordListItem.translationLang`; list rows show the word's meaning in the via (an import's translations in every pair); a list word's Definition opens in the pair's dictionary first; "Learn %@ via %@?" on import. #151 +0.25, #154 +0.5. Nothing is cut if late (Kirill).
- 2026-11-04: Greek via Russian is offered as a limited pair (Kirill, 0131): list rows follow the pair's meanings language (English for it), with a test. No size change.
- 2026-11-06: Review fix: a card's meaning follows the pair's meanings language, not the via, and an import's translations show in every pair, as the list rows do.
- 2026-11-06: #240, #241: the list queries read through 0237's `DictionarySchemas` (`union` for the lists, `sourceLanguageSQL` for languages, `schema(ofSource:)` for entries), replacing #151's lookup of every attached file; linking reads Greek forms from `ell` and English exceptions from `dict`. #240 puts E3's tables, empty, into format 4, so #152 and #153 bump no format.
- 2026-11-06: #152: Latin letters in 27 of Kirill's Greek fields (11 terms, 16 endings) are fixed in the committed copies, so Ισραηλινός merges into ισραηλινός (a sixth case pair) and A2's κεφαλαίο γράμμα into A1's; with Kirill's number merges the lists hold 1,457, 756 and 2,435 words (4,648). 4,090 link (88.0%), 3,735 are ranked; επτά, οκτώ, εννέα link to εφτά, οχτώ, εννιά by override. Greek lookalikes in the English column are fixed and gated. A merged row's repeated translation or ending appears once; an unlinked word takes the rank of its term or of its first ranked cleaned spelling; Credits also name FrequencyWords. The Greek list tables take 1.78 MB.
- 2026-11-06: #152: format 4's `wordlist` lacked `translation_lang`; #152 adds it without a format bump, since nothing has shipped with format 4, so every pack, the stub and the bundle are cut again (release `packs-20261107`).
- 2026-11-06: #153: English A1 1,063, A2 1,241, B1 2,138 (two check-in rows choose the same variant and merge), B2 2,417, C1 913, C2 875 (8,647); 98.6% link, 976 unranked. Overrides link is, am, are, 'm, 're to be and does to do (else is opens IS in En–Es). IT, March, May and Miss merge into their lowercase twins by the merge rule. The report adds a table of terms taken from a later variant and shows parts of speech for English. Octanove's `remonstrate` keeps its source part of speech "vern".
- 2026-11-07: Review fixes (CodeRabbit, PR #254): one set of counts for an import of Kirill's A1 file (1,457 words, 39 merged); a file imported alone keeps the words the built lists merge across levels (A2 758, B1 2,436); the unlinked words recounted from the report: 155 + 70 + 333 = 558.
- 2026-11-08: Review fix (CodeRabbit, PR #270): a My words word whose first row no longer resolves (its pack removed) shows through its next row, and the Learn home's My words count is the My words screen's, one per word.
- 2026-11-08: #155 as built: a first row is a header only when it names two different known columns (so a first card like λέξη,word imports); a quote followed by anything but the delimiter or the line end counts as never closed; the 1,000-character limit applies to the columns kept; pasted text has the 10 MB limit too, with a "too big" message; the paste screen has a Preview button and uses the system PasteButton (no `listImport.pasteButton` key); the summary joins `wordLists.count` with `listImport.merged` and `listImport.errors`; the launch argument is `-importListFixture <path>`; `created_at` is in milliseconds. The Anki test uses a hand-made export until a real one replaces it.
