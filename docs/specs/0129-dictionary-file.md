# Dictionaries as one read-only file

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-10-28 · Epic: #129 · Tickets: #112, #138, #139, #140 · Updated: 2026-10-30

This spec is the #112 design. It replaces the Bundled data, Database, Launch and Imported dictionaries sections of [0000-overview.md](0000-overview.md) once implemented. Order: #138, then #139 and #140.

## Why

- 1.4.0 stores every dictionary twice: `seed.sqlite` in the bundle (134.9 MB) and its unpacked copy in `Application Support/DictApp/dict.sqlite` (~138 MB, measured on a simulated 1.4.0 install). About 275 MB installed, and iCloud backup carries the copy.
- Install and every update unpack rows: 20+ s of CPU (#111 moved it to the background, #108 syncs in place).
- Row ids change when the data is rebuilt, so user data cannot point at them (1.x bookmarks do).
- Every other v2.0.0 epic ships static data (word forms, word lists, grammar, examples) and needs one place for it.

Goal: the app reads its dictionaries straight from one read-only file in the bundle. Everything the user creates lives in a small user database.

## Behaviour

| Situation | 1.4.0 | 2.0.0 |
|---|---|---|
| Fresh install | "Preparing dictionaries… N%" bar, results fill in over 20+ s | Search is ready at once, every dictionary searchable, no bar |
| App update with new dictionary data | Background sync of changed rows | Nothing to do: the new file is the data |
| Upgrade from 1.3.0 or 1.4.0 | — | Search is ready at once. History, My words (former bookmarks) and imported dictionaries appear when the move commits, within about a second. The old database is deleted: Documents & Data drops by ~138 MB |
| Bookmarks tab and star | `bookmarks.entry_id` | Until #158 replaces the tab, both read and write "My words". Former bookmarks are there |
| History row, Recent word on Search | Exact lookup of the word in any source | Opens the entry from the row's stored source (see below) |
| Dictionary Order counts | `COUNT(*)` over all rows | Same numbers, read from metadata |
| Import | Rows join the shared `entries` table | Same UI and formats. A file named like a bundled source adds only the words that source lacks, as in 1.4.0 |
| Search results | — | Identical to 1.4.0 for bundled rows and for exact and prefix matches. An imported row found only through its definition text can rank differently (Decisions) |

### Decisions

- 2026-10-22 (Kirill): bookmarks are removed in 2.0.0. Tabs become Search · Learn · History · Settings. The Definition star becomes "Learn", which adds the word to "My words" and enrols it. 1.x bookmarks migrate into "My words" (#139). #137 is closed (not planned).
- 2026-10-22 (Kirill): learning data, word lists, history and imported dictionaries live in the user database, keyed by a stable text key, never by entry row ids.
- #129, #139: an upgrade from 1.3.0 or 1.4.0 keeps bookmarks (as My words), history, imported dictionaries and preferences.
- 2026-10-27 (Kirill): History reopening a word by exact lookup in any source is a bug. It is fixed in E1 (#138): a History row opens the entry from its stored source, the one its stripe shows.
- 2026-10-28 (Kirill): every dictionary records its headword and definition languages (#208). `dict_metadata` and `imported_sources` have the columns from the start, so #208 needs no migration.
- 2026-10-28 (Kirill): search results are identical to 1.4.0 for bundled rows and for exact and prefix matches. An imported row found only through its definition text is ranked by its own index, so its place can change. Example: `entry` with the JSON fixture puts the fixture rows at places 45–50 in 1.4.0 and below the 50-row cutoff in 2.0.
- 2026-10-28 (Kirill): a History row whose entry is gone shows "not found". There is no lookup in other sources.
- 2026-10-28 (Kirill): where built-in word lists live is decided in E3's spec (#130), not here.
- 2026-10-19 (#111 PM decision 7): the bundled file is never opened through a writable GRDB connection.

### History rows (#138)

A History row and a Recent word on Search resolve like this:
1. The stored `(source, word)`. This also applies when that source is disabled: History records what the user read, and the enabled set only filters Search.
2. If that entry is missing (rows from before 1.3.0 with `source = ''`, a headword dropped by a dictionary update, an imported dictionary that is gone): the existing "not found" view.

## Design

### Files

| File | Where | Written by | Contents |
|---|---|---|---|
| `dictionaries.sqlite` | App bundle, from `DictApp/DictApp/Resources/` (Git LFS) | `Scripts/build_dictionaries.py` only | Bundled dictionaries and every epic's static data |
| `user.sqlite` | `Application Support/DictApp/` | The app | History, My words, imported dictionaries, later learning data |
| `dict.sqlite` (1.x) | `Application Support/DictApp/` | Nobody | Read once by #139, then deleted |

`seed.sqlite` becomes `dictionaries.sqlite` and `build_seed.py` becomes `build_dictionaries.py` (`git mv`), because nothing is seeded any more.

### Connection layout: one pool, dictionary file attached

- `DatabaseService` (still an `actor`) keeps one GRDB `DatabasePool` (WAL) on `user.sqlite`. `Configuration.prepareDatabase` runs on every connection, the writer and each reader, and executes `ATTACH DATABASE 'file:<bundle path>?mode=ro&immutable=1' AS dict` (the path percent-encoded).
- Why ATTACH and not two pools:
  - Search ranks bundled and imported rows in one SQL statement (exact > prefix > FTS rank, one `LIMIT`). `Search.ftsQuery`, `Search.foldGreek` (#87), `Search.assemble` and the `ORDER BY` stay exactly as in 1.4.0. Two pools would need a Swift merge of two ranked lists for every query and every preferred-mode bucket.
  - Later epics join user data with static data in SQL, e.g. the list words not yet enrolled, or the hardest words with their entries.
  - One writer queue, one reader model, one place that opens files.
- Read-only by construction:
  - `mode=ro` makes every write to `dict.*` fail with `SQLITE_READONLY` (measured).
  - `immutable=1` skips locking and change detection. The bundle never changes while the app runs.
  - URI filenames need SQLite's `USE_URI`. Apple builds SQLite with it (checked on the macOS 26 system library), and a unit test proves it on iOS. If iOS lacked it, the fallback is the plain path: the device bundle is read-only anyway.
- The file is in rollback-journal mode (checked in the header), so a read-only open never needs a `-wal` or `-shm` next to it.
- The file is not copied into the container. A one-time copy (an APFS clone, 0.33 s per #111) would add a launch step and a version check, and gain nothing.
- Rules: SQL always qualifies `dict.`. No user table shares a name with a dictionary table (`imported_entries`, not `entries`).

### The #111 cold-start crash

- Seen in #88 QA: `EXC_BREAKPOINT` in GRDB `Database.endReadOnly()` on a `DatabaseQueue.asyncRead` thread, once in ~35 cold iPad launches, while the pre-#111 code read the bundled seed through a writable `DatabaseQueue`.
- Most likely mechanism, from the GRDB 6.29.3 source in use and consistent with the stack: `await queue.read` runs `asyncRead`. It calls `beginReadOnly()` (`PRAGMA query_only = 1`) and, in a `defer`, always calls `endReadOnly()`. If `beginReadOnly()` throws under load, the `defer` still decrements `readOnlyDepth` below zero, and `assert(readOnlyDepth >= 0)` traps in Debug builds.
- 2.0 has no GRDB connection on the bundle at all: the file is attached. Pool readers are `readonly = true` (GRDB sets this), so `beginReadOnly()` and `endReadOnly()` return at once. The pool's writer is used only through `write`.
- Rule: no code opens a `DatabaseQueue` or `DatabasePool` without `readonly = true`, except the user database pool. `importSQLite` already reads its file read-only (#111). The 1.x database is attached to the writer, never opened on its own.

### Dictionary file: `dictionaries.sqlite`

| Table | Contents |
|---|---|
| `entries` | `id`, `word`, `word_normalized`, `definition`, `phonetic`, `pos`, `source`. Unique on `(word COLLATE NOCASE, source)`. No `created_at` (it stamped the build time on every row) |
| `entries_fts` | FTS5 with external content from `entries`, `unicode61 remove_diacritics 2`, as today. No triggers: the file never changes |
| `dict_metadata` | One row per dictionary source: `display_name`, `version`, `license`, `url`, `word_count` (equal to the row count, checked), `description`, `from_lang` and `to_lang` (ISO 639-3, such as `ell` and `eng`; #208). No `built_at`. Dictionaries only: every row is a Dictionary Order source |
| `data_source` | One row per non-dictionary data set (Wiktionary forms, Tatoeba, word lists): `id`, `kind`, `display_name`, `version`, `license`, `url`. Empty in E1. Credits will read it |

- `PRAGMA user_version` is the format version (1 in #140, 2 since #141 added the word-form tables). The app constant `DictionaryFile.formatVersion` must match, and a unit test checks it. The app and the file always ship together, so there is no runtime negotiation.
- No `ANALYZE`: the query plans must stay those measured below.
- Measured on today's data: 126.0 MB, against 134.9 MB for the seed. Dropping `created_at`, `built_at` and the empty `history` and `bookmarks` tables saves 8.8 MB. It returns the same results as the seed on the probe set. Compressed (IPA) size is ~45 MB either way.

#### Adding static data (E2, E3, E6, E7)

1. Write `Scripts/build_<area>.py` with a `SCHEMA` (DDL) and `build(conn, cache_dir)`, and add it to `STEPS` in `build_dictionaries.py`. Steps run after the dictionaries and may read `entries`.
2. Use plain tables and indexes. The app reads them as `dict.<table>`. Tables may join by their own ids inside the file. Anything the user database stores is a text key: an `EntryKey`, a lemma, a list id string.
3. Credits: one `data_source` row per external data set. Never a `dict_metadata` row, which would show up as a dictionary in Dictionary Order.
4. Determinism: insert in a sorted order, write no timestamps, pin every input in `Scripts/inputs.json` (an immutable URL and its sha256, or a file committed in Git LFS when the source keeps no old versions), and verify inputs before use.
5. A changed table shape bumps `user_version` and `DictionaryFile.formatVersion` in the same PR.
6. Each epic states its size budget. The build prints the size of every table (`dbstat`) and the total.
7. One rebuilt file per data PR, after rebasing. LFS already holds ~470 MB of seed versions, and each rebuild adds ~130 MB.

Owners of the DDL: E2 #136 (`lemma`, `form_lookup`, `paradigm`, `tagset`), E3 #130 (built-in word lists, if its spec puts them here), E6 #133 (`grammar_topic`, `grammar_text`, `grammar_link`, #171), E7 #134 (examples).

#### Build (#140)

- `python Scripts/build_dictionaries.py --output DictApp/DictApp/Resources/dictionaries.sqlite` writes the schema, runs the dictionary builders (parsing and row building unchanged; their `dict_metadata` writes drop `built_at` and add `from_lang` and `to_lang`), runs the static steps, rebuilds `entries_fts`, runs the checks, then `VACUUM`.
- Checks that fail the build:
  - `integrity_check` and the FTS `integrity-check`;
  - `word_count` equals the row count of each source, and the `entries` sources equal the `dict_metadata` sources;
  - every `dict_metadata` row has `from_lang` and `to_lang`;
  - `max(entries.id) < 2^40`;
  - journal mode DELETE and `user_version` set.
- The builders keep `INSERT OR IGNORE`, so a repeated headword keeps its first row, as in 1.4.0. The build prints how many rows each builder dropped this way, so a change shows up in review.
- Reproducible: the same pinned inputs and the same SQLite version give a byte-identical file. Measured: building the 2.0 file twice from today's rows gave the same sha256. `--verify` rebuilds into a temp file and compares it with the committed file.
- Inputs to pin: FreeDict picks the newest release online, OpenRussian reads GitHub `master`, and NLTK downloads `wordnet` and `omw-1.4` unversioned. Each becomes an immutable URL: the versioned FreeDict release, and a commit SHA for OpenRussian and `nltk_data`. A URL that can change is not allowed, because a sha256 only detects the change.
- `generate_seed_db.py` and `download_wordnet.py` (legacy, unused) are deleted.

### User database: `user.sqlite`

- A GRDB `DatabaseMigrator` creates the schema. It replaces `Schema.sql`, `inlineSchema`, `applySchema` and `migrate`.
- Migrations are append-only once merged to master. Each epic registers its own, named `<epic>-<n>-<what>`: `129-1-core` here, then e.g. `130-1-word-lists`, `131-1-learning`, `132-1-conjugation`, `166-1-stats`.
- **Stable entry key** (`EntryKey`): `(source, word)`, the source ID and the headword as stored.
  - No disambiguator is needed: both stores keep `(word COLLATE NOCASE, source)` unique through a unique index. A repeated headword keeps its first row, in the build (Build) and on import.
  - A user table that points at an entry has the columns `source` and `word COLLATE NOCASE`.
  - Resolution tries `dict.entries` first, then `imported_entries`.
  - A key that no longer resolves stays stored and shows as unavailable (#137 rule). It is never deleted silently.
  - Source IDs are permanent. Renaming one needs a user database migration.

Migration `129-1-core`:

| Table | Columns | Notes |
|---|---|---|
| `history` | `id`, `word` UNIQUE, `source`, `looked_at` (UTC text) | Same shape as 1.x, so `HistoryItem`, `HistoryTimestamp` and the 100-row list stay |
| `my_words` | `source`, `word COLLATE NOCASE`, `added_at`; PK `(source, word)`, `WITHOUT ROWID` | My words items. E3 decides whether its list model keeps this table or moves the rows in its own migration. E4 enrols every item: cards for all existing rows in its migration, and for each new one on add |
| `imported_entries` | The `entries` columns plus `created_at`; unique on `(word COLLATE NOCASE, source)`; index on `source` | Ids start at 2^40 (a seeded `sqlite_sequence` row) |
| `imported_fts` | FTS5 with external content from `imported_entries`, same tokenizer | Triggers `imported_ai`, `imported_ad`, `imported_au` |
| `imported_sources` | `source` PK, `imported_at`, `from_lang` and `to_lang` (NULL until #208 fills them) | One row per imported dictionary: listing without a scan, room for a future delete |
| `user_meta` | `key` PK, `value` | `legacy_migration` = the completion time |

- **Room for later epics:** own tables in own migrations. They point at entries by `EntryKey`, at lemmas by lemma text and at built-in lists by a text id. Never at `dict.*` row ids, and there are no foreign keys into `dict` (SQLite has none across schemas).
- **Entry ids** stay the in-session identity in Swift: SwiftUI lists, `Search.assemble` and the preferred-mode `NOT IN`. Bundled ids are below 2^40 and imported ids are at or above it, so one `Int64` is unique across both stores. An id is never persisted.
- **Size:** 577 KB with 2,010 imported rows, 100 History rows and 50 My words (measured). 70 KB without imports.

### Queries (#138)

| Operation | 2.0 source |
|---|---|
| `search`, `searchPreferred` | `dict.entries_fts` joined with `dict.entries`. A `UNION ALL` branch over `imported_fts` and `imported_entries` is added only when at least one imported source is enabled (`nil` means all). One `ORDER BY` (exact, prefix, `rank`) and one `LIMIT` over the union |
| `entry(for: EntryKey)` | `dict.entries`, then `imported_entries` |
| `fetchSourceStats` | `dict.dict_metadata.word_count`, plus the `imported_entries` count per source (indexed). No scan of 417k rows |
| `fetchMetadata` | `dict.dict_metadata` |
| History, My words | User database |
| Import | `imported_entries` and `imported_sources`. Rows whose key exists in `dict.entries` are skipped, like `INSERT OR IGNORE` did in 1.4.0 for a file named like a bundled source |

- The ranking SQL is 1.4.0's. An imported row matched through `imported_fts` gets its bm25 score from that small index, not from a shared one, so its place inside the FTS tier can differ from 1.4.0. In 1.4.0 the reverse held: an import shifted the bundled rankings. Exact and prefix matches are unaffected.
- Measured (M3 Max, median of 7 runs):
  - the bundled-only query matches 1.4.0 (`house` 2.1 ms against 2.2 ms, `a` 282 ms against 282 ms);
  - the import branch costs 10 to 15% on the heaviest prefixes (`a` 316 ms, `the` 120 ms against 105 ms), hence it is added only when needed;
  - first open plus first query: 4 to 5 ms.
- Swift changes:
  - `DictionaryEntry` is unchanged (`createdAt` is `nil` for bundled rows), and `DictMetadata.builtAt` goes.
  - `EntryKey` is new. `lookup(word:)` becomes `entry(for:)`.
  - `HistoryDestination(word:)` takes the `HistoryItem`, and Search's Recent words pass the item too.
- Interim bookmarks until #158: `addBookmark`, `removeBookmark`, `isBookmarked` and `fetchBookmarkedEntries` become `addToMyWords`, `removeFromMyWords`, `isInMyWords` and `fetchMyWords` on `EntryKey`. The interim tab skips items that do not resolve.

### Launch

1. `-resetDatabase` (DEBUG) deletes `user.sqlite` and any 1.x `dict.sqlite`, each with its `-wal` and `-shm`, so no legacy data comes back through the migration.
2. `setup()` opens the pool, which attaches `dict`, and runs the migrator. This takes milliseconds.
3. Test hooks: `-resetData` clears history, `my_words` and the preferences. `-clearFixtureImports` deletes the fixture's imported rows and its `imported_sources` row.
4. `normalizeDictionaryPreferences(knownSources:)` runs on the `dict.dict_metadata` sources, as today.
5. If the 1.x `dict.sqlite` exists, the move below starts as a detached utility task. It starts just before the UI shows, so every user-data call from the first frame finds it.
6. `isReady = true`.

There is no unpack, no plan and no progress state.

### 1.x migration (#139)

**Detection.** `Application Support/DictApp/dict.sqlite` exists:
- without the `user_meta.legacy_migration` marker: move, then delete;
- with the marker: the app died after the commit, so only delete.

**Move:** one write on the user database writer.
1. ATTACH the 1.x file as `legacy`, outside the transaction (as the seed ATTACH works today). It is not attached read-only, because SQLite may have to replay its WAL.
2. In one transaction:
   - **Imported dictionaries:** every `legacy.entries` row whose `(source, word COLLATE NOCASE)` is not in `dict.entries` goes into `imported_entries`, with `word_normalized = word` as on import. The triggers fill `imported_fts`. This one rule carries custom imports and imports named like a bundled source, and drops the 1.x copy of the bundled data. Rows of the v1.1.0, v1.2.0, v1.3.0 and v1.4.0 seeds missing from today's data: 0 (measured), so no bundled row turns into an import. A later dictionary update that drops headwords must repeat this check, because 1.x files do not record which rows were imported.
   - **`imported_sources`:** one row per source with at least one moved row, `imported_at` = its earliest `created_at`.
   - **History:** every row. `source` is read only if the column exists; 1.1 and 1.2 lack it, so it becomes `''`. On a word conflict, the newer `looked_at` wins.
   - **My words:** each bookmark becomes its entry's `(source, word)`, with `added_at` = the bookmark's `created_at`, through `INSERT OR IGNORE`.
   - **Marker:** `user_meta.legacy_migration` is set to now.
3. DETACH, then delete `-wal`, `-shm` and `dict.sqlite`, in that order: a kill in between leaves `dict.sqlite`, and its marker makes the next launch finish the delete.

**Crash safety.**
- Killed before the commit: the WAL rolls back, there is no marker and `legacy` is intact. The next launch repeats the move from scratch.
- Killed after the commit: the marker is set, so the next launch only deletes.
- No duplicates: the marker is written in the same transaction, and `INSERT OR IGNORE` and the upserts are a backstop.
- An unreadable 1.x file is logged, kept and retried on every launch. It is never deleted without a committed copy. A failed move still completes: waiting calls go on with the user database alone, and the legacy data appears after a later successful move.
- The move reads only the columns present in every 1.x schema (1.1.0+).

**Timing and UI.**
- 0.23 to 0.36 s on the M3 Max for a full 1.4.0-size database (100 History rows, 50 bookmarks, 2,010 imported rows), measured. Most of it is the key check over 417k legacy rows (188 ms).
- During the move, Search answers from the dictionary file at once. `DatabaseService` methods that touch user data first await the move. So History, the Bookmarks tab and Dictionary Order show their usual loading state until it commits. Then the current query re-runs once (`LegacyMigration.didCommit`), so imported results appear.
- No new progress UI. QA measures the move on a device, with a target under 2 s.

**Preferences.** UserDefaults are not touched. `enabled_sources` and `dictionary_order` hold source IDs, and imported sources keep theirs, so both still apply.

### What is removed

#138 removes the 1.x schema code, the `Bookmark` record and the runtime code of the bundled import, the unpack and the sync, with their UI and tests: once reads come from `dict.*`, that code has nothing to write to. #140 removes the files: the resources (`seed.json`, `Schema.sql`) and the legacy scripts, and it renames the seed (PM, 2026-10-29).

| Area | Removed |
|---|---|
| `DatabaseService` | `prepareBundledSeed`, `registerBundledSources`, `startBundledUnpack`, `runUnpack`, `unpackSource`, `unpackDidFinish`, `waitForBundledUnpack`, `seedIfNeeded`, `syncBundledSources`, `importJSONFallbackIfNeeded`, `unpackFailureAfterInsert`, `applySchema`, `migrate`, `inlineSchema` |
| Types | `BundledUnpackPlan`, `DictionaryUnpackStatus`, `DictionaryDefaults.unpackPriority`, the `Bookmark` record |
| UI | `UnpackProgressBar`, `search.unpacking.title` (5 languages), the `dictionary_unpack_progress` id, `SearchViewModel.unpackFraction`, `displayFraction` and the per-source re-run |
| Resources, scripts | `seed.sqlite`, `Schema.sql`, the `seed.json` fallback, `generate_seed_db.py`, `download_wordnet.py` |
| Launch arguments | `-unpackSourceDelay` |
| Unit tests | `testBundledSync*`, `testSeedIfNeeded*`, `testUnpack*`, `testUpdatePathAddsGreekInBackgroundAndKeepsBookmarks`, `testSearchDuringUnpack`, `testSourceStatsMidUnpackListAllBundledSources`, `testSearchReRunsWhenADictionaryLands`, `testStartBundledUnpackIsSingleFlight`, `testUnpackingTitleIsLocalized`, `testUnreadableBundleLeavesExistingInstallIntact`, `testMigrationFromPreV10SchemaUpgradesAndPreservesData`, `testMigrationIsIdempotent`. `waitForHostAppLaunch` stops waiting for an idle unpack |
| UI tests | `BackgroundUnpackTests`. `TabBarPage.waitForDictionariesReady()` waits for the Search screen only, with a 30 s timeout instead of 120 s |
| Docs | The overview sections listed at the top and `README.md`. `DevelopmentGuide.md` goes in #203; `docs/REMOTE_CI_SETUP.md` stays until CI moves to the new machine (Kirill, 2026-10-27) |

**Xcode project (Kirill, in the Xcode GUI).** The developer never edits `project.pbxproj` by text. #140: add `dictionaries.sqlite` to the app target and remove `seed.sqlite`, `Schema.sql` and the `seed.json` fallback. #139 needs no step: the tests read the 1.x fixtures from the source tree (History, 2026-10-29).

**Test seeding.** Unit tests that insert rows into `entries` use a helper, `TestDictionary.make(rows:)`. It copies the schema of the bundled `dictionaries.sqlite` (from `sqlite_master`) into a temp file. `setup(userPath:dictionaryURL:)` is the seam. The 1.x fixtures sit next to `DictAppTests.swift` and are read through `#filePath`, so they are in no target and never in the app bundle.

### Targets

| Metric | 1.4.0 | 2.0.0 target |
|---|---|---|
| Fresh install, launch to a usable Search (iPhone 15 Pro simulator, iOS 17.5, median of 3; and a device) | Under 5 s (#111), then 20+ s of unpack | Under 2 s, every dictionary searchable |
| Upgrade from 1.4.0, same measure | — | As fast as a fresh install. The background move takes under 2 s on a device |
| Documents & Data without imports | ~138 MB | Under 5 MB |
| App Size | Bundle with the 134.9 MB seed | Bundle with the 126 MB file, plus the E2, E3, E6 and E7 budgets |
| Search, probe set, median | Baseline | Not slower |
| Cold launches without a crash (iPad) | — | 30 of 30 |

## Test plan

Unit tests run in `DictAppTests`; new classes are `DictionaryFileTests`, `UserDatabaseTests`, `LegacyMigrationTests` and `SearchProbeTests`. "QA" rows are measurements on the iPhone 15 Pro simulator (iOS 17.5, median of 3) and on a device, recorded in this spec's History.

The probe set is ~25 queries across en, ru, es, ar and el (`house`, `a`, `the`, `ice cream`, `дом`, `casa`, `comer`, `كتاب`, `ماء`, `γράφω`, `γραφω`, `νερο`, …), in relevance mode plus 3 in preferred mode. The golden file `search-probe-1.4.0.json` holds the top 50 `(source, word)` per query. `Scripts/make_search_probe.py` generates it with the 1.4.0 SQL on a 1.4.0 database built from the `v1.4.0` seed, the way an English-UI install unpacks it. Measured: 25 of 25 lists identical without imports; 24 of 25 with the JSON fixture imported (the exception is the imported-row ranking in Decisions). Any later PR that changes `entries` regenerates the golden file, and the change is reviewed.

| Acceptance criterion | Test |
|---|---|
| #129, #140: first launch to a usable Search in under 2 s, every bundled dictionary searchable at once, no unpack progress | UI `FreshInstallTests.testFreshInstallSearchesEveryPairAtOnce`: `-resetDatabase`, then one word per pair returns results within 2 s of launch. QA: launch time |
| #129, #139, #140: installed size ≈ app bundle + user data, no duplicate copy | Unit `LegacyMigrationTests.testApplicationSupportHoldsOnlyTheUserDatabase` (only `user.sqlite` and its `-wal`/`-shm`, under 5 MB) and `DictionaryFileTests.testDictionaryFileIsNeverCopied` (the host app: no copy of the file in Application Support or Documents, under 5 MB). QA: simulator `du` of the app and data containers; device Settings → iPhone Storage, App Size and Documents & Data |
| #129, #139: upgrade from 1.3.0 and 1.4.0 keeps bookmarks (as My words), history, imported dictionaries and preferences | Unit `LegacyMigrationTests.testMigrates130Fixture`, `testMigrates140Fixture`: every bookmark is a My words key that resolves, history rows and sources are equal, both fixture imports are searchable, `enabled_sources` and `dictionary_order` still apply. Fixtures `legacy-1.3.0.sqlite` and `legacy-1.4.0.sqlite` (under 1 MB each) come from `Scripts/make_legacy_fixtures.py`, which uses each tag's `Schema.sql`, seed subset and migrations plus fixed user data. `testMigratesDatabaseWithoutHistorySource` covers 1.1/1.2 with `legacy-1.2.0.sqlite`. Edge cases: `testImportWithOnlyBundledWordsRegistersNothing`, `testBookmarkOfARowTodaysDataLacksKeepsItsEntry`, `testLegacyRowsWithNullsAndAnOrphanBookmarkMove`, `testHistoryConflictsKeepTheNewerRow`, `testLegacyDatabaseWithoutUserDataIsDeleted`, `testNoLegacyDatabaseStartsNoMove`. A real device database runs only locally: `testMigratesLocalLegacyDatabase` reads `LIBREDICT_LEGACY_DB` (passed as `TEST_RUNNER_LIBREDICT_LEGACY_DB` to `xcodebuild`) and is skipped when it is absent. QA: install a `v1.4.0` build, add data, install 2.0 over it, on the simulator and through TestFlight on a device |
| #129, #138: search identical to 1.4.0 on the probe set (en, ru, es, ar, el), including an imported dictionary | Unit `SearchProbeTests.testBundledProbeMatches140` (exact lists). `testProbeWithFixtureImports`: bundled rows keep the golden order, `qaflux` is first, `json` returns the 10 fixture rows. Existing Greek and Arabic search tests stay as they are |
| #138: importing works and stays searchable after an app update | Unit `testImportSurvivesDictionaryFileReplacement` (import into dictionary file A, swap to file B with reshuffled ids: the import is still found and My words keys resolve), `testImportNamedLikeBundledSourceAddsOnlyMissingWords`, `testPreferredModeRanksImportsInTheirBuckets`. UI `ImportDictionaryTests` unchanged |
| #138: history and learning data are written to the user database only | Unit `testDictionaryFileIsReadOnly` (a write to `dict.*` throws `SQLITE_READONLY`, which also proves URI support on iOS), `testUserWritesLandInUserDatabase` (history, My words, import), `testStarAndBookmarksTabUseMyWords` (the interim star and tab), `testUserSchemaSharesNoTableNameWithTheDictionaryFile` |
| #138: History opens the stored source (Kirill, 2026-10-27) | Unit `testHistoryOpensStoredSource`, `testHistoryOpensDisabledSource`, `testHistoryShowsNotFoundWhenEntryMissing`, `testHistoryShowsNotFoundForEmptySource`. UI `HistoryFlowTests.testHistoryReopensTheDictionaryItWasReadIn`: open "dog" from En–Es · FD ("perro"), then reopen it from History; 1.4.0 showed WordNet. `testRecentWordReopensTheDictionaryItWasReadIn` (a Recent word on Search) |
| #138: unit and UI tests green on iPhone and iPad, iOS 17.5 and 26.4 | The four-simulator regression, per the overview recipe |
| #139: killing the app during the move: the next launch finishes it, nothing lost or duplicated | Unit `testKilledBeforeCommitRetriesWithoutDuplicates` (DEBUG seam `LegacyMigration.failBeforeCommit` throws inside the transaction: user database unchanged and no marker; the second run gives exact counts) and `testKilledAfterCommitOnlyDeletes` (seam `failBeforeDelete`) |
| #139: after the move the old database is gone | Unit `testLegacyFilesDeletedAfterCommit`, `testUnreadableLegacyDatabaseIsKeptAndRetried`, `testZeroByteLegacyFileIsKept` |
| #139: Search usable during and after the move, as fast as on a fresh install | Unit `testSearchDuringMigration` (DEBUG delay seam `LegacyMigration.beforeCopy`: bundled results come back while the move runs, and the move's results appear after the re-run), `testWritesDuringTheMoveLandAfterIt` (History, My words and an import made during the move land after it). QA: upgrade launch against fresh launch, and the move's duration on a device |
| #140: the dictionary file builds reproducibly from `Scripts/` | `build_dictionaries.py --verify` gives the committed sha256, run in the #140 PR and after every data PR. Unit `testDictionaryFileFormat` (`user_version`, journal mode, `word_count` per source, no `built_at` or `created_at`), `testDictionaryFileStructure` (no triggers or `ANALYZE`, the unique `(word COLLATE NOCASE, source)` index, the FTS definition, ids below 2^40), `testSetupFailsWithoutAReadableDictionaryFile` (a missing file or a Git LFS pointer fails setup; nothing is created at the path) |
| #140: no dead code left from import, unpack and sync; tests updated and green | Review: no symbol from "What is removed" remains (`grep` for `unpack`, `BundledUnpack`, `built_at`, `seed.sqlite`). Full regression |
| #112: launch, search speed and installed size measured on the simulator and a device | QA rows above, written into History when #138 and #140 merge. The Mac numbers in this spec model the same SQL |
| #112: no app code merged from the spike | This spec is the spike's output |
| #111 crash rule (no writable GRDB connection on the bundle) | QA: 30 consecutive cold launches on the iPad simulator with no crash report. Review: the rule in "The #111 cold-start crash" |

## Open questions

None.

## History

- 2026-10-27: First version: the #112 design (connection layout, stable key, user database, 1.x migration, removals). Mac measurements: Python 3.14, SQLite 3.51.2, M3 Max, replaying the app's SQL on the shipped seed.
- 2026-10-28: `dict_metadata` and `imported_sources` get `from_lang` and `to_lang` for #208 (Kirill).
- 2026-10-28: Approved by Kirill. Open questions resolved: the imported-row ranking is accepted, a missing History entry shows "not found", and built-in word lists move to E3's spec.
- 2026-10-28: CodeRabbit review: the build prints rows dropped by `INSERT OR IGNORE` (the duplicate check was redundant with the unique index), the legacy-row check covers every 1.x seed, and a failed migration releases the calls waiting for it.
- 2026-10-29 (PM): split between #138 and #140. The dictionary file arrives with #140, so #138 attaches the bundled `seed.sqlite` as `dict` (checked: journal mode DELETE, has `entries_fts`, `word_count` equals the row counts; it lacks `from_lang`, `to_lang` and `user_version`, all #140). With every read on `dict.*`, #138 also removes the runtime unpack, sync and seed code, its UI (the progress bar, its strings and id) and its tests. #140 keeps `build_dictionaries.py`, the rename to `dictionaries.sqlite`, `DictionaryFile.formatVersion`, the removal of `seed.json`, `Schema.sql` and the legacy scripts. Nothing reads a 1.x `dict.sqlite` until #139; no release ships in between.
- 2026-10-29: #138 implementation details. An import adds its `imported_sources` row only when it stored at least one row, so a file named like a bundled source whose words the bundle already has registers nothing (the rule #139 uses). Search wraps its branches in one `SELECT * FROM (…) ORDER BY … LIMIT ?`; with no imported branch SQLite flattens it to the 1.4.0 plan (`EXPLAIN QUERY PLAN`), and 18 probe queries gave identical top-50 lists on the Mac. GRDB's unqualified `PRAGMA journal_mode = WAL` on the writer leaves the immutable `dict` in DELETE mode (checked). `TestDictionary.make(rows:metadata:)` also writes one `dict_metadata` row per source, and the unit-test helper `TestDictionaryFixture` writes a new file and reopens the service when a test adds rows, because an attached file is immutable.
- 2026-10-29 (QA): #138 tests. `search-probe-1.4.0.json` sits next to `DictAppTests.swift`, and `SearchProbeTests` reads it through `#filePath` (the simulator shares the Mac's file system), so the `DictAppTests` target needs no Xcode step; a unit-test run on a device would need it added to the target. `Scripts/make_search_probe.py` writes it: it builds a 1.4.0 database from the `v1.4.0` `Schema.sql` and LFS seed in 1.4.0's English copy order and runs 1.4.0's SQL. The probe is 23 relevance queries (en, ru, es, ar, el) and 3 in preferred mode, and reaches all nine sources. Two DEBUG test seams: `DatabaseService.writeForTesting` runs a closure on the writer, so a test proves every write to `dict.*` fails with `SQLITE_READONLY`; `HistoryDestination.entry(for:)` is the History lookup as a static function the unit tests call.
- 2026-10-29 (QA): results on the simulators. Probe: 26 of 26 lists identical to 1.4.0 on iOS 17.5 and 26.4; with both import fixtures, the bundled rows keep 1.4.0's order in all 26. Launch to a usable Search after `-resetDatabase` (iPhone 15 Pro, iOS 17.5, timed from process start): Search on screen at 0.24 s, median of 3 (0.29 s on the first launch after install), `isReady` at 0.21 s. Data container after that launch: 164 KB (`user.sqlite` with its WAL and SHM). Cold launches on the iPad Pro 11-inch (M4) simulator, iOS 17.5, half of them with `-resetDatabase`: 30 of 30 without a crash report. Device measurements are still to do.
- 2026-10-29: #139 implementation details. The move starts just before `isReady`, not after it (Launch 5 and 6 swapped): every user-data call from the first frame then finds the move, and the unit-test host starts it on its own pool before the tests swap in theirs. The UI shows at the same moment, and the move still runs detached. Every `DatabaseService` method that reads or writes user data awaits it (History, My words, imports, `entry(for:)`, the counts); Search and `fetchMetadata` do not. `imported_sources` gets a row for each `imported_entries` source not registered yet; since #138 those are exactly the moved ones. iOS SQLite leaves the 1.x `-wal` and `-shm` after the DETACH, so the delete takes them first and `dict.sqlite` last. DEBUG seams: `LegacyMigration.failBeforeCommit`, `failBeforeDelete` and the delay seam `beforeCopy`, which runs on the writer inside the transaction.
- 2026-10-29: #139 fixtures and timing. `Scripts/make_legacy_fixtures.py` writes `legacy-1.2.0.sqlite` (the 1.1/1.2 shape), `legacy-1.3.0.sqlite` and `legacy-1.4.0.sqlite` (86 to 209 KB, byte-reproducible) next to `DictAppTests.swift`. `LegacyMigrationTests` reads them through `#filePath`, like the search probe, so the `DictAppTests` target needs no Xcode step; a unit-test run on a device would need them added. `--full PATH` writes a full-size 1.4.0 database for local timing, never committed. iPhone 15 Pro simulator, iOS 17.5: the fixtures move in 1 to 3 ms; the full-size database (137.6 MB, 418,949 rows, 2,003 imported, 100 History rows, 50 bookmarks) in 0.55 s, median of 3, delete included (the same SQL in Python on the M3 Max: 0.22 s). A launch over it took `Application Support/DictApp` from 131 MB to 620 KB. Device measurements are still to do.
- 2026-10-29 (QA): #139 edge cases, eight more `LegacyMigrationTests`. An import named like a bundled source whose words the bundle has (in another case) moves nothing and registers no source; a bookmark or History row on such a word opens the bundled entry. A bundled row that today's data lacks moves as a row of its source, so its bookmark and History row still resolve. NULL phonetic, part of speech and dates move: a missing `created_at` becomes the move's time, a missing `looked_at` stays NULL and sorts last, and a bookmark whose entry is gone is skipped. On a History conflict the newer `looked_at` wins with its source, and a tie keeps the row already there. History, My words and import writes made during the move land after it. No 1.x file starts no move; a 1.x file without user data is deleted with the marker set; a zero-byte file is kept like an unreadable one. `testMigratesLocalLegacyDatabase` on the full-size database: 0.65, 0.67 and 0.94 s, with two UI streams running.
- 2026-10-29 (QA): real upgrades on the iPhone 15 Pro simulator, iOS 17.5. A `v1.4.0` build was filled through its UI and import code: `qa_glossary.json`, `freedict-eng-spa.json` (one of its 4 words is in the bundle), 7 History words from 6 dictionaries, 5 bookmarks on bundled and imported words, Arabic off, English moved last, preferred mode on. This build was then installed over it with `simctl install`. On the first launch Search was on screen 0.23 s after the launch screen (a fresh install: 0.22 s; medians of 3, from screen recordings), and the move took 0.82 s (0.72 to 0.79 s on three repeats). `Application Support/DictApp` went from 148 MB (the 136.6 MB `dict.sqlite` and its WAL) to 188 KB, and the data container from 148 MB to 364 KB. History, Recent words, My words, the imports, the order, the toggles, the pair counts (`eng-spa` 95,320 with the named import) and preferred mode matched 1.4.0; every History row reopened its stored dictionary; the preferences file was unchanged; a relaunch moved nothing. From `v1.3.0` (6 History words, 4 bookmarks): the move took 0.43 s and the data container went from 118 MB to 344 KB, with the same checks. After 1.3.0 the launch normalisation (#92) puts `wordnet-spa-eng` next to `freedict-eng-spa`, and a 1.3.0 explicit enabled set has no Greek sources, so Greek – English is off, as after an update to 1.4.0. Killed 0.35 to 1.0 s after launch, 5 times: each kill came before the commit, and the next launch moved everything once. A committed user database next to the 1.x file (a kill between commit and delete) was only deleted. Device measurements are still to do.
- 2026-10-29 (QA): #139 regression, one suite per run with the app uninstalled in between: 244 unit tests (1 local-only skip) and the 20 UI suites plus the 2 template suites on all four simulators. The iPhones passed at once. On the iPads 8 suites failed their first test (M4: DictionaryInfo, DictionaryOrderRefresh, GreekDictionary, SearchFlow; M5: BookmarkFlow, HistoryFlow, SearchFlow, SearchHighlight) and passed on rerun; 2 more M5 runs never started (the simulator refused to launch the test runner). Cause, from the simulator log: an xcodebuild install hard-links the bundle from a staging folder and removes that link seconds later, here after the app had attached `seed.sqlite`. iOS SQLite then logs "vnode unlinked while in use" and invalidates the file, and every `dict.*` read that misses the page cache fails with `disk I/O error` until the pool is reopened. A unit-test probe reproduced it on iOS 17.5 (a second link removed under an attached read-only file; a new pool reads the file). `simctl install` does not hard-link. Not caused by #139; whether a device install or update can do the same is an open question for Kirill, since the app reads the bundled file in place (#138).
- 2026-10-29: #140 implementation details. `Scripts/inputs.json` maps each input's path in the cache to its immutable URL and sha256, and `Scripts/inputs.py` downloads and verifies it (stdlib only; `requests` is gone). The pins are the inputs of the 1.4.0 seed: `nltk_data` commit `e2e0798` (the last change to `wordnet.zip` and `omw-1.4.zip`; both byte-identical to the zips that built the seed), OpenRussian `Badestrand/russian-dictionary` commit `50e210c` (its `master` since 2021), and the FreeDict releases eng-spa and ell-eng 2025.11.23 and eng-ell 0.1.1. NLTK reads only the pinned zips, never `~/nltk_data` or `nltk.download()`. `Scripts/requirements.txt` pins NLTK 3.9.4 and defusedxml 0.7.1, because NLTK's reader shapes the WordNet rows. `entries` keeps `AUTOINCREMENT`, so a dropped repeated headword uses up an id as in the seed and the ids stay the seed's. `--cache-dir` replaces the `--skip-*` and `--limit` flags. The FTS `integrity-check` runs with `rank = 1`, so it also compares the index with `entries`. `DictMetadata` gets no language fields until #208 reads them. The `seed.json` fallback was already gone.
- 2026-10-29: #140 measured (Python 3.14.0, SQLite 3.51.2, on the Mac). The rebuilt file has the seed's 416,946 rows with equal ids, words, keys, definitions, phonetics and parts of speech in all nine sources, the same `dict_metadata` apart from `built_at` and the languages, and byte-identical FTS shadow tables. Rows dropped as repeated headwords: openrussian 321, freedict-eng-spa 5,312, wordnet-spa-eng 310, the others 0. Size 126,050,304 bytes (`dbstat`: `entries` with its index 85.3 MB, `entries_fts` 40.7 MB, the rest 57 KB). Three builds, one of them `--verify`, gave sha256 `14dcb331…61c6ff5`. A build takes about 23 s with the inputs cached.
- 2026-10-29 (QA): #140 tests. `DictionaryFileTests` gets `testDictionaryFileStructure` (no triggers or `ANALYZE`, the unique key index, the `entries_fts` definition, ids below 2^40), `testSetupFailsWithoutAReadableDictionaryFile` (a missing file fails setup with `SQLITE_CANTOPEN` and nothing is created at its path; a Git LFS pointer fails with `SQLITE_NOTADB`) and `testDictionaryFileIsNeverCopied` (checked to fail with a copy of the file planted in Application Support; a 1.x `dict.sqlite` is left to #139). The UI suite `FreshInstallTests` launches with `-resetDatabase` and `-resetData`, then `dog`, `дом`, `casa`, `كتاب` and `γραφω` find rows from all nine sources; the result sort mode survives `-resetData`, so the test scrolls to a row rather than relying on its place.
- 2026-10-29 (QA): #140 results. A fresh venv from `Scripts/requirements.txt` and an empty cache downloaded 65.2 MB (the 9 pinned files) and built the file in 30 s (`--verify` with the inputs cached: 20 s), byte-identical to the committed file (sha256 `14dcb331…61c6ff5`); Python 3.13.9 gives the same file. A tampered cache file is downloaded again, and a wrong pin or an unpinned input fails the build. Fresh install on the iPhone 15 Pro simulator, iOS 17.5 (uninstall, install, first launch, timed from process start): Search on screen at 0.27 s, median of 3 (0.51 s on the first install), `isReady` at 0.23 s, no progress bar; `FreshInstallTests` sees each query's results 1.3 to 1.7 s after typing (XCUITest polling included) on all four simulators. Installed: app bundle 136,240 KB (Debug build; `dictionaries.sqlite` 126,050,304 bytes, no `seed.sqlite` or `Schema.sql`) plus a 164 KB data container, against 1.4.0's bundle with the 134.9 MB seed plus the ~138 MB unpacked copy. Regression on the four simulators: 230 unit tests, 94 UI tests on iPhone and 96 on iPad, plus the template and launch tests, all green. Device measurements are still to do.
- 2026-10-29: The invalidated-file risk found in #139 QA becomes #213 (Kirill): the app reopens the dictionary file once after a disk I/O error. The design comes into this spec before the code.
- 2026-10-30: #141 registers the first static step, `build_forms.py`, and bumps `user_version` and `DictionaryFile.formatVersion` to 2. An `inputs.json` entry may pin a committed file instead of a URL (keyed by its repository path, no `url`), for a source that keeps no old versions online; `inputs.committed()` checks its sha256 and never downloads. Details in [0136-word-forms.md](0136-word-forms.md).
