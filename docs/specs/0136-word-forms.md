# Word forms

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-10-28 · Epic: #136 · Tickets: #141, #142, #143, #144 · Updated: 2026-10-30

Read [0000-overview.md](0000-overview.md) and [0129-dictionary-file.md](0129-dictionary-file.md) first. This epic builds on #129's read-only `dictionaries.sqlite`. Numbers marked "measured" come from a prototype of the pipeline, run on 2026-10-27 against the 2026-10-01 Wiktionary snapshot and the 1.4.0 seed.

## Why

Greek is highly inflected. Of the 5,000 most frequent Greek words in subtitles, 38.9% are headwords of the bundled dictionaries. Most of the rest are inflected forms (έχεις, ήταν, είπε) that find nothing today. English learners hit the same wall with irregular forms (went, mice). Learners also want to see how a word inflects. This epic adds a form → lemma step to search and inflection tables to the Definition screen. The Greek forms data is the layer that word lists (#130), the conjugation drill (#132) and examples (#134) reuse later.

## Behaviour

### Search by any form (#142, #143)

- After sanitising, a one-word query of 2+ letters is also looked up as an inflected form:
  - every letter Greek: in the Greek forms table, ignoring accents, case and final sigma (`εγραψα`, `ΈΓΡΑΨΑ` = `έγραψα`);
  - every letter a–z, any case: through the WordNet morphy port;
  - mixed scripts, other scripts or several words: no form step.
- The lemma's rows (its headword entries in the enabled dictionaries) come right after the exact matches and before the prefix matches. Each carries a caption under the headword line.
- If the folded query is the lemma itself, nothing is added, so results for base forms do not change.
- A form shared by several lemmas shows each of them: up to 5 lemmas and 10 rows. Example: κανείς and κάνεις both fold to `κανεισ`, so the query also shows κάνω.
- In "Preferred dictionary first" mode, lemma rows go into their pair's bucket after that bucket's exact matches. The top 4 per pair is applied after the merge.
- Opening a lemma row works as today. History records the opened row's source and word (#138), i.e. the lemma, not the typed form.

| Query | Rows added after exact matches | Caption (en) |
|---|---|---|
| έγραψα, εγραψα | γράφω (El–En · FD, El–En · WN) | aorist 1sg of γράφω |
| ήταν | είμαι | imperfect 3sg of είμαι |
| έχεις | έχω | present 2sg of έχω |
| σπιτιού | σπίτι | genitive singular of σπίτι |
| της | ο | genitive singular feminine of ο |
| went | go (WordNet, En–Es · FD, En–El · FD, En–El · WN) | form of go |
| mice, geese | mouse, goose | plural of mouse |
| better | good and well, after the exact row `better` | comparative of good, comparative of well |
| running | run, after the exact row `running` | -ing form of run |

### Inflection tables (#144)

- The Definition screen of a Greek headword (sources `freedict-ell-eng`, `wordnet-ell-eng`) shows one table below the definition, titled "Conjugation" or "Declension". Words without a table show nothing: indeclinables, adverbs and gaps in Wiktionary.
- **Verbs, default view** (Kirill, 2026-10-22):
  - rows εγώ, εσύ, αυτός, εμείς, εσείς, αυτοί;
  - columns Present, Imperfect, Aorist, Future (θα γράψω), in the grammar-book order;
  - an Imperative block: rows εσύ and εσείς, columns continuous (γράφε) and simple (γράψε).
  - The main voice is active, or passive when the verb has no active present (deponents such as έρχομαι).
- **"All forms"** (Kirill, 2026-10-22) shows the rest below the default view:
  - for the main voice: future continuous (θα γράφω), subjunctive continuous and simple (να γράφω, να γράψω), perfect (έχω γράψει), pluperfect (είχα γράψει), future perfect (θα έχω γράψει), participles (γράφοντας, έχοντας γράψει) and the aorist infinitive (γράψει);
  - then everything for the other voice, if the verb has it (γράφομαι, γραφόμουν, γράφτηκα, θα γραφτώ, …, γραμμένος).
  - The button then reads "Main forms" and collapses again. Its state is not stored.
- **Nouns**: case (nominative, genitive, accusative, vocative) × number. **Adjectives**: case × gender, one block for the singular and one for the plural, then a line with the comparative and superlative when Wiktionary has them.
- **Cells**:
  - several forms in one cell are joined with " / " (γράφτηκα / γράφηκα);
  - forms tagged rare, archaic or dated are hidden from tables but stay searchable;
  - empty rows and columns are dropped (είμαι has no aorist, πρέπει has only αυτός);
  - a single missing cell shows "—".
- **Which table**: the lemma whose word equals the entry's word (NFC), else the one whose folded word equals it. If more than one lemma of the chosen part of speech matches only by folded word, no table is shown.
  - Filter by each comma-separated label of the entry's `pos`: noun → noun, adjective or adjective satellite → adj, verb → verb, proper noun → name.
  - Take the first match in the order verb, noun, adj, name.
  - If that lemma has no table but is an alternative or form of a lemma with one (πάω → πηγαίνω), show that table with the lemma under the title.
- **Layout**: the full grid when it fits (iPad, landscape), two tenses per band when that fits, otherwise one tense per block (narrow screens, accessibility text sizes).
- **Arabic**: the table is mirrored, so the pronoun column is on the right. Greek forms still read left to right.
- **VoiceOver** reads each cell as "column, row, form": "aorist, εγώ, έγραψα", "genitive, singular, σπιτιού", "aorist, εγώ, no form". Greek parts are spoken with the Greek voice.
- A footer under the table reads "Forms: Wiktionary, CC BY-SA 4.0".

### Credits

Credits gains the line "Word forms: Wiktionary contributors, via kaikki.org (CC BY-SA 4.0)" in all 5 languages. The dictionary file stores the source, version and license as a `data_source` row (#129).

### Decisions on record

- 2026-10-22 (Kirill): forms for all Greek lemmas (~26k, ~23 MB), not only the most frequent.
- 2026-10-22 (Kirill): verb tables show the main forms by default; "All forms" shows the passive, να-forms, perfect, pluperfect, future perfect and participles.
- 2026-10-22 (Kirill, #143): English uses a Swift port of WordNet morphy plus WordNet's exception lists, not a Wiktionary English table.
- 2026-10-28 (Kirill): the verb table's main columns follow grammar books: Present, Imperfect, Aorist, Future. "Future" is future simple (θα γράψω); future continuous (θα γράφω) is under "All forms".
- 2026-10-28 (Kirill): an English irregular form is captioned "form of go", because morphy does not tell the past from the participle.
- Interface languages en, ru, es, ar (RTL), el; Wiktionary is credited (#136).

### Out of scope

Russian and Spanish forms. English inflection tables. Articles in noun tables. Highlighting the searched cell. Tables for imported dictionaries. Tables for pronouns, articles and numerals: their forms are searchable, but they get no table. Hand-written paradigms for Wiktionary gaps: gaps are fixed upstream in Wiktionary, and the next snapshot picks them up.

## Design

### Dependency on #129

E2 follows #129's rules for static data ("Adding static data" in [0129](0129-dictionary-file.md)). The names it shares:

| #129 name | E2 use |
|---|---|
| `dictionaries.sqlite`, built by `Scripts/build_dictionaries.py` | Every E2 table lives in this file. E2 adds no user-database table and no migration |
| `STEPS` in `build_dictionaries.py`; a step is `Scripts/build_<area>.py` with `SCHEMA` and `build(conn, cache_dir)`, run after the dictionaries | Two steps: `build_forms.py` (#141) and `build_morphy.py` (#143). They create and fill only their own tables, plus the forms' `data_source` row, and only read `entries`. They never touch the FTS index or `dict_metadata` |
| The file is attached read-only and immutable as `dict` on the user-database pool | All E2 SQL says `dict.lemma`, `dict.form_lookup`, `dict.paradigm`, `dict.tagset`, `dict.morphy_exception`, `dict.morphy_lemma`, `dict.data_source` |
| `data_source` (`id`, `kind`, `display_name`, `version`, `license`, `url`) | One row: the Wiktionary forms. Never a `dict_metadata` row, which would appear as a dictionary in Dictionary Order |
| `Scripts/inputs.json` (immutable URL and sha256 of every input, verified before use) | The Greek snapshot and the frequency list are pinned there. WordNet's pin comes from #140 |
| `user_version` and `DictionaryFile.formatVersion` | The PR that registers the E2 steps bumps both |
| User data points at static data only by text key | E2 stores nothing in the user database; History keeps the opened row's `(source, word)`. A lemma's text key is `(lang, word, pos)`, unique in `lemma`. Later epics (#130, #132) use it, never `lemma.id` |
| Search: one SQL over `dict.entries_fts`, plus a `UNION ALL` branch over `imported_fts` when an imported source is enabled | The lemma-row query follows the same rule |
| `SearchProbeTests` and the golden file `search-probe-1.4.0.json` | Stays green with the lemma step on. None of the probes named in 0129 gains lemma rows (checked with the prototype: `house`, `the`, `comer`, `casa`, `γράφω`, `γραφω`, `νερο`; `a` is too short). A probe that does is an intended change and its golden list is regenerated and reviewed |

**Before #129 lands**, #141 runs standalone: `python3 Scripts/build_forms.py --standalone <dir>/forms.sqlite --headwords DictApp/DictApp/Resources/dictionaries.sqlite` applies `SCHEMA`, runs `build()` and reads the QA report's headwords from the dictionary file (the 1.4 seed's rows; #140 renamed the seed). In the dictionary build the step reads them from `entries`. #142–#144 start once `dictionaries.sqlite` exists, following the epic's ticket order.

### Data

These tables live in `dictionaries.sqlite`. Size budgets: Greek tables ≤ 25 MB (24.1 MB as built by #141, 1.7 MB of it the two `lemma` indexes), morphy ≤ 1.5 MB (measured 1.3 MB). Gzip compresses them to 6.7 MB and 0.6 MB, roughly the growth of the App Store download. The build prints each table's size (`dbstat`), as #129 requires.

| Table | Columns | Rows (#141 build; morphy measured) |
|---|---|---|
| `lemma` | `id INTEGER PRIMARY KEY`, `lang` (`ell`), `word` (NFC), `word_normalized` (`normalize_greek(word)`), `pos` (Wiktextract POS: verb, noun, adj, adv, name, pron, article, …). `UNIQUE (lang, word, pos)`, the text key. Index on `word_normalized` | 27,350 |
| `tagset` | `id INTEGER PRIMARY KEY`, `tags` (Wiktextract tags, sorted, space-separated, UNIQUE) | 970 |
| `paradigm` | `lemma_id`, `ord` (table order), `form` (NFC, one word), `tagset_id`. `PRIMARY KEY (lemma_id, ord) WITHOUT ROWID` | 390,598 |
| `form_lookup` | `form_norm`, `lemma_id`, `tagset_id` (the first cell in table order with that key). `PRIMARY KEY (form_norm, lemma_id) WITHOUT ROWID` | 247,476 |
| `morphy_exception` | `form`, `pos` (n, v, a, r), `base`. `PRIMARY KEY (form, pos, base) WITHOUT ROWID` | 6,053 |
| `morphy_lemma` | `word PRIMARY KEY` (single-word WordNet lemmas), `pos_mask` (1 noun, 2 verb, 4 adj, 8 adv). `WITHOUT ROWID` | 77,898 |
| `data_source` (#129's table) | Row `wiktionary-ell-forms`, kind `word_forms`, "Wiktionary (Greek word forms)", version `enwiktionary 2026-10-01`, CC BY-SA 4.0, `https://kaikki.org/dictionary/`. Morphy adds no row: its data is WordNet's, already credited as the `wordnet` dictionary | 1 |

- Every lookup goes through the primary-key prefix `form_norm = ?`. In the prototype, a lookup that missed the key's first column scanned the table and made search 6× slower. #129 runs no `ANALYZE`, so the plan stays the primary key.
- Periphrastic forms (θα, να, έχω, είχα, έχοντας + form) are generated by the app (see "Tables"). They are never stored.

### Pipeline: Greek forms (#141)

**Source and pin**
- Input: kaikki.org's raw Wiktextract dump of the English Wiktionary, `https://kaikki.org/dictionary/raw-wiktextract-data.jsonl.gz`. The per-language files are marked deprecated. Current dump: enwiktionary 2026-10-01, 3,082,185,963 bytes, SHA-256 `784574cc…ec29b2d`. Streaming it took 12 min (11,121,531 lines).
- The build keeps lines whose `lang_code` is `el`: 85,425 entries, the same tables as the per-language file (measured).
- kaikki.org keeps only its latest dump, so a URL plus hash cannot pin it. The filtered subset is the pin: `Scripts/data/kaikki-el-20261001.jsonl.gz`, 19.1 MB in Git LFS, added once per snapshot (a dictionary rebuild adds ~130 MB). `Scripts/inputs.json` records the dump URL, date and SHA-256 together with the subset's own SHA-256, and the step checks the subset before use. The step works offline.
- `build_forms.py --refresh` streams the current dump and writes a new dated subset and its `inputs.json` entry. A refresh is a reviewed PR of its own.

**Steps** (`build(conn, cache_dir)` in `Scripts/build_forms.py`; it imports `normalize_greek` from [build_greek.py](../../Scripts/build_greek.py) and has no folding of its own)
1. **Lemma pages.** An entry is a lemma when at least one sense has no `form_of`/`alt_of` and no "… of X" gloss. A sense about a periphrastic form ("θα κάνεις: second-person singular perfective future of κάνω") is such a gloss and adds no link. One lemma per (word, pos), ordered by (word, pos), so ids are stable for a given snapshot.
2. **Cells.** Keep table cells, i.e. forms with a `source`. First:
   - a cell with variants joined by " - " (contracted verbs: `θυμάμαι - θυμούμαι`, `οδηγώ - οδηγάω`) gives one cell per variant: 1,088 cells in 63 lemmas;
   - a trailing parenthesised note (`κάνω (κάμνω →)`, `μιλάς (μιλείς → ομιλώ)`) and footnote marks (`έμπαινε²`, `θέλουν² (θένε)`) are stripped: 131 cells in 96 lemmas. A cell that is only a note stays multi-word.

   Then drop:
   - meta rows (`romanization`, `table-tags`, `inflection-template`, `class`);
   - placeholders and non-Greek strings (`-`, `‑η`, Latin letters such as `Αναξιμένoυς`, `➤`): 10,687 cells;
   - multi-word cells (Wiktionary's partial `θα γράφω` rows and prose): 11,835;
   - spellings no Greek word has, left by template errors: two accents (`γόνιμός`, `εκστρατεύόμαστε`; acute, grave and circumflex count, breathings and the diaeresis do not), 341 cells in 40 lemmas; a final sigma inside the word (`άφυλλοςος`, the whole word given as the stem), 367 in 15;
   - cells tagged `error-*` (220) or single-word `future` (315).
   No length filter: `δω` (dependent of βλέπω) is real.
3. **Table guards.**
   - Pronoun tables that mix persons are dropped. They are Wiktionary's shared personal-pronoun template, which made `σας → τα`.
   - **Another word's table.** A table none of whose cells is the headword or begins with its stem (the folded headword without its last two letters, four for -μαι: θυμάμαι → θυμ) is dropped. Wiktionary declined another word there (κρεατομηχανή held μηχανή's forms, υπερβασίλειο αυτοκρατορία's, κολοβός αναληπτικός's) or gave the template no stem (αισώπειος: ος, α, ου): 40 tables, 571 cells, all listed in the QA report. A suppletive table holds its headword, so it stays (βλέπω: είδα, δω).
   - **Bare endings.** A cell that is exactly the ending other tables give the same slot (the same tags) after their stem, and does not begin with its headword's first letter, is dropped: σαλπάρω (εί, ούν, ηκα, όμαστε), διαβαίνω (ανε), αρχαΐζων (ούσης, όντων), αιθεροβάμων (όνων), συνθέτω (όμαστε): 37 cells in 5 lemmas. A stem of one letter or none is not checked, as its forms are almost endings themselves (είμαι: όντας); nor is a form that begins like its headword (αφήνω: άσε).
   - Checked by hand: no top-500 verb, noun or adjective loses a table; the suppletive forms stay (πήγα, είδα, δω, είπα, έφαγα, ήρθα, έλα, βγήκα, μπήκα, ανέβηκα, ήπια).
4. **Links.** These turn non-lemma pages into lookup rows with their sense tags:
   - `form_of` (έγραψα → γράφω);
   - `alt_of` (αγαπώ → αγαπάω, tag `alternative`);
   - a gloss regex for pages without markup, "first-person singular dependent active of πηγαίνω and πάω" (465 links); its words are mapped to tags, and unknown words are dropped.
   Targets that are themselves form pages are followed for up to 2 steps. Multi-word forms and lemmas never enter `form_lookup`. A `form_of` or `alt_of` sense tagged `error-*` or single-word `future` gives no link, as such cells give no row (γάτος → γάτα, `error-lua-exec`; πέρδεσαι, "present/future of πέρδομαι"): 26 senses. A link without an aspect tag takes the one its gloss names ("simple past" → perfective, "imperfect" → imperfective: μετέθεσα → μεταθέτω is perfective, as #142 captions need): 5,232 links.
5. **Stoplist.** A curated list in the script (articles, conjunctions, particles, prepositions, clitic pronouns: ο, η, το, του, της, τον, αν, όταν, είτε, και, να, θα, ας, δεν, μην, σε, με, για, από, μου, σου, …) is compared exactly (NFC, lowercase, never folded). A stoplisted form is dropped from any verb, noun, adj or adv paradigm or link unless it is that lemma's own headword. It runs before the bare-ending check. Measured: 17 rows (ο@καλύπτω, αν@διαβαίνω, όταν/είτε@σαλπάρω, θα→έχω, …); the allowlist re-admits 4 of them, so 13 are dropped. αισώπειος's 7 went with its table (step 3).
   - `Scripts/data/forms-allowlist.tsv` re-admits reviewed false hits, e.g. `παρά` as a form of παράς.
   - Folded matching is wrong here: it would block κάνεις → κάνω (κανείς) and έλα → έρχομαι.
6. **Lookup.** `form_norm = normalize_greek(form)` for every kept cell, head form and link. The first cell in table order sets the caption tagset; a key with no cell takes the first link's tags, and a head form alone takes the empty tag set.
7. **Credit.** Write the `data_source` row (see Data). Every insert runs in sorted order and nothing stores a timestamp, so the file stays byte-identical across builds (#129).

**QA report** (`Scripts/reports/forms-qa.md`, rewritten on every build and committed with the dictionary file, so the PR diff shows what changed)
- Snapshot date and SHA-256 values; counts of lemmas (by pos), tables, cells, lookup keys, ambiguous keys and tagsets.
- Junk caught per rule: every stoplist hit, allowlist use, table of another word and bare ending in full, samples of the rest. Unresolved link targets (measured: 388) with the top 50.
- Coverage and findability, with the gates below.
- Size of the forms tables, and a SHA-256 of each table's rows in key order.

**Coverage metric.** It uses [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) `content/2018/el/el_50k.txt` at commit `072bbed2` (OpenSubtitles 2018, CC BY-SA 4.0), pinned in `inputs.json` (SHA-256 `7ec8f6de…`) and downloaded to `cache_dir`. The list is a build input for the QA report only and is not shipped.
- Tokens are lowercased, NFC-normalised and folded.
- **Findable** (top 5,000): the token is a headword of `freedict-ell-eng` or `wordnet-ell-eng`, or `form_lookup` maps it to a lemma that is.
- **Top-500 verbs and nouns**: each of the 50,000 tokens adds its count to every lemma it maps to (via `form_lookup`, or itself as a lemma). Lemmas are ranked within each pos, ties broken by word.
- **Covered**: the lemma has a table (a verb has at least one finite cell with a person tag; a noun or adjective has at least two case cells), or its own headword maps to a lemma of the same pos that has one (πάω → πηγαίνω).

| Gate (`build()` raises, so `build_dictionaries.py` fails) | Measured |
|---|---|
| Top-500 verbs covered ≥ 95% | 96.4% (437 own table, 45 via link; misses are mostly participles tagged as verbs: μεθυσμένος, καταραμένος; and gaps: μεγαλώνω, αναλαμβάνω) |
| Top-500 nouns covered ≥ 90% | 95.4% (misses: indeclinables ραντεβού, πάρτι; homographs ναι, όχι) |
| Top-5,000 findable ≥ 87% | 89.2% (headword 38.9%, via forms 50.3%, lemma missing from the dictionaries 4.4%, unknown 5.5%: names, OCR noise such as `vα`, clipped forms; not Greek 0.9%) |
| No stoplisted form maps to a verb | 0 after the filter |
| Forms tables ≤ 25 MB | 24.1 MB |

Top-500 adjectives (97.0%) are reported, not gated.

**Reproducibility and checks**
- `python3 Scripts/build_forms.py --self-check` runs offline on `Scripts/fixtures/kaikki-el-sample.jsonl`, 27 real lines (γράφω, έγραψα, ξέρεις, both πάω pages, αγαπώ, καλύπτω, σαλπάρω, διαβαίνω, the pronoun τα, σπίτι, καλός, βλέπω/δω, κάνω, θυμάμαι, μεταθέτω/μετέθεσα, γόνιμος, κρεατομηχανή, αισώπειος). It builds them twice, requires identical table hashes and checks the cases in the test plan. It follows the `build_greek.py` self-check pattern.
- On the real pin, `build_dictionaries.py --verify` (#140) proves the whole file byte-identical. Before #140 exists, two `--standalone` builds must give equal table hashes in the report.

### Morphy (#143)

- **Data**: the `build_morphy.py` step reads WordNet 3.0 (`index.*` and `*.exc`) from the NLTK corpus the dictionary build already downloads and #140 pins. Same license as `wordnet`. `morphy_lemma` is needed because the `wordnet` rows' `pos` column comes from NLTK synsets and already lists morphy's guesses (`running` shows "verb"). Checking candidates against any headword added 170 wrong bases in the English top 5,000 (news → new, mother → moth).
- **Algorithm** (`Morphy`, pure Swift, the WordNet 3.0 morphy):
  0. Lowercase the token (`lowercased()`, which ignores the locale).
  1. Exception candidates from `morphy_exception` (went → go; better → good, well).
  2. For each pos without an exception, the detachment rules:
     - noun: s→, ses→s, xes→x, zes→z, ches→ch, shes→sh, men→man, ies→y;
     - verb: s→, ies→y, es→e, es→, ed→e, ed→, ing→e, ing→;
     - adj: er→, est→, er→e, est→e.
  3. Keep a rule result only if `morphy_lemma` has it for that pos.
  4. Drop the query itself and repeated bases. Order: exceptions, then verb, noun, adj, adv.
- **Noise guard**: rule results for nouns and adjectives need a base of 3+ letters. This removes was → wa, as → a, us → u, has → ha and keeps goes → go. Measured on the English top 5,000: 1,354 tokens get a base, 209 of them from exceptions.
- **Caption**: noun → "plural"; adj/adv ending in -er → "comparative", in -est → "superlative"; verb ending in -ing → "-ing form"; everything else → "form" ("form of go"). Morphy does not tell the past from the participle (Decisions on record).

### Search path (#142, #143)

The change goes into `DatabaseService.search` and `searchPreferred` as #138 leaves them, inside the same read:

1. **Base query.** #138's query with the same ranking and one more output column, `is_exact`: the existing `word_normalized = key COLLATE NOCASE` test, which today is only an ORDER BY term.
2. **Candidates.**
   - Greek: `SELECT … FROM dict.form_lookup JOIN dict.lemma JOIN dict.tagset WHERE form_norm = Search.foldGreek(token)`, minus lemmas whose `word_normalized` equals the key, ordered verb, noun, adj, others, then by word. No cap here: the lemma-row query's LIMIT 10 applies after the enabled-source filter.
   - English: one query on `dict.morphy_exception` and one on `dict.morphy_lemma` (an `IN` list of the rule outputs), then `Morphy`.
3. **Lemma rows.** One query of the base query's shape: an FTS column filter `{word_normalized} : ("γραφω" OR …)` plus `word_normalized COLLATE NOCASE IN (…)` over `dict.entries_fts`, with #138's imported branch when an imported source is enabled. Imported rows keep `word_normalized = word`, so that branch also matches each lemma's own word (γράφω as well as γραφω). Enabled sources only, LIMIT 10, ordered by candidate, then rank. The column filter uses the FTS index; a plain `word_normalized = ?` would scan, because the column has no index.
4. **Merge** with the pure `Search.mergeLemmaBucket(ranked:lemmaRows:limit:)`: exact rows, then lemma rows not already present, then the remaining base rows, cut to `limit`.
   - Relevance mode: the limit is 50.
   - Preferred mode: one merge per pair bucket with `topN`, before the tail query, so the tail excludes the merged ids. `Search.assemble` then works as today.
   - Lemma rows from sources outside every pair group (imports not yet in the order) are merged into the relevance tail the same way, with the tail's limit.
5. **Result type.** `SearchResult { entry: DictionaryEntry; formMatch: FormMatch? }` replaces `[DictionaryEntry]` in `SearchViewModel.results`; its identity is the entry id, unique across both stores (#129). `FormMatch` holds the lemma word and either a tag set (Greek) or a morphy pos, rule and suffix (English). Nothing of it is persisted.

**Caption.** `FormCaption.text(for:locale:)` is pure. It resolves its strings through the per-locale bundle, as `SettingsViewModel.localizedString(_:locale:)` does.
- Greek labels, joined with spaces:
  - finite verbs: tense or mood (present, imperfect, aorist, dependent, imperative continuous/simple), then "passive" if tagged, then person-number (1sg … 3pl);
  - nonfinite: participle or aorist infinitive;
  - nominals: comparative/superlative if tagged, then case, number, and gender for adjectives;
  - `alternative` → "alternative form"; nothing recognised → "form".
- The result goes into the format `forms.caption` ("%1$@ of %2$@").
- In Arabic the caption starts with U+200F, and the Greek lemma is wrapped in FSI…PDI, as in #119.
- VoiceOver reads the person as the Greek pronoun ("aorist, εγώ, of γράφω"), the same words as in the tables.

**Performance.** Measured on the 1.4.0 seed with the prototype tables attached as a second schema (#129's layout), 17 probes, median of 5 runs: 33.1 ms without the lemma step, 31.8 ms with it, i.e. within noise. Prefix keystrokes cost one primary-key probe that finds nothing. Gate: on #129's probe set plus the inflected probes, search with the lemma step is at most 10% slower than the 1.4.0 baseline, measured as #129 measures (iPhone 15 Pro simulator, iOS 17.5, median of 3, and a device).

### Tables (#144)

- **Loading.** `DatabaseService.inflection(for: DictionaryEntry) -> LemmaParadigm?` picks the lemma by the "Which table" rule and returns its cells (form plus tag set). `DefinitionViewModel` publishes it. Entries of other sources skip the query.
- **Slots.** `ParadigmLayout` is pure. It maps cells to slots by tag subsets:
  - voice: `passive` → passive, otherwise active;
  - persons: first/second/third-person × singular/plural;
  - present: `present indicative`, not `dependent`;
  - imperfect: `imperfect`;
  - aorist: `past perfective`;
  - dependent: `dependent`;
  - imperative continuous/simple: `imperative` with `imperfective`/`perfective`, 2sg and 2pl;
  - aorist infinitive: `infinitive-aorist`;
  - participles: `participle` with `present`/`past`, nominative masculine singular only;
  - nominals: case × number (× gender);
  - adjective degrees: `comparative` and `superlative`.
  Cells tagged `rare`, `archaic` or `dated` are hidden; cells matching no slot are not shown.
- **Generated forms**, one per variant of the source cell:
  - future continuous: θα + present; future simple: θα + dependent;
  - subjunctive: να + present (continuous), να + dependent (simple);
  - perfect: έχω/έχεις/έχει/έχουμε/έχετε/έχουν + aorist infinitive of the same voice;
  - pluperfect: είχα/είχες/είχε/είχαμε/είχατε/είχαν + the same infinitive;
  - future perfect: θα + the perfect;
  - perfect participle: έχοντας + infinitive.
  The auxiliaries are constants in code: fixed grammar, not data.
- **Model.** `InflectionTable` → sections (title, `isMain`) → columns and rows → cells (forms, accessibility label, id). Sections, columns and rows that end up empty are dropped.
- **Views.** `InflectionTableView` uses `ViewThatFits(in: .horizontal)` over three renderings of the same model: a full `Grid`, bands of two columns, and one block per column. Each data cell is one accessibility element with the composed label, and header cells are hidden from VoiceOver. The section title has the `.isHeader` trait. Greek runs carry the `el` language attribute. Layout uses leading/trailing only, so RTL mirrors itself.
- **Pronouns** (εγώ, εσύ, αυτός, εμείς, εσείς, αυτοί) are Greek constants and are not translated.
- **Identifiers**: `inflection_table`, `inflection_all_forms_button`, cells `inflection_cell_<voice>_<slot>_<person>` (e.g. `inflection_cell_active_aorist_1sg`) or `inflection_cell_<case>_<number>[_<gender>]`, `form_caption` on the Search row, `credits_wiktionary`.

**New catalog keys** (about 45, all 5 languages, written by the implementing agent; `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage` covers them):
- `forms.section.conjugation`, `forms.section.declension`, `forms.button.allForms`, `forms.button.mainForms`, `forms.source`, `forms.caption`;
- tenses: present, imperfect, aorist, future, futureContinuous, dependent, perfect, pluperfect, futurePerfect;
- moods and aspects: subjunctive, imperative, continuous, simple;
- voices: active, passive;
- nonfinite: participle, infinitive;
- 4 cases, 2 numbers, 3 genders, 2 degrees, 6 person-number abbreviations;
- `forms.alternative`, `forms.form`, `forms.ingForm`, `forms.a11y.noForm`;
- `credits.dataSources.wiktionary`.

### Code map

| Path | Change |
|---|---|
| `Scripts/build_forms.py`, `Scripts/build_morphy.py` | New steps (#141, #143), registered in `STEPS` of `build_dictionaries.py`; `build_forms.py` also runs `--standalone` and `--self-check` |
| `Scripts/inputs.json`, `Scripts/inputs.py` | Entries for the Greek snapshot (a committed file, checked by `inputs.committed()`) and the frequency list |
| `Scripts/data/kaikki-el-20261001.jsonl.gz` (LFS, `Scripts/data/*.jsonl.gz` in `.gitattributes`), `Scripts/data/forms-allowlist.tsv`, `Scripts/fixtures/kaikki-el-sample.jsonl`, `Scripts/reports/forms-qa.md` | New |
| `DictApp/DictApp/Resources/dictionaries.sqlite` | Rebuilt with the E2 tables; `user_version` and `DictionaryFile.formatVersion` bumped in the same PR |
| `DictApp/DictApp/Services/WordForms.swift` | New, pure: `Morphy`, `FormMatch`, `FormCaption`, `ParadigmLayout`, `InflectionTable` |
| `DictApp/DictApp/Services/DatabaseService.swift` | Lemma step in `search` and `searchPreferred`, `Search.mergeLemmaBucket`, `inflection(for:)` |
| `DictApp/DictApp/Models/Models.swift` | `SearchResult` |
| `DictApp/DictApp/ViewModels/SearchViewModel.swift`, `DictApp/DictApp/ViewModels/DefinitionViewModel.swift` | `[SearchResult]`; the published inflection table |
| `DictApp/DictApp/Views/SearchView.swift` | Caption line in `EntryRow` |
| `DictApp/DictApp/Views/InflectionTableView.swift` | New |
| `DictApp/DictApp/Views/DefinitionView.swift`, `DictApp/DictApp/Views/CreditsView.swift` | Table section; Wiktionary line |
| `DictApp/DictApp/Resources/Localizable.xcstrings` | The keys above |

The app target lists its files explicitly, so Kirill adds the two new Swift files to it in the Xcode GUI; the developer never edits `project.pbxproj` by text.

Layering: SQL stays in `DatabaseService` and always qualifies `dict.`. Morphy, captions, slots and generated forms are pure and unit-tested without a database. Views only render the `InflectionTable` and `SearchResult` they are given.

## Test plan

Unit classes go in the `DictAppTests` target. `WordForms*` classes that touch SQL read the real bundled `dictionaries.sqlite`; tests that need made-up rows use #129's `TestDictionary.make(rows:)` and `setup(userPath:dictionaryURL:)`. UI suites run on the four-simulator matrix (iPhone and iPad, iOS 17.5 and 26.4), one suite per run.

| Acceptance criterion | Test |
|---|---|
| #141, #136: ≥ 95% of top-500 verbs and ≥ 90% of top-500 nouns have a paradigm | QA gate in `build_forms.py` (build fails below it); figures in `forms-qa.md` |
| #141, #136: closed-class words (ο, αν, όταν, …) are not forms of any verb | `--self-check` (ο ∉ καλύπτω, αν ∉ διαβαίνω, όταν/είτε ∉ σαλπάρω, θα ↛ έχω, δω kept, κάνεις → κάνω kept); QA gate; `WordFormsLookupTests.testStoplistFormsMapToNoVerb`, `testStoplistedWordsAreNoCellOfAnOpenClassTable` (no stoplisted cell in a verb, noun, adjective or adverb table but the allowlisted παρά) |
| #141: build reproducible from `Scripts/` with the pinned snapshot; QA report written | `--self-check` builds twice with equal table hashes, and checks each rule on made-up pages (empty input, another language, every cell rule, the allowlist file, link depth 2 not 3, unresolved targets, periphrastic senses, line order, notes and " - " variants, misspellings, another word's table, bare endings, link tags and aspects); `build_dictionaries.py --verify` gives the committed sha256 (before #140: two `--standalone` builds with equal hashes in `forms-qa.md`, recorded in the PR); the step fails on a subset whose SHA-256 differs from `inputs.json` |
| #141: the tables, keys and junk filter as specified (one Greek word per value, `normalize_greek` as the app's folding, the pronoun template guard) | `WordFormsLookupTests.testFormsTablesFollowTheSpec` (keys, indexes, `ord` 1…n, no orphan rows), `testLookupKeysAreTheAppsFolding` (`word_normalized` and `form_norm` equal `Search.foldGreek` byte for byte; every cell and head form has its lookup row), `testFormsAreOneGreekWord` (no Latin, digit, space, hyphen or placeholder; no `error-*` or `future` cell; no cell with two accents or a final sigma inside), `testLinksAndPronounGuardOnTheSnapshot` (cell, `form_of`, `alt_of` and gloss links with their caption tags; τα, εγώ, εσύ keep no table; κάνω has its present 1sg, πήγα → πάω is perfective, κρεατομηχανή keeps no table, ει is no form of σαλπάρω) |
| #141: added size ≤ 25 MB; source and license in `dict.data_source` | QA gate (size, `dbstat`); `WordFormsLookupTests.testWiktionaryDataSourceRow` (`dict.data_source` row, CC BY-SA 4.0; no forms row in `dict_metadata`) |
| #142: έγραψα → γράφω, ήταν → είμαι, έχεις → έχω, also εγραψα | `WordFormsSearchTests.testInflectedGreekFindsLemma` (`DatabaseService.search`, lemma rows right after exact rows, caption tags) |
| #142, #136: about 87% of the top-5,000 subtitle words findable | QA gate (≥ 87%, measured 89.1%); `WordFormsSearchTests.testFindabilitySpotList` (20 frequent forms from the list) |
| #142: accent-fold collisions return every lemma | `WordFormsLookupTests.testFoldCollisionReturnsAllLemmas` (κανεισ → κανένας, κάνω) |
| #142: unit tests for the new bucket | `SearchAssembleTests`: lemma rows after exact, before prefix; no duplicates; limit; preferred-mode bucket merge and tail exclusion; no candidates → identical to today |
| #142: caption localized in 5 languages | `FormCaptionTests` (en "aorist 1sg of γράφω", ru, es, el, ar with RLM and isolates; passive; nominal; alternative; unknown tags → "form") |
| #142: UI test for one inflected query | `WordFormsSearchFlowTests.testInflectedGreekQuery` (έγραψα → first row γράφω with `form_caption`) |
| #143: went → go, mice → mouse, better → good and well, running → run, geese → goose | `MorphyTests` (pure, with exception and lemma fixtures: the five cases plus WENT, RUNNING, dogs, boxes, cities, walked; noise: news ↛ new, was → be only, us → none); `WordFormsSearchTests.testEnglishIrregularForms` (real file); `WordFormsSearchFlowTests.testEnglishIrregularQuery` (went) |
| #143: results for base forms unchanged | `WordFormsSearchTests.testBaseFormResultsUnchanged`: #129's probe queries plus go, mouse, good, run, house, γράφω, σπίτι, identical with the lemma step on and off (seam `DatabaseService.lemmaStepEnabled`); `SearchProbeTests.testBundledProbeMatches140` stays green with the step on |
| #142, #143, #136: probe set not slower than 1.4.0 (±10%) | QA, measured as #129 does: #129's probe set plus έγραψα, ήταν, went, mice with the step on, ≤ 1.10 × the 1.4.0 baseline on the iPhone 15 Pro simulator (iOS 17.5) and a device, recorded in History. Unit `WordFormsLookupTests.testLookupsUsePrimaryKey`: `EXPLAIN QUERY PLAN` of the form and morphy lookups shows no `SCAN`, which guards against the measured 6× slowdown |
| #144: γράφω shows present, imperfect, aorist, future, imperative; "All forms" shows the passive and perfect tenses | `ParadigmLayoutTests` (column order, θα γράψω, imperative 2×2, passive section, έχω γράψει, θα έχω γράψει, να-forms, deponent έρχομαι, defective είμαι, impersonal πρέπει, hidden rare forms, variants); `InflectionTableTests.testVerbMainAndAllForms` |
| #144: nouns and adjectives show their tables | `ParadigmLayoutTests` (σπίτι 4×2, καλός 4×3 twice); `InflectionTableTests.testNounAndAdjectiveTables` |
| #144: labels localized in 5 languages; Arabic right to left | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`; `FormLabelTests` (every slot label resolves in en, ru, es, ar, el); `ArabicLocalizationTests.testInflectionTableIsRightToLeft` (Arabic header, pronoun cell right of the form cell); `GreekLocalizationTests.testInflectionLabelsInGreek` |
| #144: VoiceOver reads "aorist, εγώ, έγραψα" | `ParadigmLayoutTests.testCellAccessibilityLabel`; `InflectionTableTests.testCellLabel` (the cell's `label`) |
| #144: UI tests green on iPhone and iPad, iOS 17.5 and 26.4 | The matrix run of `InflectionTableTests`, `WordFormsSearchFlowTests` and the two extended language suites |
| #136: Wiktionary credited | `WordFormsSearchFlowTests.testCreditsListsWiktionary` (`credits_wiktionary`); `testWiktionaryDataSourceRow` |

## Open questions

None.

## History

- 2026-10-27: First draft. Sizes, coverage and timing measured with a prototype of the pipeline on the 2026-10-01 snapshot. Aligned with the names and rules of [0129-dictionary-file.md](0129-dictionary-file.md).
- 2026-10-28: Approved by Kirill. Open questions resolved: verb columns in grammar-book order (Present, Imperfect, Aorist, Future), and "form of go" for English irregular forms.
- 2026-10-28: CodeRabbit review: Morphy lowercases first, `pos` is matched per label, the imported branch also matches a lemma's own word, `better` gives good and well, the candidate cap is gone (LIMIT 10 applies after the enabled filter), and code-map paths start at the repository root.
- 2026-10-28: CodeRabbit review: an ambiguous folded-only lemma match shows no table; the #141 criterion names `dict.data_source`.
- 2026-10-28: CodeRabbit review: in preferred mode, lemma rows from sources outside the order join the relevance tail instead of being dropped.
- 2026-10-29: #140 renamed the seed to `dictionaries.sqlite` (same rows), so the standalone `--headwords` path names it.
- 2026-10-30: #141 pinned the snapshot the research measured: kaikki.org still serves the enwiktionary 2026-10-01 dump (3,082,185,963 bytes, 11,121,531 lines, SHA-256 `784574cc…ec29b2d`). `--refresh` streamed it into `Scripts/data/kaikki-el-20261001.jsonl.gz`: 85,425 lines, 19,081,276 bytes, SHA-256 `9713b588…214dd5`. Its `inputs.json` entry has no `url`: it is keyed by its path in the repository, and `inputs.committed()` checks it. The prototype reproduces the measured numbers on it exactly.
- 2026-10-30: #141 implementation details, no change to the tables or the behaviour. Cells that repeat (form, tags) within a lemma, from two entries of the same (word, pos), are stored once. The caption tagset of a key with no cell comes from the first link, then the head form (empty tag set). A periphrastic sense ("θα κάνεις: …") is not a lemma sense; without this, 9 form pages (κάνεις, ξέρεις, …) became lemmas. Gloss words also map `simple` (simple past) to perfective, `perfect` (perfect participle) to past and `mediopassive` to passive. "Has a table" ignores hidden cells. The size gate measures a `VACUUM INTO` copy, since the build packs its pages only in its final `VACUUM` (27.0 MB before it, 24.0 MB after). `--make-fixture` cuts the self-check fixture from the pin (21 lines, cut to the keys the step reads, 115 KB). The allowlist holds `παρά` → παράς (noun).
- 2026-10-30: #141 measured (Python 3.14.0, SQLite 3.51.2, M3 Max): 27,350 lemmas, 390,197 cells, 246,836 lookup rows (236,112 keys, 9,913 ambiguous), 984 tag sets, 388 unresolved link targets, 20 stoplist hits. Gates: top-500 verbs 96.2% (437 own table, 44 via link), nouns 95.4%, adjectives 97.0%, top-5,000 findable 89.1%, 0 stoplisted forms on a verb. The forms tables take 24,018,944 bytes (`paradigm` 13.0 MB, `form_lookup` 7.8 MB, `lemma` with its two indexes 3.2 MB, `tagset` 0.1 MB), against the prototype's 22.5 MB, which had no `lemma` index. `dictionaries.sqlite` grows from 126,050,304 to 150,069,248 bytes, with `entries` and `entries_fts` unchanged, `user_version` 2, SHA-256 `46a68e23…ff56e5505`. The build takes 32 s with the inputs cached; `--verify` and two `--standalone` builds were byte-identical, also under another `PYTHONHASHSEED`. A subset whose SHA-256 differs from its pin fails the step.
- 2026-10-30 (QA): #141 results. A fresh venv from `Scripts/requirements.txt` and an empty cache downloaded 66.2 MB (the 10 pinned files; the subset is committed), and `--verify` rebuilt the file in 44 s (32 s warm), byte-identical to the committed one (`46a68e23…ff56e5505`), also under `PYTHONHASHSEED=7`; `forms-qa.md` came out unchanged. An LFS pointer, one changed byte, a missing subset, two pinned subsets, a file without Greek headwords and a failed gate each stop the step; a failed gate keeps the previous file but leaves `dictionaries.sqlite.part` beside it, which Git does not ignore. Recomputed from the built file, apart from the step: top-500 verbs 96.2% (437 own table, 44 linked), nouns 95.4%, adjectives 97.0%, with the same misses; 119 closed-class words map to no verb, and the only stoplisted cell left in an open-class table is the allowlisted παρά. 30 random lookup rows and 34 frequent forms (είναι, ήταν, πήγα, δω, κάνεις, σας, μου, …) map to plausible lemmas. `entries`, `entries_fts` and `dict_metadata` are row-identical to master's; the forms tables take 24,018,944 bytes; `data_source` holds the one Wiktionary row. Fresh install on the iPhone 15 Pro simulator, iOS 17.5: Search on screen 0.26 s after process start (median of 3, three rounds; the #140 build 0.265 s in the same session); app bundle 159,776 KB (Debug, arm64), 23,536 KB over #140's 136,240 KB. Regression: 255 unit tests (1 local-only skip), the 21 UI suites (94 tests) plus the template and 64 launch tests passed on all four simulators at the first run; `FreshInstallTests` sees each query's results 1.4 to 1.6 s after typing. QA added 5 `WordFormsLookupTests` and 16 made-up-page checks to `--self-check` (test plan).
- 2026-10-30 (QA): #141 data findings for Kirill; no gate moves. (1) 111 cells that are one word plus a note (`κάνω (κάμνω →)`, `μιλάς (μιλείς → ομιλώ)`, `θέλουν² (θένε)`) are dropped as multi-word. 82 lemmas lose a cell, among them 31 of the top-500 verbs, 23 of which lose their own present 1sg (κάνω, σκέφτομαι, γυρίζω, κοιτάζω, κλείνω): #144 would show "—" there. Stripping the note and footnote marks before the one-word test keeps them. (2) Wiktionary template errors pass every rule: 341 cells with two accents in 40 lemmas (γόνιμός, αιμομικτικόςή, εκστρατεύόμαστε), bare endings as cells (αισώπειος: ος, α, ου, ων; σαλπάρω: ει, ουν), and tables declined from another word (κρεατομηχανή holds μηχανή's cells, υπερβασίλειο αυτοκρατορία's, κολοβός αναληπτικός's, αττικιστής μιμητής's). With #142, μηχανή (rank 1,039 in the subtitle list) would add κρεατομηχανή and ει (rank 982) σαλπάρω.
- 2026-10-30: #141 fixes QA's data findings before the PR (Kirill: now, so the dictionary file lands in Git LFS once); new rules in Steps 2–4 with their counts. Cells: a trailing note and footnote marks are stripped and " - " variants split, which gives 31 top-500 verbs their headword cell back (18 by the notes: κάνω, σκέφτομαι, γυρίζω; 13 by the split: θυμάμαι, ακολουθώ, οδηγώ); cells with two accents or a final sigma inside are dropped. Tables: another word's table and bare endings are dropped. Links: `error-*` and single-word `future` senses give no link, and a link without an aspect takes its gloss's. Beyond QA's list are the " - " split (the same loss as the notes) and the final-sigma check (the same template error as two accents). Left as they are: 295 cells without an accent in 28 rare lemmas (`ανιμιστικος`; dropping them would also lose their lookup keys, which fold right), about 15 tables built on a wrong stem that pass both checks (`αμετάθετοος`, `χαμόμηλοο`), single stray cells (`απογοητεύστε` in εξολοθρεύω's table) and the Cypriot combining-mark keys. A failed build's `dictionaries.sqlite.part` is ignored by Git (`*.part`).
- 2026-10-30: #141 measured after the fixes: 27,350 lemmas, 390,598 cells, 247,476 lookup rows (236,935 keys, 9,746 ambiguous), 970 tag sets, 388 unresolved link targets, 13 stoplist hits. Against the first build, 66 tables and 1,309 cells are gone, 1,710 cells are new. Top-500: no table lost; the only cell lost is the misspelt κάκιστά (κακός), and γάτα loses the keys of γάτος, whose link is `error-lua-exec`. Gates: verbs 96.4% (437 own table, 45 via link), nouns 95.4%, adjectives 97.0%, findable 89.2%, 0 stoplisted forms on a verb, forms tables 24,051,712 bytes. `dictionaries.sqlite` is 150,102,016 bytes, SHA-256 `b3c7fefc…2ea4f99`; `--verify` rebuilt it byte-identical, also under `PYTHONHASHSEED=7`. 255 unit tests pass (1 local-only skip) on an iPhone 15 Pro simulator, iOS 17.5.
- 2026-10-30 (QA): #141 re-check after the fixes. QA's first-round findings are fixed: no one-word cell with a note is lost (no top-500 verb misses its present 1sg), no cell has two accents or an `error-*` or `future` tag, κρεατομηχανή, υπερβασίλειο, κολοβός, αττικιστής and αισώπειος keep no table, and μηχανή, ει, ε, α no longer reach κρεατομηχανή, σαλπάρω or αισώπειος. Against the first build, a rule explains every lost and gained cell. The 1,601 cells from the " - " split and the 109 from stripped notes are real forms, apart from 12 in καρτερώ's misspelt `καρετερ-` conjugation (the known wrong-stem tables); the 708 misspelt cells and 37 bare endings are template garbage; of the 40 tables of another word only φημίζομαι's was its own (the participle φημισμένος, still a FreeDict headword). γόνιμος keeps only its comparatives, which #144 must not show as the positive grid. The suppletive and frequent forms (είναι, έχω, κάνεις, πήγα, δω, είδα, ήρθα, είπα, έφαγα, ήπια, σας, μου) map as before, and the aspect is right on 20 random links that take it from the gloss and on 12 "imperfect" ones (βαριόσαστε keeps its page's first sense, present). Gates recomputed apart from the step: verbs 96.4%, nouns 95.4%, adjectives 97.0%, findable 89.2%, no closed-class word on a verb, forms tables 24,051,712 bytes; `entries`, `entries_fts` and `dict_metadata` are row-identical to master's. With a fresh venv and an empty cache, `--verify` rebuilt the file byte-identical (`b3c7fefc…2ea4f99`, 68 s), also under `PYTHONHASHSEED=7`, and `forms-qa.md` came out unchanged; `--self-check` passes. QA added a self-check page for a link whose tagged aspect differs from its gloss (13 of 14 mutants of the new rules now fail the self-check; the 14th is equivalent) and 8 assertions to `testLinksAndPronounGuardOnTheSnapshot` (both θυμάμαι variants, a nested note, βλέπω's suppletive cells, αισώπειος, γάτος). 255 unit tests pass (1 local-only skip) on an iPhone 15 Pro simulator, iOS 17.5, with no compiler warnings.
