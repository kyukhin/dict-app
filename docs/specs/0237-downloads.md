# Dictionaries and word lists downloaded at setup

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-11-04 · Epic: #237 · Tickets: #240 (T1, done), #241 (T2, done), #242 (T3, done), #243 (T4), #244 (T5, done), #245 (T6), #246 (T7) · Updated: 2026-11-06

Read [0000-overview.md](0000-overview.md), [0129-dictionary-file.md](0129-dictionary-file.md) and [0136-word-forms.md](0136-word-forms.md) first. This epic changes 0129's single bundled file into an English bundle plus language packs, attached the same way. E3 ([0130](0130-word-lists.md), word lists) and E4 ([0131](0131-learning.md), learning) are drafted in parallel and call this spec's API ("For E3 and E4"). Numbers marked "measured" come from a prototype of the cut, run on 2026-11-03 and 11-04 against the dictionary file of master `fc8c930` (151,674,880 bytes, sha256 `24a1494d…`), Python 3.14.0, SQLite 3.51.2, on a Mac under heavy load (timings are relative).

## Why

- 2.0.0 ships every dictionary to every user: 151.7 MB in the bundle, 158.3 MB App Size on an iPhone (0129, device check of 2026-11-03). Most users read one or two languages. Kirill, 2026-11-03: "2.0 must already be free of clutter."
- E3 adds word lists and E6/E7 more static data per language. In the bundle, every user would carry all of them.
- Goal: the App Store download holds English only. Every other language, with its dictionaries, word forms and word lists, is a pack the user downloads once, during setup. After that the app is as offline as today.

## Behaviour

### What ships where

| Content | Where | Download (xz) | Installed |
|---|---|---|---|
| WordNet (English – English), English word forms (morphy), the pack catalog | App bundle, `dictionaries.sqlite` | in the app | 56.2 MB |
| Spanish: En–Es · FD, Es–En · WN | Pack `spa` | 6.9 MB | 26.2 MB |
| Russian: OpenRussian | Pack `rus` | 2.3 MB | 9.8 MB |
| Arabic: Ar–En · WN | Pack `arb` | 2.0 MB | 8.9 MB |
| Greek: El–En · FD, El–En · WN, En–El · FD, En–El · WN, Greek word forms, Greek lists A1–B1 | Pack `ell` | 10.7 MB (+0.5 MB lists, estimated) | 56.3 MB (+1.5 MB lists) |
| English lists: CEFR-J A1–B2, Octanove C1–C2, English frequency ranks | Pack `eng-lists` | 3.5 KB until E3 (#153); ~0.6 MB with the lists (estimated from 0130) | 0.2 MB; ~1.9 MB |

Measured on the cut of #240 (2026-11-06), MB = 10^6 bytes. The list figures are 0130's table sizes split by language; E3 fills them. All four languages: 21.9 MB to download (22.4 MB with the Greek lists), 101.2 MB installed.

| | 2.0 alpha (today) | 2.0 with packs |
|---|---|---|
| Dictionary file in the bundle | 151.7 MB | 56.2 MB |
| Its share of the App Store download (deflate, as in an IPA) | 52.0 MB | 21.0 MB |
| App Size on the device | 158.3 MB | about 63 MB |
| Documents & Data | 0.5 MB | 0.5 MB plus the installed packs |

### First launch (Kirill, 2026-11-03)

- The app opens on Search with English ready, and a sheet over it: "Welcome to LibreDict".
  - "English is included and works offline. Add other languages: each downloads once, then works offline too."
  - One row per downloadable language, in the UI language's names: "Spanish · 2 dictionaries · 6.9 MB", "Greek · 4 dictionaries, word forms, word lists · 11.2 MB". A checkmark toggles a row.
  - Checked at first: the UI language's pack, and the packs of the device's preferred languages (`Locale.preferredLanguages`). An English UI on an English-only device checks nothing.
  - "Download 18.1 MB" (the checked total), or "Continue" with nothing checked. "Not now". A link "Import your own dictionary" pushes today's Manage Dictionaries screen.
- After "Download" the sheet shows one progress row per language ("Spanish · 3.1 of 6.9 MB", "Greek · waiting") and a "Done" button. Done closes the sheet; the downloads go on. Each language becomes searchable as soon as it is installed: its chip appears on Search and the current query runs again. No restart.
- The sheet appears once. Swiping it down is "Not now". Settings → Dictionaries → Languages does the same later.

### Settings → Dictionaries

The section becomes: Dictionary Order, **Languages** (new), Manage Dictionaries (today's import screen).

The Languages screen lists every language the app knows, English first, then by name:

| State | Row |
|---|---|
| Included | English · "Included" (WordNet). Its word lists are a row of their own: "English word lists · 0.6 MB" |
| Not installed | Name, contents, "Download · 6.9 MB" |
| Waiting, downloading, installing | A progress bar with "3.1 of 6.9 MB", then "Installing…"; a Cancel button |
| Installed | "Installed · 25.0 MB". Swipe or Edit to remove |
| Update available (same format, newer data) | "Update · 6.9 MB" |
| Update required (the app reads a newer pack format) | "Update required · 6.9 MB". Its dictionaries are off until updated |
| Failed | The reason in red under the name, and "Try again" |

- **Remove**: "Remove Greek? Its dictionaries, word forms and word lists are deleted. Your History, My words and learning progress stay." When the language is being learned (E4), a second sentence: "You can go on learning the words you have. Greek lists come back when you download Greek again." When a learned pair of another language uses its dictionaries (English via Greek, E4), one more: "English via Greek shows no meanings until you download Greek again."
- Dictionary Order shows installed dictionaries only. Its footer links to Languages: "More languages".
- A removed language keeps its place and switch in Dictionary Order for when it returns.

### Learning a pair (for E3, E4; Kirill, 2026-11-03 and 2026-11-04)

Learning is chosen as a pair, the language learned and the language it is learned through (E4, 0131): "Greek via English", "English via Spanish". The catalog says which pairs exist (Design, "Pairs"), and a pair downloads only what it needs, when the user starts learning it: nothing unneeded lies on the phone.

| Pair (2.0) | Downloads | Why |
|---|---|---|
| Greek via English | `ell` | Greek lists, forms, examples and grammar; El–En · FD, El–En · WN |
| Greek via Russian, limited (meanings in English) | `ell` | As Greek via English: the meanings come from El–En; the Russian grammar texts and the examples' Russian translations are in the Greek pack too. Nothing from `rus` (OpenRussian goes from Russian into English) |
| English via Greek | `eng-lists`, `ell` | English lists and examples; En–El · FD and En–El · WN are in the Greek pack |
| English via Spanish | `eng-lists`, `spa` | English lists and examples; En–Es · FD |
| English via English | `eng-lists` | English lists and examples; WordNet is in the bundle |
| Spanish via English | `spa` | Es–En · WN; no built-in lists |
| Russian via English | `rus` | OpenRussian; no built-in lists |
| Arabic via English | `arb` | Ar–En · WN; no built-in lists |

- A pair's packs are the learned language's lists pack, when it has built-in lists (`ell` for Greek, `eng-lists` for English), then the packs of the pair's dictionaries (for a limited pair, those into its meanings language); packs already installed and the bundle are skipped. Choosing a pair installs the missing ones (E4's picker shows their size first). English examples come only with `eng-lists`, so only with English learning.
- Changing a learned language's via (E4's Settings) installs the new pair's missing packs. Stopping a language or changing its via removes nothing; Remove stays in Settings → Dictionaries → Languages.
- English via Greek pulls the whole Greek pack (11.9 MB to download), since packs are not split (Out of scope). A Greek UI, the one whose default this pair is, checks the Greek pack at first launch anyway.
- The install shows E4's own progress row, through the same API and states as the Languages screen.
- Imported lists get frequency ranks only when their language's pack is installed (0130).

### Update from 1.x and from the 2.0 alpha

- History, My words and imported dictionaries come through as in 0129 (#139).
- The first launch shows the same sheet with other words: "LibreDict 2.0 downloads languages other than English once. Your History and My words are here." Checked: the packs of the dictionaries that were enabled (`enabled_sources`; absent means all were on, so all four). One tap on "Download 22.4 MB" restores the dictionaries the user had.
- Until a language is installed, its History rows and My words open a "not downloaded" view: "This word is in the Greek dictionaries. Download Greek · 11.2 MB" with a Download button.
- Dictionary Order and the switches come back as they were when the packs install.

### Offline and errors

| Situation | What the user sees |
|---|---|
| No network at first launch | English works. A Download shows "No internet connection." and "Try again" per language |
| The connection drops mid-download | "The download stopped. Check your connection and try again." Try again continues where it stopped when the server allows it, else starts over |
| The file on GitHub is missing or the server fails (HTTP 4xx, 5xx) | "This download is not available right now. Try again later." |
| The download does not match its sha256 | "The download was damaged. Try again." Nothing is installed |
| Not enough storage | "Not enough storage. Greek needs 68 MB free." Partial files are deleted |
| The app is closed or killed mid-download | The next launch deletes the partial file. The language is not installed; Download starts over |
| The app goes to the background | The download goes on while iOS allows (`beginBackgroundTask`), then stops; on return it shows Try again |
| A query in a script whose pack is not installed (Greek, Cyrillic, Arabic) finds nothing | The no-results view adds "Greek is not downloaded" and a Download button |
| Restored from a backup, or a new app version needs a newer pack format | The sheet offers the missing languages again in one tap: "Your languages need to be downloaded again" |
| Search, History, learning, Settings after setup | Offline. No network access, except a download the user starts (Settings → Dictionaries → Languages, or a pair chosen to learn) |

### Decisions

- 2026-11-03 (Kirill): 2.0.0 ships with the downloads; the release date moves for them (it was 11-27 to Apple).
- 2026-11-03 (Kirill): the bundle holds English only (WordNet). Each bilingual dictionary goes with its non-English language: En–Es, Es–En · WN → Spanish; En–El, El–En → Greek; OpenRussian → Russian; Ar–En → Arabic. Word forms go with their language; English forms stay in the bundle. Word lists go with their language: Greek lists in the Greek pack, English lists in an English lists pack, downloaded when the user chooses to learn English.
- 2026-11-03 (Kirill): hosting is GitHub Releases of the public repository `kyukhin/dict-app`, every asset pinned by sha256. No other server.
- 2026-11-03 (Kirill): the app goes online only during setup: first launch, Settings → Dictionaries, choosing a language to learn. Search, learning and everything else stay offline. No network access outside a download the user started.
- 2026-11-03 (Kirill): first launch offers our dictionaries by language and the import of the user's own; later, Settings → Dictionaries downloads more or removes.
- 2026-11-03 (Kirill): learning starts with "I want to learn <language>", which downloads the language's lists if it has any; without lists it offers importing a list or Learn on a word.
- 2026-11-03 (Kirill): an update from 1.4.1 keeps History and My words (0129's move) and offers, in one tap, the packs of the dictionaries that were enabled.
- 2026-11-04 (Kirill): new dates with #237: E3, E4, E10 and #237 done by 11-20; code complete 11-27; submission to Apple 12-04. A second data stream runs (2 UI + 2 data). If behind, E7 and #160 move to 2.0.x first, then the agreed cut order.
- 2026-11-04 (Kirill, Open questions 1–5): accepted as recommended: the 2.0 search order becomes the golden file, with exact rows kept equal to 1.4.0; the first-launch sheet checks the UI language's and the device's preferred languages' packs; hints only in the two empty states; a `packs-YYYYMMDD` release per data change; xz assets in Git LFS under `Packs/`.
- 2026-11-04 (Kirill, Open question 6): the privacy text lives in the App Store description (`metadata/*.md`, five languages); #246 changes its offline wording and adds one sentence on downloads from GitHub.
- 2026-11-04 (Kirill): learning is chosen as a language pair (0131). 2.0 offers the pairs the data has a dictionary for (and the limited Greek via Russian, decided later that day, below); which pairs exist comes from the catalog, so a later source adds a pair with no code change. A pair downloads the learned language's pack plus what the pair needs, only when the user starts learning it; English examples only with English learning.
- 2026-11-04 (Kirill): nothing is cut from 2.0 if it runs late: the release date moves instead (0131). This replaces "E7 and #160 move to 2.0.x first, then the agreed cut order" above.
- 2026-11-04 (Kirill): Greek via Russian is offered as a limited pair, although there is no Greek–Russian dictionary: grammar and notes in Russian, word meanings and list translations in English, examples in Russian when Tatoeba has a direct translation, else English; its picker row warns about it. Data-driven: the catalog marks the pair as limited (`catalog_pair`: via `rus`, meanings `eng`), and it downloads what Greek via English does. English via Russian stays out of 2.0.

Design choices of this spec, for review: one SQLite file per pack, attached like `dict` (not merged); one schema for every file with an empty stub for a missing pack; the catalog inside the bundled file; xz assets, content-addressed; packs in Application Support excluded from backup; a data release tag per data change; no disk-space query. Each is argued in Design.

### Out of scope

Downloading in the background after the app is closed (a background `URLSession`). Automatic updates of packs. Splitting a language into smaller packs (dictionaries without forms or lists). Delta updates. Any server but GitHub Releases. Imported dictionaries as packs. Hosting user data.

## Design

### Files

| File | Where | Written by | Contents |
|---|---|---|---|
| `dictionaries.sqlite` | App bundle (Git LFS) | `Scripts/cut_packs.py` | WordNet, morphy, the catalog (`catalog_*`), every other table empty |
| `empty-pack.sqlite` | App bundle (Git LFS) | `Scripts/cut_packs.py` | The same schema with no rows: the stub attached for a pack that is not installed |
| `Packs/<id>-<version>.sqlite.xz` | Repository root (Git LFS), and the GitHub release | `Scripts/cut_packs.py` | The release assets. Never in a target |
| `<id>-<version>.sqlite` | `Application Support/DictApp/Packs/`, excluded from backup | The app, on install | An installed pack: the asset, decompressed |
| `<id>-<version>.sqlite.partial` | Same folder | The app, while installing | Deleted at launch if present |
| `<id>.removing` | Same folder | The app, while removing | An empty marker: the next launch finishes the removal (Crash safety) |
| Download in progress | `Caches/DictApp/Downloads/` | `URLSession`, then the app | Deleted after the install or at launch |
| `user.sqlite` | `Application Support/DictApp/` | The app | Unchanged (0129) |

- `<version>` is the first 12 hex digits of the pack file's sha256. A pack rebuilt with the same content keeps its name, its URL and its installed file: nothing is uploaded or downloaded again.
- Application Support, not Caches: iOS purges Caches under storage pressure, and a dictionary must not vanish. Excluded from backup (`isExcludedFromBackup` on the folder and each file), because it can be downloaded again (Apple's data storage guidelines). A restore then offers the download (Behaviour, Offline and errors).

### Connection layout: every pack attached under a fixed name

- `DatabaseService` keeps 0129's one pool on `user.sqlite`. `prepareDatabase` attaches the bundled file as `dict`, as today, and then every catalog pack under its schema name: `spa`, `rus`, `arb`, `ell`, `eng_lists` (the pack id with `-` as `_`). The file behind a name is the installed pack, or `empty-pack.sqlite` when the pack is missing or unusable. All read-only and immutable (`mode=ro&immutable=1`), as 0129.
- So every connection always has the same schema names, and the SQL is the same with or without a pack: a query of `ell.form_lookup` on the stub returns nothing. Measured: SQLite attaches one file under several names.
- `prepareDatabase` runs on GRDB's queues, so it reads the map schema → file from a lock-protected snapshot (`DictionaryFiles`), never from the actor.
- **Limit**: SQLite allows 10 attached databases (`SQLITE_MAX_ATTACHED`; measured 10 on macOS 26's system library and Python's 3.51.2). Today: `dict` + 5 packs, plus `legacy` during a 1.x move = 7. The cut fails the build above 8 packs; a ninth language needs a design change (merge two packs into one file). A unit test reads the limit on iOS.
- **Why attached files and not one merged database**: merging means copying rows into a writable local database on every install: the 1.x unpack that #129 removed, 20+ s of CPU for all languages, a second copy during the install, and a file no sha256 can check. Attached files keep #129's properties: read in place, immutable, verifiable, no unpack. The cost is the search ranking (Search, below).
- **Install, remove, update**: change the snapshot, then `reattach`, which is #213's `reopenDictionary` generalised: idle readers close (`invalidateReadOnlyConnections`), and the writer runs `DETACH` and `ATTACH` for each changed name, queued with `asyncWriteWithoutTransaction`. It bumps the reopen generation, so a read that fails with `SQLITE_IOERR` meanwhile retries once on a new reader (#213). The #213 reopen after an I/O error attaches the current snapshot.
- **Entry ids**: the cut gives each file its own id range: `entries.id = (ord << 32) + n`, where `ord` is the pack's permanent number (bundle 0, `spa` 1, `rus` 2, `arb` 3, `ell` 4, `eng-lists` 5) and `n` the row's place in the full build. So ids never collide across files, also with an older pack next to a newer bundle, and stay below 2^40, under imported ids (0129). Ids are still never stored. The larger ids make each pack 0.4 to 1.2 MB bigger than the prototype's (#240).

### Reading across files

| Read | 2.0 alpha | With packs |
|---|---|---|
| Search, preferred mode, lemma rows (#142, #143) | One branch on `dict.entries_fts` plus the imported branch | One branch per file that holds an enabled source (`nil`: every installed file), plus the imported branch. Each branch sorts and keeps its own top `limit` (`ORDER BY … LIMIT`), and one `ORDER BY … LIMIT` ranks the union. Measured: the same lists as without the branch limits. Lemma rows have no branch limit: a few keys match few rows |
| Greek form step, inflection tables (#142, #144) | `dict.lemma`, `dict.form_lookup`, … | `ell.lemma`, `ell.form_lookup`, `ell.paradigm`, `ell.tagset`, `ell.form_link`. Without the Greek pack: no form rows and no tables, with no special code |
| Morphy (#143) | `dict.morphy_*` | Unchanged. English lemma rows come from every file's English-headword dictionaries |
| `fetchMetadata`, `fetchSourceStats`, English headword sources | `dict.dict_metadata` | `UNION ALL` of `dict_metadata` over `dict` and the pack schemas, in file order: the bundle, then the packs by `ord` |
| `entry(for:)` | `dict.entries`, then imports | The file of the key's source (`DictionarySchemas.schema(ofSource:)`; the bundle for a source no file claims), then imports |
| Import key check, 1.x move key check | `dict.entries` | The file of the row's source |
| Word lists (E3) | — | `wordlist`, `wordlist_item`, `word_rank` of the language's pack (`ell`, `eng_lists`), read through `DictionarySchemas` (For E3 and E4) |
| Credits data sources | `dict.data_source` | `SELECT DISTINCT` over every file |

Source IDs, badges, stripe colours, pair keys (`DictionaryGrouping.bundledSourceIDs`) and Credits lines stay in the app for every catalog source, installed or not.

`DictionarySchemas` (pure, in `Models.swift`) holds the schema names, the source → schema map from the catalog and the bundle, and the language → lists schema map, and builds the `UNION ALL` fragments. SQL stays in `DatabaseService`.

**Search ranking.** Each file has its own FTS index, so bm25 scores of rows from different files are on different scales. With all four packs installed, against 1.4.0's golden lists (`search-probe-1.4.0.json`), measured:
- the exact-match rows are the same in 23 of 23 queries, and in the same order in 20 (`a`, `the` and `light` swap rows of equal standing, e.g. WordNet `a` moves from 4th to 2nd);
- whole top-50 lists are identical in 9 of 23 (every Russian, Arabic and Greek query, which read one pack), the same rows in 12; the 3 preferred-mode lists differ from row 11 to 18;
- the change is in the prefix and FTS tiers across dictionaries (`casa`: WordNet `casaba` now 2nd, FreeDict `Casablanca` 5th).
- This reverses 0129's decision of 2026-10-28 ("identical to 1.4.0 for bundled rows"), so it is Open question 1. Recommendation: accept, and take the 2.0 lists as the new golden file.
- Speed, on the loaded Mac, median of 7, all packs installed: `house` 6.8 ms against 6.8 ms on one file; `the` 205 against 149 ms; `a` 471 against 403 ms. Without the per-branch limit: 248 and 693 ms. Users with one or two packs get fewer branches.

### The catalog (in `dictionaries.sqlite`)

The bundled file says which packs exist for this app version, so the app needs no server to know them, and an app update brings the new list with it.

```sql
CREATE TABLE catalog_pack (
    id          TEXT PRIMARY KEY,   -- 'spa', 'rus', 'arb', 'ell', 'eng-lists'; permanent, like source IDs
    ord         INTEGER NOT NULL UNIQUE, -- permanent; the id range (ord << 32) and the display order
    lang        TEXT NOT NULL,      -- ISO 639-3 of the language it serves
    kind        TEXT NOT NULL,      -- 'language' (dictionaries, maybe forms and lists) or 'lists'
    version     TEXT NOT NULL,      -- first 12 hex digits of file_sha256
    url         TEXT NOT NULL,      -- https://github.com/kyukhin/dict-app/releases/download/<tag>/<id>-<version>.sqlite.xz
    sha256      TEXT NOT NULL,      -- of the asset
    size        INTEGER NOT NULL,   -- of the asset, bytes
    file_sha256 TEXT NOT NULL,      -- of the installed file
    file_size   INTEGER NOT NULL
);
-- The dict_metadata row of every pack dictionary, so the app knows a
-- dictionary it has not installed: its language, name and word count.
CREATE TABLE catalog_source (pack_id TEXT NOT NULL, source TEXT PRIMARY KEY, display_name TEXT NOT NULL,
    version TEXT, license TEXT, url TEXT, word_count INTEGER NOT NULL, description TEXT,
    from_lang TEXT NOT NULL, to_lang TEXT NOT NULL);
-- One row per built-in list (0130's wordlist columns), for "With word lists".
CREATE TABLE catalog_list (pack_id TEXT NOT NULL, id TEXT PRIMARY KEY, lang TEXT NOT NULL,
    level TEXT NOT NULL, word_count INTEGER NOT NULL);
-- One row per limited learning pair (E4): a via without a dictionary into it,
-- whose word meanings are in another language. 2.0: ('ell', 'rus', 'eng').
CREATE TABLE catalog_pair (lang TEXT NOT NULL, via TEXT NOT NULL, meanings_lang TEXT NOT NULL,
    PRIMARY KEY (lang, via));
```

- `catalog_source` serves the first-launch sheet, the 1.x move (word counts), E4's language of a My words row whose pack is missing, E4's pairs (below), and the "not downloaded" view.
- **Pairs** (E4's learning pairs, Kirill 2026-11-04). A pair has a learned language, a via language (explanations) and a meanings language (word meanings).
  - **Full pairs** need no table: a pair (lang, via) exists when a dictionary goes from `lang` into `via`, with meanings = via: every distinct (`from_lang`, `to_lang`) of the bundle's `dict_metadata` and of `catalog_source`, read through `DictionarySchemas.sourceLanguageSQL`, `und` left out. 2.0's nine dictionaries give seven (Behaviour, "Learning a pair"). There is no English via Russian or via Arabic: OpenRussian and Ar–En · WN only go into English.
  - **Limited pairs** are rows of `catalog_pair` (lang, via, meanings_lang), written by the cut from `Scripts/packs.json`'s `limited_pairs` list (Kirill, 2026-11-04): 2.0 has one, Greek via Russian with English meanings. Its dictionaries and packs are those of its (lang, meanings) pair. The cut fails on a row whose (lang, meanings) has no dictionary, or whose (lang, via) is already a full pair.
- A later source adds or completes a pair with no code change and no format bump: a Greek–Russian dictionary (2.1, perhaps LLM-filled), with `from_lang` `ell` and `to_lang` `rus`, is rows of the existing `entries` and `dict_metadata` shape in a pack, and its `catalog_source` row ships with the app update that brings the catalog. The same update drops the `catalog_pair` row, and Greek via Russian becomes a full pair with Russian meanings, downloading `ell` plus that pack.
- `catalog_pair` is one more catalog table, so it goes into T1's format 4 with the other catalog tables (not shipped yet, so free).
- One format for every file: `PRAGMA user_version` of the bundle, the stub and every pack is `DictionaryFile.formatVersion`, 4 from T1 (the catalog tables). A pack is usable when its header's `user_version` (4 bytes at offset 60, read without opening SQLite) equals it.
- **Same schema everywhere**: every file has every table of the full build (`entries`, `entries_fts`, `dict_metadata`, `data_source`, the forms, morphy and E3 list tables, E6's grammar and E7's example tables); a file fills only its own. An empty table costs one page, an empty FTS table a few (the stub is 188 KB). One DDL, one stub, one SQL shape. #240 registers `build_wordlists.py`, `build_grammar.py` and `build_examples.py` with their tables empty, so E3's, E6's and E7's data only changes pack versions, never the format.
- **Format rule**: a changed or added table changes every file's shape, so it bumps the format. Before 2.0 ships that is free. After it, a bump forces every user to download their packs again (the "Update required" state and the sheet), so data tables for 2.x go in before the release, or a bump waits for a release that needs one anyway.

### Download and install

`PackService` (an `actor`, `.shared`, in `Services/PackService.swift`) owns the network, the files and the install queue. `PackStatusModel` (`@MainActor ObservableObject`) publishes each pack's `PackState` to the views.

1. **Request.** One `URLSession` with the `.ephemeral` configuration: no cookies, no URL cache on disk, no credentials. `waitsForConnectivity = false`, so no network fails at once with `NSURLErrorNotConnectedToInternet`; `allowsCellularAccess`, `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` stay true, because the user started it and saw the size. A `downloadTask` on the selected row's `catalog_pack.url`; GitHub redirects to its CDN, which `URLSession` follows. Progress = bytes received / `catalog_pack.size` (the redirect hides the length). No background `URLSession`: it ignores `protocolClasses`, so no test could stub it, and iOS's per-app limits on it are unpredictable; `beginBackgroundTask` covers a short trip to the background.
2. **One at a time.** Installs run in the order chosen, so the first language is usable sooner; the others show "waiting".
3. **Verify the asset.** SHA-256 (CryptoKit, streamed in 1 MB chunks) and size against `catalog_pack.sha256` and `size`, before any byte reaches the decompressor or SQLite. Mismatch: delete, "damaged".
4. **Decompress** with the `Compression` framework (`OutputFilter`, `.lzma`, streamed) into `Packs/<id>-<version>.sqlite.partial`, hashing as it writes; the result must equal `file_sha256`. Measured on the Mac: the Greek pack (55 MB) decompresses in 0.6 s.
5. **Commit.** Set `isExcludedFromBackup`, then `rename(2)` the partial file to `<id>-<version>.sqlite`. The rename is the commit: the folder is the registry, and there is no install table to keep in step. A crash before it leaves a partial file, deleted at the next launch.
6. **Attach.** Snapshot: the pack's name → the new file; `reattach`.
7. **Imports the pack covers.** On the writer (with #213's retry, as the import): delete `imported_entries` rows of the pack's sources whose key the pack has, and `imported_sources` rows left with no rows. This covers a file named like a pack source imported before the pack (`freedict-eng-spa.json`), and the rare 1.x case below. A failure here does not fail the install: the pack is attached, and the rows left only repeat its own.
8. **Preferences** (`SettingsService`): a stored `enabled_sources` set gains the pack's sources (`nil` stays `nil`); a stored order lacking them gets them first when they are the UI language's dictionaries (`DictionaryDefaults.preferredSources`, #74), else last; a re-installed pack keeps its old place and switch. `packs_installed` gains the id, last: it is the install's final write.
9. **Tell the app.** `PackService.didChange` (a `Notification` on the main thread, its object the `PackService`, `userInfo["packs"]` the changed ids): Search re-runs its query once, `DictionarySelection` reloads (the chip appears), E3 and E4 reload their lists.

- **Cancel**: cancels the task, deletes temporary files; the state goes back to what it was: "not installed" for a first install; for an update, the old file stays attached as it was, and the pack shows "Update available" (or "Update required" after a format mismatch).
- **Try again**: uses the failed task's resume data when it has some (the CDN supports ranges, but its signed URL expires), else starts over. When the resumed request is refused (it ends in HTTP 4xx or 5xx: the signed URL expired, or the server rejects the range), it drops the resume data and makes one fresh request on `catalog_pack.url`, from the first byte. No other automatic retry.
- **Not enough storage**: there is no check before (a disk-space query is a required-reason API needing a privacy manifest, which the app does not have). `NSFileWriteOutOfSpaceError` or `ENOSPC` while writing shows the error with `size + file_size` and deletes the partial files.
- **Remove**: create the marker `Packs/<id>.removing`, snapshot to the stub, `reattach`, then delete the file once the writer's re-attach has run. A reader still busy on the old file finishes; if its read fails, #213's retry runs it on a new reader. `packs_installed` loses the id, then the marker is deleted; preferences are kept.
- **Update** (same format, newer `version`): download and verify the new file next to the old one, attach it, then delete the old file. An installed pack of the right format but an older version stays usable until then ("Update available").
- **Format mismatch**: the stub is attached instead, the pack shows "Update required", and the sheet offers the update at launch.
- **Crash safety.** An install or a removal can be cut off at any step. The launch scan reads the state from the folder and `packs_installed`, and finishes the operation before `isReady`:

  | At launch | `packs_installed` | Means | The scan |
  |---|---|---|---|
  | A `.partial` file or a `Downloads/` file | — | An install stopped before its commit | Deletes them |
  | A usable pack file, no marker | Lacks the id | An install stopped after its commit (step 5), before step 8 ended | Attaches the file, replays steps 7 and 8 (both idempotent), and adds the id last |
  | A usable pack file, no marker | Has the id | Installed | Attaches the file |
  | `<id>.removing` | Either | A removal stopped half way | Attaches the stub, deletes the pack's files, drops the id, then deletes the marker |
  | No usable file | Has the id | A restore from backup, or a format bump | Attaches the stub; `PackOffer`'s missing sheet offers the pack |

  An update writes no preference: a crash leaves two versions, and the scan keeps the newer one, as it deletes superseded files.

### Launch

0129's Launch, with two steps added (bold):

1. `-resetDatabase` (DEBUG) as today. **`-resetPacks` (DEBUG) deletes the Packs folder.**
2. `setup()` opens the pool; `prepareDatabase` attaches `dict` and every pack name, each on the stub (the snapshot starts empty).
3. **Scan `Packs/`**, with the catalog read through the pool (`dict.catalog_pack`; no connection is opened on the bundle, #111): delete `*.partial`, the `Downloads` folder, files of unknown packs and files superseded by a newer version of the same pack. For each catalog pack take its current file, else an older one of the right format, else the stub. Then the snapshot gets the chosen files and one `reattach` attaches them; no reader is busy yet. Last, it finishes an install or a removal that a crash cut off (Crash safety, above). Milliseconds, plus the replayed steps.
4. DEBUG hooks (below), `-installPacks` last.
5. `normalizeDictionaryPreferences` on the bundle's and the catalog's sources, so a missing pack's sources keep their place and switch.
6. The 1.x move, if any (below).
7. `isReady`. `ContentView` asks `PackOffer` whether to show the sheet.

DEBUG launch arguments (release builds ignore them, as #203's do):

| Argument | Effect |
|---|---|
| `-resetPacks` | Deletes `Packs/` and `Downloads/` before setup |
| `-installPacks <all\|id,…>` with `-packFixtures <path>` | Installs the packs from the committed assets at `<path>` through the install path, no network; skips a pack already installed at that version. When one fails, the packs installed before it are attached, then it throws |
| `-packDownloads <mode>` | Every download goes through `PackFixtureURLProtocol`: `ok`, `slow`, `offline`, `failOnce`, `http404`, `corrupt`, `noSpace`, `expiredResume` (as `failOnce`, then HTTP 403 for a resumed request) |
| `-skipWelcome` | Sets `packs_offered`, and launch decides no sheet: none of the three kinds shows |
| `-legacyFixture <path>` | Before setup, deletes the user database (as `-resetDatabase`), copies a 1.x fixture to `dict.sqlite` and clears `packs_offered` and `packs_installed`, for the upgrade UI test |

`PackOffer.decide` (pure) returns nothing or a sheet:
- **fresh**: `packs_offered` absent and no sign of an earlier install. Checked: the UI language's and the device languages' packs.
- **upgrade**: `packs_offered` absent and an earlier install: a 1.x `dict.sqlite` found at this launch, the `legacy_migration` marker, a stored `dictionary_order` that holds a pack's dictionary (a fresh 2.0 install stores only installed ones, and installs only after the sheet's answer), or user rows in History, My words or imports (the 2.0 alpha). Checked: the packs of the enabled sources.
- **missing**: `packs_installed` names packs that are not usable (a restore from backup, a format bump), whatever `packs_offered` says; it comes before the other two. Checked: those packs.
- Download or "Not now" sets `packs_offered`; the missing sheet's answer also drops its packs from `packs_installed`, so it shows once (an install adds each one again).

### Update from 1.x (changes to 0129's move, #139)

0129's move puts every 1.x row whose key the dictionary file lacks into `imported_entries`. With English-only bundles that would turn 270k rows of the other dictionaries into imports. The rule becomes, per source of the 1.x file:
- `wordnet` and custom sources: as today (`dict.entries`, the import rule).
- **A pack source** (in `catalog_source`) whose pack is not installed at the move: if its 1.x row count equals the catalog's `word_count`, its rows are the pack's and are dropped; otherwise all its rows move into `imported_entries`, and the pack's install later deletes the rows it has (Download and install, step 7). An installed pack's rows take the import rule, as `wordnet`'s.
- Why this is exact: every 1.x seed (1.1.0 to 1.4.1) holds exactly today's rows of each dictionary it shipped (measured: per-source counts equal, 0 rows missing). Imports named like a source add keys, never remove them, so the count equals `word_count` only when no row is an import. A 1.x import under a pack source ID (the #105 feature) is the only case that takes the second branch; it costs up to the dictionary's size in `user.sqlite` until the pack is installed.
- History and My words move as today. Their keys resolve once the pack is installed; until then the "not downloaded" view.
- The 2.0 alpha needs no data step: its `user.sqlite` is already 2.0's. Imports it made under a pack source ID are covered by step 7.
- Preferences: `DictionarySelection.load` keeps stored IDs that are installed or in the catalog, and shows only installed ones (today it drops IDs it does not see, which would lose the order of a pack not yet installed).

### Build and release

- `build_dictionaries.py` keeps building the full file, as today, but into the cache folder, not into the app. Every builder and static step is unchanged.
- `Scripts/packs.json` maps the full file to its outputs: per pack its id, `ord`, language, kind, sources, whole tables (`lemma`, `tagset`, `paradigm`, `form_lookup`, `form_link` → `ell`; `morphy_*` → bundle) and row filters (`wordlist`, `wordlist_item`, `word_rank` and the example tables by language; the cut skips a table the full file lacks). `data_source` rows go with their data. A `limited_pairs` list gives the limited learning pairs (`{"lang": "ell", "via": "rus", "meanings_lang": "eng"}`), written into `catalog_pair`.
- `Scripts/cut_packs.py` writes each output: the full schema, its rows with ids moved into its range, `entries_fts` rebuilt, `user_version`, journal DELETE, `VACUUM`; then the stub; then the xz assets (`lzma`, preset 6, no integrity check: byte-identical to Apple's `compression_tool -a lzma`, measured, so `Compression` reads it; sha256 does the checking); then the catalog tables into the bundle, last.
- **Checks** that fail the build: every row of every table but `data_source` lands in exactly one file (counts summed); every catalog source in one pack; every `catalog_pair` row has a dictionary from its `lang` into its `meanings_lang` and is no full pair; `word_count` equals rows; FTS `integrity-check` in each file; ids in range and below 2^40; at most 8 packs; each asset decompresses to its file (round trip); bundle under 60 MB. It prints each file's table sizes (`dbstat`) and totals.
- **Reproducible**: the same inputs and SQLite version give byte-identical files (measured: two cuts, same sha256 for all five). `--verify` rebuilds and compares the bundle, the stub and each pack's `file_sha256`. Compression is not part of it: the committed asset is the pinned one.
- **LFS**: the bundle (56 MB) changes only when English data changes; an unchanged pack keeps its asset, so a data PR adds only the changed packs' assets (2 to 11 MB each) instead of today's 152 MB file.
- **Release** (Kirill, once per data change that ships):
  1. The data PR passes `--release-tag packs-YYYYMMDD`; new assets get that tag's URL, unchanged ones keep theirs.
  2. After merge: `git tag -a packs-YYYYMMDD <merge commit>`, then `gh release create packs-YYYYMMDD Packs/<new assets>` with the sha256s in the notes.
  3. `python3 Scripts/check_release_assets.py` downloads every catalog URL and checks size and sha256. It must pass before any TestFlight or App Store upload.
  4. Turn on GitHub's immutable releases for the repository, so an asset cannot be replaced; the pin would catch it anyway.
- Data tags must never show in Settings: `generate_build_info.sh` and `validate_build_info.sh` call `git describe --tags --match 'v[0-9]*'` (T1).
- Asset URLs are `https://github.com/kyukhin/dict-app/releases/download/<tag>/<id>-<version>.sqlite.xz`. No manifest is fetched: the catalog is in the app.

### For E3 and E4

What 0130 and 0131 call; names are this spec's:

1. **Read the installed packs and their list tables.** `PackService.installedPacks() -> [InstalledPack]` (id, lang, version, usable). The tables have 0130's shapes in every file; `DictionarySchemas.listsSchema(for lang:) -> String?` gives `ell` or `eng_lists`, and `DictionarySchemas.union(_ table:)` the `UNION ALL` over every file for `wordLists()`. A missing pack reads as empty (the stub).
2. **The languages and the pairs.** `PackCatalog.languages -> [CatalogLanguage]`: `lang`, `isBundled` (English), `dictionaryPack: PackID?`, `listsPack: PackID?` (`ell` for Greek, `eng-lists` for English, nil for the others), `hasBuiltInLists`, sizes. `PackCatalog.pairs -> [CatalogPair]` (T2): `lang`, `via`, `meaningsLang` (= `via`, except in a `catalog_pair` row), `isLimited`, `sources` (the dictionaries from `lang` into `meaningsLang`, in catalog order), `packs: [PackID]` (the lists pack of `lang` when it has built-in lists, then the packs of `sources`, without duplicates or the bundle) and `downloadSize(installed:)`, the asset sizes of its packs not installed. E4 adds the pairs of imports with both languages (#208), which need no pack.
3. **Install.** `PackService.install(_ id: PackID) async throws` and `PackService.installPair(lang: String, via: String) async throws -> [PackID]` (T3), which replaces `installLists(for:)`: it installs the pair's missing packs (no usable file) in order and returns them, empty when nothing was missing or the catalog has no such pair (no request); throws `PackError` (`.offline`, `.stopped`, `.unavailable`, `.damaged`, `.noSpace`, `.cancelled`), the first pack's that fails, and leaves the packs after it missing. Progress through `PackStatusModel.state(of:)`. E4 adds the pair even if the install fails, and offers Try again.
4. **A source's language** for E4's enrol SQL: `DictionarySchemas.sourceLanguageSQL`, the bundle's `dict_metadata` and `dict.catalog_source`, so a My words row of a missing pack keeps its language instead of `und`.
5. **UI-test hook**: DEBUG `-installPacks <all|id,…>` installs packs from the committed assets through the real install path, with no network, before the UI shows; it skips a pack already installed at that version. The suite passes the assets folder with `-packFixtures <path>` (`UITestHelpers.packArguments(_:)`, from `#filePath`). Unit tests use `PackFixtures.install(_:into:)`.

### UI

- `LanguagesView` (Settings) and `WelcomeSheet` (the first-launch, upgrade and missing sheet) share `PackRow`. View models: `LanguagesViewModel`, `WelcomeViewModel`. Views render `PackState` and call `PackService`; no file or network code in views.
- Sizes use `ByteCountFormatter` (`.file`), so they read "6.9 MB" in every language. Language names reuse `SettingsViewModel.languageName(iso3:locale:)`.
- iPad: the sheet is a form sheet; several windows share `PackStatusModel`, and the sheet shows in one.
- Arabic: rows mirror; composed strings start with U+200F (#119).
- About 27 new keys in the five languages (the implementing agent translates):

| Key | en |
|---|---|
| `welcome.title`, `welcome.body` | Welcome to LibreDict · English is included and works offline. Add other languages: each downloads once, then works offline too. |
| `welcome.upgrade.body`, `welcome.missing.body` | LibreDict 2.0 downloads languages other than English once. Your History and My words are here. · Your languages need to be downloaded again. |
| `welcome.download`, `welcome.continue`, `welcome.notNow`, `welcome.import`, `welcome.done` | Download %@ · Continue · Not now · Import your own dictionary · Done |
| `languages.title`, `languages.included`, `languages.installed`, `languages.download`, `languages.update`, `languages.updateRequired`, `languages.waiting`, `languages.installing`, `languages.progress`, `languages.retry`, `languages.more` | Languages · Included · Installed · %@ · Download · %@ · Update · %@ · Update required · %@ · Waiting · Installing… · %1$@ of %2$@ · Try again · More languages |
| `languages.contents.*` | %lld dictionaries · word forms · word lists |
| `languages.remove.title`, `.message`, `.learning`, `.pair` | Remove %@? · Its dictionaries, word forms and word lists are deleted. Your History, My words and learning progress stay. · You can go on learning the words you have. %@ lists come back when you download %@ again. · %1$@ shows no meanings until you download %2$@ again. (the pair's name is E4's `learn.pair`) |
| `pack.error.offline`, `.stopped`, `.unavailable`, `.damaged`, `.noSpace` | The texts in "Offline and errors" |
| `notDownloaded.message`, `notDownloaded.search` | This word is in the %1$@ dictionaries. · %@ is not downloaded. |

| Element | Identifier |
|---|---|
| Sheet, a language row (value `checked`), Download, Not now, Import, Done | `welcome_sheet`, `welcome_language_<id>`, `welcome_download`, `welcome_not_now`, `welcome_import`, `welcome_done` |
| Settings row, screen | `dictionary_languages_link`, `languages_screen` |
| Per pack | `pack_row_<id>`, `pack_download_<id>`, `pack_progress_<id>`, `pack_cancel_<id>`, `pack_remove_<id>`, `pack_update_<id>`, `pack_retry_<id>`, `pack_error_<id>` |
| "Not downloaded" view and Search hint | `not_downloaded_download`, `search_not_downloaded` |

### App Store review and privacy

- **Guideline 2.5.2**: packs are data (SQLite), never code.
- **Guideline 4.2.3 (ii)**: resources needed at first launch must show their size and ask first. The app works without them, and the sheet shows sizes and asks.
- **Review**: the assets of the submitted catalog are public before submission (`check_release_assets.py`). Review notes: "Languages other than English download from GitHub on first launch or in Settings → Dictionaries → Languages. No account."
- **Privacy label** stays "Data Not Collected": a download is a plain GET of a public file, from an ephemeral session, with no identifier. GitHub receives the IP address and the system user agent, as for any download. The privacy policy gains that sentence (Kirill, wherever it is hosted).
- **Export compliance**: HTTPS through `URLSession` is exempt; `ITSAppUsesNonExemptEncryption` stays false. No ATS exception (HTTPS only).
- **Privacy manifest**: none is needed by this epic: it uses no required-reason API.
- **Metadata** (2.3.1, accurate): "100% Offline: every dictionary lives on your device" and "six built-in dictionaries" change to "English is included; other languages download once, then everything works offline" in all five listings (T7).
- The overview's rule "the app makes no network calls of its own" becomes "only downloads the user starts" (0000-overview).

### Code map

| Path | Change | Ticket |
|---|---|---|
| `Scripts/packs.json`, `Scripts/cut_packs.py`, `Scripts/check_release_assets.py` | New | T1 |
| `Scripts/build_dictionaries.py`, `build_wordlists.py`, `build_grammar.py`, `build_examples.py`, `grammar_schema.sql` | Builds the full file into the cache; `FORMAT_VERSION` 4; the E3, E6 and E7 steps registered, their tables empty | T1 |
| `Scripts/make_search_probe.py`, `DictApp/DictAppTests/search-probe-2.0.json` | `--packs`: the 2.0 golden lists | T1 |
| `Scripts/generate_build_info.sh`, `Scripts/validate_build_info.sh` | `--match 'v[0-9]*'` | T1 |
| `DictApp/DictApp/Resources/dictionaries.sqlite`, `empty-pack.sqlite`; `Packs/*.sqlite.xz` | English bundle with catalog; stub; assets | T1 |
| `Models/Models.swift` | `DictionaryFile.formatVersion` 4, `DictionarySchemas`, `PackID`, `PackState`, `PackOffer` | T2, T3, T5 |
| `Services/DatabaseService.swift` | `DictionaryFiles` snapshot, attaches, `reattach`, reads across files, the 1.x count rule | T2, T5 |
| `Services/PackService.swift` (new) | `PackCatalog` with `pairs`, `PackService` with `installPair(lang:via:)`, `PackStatusModel`, DEBUG `PackFixtureURLProtocol` | T2 (install from file, `pairs`), T3 (`installPair(lang:via:)`) |
| `Services/SettingsService.swift`, `ViewModels/SettingsViewModel.swift` | `packs_installed`, `packs_offered`; enable and order on install; `DictionarySelection` keeps catalog sources | T3, T5 |
| `ViewModels/PacksViewModel.swift` (new), `Views/LanguagesView.swift` (new) | Languages screen, Welcome sheet | T4, T6 |
| `Views/SettingsView.swift`, `DictionaryOrderView.swift`, `SearchView.swift`, `DefinitionView.swift`, `HistoryView.swift`, `DictApp.swift` | Section rows, footer, hints, "not downloaded", launch steps, DEBUG hooks | T2–T6 |
| `Resources/Localizable.xcstrings` | Keys | T4, T6 |
| `DictAppTests/DictAppTests.swift`; `DictAppUITests/…` | Tests below; every suite gains `-skipWelcome`, 16 also `-installPacks all` | all |
| `metadata/*.md` | Listings | T7 |
| `docs/specs/0000-overview.md`, `0129-dictionary-file.md`, `0136-word-forms.md` | The bundled data, the connection layout, `ell.` instead of `dict.` for the forms | T1, T2 |

**Xcode step (Kirill, once, in the Xcode GUI, before T2)**: add to the app target `Services/PackService.swift`, `ViewModels/PacksViewModel.swift`, `Views/LanguagesView.swift` (empty files) and the resource `Resources/empty-pack.sqlite`. It can join E3/E4/E10's batch if that one has not run yet. `Packs/` stays out of every target. `Compression` and `CryptoKit` are system frameworks.

### Tickets, order and sizes

Sizes are pipeline days: development, QA on the four simulators, review and the daily merge. Streams as agreed on 2026-10-26: two UI, one data.

| Ticket | Scope | Needs | Size | Stream |
|---|---|---|---|---|
| T1 Build packs (#240) | `packs.json`, `cut_packs.py` (cut, id ranges, catalog, stub, assets, checks, `--verify`, `catalog_pair` from `packs.json`), `check_release_assets.py`, the 2.0 probe golden, `--match` in the build-info scripts, format 4 | Approval | M, 2.25 | Data |
| T2 Read packs (#241) | `DictionaryFiles`, attaches with the stub, `reattach`, reads across files with per-branch limits, `DictionarySchemas`, `PackCatalog` with `pairs`, launch scan, DEBUG `-installPacks` from the committed assets (verify, decompress, rename), `PackFixtures`; every unit and UI test kept green (every suite gets `-skipWelcome`, the 16 that read other languages also `-installPacks all`; `FreshInstallTests` rewritten). Merges in one batch with T1, since T1 alone would leave master's tests without their dictionaries | T1, the Xcode step | L, 3.75 | Data |
| T3 Downloads (#242) | `PackService` network path: session, progress, queue, verify, cancel, try again, remove, update, format check, step 7 and 8, `didChange`, errors, `-packDownloads`, the network audit test; `installPair(lang:via:)` | T2 | L, 3.25 | Data |
| T4 Languages screen (#243) | Settings rows, Languages screen and its states, remove alert (with the learned-pair sentence), Dictionary Order footer, strings, `LanguagesFlowTests` | T3 (starts on a fake `PackService` after T2) | M, 2.25 | UI 1 |
| T5 Upgrade (#244) | `PackOffer`, the 1.x count rule, `DictionarySelection` keeping catalog sources, `-legacyFixture`, unit tests; QA real upgrades 1.4.1 → 2.0 and 2.0-alpha → 2.0 | T2 | M, 1.5 | UI 2 |
| T6 Welcome sheet (#245) | The sheet in its three kinds, progress, Not now, Import link; the "not downloaded" view and the Search hint; strings; `WelcomeFlowTests`, `UpgradeOfferTests` | T3, T5 | M, 2.5 | UI 2 |
| T7 Release (#246) | Metadata in five languages, privacy policy line, review notes, the first data release and its check, device QA | All | S, 1 | Data, with Kirill |

- 16.5 stream-days: data 10.25 (T1, T2, T3, T7), UI 1 2.25 (T4), UI 2 4 (T5, T6). Learning pairs (Kirill, 2026-11-04) add 0.75: T2 +0.25 (`PackCatalog.pairs`), T3 +0.25 (`installPair(lang:via:)`), T4 +0.25 (the remove alert's pair sentence). T2's and T3's code is already built, so for them this is rework before they merge. The limited Greek via Russian adds 0.25 to T1 (`catalog_pair`: DDL, `packs.json`, the cut and its checks; T1 is built); T2 reads the table within its pairs work.
- Critical path T1 → T2 → T3 → T6 → T7: about 11.5 pipeline days from approval, if the data stream does nothing else.
- If late, nothing is cut: the release date moves (Decisions).
- **The data stream is the bottleneck.** E3 (#151, #152, #153) and E4/E10 (#157, #163) hold about 8.75 more data-stream days (with learning pairs). Replan with the PM: T5 is already on a UI stream; #151 or #157 could move too. E3's data tickets put their rows into the packs through T1's map, so they can merge before or after T1; each changes the shared schema, so the format bumps again (free before 2.0 ships).

## Test plan

Unit classes go in `DictAppTests.swift`; async tests are `@MainActor` (#229). No test touches the network: unit tests give `PackService` a session whose `protocolClasses` is `[PackFixtureURLProtocol]`, which serves the committed assets from `Packs/` (through `#filePath`) and can fail on purpose; UI tests reach the same protocol through `-packDownloads <mode>` (`ok`, `slow`, `offline`, `failOnce`, `http404`, `corrupt`, `noSpace`) and `-installPacks`. UI suites run on the four-simulator matrix, one suite per `xcodebuild` run with the app uninstalled before it.

| Acceptance criterion | Test |
|---|---|
| #237: the App Store download holds English only | Build checks (T1). Unit `PackFileTests.testBundleHoldsEnglishOnly` (`dict.dict_metadata` is `wordnet` alone; the forms and list tables of `dict` are empty; the catalog lists `spa`, `rus`, `arb`, `ell`, `eng-lists` with their sources), `testEveryFileHasTheFormat` (bundle, stub, each committed asset decompressed). QA: App Size and the download size in TestFlight, recorded in History |
| #237: fresh install, English search works with no network | UI `FreshInstallTests.testEnglishWorksOffline` (`-resetDatabase -resetPacks -packDownloads offline`: the sheet shows; Not now; `dog` gives WordNet rows within 2 s; `casa` gives none and the Search hint; Settings → Languages shows Download for four languages) |
| #237: a pack downloads, is verified and is searchable without a restart | Unit `PackServiceTests.testInstallVerifiesThenAttaches` (stub protocol: the file is renamed into `Packs/` only after both sha256 checks; `search("casa")` returns Es–En rows with no new `setup`), `testInstallReattachesReadersAndWriter` (a reader opened before the install finds the pack after it; an import's key check on the writer sees it). UI `WelcomeFlowTests.testDownloadSpanishThenSearch` (`-packDownloads ok`: check Spanish, Download, progress, Done; `casa` finds Es–En rows and the Spanish – English chip appears in the same launch) |
| #237: no network access outside a download the user started | Unit `NetworkAuditTests.testOnlyPackServiceUsesTheNetwork` (reads the app sources through `#filePath`: `URLSession`, `URLRequest`, `NWConnection`, `NWPathMonitor` appear only in `PackService.swift`), `PackServiceTests.testNoRequestUntilInstall` (a recording protocol: launch scan, catalog reads, states, `installedPacks`, search: zero requests; one `install`: one request to the catalog URL). QA: Instruments' Network template on a device: launch, search, History, learning, Settings: no connection; one download: connections to GitHub only |
| #237: update from 1.4.1 keeps History and My words and offers the dictionaries that were enabled | Unit `LegacyMigrationTests.testMoveWithPacksMissing` (1.4.0 fixture, an English-only test bundle whose catalog counts equal the fixture's seed rows: History and My words as in #139; pack-source rows dropped; `my_glossary` imported), `testImportUnderAPackSourceMovesUntilThePackArrives` (a count above the catalog's: all rows of that source move, then the pack's install leaves only the imported keys), `PackOfferTests` (pure: fresh, upgrade from each signal, missing; `nil` enabled checks all four; a 1.3.0-style set without Greek leaves Greek unchecked). UI `UpgradeOfferTests.testUpgradeOffersEnabledDictionaries` (`-legacyFixture legacy-1.4.0.sqlite`: History rows show; the sheet's upgrade text with four languages checked; Download; a Greek History row opens its entry). QA: install the App Store 1.4.1, add History, bookmarks and an import, update to the 2.0 build (simulator and TestFlight), then the same from 2.0.0 (6) |
| #237: a failed or partial download leaves the app working and can be retried | Unit `PackServiceTests.testFailureMidDownloadInstallsNothing` (fails after half: no file in `Packs/` or `Downloads/`, state `.failed(.stopped)`, search works; Try again installs), `testDamagedDownloadIsRejected` (`corrupt`), `testOfflineFailsAtOnce`, `testHTTP404IsUnavailable`, `testNoSpaceCleansUp` (a write seam throws `ENOSPC`), `testCancelDeletesTemporaryFiles`, `testCancelledUpdateKeepsTheOlderVersion` and `testCancelledUpdateOfAnotherFormatIsUpdateRequired` (mid-update: the old file stays attached as it was, Update available or Update required), `testLaunchDeletesPartialFiles` (a planted `.partial` and a `Downloads/` file), `testCrashAfterCommitFinishesTheInstall` (a DEBUG seam stops the install after step 5, after step 6 and after step 7: each next launch attaches the pack, deletes the covered import rows, enables and orders its sources and adds it to `packs_installed`; a second launch changes nothing), `testCrashDuringRemovalFinishesIt` (a seam stops after the marker and after the re-attach: the next launch attaches the stub, deletes the file, drops the id and deletes the marker), `testRestoredBackupOffersTheMissingPack` (the id stored, no file: nothing is replayed, the missing sheet), `testExpiredResumeDataStartsOver` (the fixture protocol refuses the resumed request with HTTP 403: one fresh request to the catalog URL follows, and the install completes), `testRefusedFreshRequestIsNotRetried`, `testLaunchScansAfterSetup` (setup attaches the stubs; the scan reads `catalog_pack` through the pool, keeps the current file, falls back to an older one of the right format, deletes an unknown pack's file and a superseded one; after the re-attach the kept packs are searchable before `isReady`). UI `WelcomeFlowTests.testFailedDownloadCanBeRetried` (`failOnce`: the error and Try again; the second attempt installs) |
| Kirill 2026-11-03: Settings → Dictionaries downloads more and removes | UI `LanguagesFlowTests.testDownloadAndRemoveGreek` (Download, progress, Installed; `γραφω` finds rows and the inflection table shows; Remove with its alert; `γραφω` finds nothing; Dictionary Order keeps the pair's place for the next install), `testCancelDownload` (`slow`). Unit `PackServiceTests.testRemoveDetachesThenDeletes`, `testReinstallKeepsOrderAndSwitch`, `testInstallEnablesAndOrders` (UI language first, else last; `nil` stays `nil`) |
| Kirill 2026-11-03 and 2026-11-04: choosing a pair to learn downloads what it needs, nothing more | Unit `PackCatalogTests.testPairsComeFromTheCatalog` (the seven pairs with their sources and packs, as in "Learning a pair"; Greek via Russian limited, with `meaningsLang` `eng`, the El–En sources and `ell`; no `eng` → `rus` or `eng` → `arb`; a test catalog with an `ell` → `rus` source makes Greek via Russian a full pair with Russian meanings, and its cut fails while the `catalog_pair` row stays; `und` gives none), `PackServiceTests.testInstallPairPacks` (Greek via English → `ell`; English via Greek → `eng-lists`, then `ell`; English via English → `eng-lists`; Spanish via English → `spa`; Greek via Russian → `ell`, nothing from `rus`; all installed → empty and no request), `testInstallPairStopsAtTheFirstFailure`, `testDownloadSizeCountsOnlyMissingPacks`. E4's `LearningLanguageServiceTests.testChoosingAPairStoresItsViaAndInstallsItsPacks` (0131). Unit `LanguagesViewModelTests.testRemoveAlertNamesTheLearnedPair` (Greek's alert with English via Greek learned has the pair sentence; with Greek via English only, the learning sentence alone) |
| Kirill 2026-11-03: word forms and lists go with their language | Unit `PackFileTests.testGreekFormsAndListsAreInTheGreekPack`, `testEnglishFormsStayInTheBundle`; the existing `WordFormsLookupTests`, `WordFormsSearchTests`, `InflectionLookupTests` read the Greek pack through `PackFixtures` and keep their expectations |
| Search keeps working across files (Open question 1) | Unit `SearchProbeTests.testProbeMatches20` (`search-probe-2.0.json`, all packs installed), `testExactRowsMatch140` (each query's exact rows equal 1.4.0's set), `testBranchLimitKeepsTheLists` (with and without the per-branch limit), `testOnlyEnabledFilesAreSearched` (`EXPLAIN QUERY PLAN`), `testIdsAreUniqueAcrossFiles`. QA: the probe timing on the iPhone 15 Pro simulator and a device, against the 2.0 alpha |
| An app update with a new pack format, a restore | Unit `PackServiceTests.testWrongFormatAttachesTheStub` (header `user_version` 3: stub, "Update required", the sheet's missing kind), `testOlderVersionStaysUsable`, `testUpdateReplacesTheOldFile` |
| The build is reproducible and complete | `cut_packs.py --verify` in T1 and every data PR. Unit `PackFileTests.testAttachLimit` (`sqlite3_limit` on iOS ≥ packs + 2) |
| Five UI languages, Arabic right to left, iPad | `testEveryCatalogKeyIsTranslatedInEveryShippedLanguage`. UI `ArabicLocalizationTests.testLanguagesScreenIsRightToLeft`, `iPadSpecificTests.testWelcomeSheetOnIPad` |
| No regression | Every existing suite with `-skipWelcome`, and `-installPacks all` where it reads other languages; `LegacyMigrationTests`, `DictionaryReopenTests` (the reopen re-attaches every name) and `UserDatabaseTests` green |

QA records in History: the sizes of each asset and file, App Size and the download size, the probe timing, install times per pack on a device (download on Wi-Fi and cellular, decompress, attach), the upgrade runs, and the Instruments network check.

## Open questions

1. **Search order across languages.** Resolved 2026-11-04: as recommended (Decisions).
2. **Which languages the first-launch sheet checks.** Resolved 2026-11-04: as recommended (Decisions).
3. **Hints for a language not downloaded.** Resolved 2026-11-04: as recommended (Decisions).
4. **Data release tags.** Resolved 2026-11-04: as recommended (Decisions).
5. **Assets in Git LFS.** Resolved 2026-11-04: as recommended (Decisions).
6. **Privacy policy.** Resolved 2026-11-04: the privacy text is the App Store description, `metadata/*.md` (Decisions).

## History

- 2026-11-04: First draft, with Kirill's decisions of 2026-11-03. Measured with a prototype cut of master `fc8c930`'s dictionary file: file and asset sizes, reproducibility, xz byte-identical to Apple's encoder, the probe lists across five attached files, search timing with and without per-branch limits, the 1.x seeds against today's rows (1.1.0 to 1.4.1: equal per source, nothing missing), and the attach limit (10).
- 2026-11-04: Approved by Kirill.
- 2026-11-04: Review fixes: the entry id formula parenthesised, the download URL named, 0129's search row qualified for installed packs.
- 2026-11-04: Learning is chosen as a language pair (Kirill, 0131): pairs come from the dictionaries' directions in the catalog (no new table, no format change; seven in 2.0); `PackCatalog.pairs` and `PackService.installPair(lang:via:)`, which replaces `installLists(for:)`; a pair downloads its learned language's lists pack and its dictionaries' packs, only when chosen; the remove alert names a learned pair that needs the language. T2, T3 and T4 +0.25 each. Nothing is cut if late (Kirill).
- 2026-11-04: Greek via Russian is offered as a limited pair (Kirill): `catalog_pair` (lang, via, meanings) in the bundle's catalog, written from `packs.json` and checked by the cut; `CatalogPair` gains `meanings` and `isLimited`; a limited pair downloads the packs of its (lang, meanings) pair, `ell` for Greek via Russian. T1 +0.25.
- 2026-11-04: Rebased on master with 0130 (#234). Review fixes: the launch scan reads the catalog through the pool after `setup()` attaches every pack on the stub, then one `reattach` attaches the chosen files (no connection on the bundle, #111), with a test; the 2026-11-04 pairs decision names the limited Greek via Russian; the overview, 0129 and 0136 point to 0237 as Approved, 0136 with `ell.` for the Greek tables, and the overview has `eng-lists` downloaded when English learning starts.
- 2026-11-05: Review fixes: install and removal are crash-safe. An install writes `packs_installed` last; a removal starts with a `<id>.removing` marker. The launch scan finishes any interrupted install or removal from the folder and `packs_installed`, with tests for each crash point. Try again falls back to a fresh request when resume data is refused.
- 2026-11-05: Review fixes: the offline row excludes downloads the user starts; cancelling an update keeps the installed pack (Update available, or Update required); 0129's fresh-install target covers English and the installed packs.
- 2026-11-06: #240 measured (SQLite 3.51.2): bundle 56,201,216 bytes, stub 188,416; packs installed / to download: `spa` 26,177,536 / 6,889,888, `rus` 9,818,112 / 2,285,500, `arb` 8,904,704 / 2,032,668, `ell` 56,336,384 / 10,707,004, `eng-lists` 188,416 / 3,484. `--verify` byte-identical. Release tag `packs-20261106`.
- 2026-11-06: #240: the packs are 0.4 to 1.2 MB larger than the prototype's (101.2 against 97.9 MB installed): `(ord << 32) + n` ids take more bytes.
- 2026-11-06: #240: `eng-lists` is empty until E3 (#153); its file equals the stub.
- 2026-11-06: #240: `packs.json` names the limited pairs `limited_pairs`, with `meanings_lang`; the cut writes them into `catalog_pair`.
- 2026-11-06: #240: `build_grammar.py` and `build_examples.py` exist early, and `build_wordlists.py` (#151) is registered, all with empty tables, so E3's, E6's and E7's tables are in format 4.
- 2026-11-06: #241: lemma rows have no per-branch limit; one `LIMIT` over the union.
- 2026-11-06: #241: `fetchMetadata` and `fetchSourceStats` read the files in order: the bundle, then the packs by `ord`.
- 2026-11-06: #241: a source no file claims (an import, a test dictionary without metadata) reads from the bundle.
- 2026-11-06: #241: `-installPacks` attaches the packs installed before a failure, then throws.
- 2026-11-06: #241, rebased on #151: the word list queries read through `DictionarySchemas` (`union`, `sourceLanguageSQL`, `schema(ofSource:)`), and linking reads Greek forms from `ell`; installing or removing a pack drops the cached new-word order.
- 2026-11-06: Review fixes (CodeRabbit, PR #252): the cut opens and attaches files as escaped URIs with URI parsing on; the DDL and `CatalogPair` use the implemented names `meanings_lang` and `meaningsLang`.
- 2026-11-06: #242: `PackError` has `.stopped` (the connection dropped, or the background time ran out), the error behind "The download stopped".
- 2026-11-06: #242: `didChange` carries the `PackService` as its object and the changed ids in `userInfo["packs"]`, so a unit test's service never reaches the app's observers.
- 2026-11-06: #242: a failed step 7 does not fail the install: the pack is already attached.
- 2026-11-06: #242: `installPair` stops at the first pack that fails, and returns empty for a pair the catalog lacks (a pair of imports needs no pack).
- 2026-11-06: #242: a resumed request counts as refused when it ends in HTTP 4xx or 5xx; DEBUG `-packDownloads expiredResume` refuses it with 403 for the tests.
- 2026-11-06: #153: the `eng-lists` pack measures 496,404 B to download, 1,691,648 B installed.
- 2026-11-06: #244: the 1.x count rule applies only to packs not installed at the move; an installed pack's rows go through the key check.
- 2026-11-06: #244: the missing sheet shows even after `packs_offered`, and its answer drops its packs from `packs_installed`.
- 2026-11-06: #244: a stored order is an upgrade sign only when it holds a pack's dictionary: a fresh 2.0 install stores only the bundle's and installed ones.
- 2026-11-06: #244: `-legacyFixture` also deletes the user database and clears `packs_offered` and `packs_installed`, so the launch is a clean 1.x update.
- 2026-11-06: #244: `-skipWelcome` suppresses every kind of sheet, the missing one too.
- 2026-11-06: #244, rebased on #242: the offer is decided after the launch scan, which now runs after `setup()` and finishes an interrupted install or removal first, so `packs_installed` and the usable packs it reads are settled.
- 2026-11-07: #242 test fix: the fake servers (`PackFixtureURLProtocol`, `ScriptedAssetProtocol`) drop a connection only after the task has received the bytes, so a resume never starts from 0.
- 2026-11-07: #243 as built: the remove alert promises lists back only for a language with built-in lists (`hasBuiltInLists`), others get `languages.remove.learning.noLists`; the Languages screen has its own Edit/Done (`languages.edit`, `languages.done`, id `languages_edit`) so it follows the in-app language; new keys `languages.cancel`, `.remove`, `.lists` ("English word lists"), ids `pack_installed_<id>`, `pack_row_eng`, `dictionary_order_more_languages`; sizes use `ByteCountFormatStyle(.file)` in the in-app language; "Word forms" in a row's contents is Greek's only (the catalog has no field for it). The remove message still names word forms and lists for languages without them (follow-up).
- 2026-11-08: #243, rebased on E4: the remove alert finds a learned pair with E4's `LearningPairs.pair` and names it with `LearnViewModel.pairName` instead of its own copies; Settings keeps both Languages rows, Learning → Languages (`settings_learning_languages`) and Dictionaries → Languages (`dictionary_languages_link`).
