# LibreDict overview

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-10-27 · Epic: — · Tickets: — · Updated: 2026-10-29

This spec describes the app as shipped in 1.4.0 (tag `v1.4.0`, master `f0f806e`), plus the v2.0.0 changes merged since (see History). Read it before any design, development, testing or review task, then read the spec of your epic. It describes the code as it is now. The last sections list what v2.0.0 will change. Paths are relative to the repo root. Links work from this folder.

## Why

LibreDict is a free offline dictionary for iPhone and iPad. It has no account, no ads and no analytics. The app makes no network calls of its own: only the user-initiated mail and App Store links leave the device. The code is MIT ([LICENSE](../../LICENSE)), and each dictionary keeps its own license.

| | |
|---|---|
| Platforms | iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), iOS/iPadOS 17.0+ on every target. iPadOS 26 has its own layout rules (see below) |
| Stack | SwiftUI, Swift 5 language mode, [GRDB](https://github.com/groue/GRDB.swift) 6.24+ (the only dependency, an SPM package in the Xcode project), SQLite FTS5, XCTest and XCUITest |
| Interface languages | en (source), ru, es, ar (right to left), el |
| Dictionaries | 9 bundled sources in 5 language pairs, 416,946 entries in total. Users can import more |
| Identity | The display name "LibreDict" comes from the build setting `INFOPLIST_KEY_CFBundleDisplayName`. The partial [Info.plist](../../DictApp/DictApp/Info.plist) holds only `GIT_DESCRIBE`. Bundle id `com.kyukhin.DictApp`, version 1.4.0 (build 4). The project, target and scheme are still named `DictApp` |
| Store | App Store id 6763217128. Listings are in [metadata/](../../metadata), screenshots in [Screenshots/](../../Screenshots), the release log in [CHANGELOG.md](../../CHANGELOG.md) |

## Behaviour

### Screens

[ContentView](../../DictApp/DictApp/Views/ContentView.swift) is a `TabView` with four tabs: Search, History, Bookmarks and Settings. Each tab has its own `NavigationStack`.

| Screen | What the user sees | View · logic |
|---|---|---|
| Search | A search-as-you-type field (150 ms debounce) and up to 50 results. Each result shows the headword, a source badge (`Es–En · WN`), the phonetic, the part of speech, a 2-line snippet and a colour stripe per source. With an empty field it shows the 10 most recent History words. There is a "no results" view | [SearchView](../../DictApp/DictApp/Views/SearchView.swift) · `SearchViewModel` |
| Reading Mode | An open-book toggle on Search and Definition that keeps the screen awake through `UIApplication.shared.isIdleTimerDisabled`. It lasts for the session only and is not persisted. It turns off when the app goes to `.background`, but not on `.inactive` (#5, #127) | `ReadingModeToolbarButton` in DefinitionView.swift · `ReadingModeService` in ReviewRequestService.swift |
| Definition | The headword, phonetic, part of speech and the definition as Markdown (inline syntax only, selectable). A speaker button next to the headword reads it aloud (TTS), and is hidden when the device has no voice for the headword's language (#202). Toolbar: Reading Mode, bookmark (adds the entry to My words or removes it, #138). Opening the screen records History and counts towards the review prompt | [DefinitionView](../../DictApp/DictApp/Views/DefinitionView.swift) · `DefinitionViewModel` |
| History | Up to 100 words, newest first, each with its source stripe and a local-time caption ("Today, 8:41 PM", #114). A Clear button removes all of them | [HistoryView](../../DictApp/DictApp/Views/HistoryView.swift) · `HistoryViewModel`, `HistoryTimestamp` |
| Bookmarks | My words (the former bookmarks, until #158 replaces the tab), newest first, with a one-line snippet. Swipe to delete. No stripe | [BookmarksView](../../DictApp/DictApp/Views/BookmarksView.swift) · `BookmarksViewModel` |
| Settings | Sections in this order: Language, Result sorting, Dictionaries, Learning Mode ("Coming Soon" stub), Support, About (name, tagline, description), Version with a license note | [SettingsView](../../DictApp/DictApp/Views/SettingsView.swift) · `SettingsViewModel` |
| Language | A pushed list of the 5 languages with the localised name, the native name and a checkmark. Picking a language rebuilds the whole UI at once | `UILanguagePickerView` in SettingsView.swift · `LocalizationManager` |
| Result sorting | A picker with two modes: Relevance (the default) and Preferred dictionary first (#6) | SettingsView · `SettingsService` |
| Dictionary Order | One row per language pair, e.g. "Spanish – English". Each row has a drag grip, the summed entry count, an (i) button and one toggle. Disabled pairs stay in the list, greyed out and still draggable. The list reloads every time the screen appears (#92, #105) | [DictionaryOrderView](../../DictApp/DictApp/Views/DictionaryOrderView.swift) · `SettingsViewModel` |
| Dictionary info (i) | One section per source of the pair: provider, direction, source ID, version, entry count and the full license (#91) | [DictionaryDetailView](../../DictApp/DictApp/Views/DictionaryDetailView.swift), a pure renderer |
| Manage Dictionaries | Imports a `.json`, `.sqlite` or `.db` file through the system file picker, then shows a message with the entry count. Also shows a reference of the supported formats | [ManageDictionariesView](../../DictApp/DictApp/Views/ManageDictionariesView.swift) · `ManageDictionariesViewModel` |
| Support | Report a bug: the mail sheet, then a `mailto:` link, then a "copy address" alert as the last fallback. Write a review: an App Store deep link (#81). Credits: the data sources and a "Full license information coming soon." placeholder | `SupportViewModel`, `SupportService`, `MailComposeView`, `CreditsView` |
| Version | `AppVersion.current.displayString`, i.e. the `git describe` of the build (see Release) | SettingsView · [AppVersion](../../DictApp/DictApp/Models/AppVersion.swift) |

`AboutView.swift` is an empty leftover: About is a section of Settings.

### Rules worth knowing

- Search matches both headwords and definition text, because FTS indexes both columns. An English query therefore also finds reverse translations.
- `nil` enabled sources means all dictionaries are on (a fresh install). An explicitly empty set returns no results.
- History stores the word text and the source of the entry viewed last. A History row (or a Recent word on Search) reopens the entry of that stored source, also when the source is disabled. A missing entry (a row from before 1.3.0 with no source, a dropped headword, a removed import) shows "not found"; there is no lookup in other sources (#138).
- The bookmark star and the Bookmarks tab read and write My words, keyed by `EntryKey` `(source, word)`, never by a row id (#138). A key that no longer resolves stays stored and the tab skips it.
- TTS (`AVSpeechSynthesizer`) reads each headword in its source's headword language (#202). `SpeechService.language(forSource:)` takes the first language of `DictionaryGrouping.parse` and maps it to a voice: `eng` en-US, `rus` ru-RU, `spa` es-ES, `arb` ar-SA, `ell` el-GR. So `freedict-eng-spa`, `freedict-eng-ell` and `wordnet-eng-ell` speak English. Imports declare no language and get `en-US`, unless the file is named like a bundled source ID.
- The review prompt (#12) needs at least 5 Definition views and 30 s, then 10 min, then 60 min of cumulative active time. It fires at most once per session and three times per install, and Apple decides whether it shows. `-disableReviewPrompt` turns it off.
- On a fresh install or after an update, Search appears at once with every dictionary searchable: the app reads the bundled file in place, nothing is unpacked (#138).
- Arabic: a bare (unvocalised) query finds vocalised headwords. A vocalised query does not (known limitation since 1.3.0). Greek: search ignores accents, case and final sigma, in headwords and in English → Greek translations (#87). Imported dictionaries are searched with their diacritics as stored.

### iPad and iPadOS 26

- iPhone supports portrait and both landscapes (no upside down). iPad supports all four orientations.
- On iPadOS 26 the tabs are a floating strip in the navigation bar, with no `UITabBar`. Search uses `.navigationBarDrawer(displayMode: .always)` plus `.searchPresentationToolbarBehavior(.avoidHidingContent)`, so the strip stays visible while the field holds a query (#120). Dictionary Order pins an inline title (#123). Both checks use the device idiom, not the width, so Split View resizes never change them.
- The language selector is a custom list because `Picker(.navigationLink)` renders empty rows on iPad iOS 17.5.

### Decisions on record

- 2026-10-16 (Kirill): Greek ships as one "Greek – English" pair of four sources. The Freelang origin of `freedict-eng-ell` is accepted.
- 2026-10-21 (Kirill): no custom review prompt (#83 went to the wishlist under App Review guideline 5.6.1). #12 and #81 cover reviews.
- 2026-10-22 (Kirill): bookmarks are removed in 2.0.0 (see Upcoming changes).
- 2026-10-26: archives must be built from a tagged commit. 1.4.0 was archived before tagging and shows `1.3.0-20-gbd22843` in Settings.
- 2026-10-27 (Kirill): bug reports keep the marketing version and build number. Since #196 every App Store build sits on its release tag, so they identify the commit. The unused `AppVersion.verboseString` is removed (#203).
- 2026-10-27 (Kirill): `-resetData`, `-clearFixtureImports` and `-importFixtureViaCallback:` work in DEBUG builds only (#203). No user can pass launch arguments to an App Store build, so this is hygiene, not security. The 14 KB import fixtures stay in the bundle.
- 2026-10-27 (Kirill): the old Cline rulebook and development guide are deleted in favour of the agent prompts in `.claude/agents/`, the README and the specs (#203). `docs/REMOTE_CI_SETUP.md` stays as it is until CI moves to a new machine.
- 2026-10-27 (PM): with no voice for the headword's language, Definition hides the speaker button rather than read the word with another language's voice (#202).

## Design

### Code map

The app code is in `DictApp/DictApp/`. These are Xcode groups, not a synchronized folder, so a new file needs a `project.pbxproj` edit.

| Path | Contents |
|---|---|
| [DictApp.swift](../../DictApp/DictApp/DictApp.swift) | `@main`. Runs the launch sequence (below) and sets the root environment (`\.locale`, `\.layoutDirection`, `.id(language)`) and the scene-phase hooks (review timer, Reading Mode) |
| `Models/` | [Models.swift](../../DictApp/DictApp/Models/Models.swift): the GRDB records `DictionaryEntry`, `HistoryItem` and `DictMetadata`, the stable entry key `EntryKey`, plus `SourceStat`, `DictionaryPair`, `DictionaryItem` and `ResultSortMode`. Also `AppVersion`, `AppConstants` and `UILanguage` |
| `Services/` | [DatabaseService](../../DictApp/DictApp/Services/DatabaseService.swift) (an `actor`; the same file holds `Search` and the user database migrator), [SettingsService](../../DictApp/DictApp/Services/SettingsService.swift) (also `KeyValueStore`, `DictionaryDefaults` and `DictionaryGrouping`), `LocalizationManager`, `ReviewRequestService` (also `ReadingModeService`), `SupportService`, `SpeechService` |
| `ViewModels/` | One `@MainActor ObservableObject` per screen |
| `Views/` | SwiftUI views. `SourceStripeRow` is shared by Search and History |
| `Resources/` | `seed.sqlite` (the dictionary file), `Schema.sql` (unused since #138, removed by #140), `Localizable.xcstrings`, `SupportedLocales.json` and the import test fixtures |
| `DictApp/Assets.xcassets` | Stripe colours `Sources/<source id>`, with the fallback `Sources/default` |

Layering: views hold no SQL and no business rules. Pure logic lives in caseless enums and static functions that unit tests call without a database: `Search` (folding, the FTS query, `assemble`), `DictionaryGrouping`, `DictionaryDefaults`, `HistoryTimestamp`, `AppVersion`, and the `nonisolated static` naming helpers of `SettingsViewModel`. `DatabaseService` is the only code that touches SQLite. `SettingsService` and `ReviewRequestService` are the only code that touches `KeyValueStore`. Services are `.shared` singletons with injectable initialisers for tests.

### Bundled data: `seed.sqlite`

- The seed is [`DictApp/DictApp/Resources/seed.sqlite`](../../DictApp/DictApp/Resources), 134,860,800 bytes (~129 MiB), stored in Git LFS (`*.sqlite` in `.gitattributes`). Without `git lfs pull` it is a pointer file and the app fails at launch.
- [`Scripts/build_seed.py`](../../Scripts/build_seed.py) builds it and needs `pip install nltk requests defusedxml`. Downloads are cached in `Scripts/.cache/`. The script writes the schema, runs each builder, rebuilds FTS and runs `VACUUM`. WordNet (via NLTK) and OpenRussian are built inside the script. The other builders are `build_freedict_eng_spa.py` (FreeDict TEI for any pair), `build_spanish_wordnet.py`, `build_arabic_wordnet.py` (with `arabic_normalize.py`) and [`build_greek.py`](../../Scripts/build_greek.py) (the four Greek sources, `normalize_greek`, `decompose_greek`; run alone it performs a folding self-check). `generate_seed_db.py` and `download_wordnet.py` are legacy and not used for the shipped seed.
- Source IDs follow two patterns. Monolingual and legacy sources use the bare provider name (`wordnet`, `openrussian`). All others use `provider-src-tgt` with ISO 639-3 codes.
- Every row has a `word_normalized` search key. It equals `word` for the en, ru and es sources and is harakat-stripped for Arabic. For the four Greek sources it is Greek-folded, and their definitions store Greek in NFD, so FTS indexes it accent-free.
- Since #138 the app attaches the seed read-only as `dict` (see Database) and reads its `dict_metadata.word_count` for the Settings counts. `built_at` is no longer read; #140 drops it when the seed becomes `dictionaries.sqlite`.

| Source ID | Pair row | Badge | Entries | Version | License |
|---|---|---|---|---|---|
| `wordnet` | English | WordNet | 147,306 | 3.0 | WordNet 3.0 (BSD-style) |
| `openrussian` | Russian – English | OpenRussian | 45,647 | 2024 | CC BY-SA 4.0 |
| `freedict-eng-spa` | Spanish – English | En–Es · FD | 58,946 | 2025.11.23 | CC BY-SA 3.0 |
| `wordnet-spa-eng` | Spanish – English | Es–En · WN | 36,371 | OMW 1.4 / WordNet 3.0 | CC BY 3.0 |
| `wordnet-arb-eng` | Arabic – English | Ar–En · WN | 17,785 | OMW 1.4 / WordNet 3.0 | CC BY-SA 3.0 |
| `freedict-ell-eng` | Greek – English | El–En · FD | 41,589 | 2025.11.23 | CC BY-SA 3.0 |
| `wordnet-ell-eng` | Greek – English | El–En · WN | 17,882 | OMW 1.4 / WordNet 3.0 | Apache 2.0 |
| `freedict-eng-ell` | Greek – English | En–El · FD | 20,745 | 0.1.1 | CC BY-SA 3.0 (Freelang origin) |
| `wordnet-eng-ell` | Greek – English | En–El · WN | 30,675 | OMW 1.4 / WordNet 3.0 | Apache 2.0 |

Pair keys are runtime-only and also serve as accessibility ids: `eng`, `eng-rus`, `eng-spa`, `arb-eng` and `ell-eng`, plus `custom:<id>` for imports. They come from `DictionaryGrouping.pairKey(forSource:)`. A new bundled bilingual source needs an entry in `DictionaryGrouping.bundledSourceIDs`, a badge in `DictionaryEntry.sourceLabel`, a colour set and a Credits line. If it is a UI language's dictionary, it also needs an entry in `DictionaryDefaults.preferredSources`.

### Database (#138)

The full design is [0129-dictionary-file.md](0129-dictionary-file.md).

- `DatabaseService` keeps one GRDB `DatabasePool` (WAL) on `Application Support/DictApp/user.sqlite`. `Configuration.prepareDatabase` attaches the bundled `seed.sqlite` to every connection as `dict`, with `file:<path>?mode=ro&immutable=1`. SQL always qualifies `dict.`; a write to it fails with `SQLITE_READONLY`. No GRDB connection is opened on the bundle (the #111 crash rule).
- A GRDB `DatabaseMigrator` creates the user schema. Migrations are append-only, named `<epic>-<n>-<what>`. `129-1-core`:

| Table | Columns and rules |
|---|---|
| `history` | `word` (UNIQUE), `source` (the entry viewed last, #6) and `looked_at` (UTC text from `datetime('now')`) |
| `my_words` | `source`, `word COLLATE NOCASE`, `added_at`; primary key `(source, word)`, `WITHOUT ROWID` |
| `imported_entries` | The dictionary `entries` columns plus `created_at`. Unique on `(word COLLATE NOCASE, source)`, indexed on `source`. Ids start at 2^40, so one `Int64` identifies a row in either store |
| `imported_fts` | FTS5 with external content from `imported_entries`, same tokenizer as `entries_fts`. Triggers `imported_ai`, `imported_ad`, `imported_au` |
| `imported_sources` | One row per imported dictionary: `source`, `imported_at`, `from_lang` and `to_lang` (NULL until #208) |
| `user_meta` | `key`, `value` (#139's migration marker) |

- The dictionary file holds `entries` (unique on `(word COLLATE NOCASE, source)`), `entries_fts` and `dict_metadata`, as `build_seed.py` writes them (Bundled data).
- User data points at entries by `EntryKey` `(source, word)`. `entry(for:)` tries `dict.entries`, then `imported_entries`.
- A 1.x `Application Support/DictApp/dict.sqlite` stays on disk unread until #139 moves its data.

### Launch (#138)

`DictApp.initializeDatabase()` runs once per app, not once per iPad window:

1. `-resetDatabase` (DEBUG) deletes `user.sqlite` and any 1.x `dict.sqlite`, each with its `-wal` and `-shm`.
2. `setup()` opens the pool, which attaches `dict`, and runs the migrator. This takes milliseconds.
3. In DEBUG builds the launch test hooks run (`-resetData`, `-clearFixtureImports`).
4. `normalizeDictionaryPreferences` runs on the `dict.dict_metadata` sources (pair invariants).
5. `isReady = true` shows the UI.

There is no unpack, sync or progress state, and the dictionary data is stored once, in the bundle.

### Imported dictionaries

`ManageDictionariesViewModel.performImport` takes the file name without its extension as the source ID.
- A JSON file `[{word, definition, phonetic?, pos?}]` goes through `importJSON`.
- A SQLite or DB file with an `entries` table goes through `importSQLite`, which opens it read-only.

Both write `imported_entries` in one transaction with `INSERT OR IGNORE` and `word_normalized = word`, so imports get no Arabic or Greek normalisation. A row whose key the dictionary file already has is skipped, and the source gets an `imported_sources` row once it has rows (#138). After a successful import the source is enabled and appended to a stored order (#105). A file named like a bundled bilingual ID joins that pair. Imports have no metadata row, and there is no UI to delete them.

### Search

`SearchViewModel.onQueryChanged` debounces for 150 ms. It then calls `DatabaseService.search` (relevance), or `searchPreferred` when the mode is "preferred" and an order is stored.
- **Sanitising** (`sanitizeFTS`): keep Unicode letters, marks, digits and spaces, then trim. An empty result returns nothing.
- **FTS query** (`Search.ftsQuery`): the query is folded with `Search.foldGreek`, which must match `normalize_greek` scalar for scalar. If folding changes nothing, the MATCH is `q*`. Otherwise it is `(raw*) OR (folded*)`. Several tokens are ANDed.
- **Arabic**: there is no query-side normalisation. A bare query matches the harakat-free `word_normalized`.
- **Ranking**:
  1. an exact `word_normalized` match on the folded or raw key (NOCASE);
  2. a prefix `LIKE` match;
  3. FTS `rank`.

  Results are capped at 50. Each query reads `dict.entries_fts` joined with `dict.entries`, plus a `UNION ALL` branch over `imported_fts` and `imported_entries` when an enabled source is imported; one ORDER BY and one LIMIT rank the union (#138).
- **Enabled sources**: `SettingsService.enabledSources` becomes `source IN (...)`. `nil` means no filter.
- **Preferred dictionary first** (#6, #92): one query per pair group in Dictionary Order (`DictionaryGrouping.sourceGroups`), taking the top 4 of each (`Search.preferredDictionaryTopN`). A relevance tail over all enabled sources follows, minus the rows already taken. The pure `Search.assemble` combines them.
- **Re-runs**: Search `onAppear` re-runs the query to pick up Settings changes.

### Preferences

`SettingsService` stores everything through `KeyValueStore`. Today that is `UserDefaults`; the seam exists for iCloud sync (#73, v2.1.0).

| Key | Meaning |
|---|---|
| `ui_language` | The in-app language code. Absent means the device language |
| `enabled_sources` | A JSON array of source IDs. Absent means all are enabled |
| `dictionary_order` | A JSON array of source IDs. It stays absent until Settings first loads the list, then defaults to entry count descending with the UI language's dictionaries first (#74) |
| `result_sort_mode` | `relevance` (default) or `preferredDictionary` |
| `review_*` | The review-prompt counters, owned by `ReviewRequestService` |

Pair invariants (#92):
- all sources of a pair share one enabled state (enabled if any member is);
- the sources of a pair stay next to each other in the order.

They are enforced at launch and on every Dictionary Order load, with writes only on change. Reading Mode is not persisted.

### Localization

- [Localizable.xcstrings](../../DictApp/DictApp/Resources/Localizable.xcstrings) has 90 keys, all translated into en, ru, es, ar and el. `knownRegions` is en, Base, ru, es, ar, el. [SupportedLocales.json](../../DictApp/DictApp/Resources/SupportedLocales.json) lists the picker languages: code, catalog key and native name.
- `LocalizationManager` picks the language in this order: the stored `ui_language`, the device's preferred languages, then en. A switch sets `\.locale`, `\.layoutDirection` (RTL for ar) and `.id(code)` at the app root, which rebuilds the view tree.
- A string built outside `Text` must resolve against the in-app language's `.lproj` (`LocalizationManager.localizedBundle`, `SettingsViewModel.localizedString`). `String(localized:locale:)` alone reads the device-language table.
- Composed Arabic strings start with U+200F so they read right to left (#119). Brand names, "LibreDict", `display_name` and the badge text are not translated. The implementing agent writes the translations for all five languages.

### Version, release, support

- **Version** (#39): the scheme's Build pre-action [`generate_build_info.sh`](../../Scripts/generate_build_info.sh) writes the git-ignored `DictApp/DictApp/BuildInfo.xcconfig` with `git describe`. A HEAD on a tag gives the bare tag; otherwise the value looks like `v1.4.0-N-g<sha>`. The value then flows through `Version.xcconfig`, `GIT_DESCRIBE`, Info.plist and `AppVersion.displayString`, which strips the leading `v`. A Run Script phase fails the build when the value is stale or `.git` is missing.
- **Release order**: merge the version bump and the CHANGELOG cut to master, push the annotated tag `vX.Y.Z` ("X.Y.Z version of the Dict app."), archive from the tagged commit, then submit. #196 (v1.4.1) adds an archive guard that fails untagged archives.
- **CHANGELOG.md** follows Keep a Changelog, one `[#N]` line per change.
- **Support mail** goes to `support@libredict.app` with the subject `[LibreDict <marketing version> b<build>] …` and an English telemetry block: version, iOS, device model, UI language and locale.

## Test plan

These tests prove today's behaviour. A feature spec maps its acceptance criteria to tests in the same way.

| Area | Unit tests (classes) | UI suites |
|---|---|---|
| Search, ranking, filters | `DictAppTests`, `SearchAssembleTests`, `SearchProbeTests` (1.4.0 probe, #138) | `SearchFlowTests`, `DictionaryFilterTests`, `SearchHighlightTests` |
| Greek and Arabic search | `GreekFoldAndBadgeTests`, `DictAppTests` (#10, #87) | `GreekDictionaryTests`, `ArabicLocalizationTests` |
| History, My words (bookmarks), user database | `DictAppTests`, `HistoryTimestampTests`, `UserDatabaseTests` (#138) | `HistoryFlowTests`, `BookmarkFlowTests` |
| Preferences, pairs, order | `SettingsServiceTests`, `DictionaryGroupingTests`, `DictionaryDefaultsTests`, `SettingsViewModelPairTests` | `DictionaryPairGroupingTests`, `DictionaryOrderDefaultTests`, `DictionaryOrderReorderTests`, `DictionaryOrderRefreshTests` |
| Dictionary info, import | `DictionaryInfoDetailTests`, `SettingsViewModelPairTests` (#105), `DictAppTests` | `DictionaryInfoTests`, `ImportDictionaryTests` |
| Localization | `DictAppTests` (#88), `ArabicBidiOrderTests` | `SpanishLocalizationTests`, `ArabicLocalizationTests`, `GreekLocalizationTests` |
| Reading Mode, review, version | `ReadingModeServiceTests`, `ReviewRequestServiceTests`, `DictAppTests` | `ReadingModeTests`, `VersionDisplayTests`, `ReportBugFlowTests` |
| Speaker (TTS) language | `SpeechLanguageTests` (#202) | `ArabicLocalizationTests`, `GreekLocalizationTests` (the button is present) |
| Navigation, iPad | — | `NavigationTests`, `iPadSpecificTests` |

### Unit tests

There are 226 tests in 15 classes, all in [DictAppTests.swift](../../DictApp/DictAppTests/DictAppTests.swift), target `DictAppTests`. The real app hosts the tests. A class that swaps the shared database first calls `DictAppTests.waitForHostAppLaunch()`, then `setup(userPath:dictionaryURL:)` on a temp user database. Test seams:
- `TestDictionary.make(rows:)`: a dictionary file with the bundled file's schema and only the given rows; `TestDictionaryFixture` writes a new one and reopens the service as a test adds rows (#138);
- `InMemoryKeyValueStore`;
- `FakeIdleTimer`.

The unit tests do not run in parallel (see [DictApp.xctestplan](../../DictApp/DictApp.xctestplan)).

### UI tests

- There are 20 suites with 93 tests in `DictAppUITests/TestCases/`, plus the 2 Xcode template launch tests. They use the page objects in `PageObjects/`, the ids in [AccessibilityIdentifiers.swift](../../DictApp/DictAppUITests/TestHelpers/AccessibilityIdentifiers.swift), the data in `TestData.swift` and the helpers in [UITestHelpers.swift](../../DictApp/DictAppUITests/TestHelpers/UITestHelpers.swift).
- Launch arguments:

  | Argument | Effect |
  |---|---|
  | `-resetData` | Clears My words (bookmarks), history, enabled sources, the order, the review counters and the in-app language. Imported entries stay (DEBUG only) |
  | `-disableReviewPrompt` | Turns off the review prompt |
  | `-resetDatabase` | Deletes the user database and any 1.x database (DEBUG only) |
  | `-clearFixtureImports` | Removes the rows imported from the test fixture and its `imported_sources` row (DEBUG only) |
  | `-importFixtureViaCallback:json` or `:sqlite` | Skips the file picker and imports the bundled fixture (DEBUG only) |
  | `-AppleLanguages` / `-AppleLocale` | Set the language in the language suites |

  Five log-heavy suites set `OS_ACTIVITY_MODE=disable` so XCTest logging cannot crash the app on iOS 17.5 (#125): DictionaryInfo, DictionaryPairGrouping, DictionaryOrderRefresh and the two Greek suites.
- Every suite creates `TabBarPage` right after launch. Its initialiser waits in `waitForDictionariesReady()` until the Search screen is up (30 s); every dictionary is searchable from the first frame (#138).
- Switch tabs only through `TabBarPage.tap(_:)` / `XCUIApplication.tabButton(_:)`. With a `UITabBar` (iPhone, iPad 17.x) the button is found by index. On the iPadOS 26 strip it is found by the SF Symbol identifier: `magnifyingglass`, `clock`, `bookmark` or `gearshape`. The helper dismisses the keyboard first, checks that the tab got selected and pops a pushed Definition (#76, #102, #104).
- `scrollToElement` decides reachability by geometry and never reads `isHittable`, which can throw on slow simulators.

### Matrix and recipe

- The matrix is four simulators: iPhone and iPad, each on iOS 17.5 and on iOS 26.4. The full regression runs before a release. A ticket runs the suites of the areas it touches on all four. The 1.4.0 regression (2026-10-22) was green: 236 unit tests, and 93 UI tests on iPhone and 95 on iPad, because `iPadSpecificTests` skips on iPhone.
- Run one suite per `xcodebuild` run (`-only-testing:DictAppUITests/<Suite>`) and uninstall the app between runs (`xcrun simctl uninstall <device> com.kyukhin.DictApp`). Never run the whole bundle in one go on a warm simulator. Keep one booted simulator per stream, and don't build or rebuild the seed while streams run.
- Since #74, `-resetData` also clears the in-app language, so language suites do not need an erased simulator for that.
- Intel CI (x86_64, iOS 18.5) is described in [REMOTE_CI_SETUP.md](../REMOTE_CI_SETUP.md). Two tests are accepted skips there (#60).

### Known gotchas

- A seed that was never pulled from LFS makes every UI test time out.
- With the simulator setting "Connect Hardware Keyboard" on, typed text never reaches the field. Turn it off with `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`.
- `HistoryFlowTests` can fail when it runs after other suites on a warm simulator. It passes when run alone.
- A SwiftUI `List` materialises only the visible rows, so `cells.count` under-reports. Scroll first, then assert.
- The back button carries the previous screen's title, not "Back". Tap the leading navigation-bar button by index.

## Upcoming changes (v2.0.0, due 2026-11-27)

The specs of these epics will replace parts of this overview:

- #129 Dictionaries as one read-only file ([0129-dictionary-file.md](0129-dictionary-file.md)): #138 attaches the bundled file and moves user data to the user database (Database, Launch, Imported dictionaries above). Still to come: #139 migrates 1.x data, #140 builds `dictionaries.sqlite` and drops `built_at` and the seed resources.
- #131 Learning with spaced repetition: a Learn tab replaces Bookmarks, giving the tabs Search · Learn · History · Settings. Bookmarks migrate into a "My words" list, and the Definition bookmark becomes "Learn".
- #136 Word forms: search by any inflected form (Greek from Wiktionary, English through WordNet morphy) and inflection tables on Definition. Affects Search, Definition and the seed pipeline.
- #146 Quick dictionary chips on Search, in Dictionary Order sequence. Affects Search and Preferences.
- #130 Word lists by level and list import · #166 Learning statistics · #132 Greek conjugation drill · #133 Grammar reference · #134 Example sentences.
- Elsewhere: #196 archive guard (v1.4.1); #73 iCloud preference sync (v2.1.0).

## Open questions

1. Resolved by #202: TTS speaks each headword in its source's language (see Rules worth knowing).
2. Resolved (Kirill, 2026-10-27): History ignoring the stored `source` is a bug, fixed in E1 (#138, see [0129-dictionary-file.md](0129-dictionary-file.md)).

## History

- 2026-10-26: First version, describing master `f0f806e` (1.4.0).
- 2026-10-27: Approved by Kirill.
- 2026-10-27: Open questions 3–5 resolved and moved to Decisions on record (#203): the launch test hooks are DEBUG only, `AppVersion.verboseString` is gone, two stale root documents are deleted, and the agent prompts name the right unit-test target.
- 2026-10-27: #202 speaks each headword in its source's language and hides the speaker button when the device has no voice for it (PM decision). Resolves open question 1.
- 2026-10-29: #138: the app attaches the bundled seed read-only as `dict` and keeps user data in `user.sqlite`. The unpack, its progress bar and the 1.x schema code are gone. History and Recent words reopen the stored source; the bookmark star and tab use My words. Updated Screens, Rules, Code map, Bundled data, Database, Launch, Imported dictionaries, Search, Localization and the test sections.
