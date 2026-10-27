# LibreDict overview

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-10-27 · Epic: — · Tickets: — · Updated: 2026-10-27

This spec describes the app as shipped in 1.4.0 (tag `v1.4.0`, master `f0f806e`). Read it before any design, development, testing or review task, then read the spec of your epic. It describes the code as it is now. The last sections list what v2.0.0 will change. Paths are relative to the repo root. Links work from this folder.

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
| Search | A search-as-you-type field (150 ms debounce) and up to 50 results. Each result shows the headword, a source badge (`Es–En · WN`), the phonetic, the part of speech, a 2-line snippet and a colour stripe per source. With an empty field it shows the 10 most recent History words. There is a "no results" view. The bar "Preparing dictionaries… 35%" sits above the tab bar while the bundled dictionaries unpack | [SearchView](../../DictApp/DictApp/Views/SearchView.swift) · `SearchViewModel` |
| Reading Mode | An open-book toggle on Search and Definition that keeps the screen awake through `UIApplication.shared.isIdleTimerDisabled`. It lasts for the session only and is not persisted. It turns off when the app goes to `.background`, but not on `.inactive` (#5, #127) | `ReadingModeToolbarButton` in DefinitionView.swift · `ReadingModeService` in ReviewRequestService.swift |
| Definition | The headword, phonetic, part of speech and the definition as Markdown (inline syntax only, selectable). Toolbar: speaker (TTS), Reading Mode, bookmark. Opening the screen records History and counts towards the review prompt | [DefinitionView](../../DictApp/DictApp/Views/DefinitionView.swift) · `DefinitionViewModel` |
| History | Up to 100 words, newest first, each with its source stripe and a local-time caption ("Today, 8:41 PM", #114). A Clear button removes all of them | [HistoryView](../../DictApp/DictApp/Views/HistoryView.swift) · `HistoryViewModel`, `HistoryTimestamp` |
| Bookmarks | Bookmarked entries, newest first, with a one-line snippet. Swipe to delete. No stripe | [BookmarksView](../../DictApp/DictApp/Views/BookmarksView.swift) · `BookmarksViewModel` |
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
- History stores the word text and the source of the entry viewed last. A History row (or a Recent word on Search) reopens by an exact case-insensitive lookup of `word` in any source, with an FTS search as the fallback.
- Bookmarks point at `entries.id`. They survive dictionary updates because updates keep ids (#108).
- TTS uses `AVSpeechSynthesizer` with the `en-US` voice for every word.
- The review prompt (#12) needs at least 5 Definition views and 30 s, then 10 min, then 60 min of cumulative active time. It fires at most once per session and three times per install, and Apple decides whether it shows. `-disableReviewPrompt` turns it off.
- On a fresh install or after an update, Search appears at once. The bundled dictionaries unpack in the background, and each one is searchable as soon as it commits. The current query re-runs after each one.
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

## Design

### Code map

The app code is in `DictApp/DictApp/`. These are Xcode groups, not a synchronized folder, so a new file needs a `project.pbxproj` edit.

| Path | Contents |
|---|---|
| [DictApp.swift](../../DictApp/DictApp/DictApp.swift) | `@main`. Runs the launch sequence (below) and sets the root environment (`\.locale`, `\.layoutDirection`, `.id(language)`) and the scene-phase hooks (review timer, Reading Mode) |
| `Models/` | [Models.swift](../../DictApp/DictApp/Models/Models.swift): the GRDB records `DictionaryEntry`, `HistoryItem`, `Bookmark` and `DictMetadata`, plus `SourceStat`, `DictionaryPair`, `DictionaryItem` and `ResultSortMode`. Also `AppVersion`, `AppConstants` and `UILanguage` |
| `Services/` | [DatabaseService](../../DictApp/DictApp/Services/DatabaseService.swift) (an `actor`; the same file holds `Search`, `BundledUnpackPlan` and `DictionaryUnpackStatus`), [SettingsService](../../DictApp/DictApp/Services/SettingsService.swift) (also `KeyValueStore`, `DictionaryDefaults` and `DictionaryGrouping`), `LocalizationManager`, `ReviewRequestService` (also `ReadingModeService`), `SupportService`, `SpeechService` |
| `ViewModels/` | One `@MainActor ObservableObject` per screen |
| `Views/` | SwiftUI views. `SourceStripeRow` is shared by Search and History |
| `Resources/` | `seed.sqlite`, `Schema.sql`, `Localizable.xcstrings`, `SupportedLocales.json` and the import test fixtures |
| `DictApp/Assets.xcassets` | Stripe colours `Sources/<source id>`, with the fallback `Sources/default` |

Layering: views hold no SQL and no business rules. Pure logic lives in caseless enums and static functions that unit tests call without a database: `Search` (folding, the FTS query, `assemble`), `DictionaryGrouping`, `DictionaryDefaults`, `BundledUnpackPlan`, `HistoryTimestamp`, `AppVersion`, and the `nonisolated static` naming helpers of `SettingsViewModel`. `DatabaseService` is the only code that touches SQLite. `SettingsService` and `ReviewRequestService` are the only code that touches `KeyValueStore`. Services are `.shared` singletons with injectable initialisers for tests.

### Bundled data: `seed.sqlite`

- The seed is [`DictApp/DictApp/Resources/seed.sqlite`](../../DictApp/DictApp/Resources), 134,860,800 bytes (~129 MiB), stored in Git LFS (`*.sqlite` in `.gitattributes`). Without `git lfs pull` it is a pointer file and the app fails at launch.
- [`Scripts/build_seed.py`](../../Scripts/build_seed.py) builds it and needs `pip install nltk requests defusedxml`. Downloads are cached in `Scripts/.cache/`. The script writes the schema, runs each builder, rebuilds FTS and runs `VACUUM`. WordNet (via NLTK) and OpenRussian are built inside the script. The other builders are `build_freedict_eng_spa.py` (FreeDict TEI for any pair), `build_spanish_wordnet.py`, `build_arabic_wordnet.py` (with `arabic_normalize.py`) and [`build_greek.py`](../../Scripts/build_greek.py) (the four Greek sources, `normalize_greek`, `decompose_greek`; run alone it performs a folding self-check). `generate_seed_db.py` and `download_wordnet.py` are legacy and not used for the shipped seed.
- Source IDs follow two patterns. Monolingual and legacy sources use the bare provider name (`wordnet`, `openrussian`). All others use `provider-src-tgt` with ISO 639-3 codes.
- Every row has a `word_normalized` search key. It equals `word` for the en, ru and es sources and is harakat-stripped for Arabic. For the four Greek sources it is Greek-folded, and their definitions store Greek in NFD, so FTS indexes it accent-free.
- `dict_metadata.built_at` holds each source's build time, and the app uses it as the version marker. Any seed rebuild therefore re-syncs every source on existing installs. Only changed rows are written.

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

### Database

The app database is `Application Support/DictApp/dict.sqlite`, opened in WAL mode through a GRDB `DatabasePool`. The schema comes from [Schema.sql](../../DictApp/DictApp/Resources/Schema.sql), and the fallback copy `DatabaseService.inlineSchema` must stay in sync with it. Migrations live in `applySchema` and `migrate`, and `PRAGMA user_version` is 1. GRDB enforces foreign keys.

| Table | Columns and rules |
|---|---|
| `entries` | `id`, `word`, `word_normalized` (search key), `definition` (Markdown), `phonetic`, `pos`, `source`, `created_at`. Unique on `(word COLLATE NOCASE, source)` |
| `entries_fts` | FTS5 with external content from `entries` over `word_normalized` and `definition`. Tokenizer `unicode61 remove_diacritics 2`. Kept in sync by the triggers `entries_ai`, `entries_ad` and `entries_au` |
| `dict_metadata` | One row per bundled source: English `display_name`, `version`, `license`, `url`, `word_count`, `built_at` (the unpack marker) and `description`. Imports have no row |
| `history` | `word` (UNIQUE), `source` (the entry viewed last, #6) and `looked_at` (UTC text from `datetime('now')`). Not linked to `entries` |
| `bookmarks` | `entry_id` (UNIQUE), referencing `entries(id) ON DELETE CASCADE`, and `created_at` |

Migrations so far: `dict_metadata.description` and `history.source` (added after a column check), and `user_version` 1, which adds `word_normalized` and rebuilds FTS (#10). The seed has the same `entries`, FTS and metadata shape. The app only ever ATTACHes it and never opens it as a connection of its own.

### Launch, unpack and update (#111, #108)

`DictApp.initializeDatabase()` runs once per app, not once per iPad window:

1. `setup()` opens the app database and applies the schema and migrations.
2. `prepareBundledSeed` ATTACHes the seed and registers every bundled source in `dict_metadata` in one transaction. A source that is not unpacked yet gets `built_at = ''`. The step returns a `BundledUnpackPlan` of the pending sources, i.e. those whose marker is missing, empty or different from the seed's. Plan order:
   1. new sources before stale ones;
   2. within each group, `wordnet` first;
   3. then the UI language's dictionaries;
   4. then the rest in seed order.
3. In DEBUG builds the launch test hooks run (`-resetData` and the others), then `normalizeDictionaryPreferences` (pair invariants).
4. `DictionaryUnpackStatus.begin(plan)` sets the progress state, then `isReady = true` shows the UI.
5. `startBundledUnpack` runs as a detached utility task, one transaction per source:
   - `UPDATE` the changed rows in place, matched on `word` NOCASE (this keeps ids and bookmarks);
   - `INSERT OR IGNORE` the missing rows;
   - copy the metadata row, whose `built_at` marker is written last.

   It never uses DELETE or REPLACE. The first failure stops the run, and the next launch resumes from the markers. The task finishes with a WAL checkpoint.

Progress is the share of bundled rows already present. `SearchViewModel.unpackFraction` floors it to whole percents. Without a bundled `seed.sqlite`, a `seed.json` fallback imports into an empty database, but no `seed.json` ships today. Because the seed stays in the bundle, the dictionary data is stored twice on disk. #129 removes the duplicate.

### Imported dictionaries

`ManageDictionariesViewModel.performImport` takes the file name without its extension as the source ID.
- A JSON file `[{word, definition, phonetic?, pos?}]` goes through `importJSON`.
- A SQLite or DB file with an `entries` table goes through `importSQLite`, which opens it read-only.

Both use `INSERT OR IGNORE` with `word_normalized = word`, so imports get no Arabic or Greek normalisation. After a successful import the source is enabled and appended to a stored order (#105). A file named like a bundled bilingual ID joins that pair. Imports have no metadata row, and there is no UI to delete them.

### Search

`SearchViewModel.onQueryChanged` debounces for 150 ms. It then calls `DatabaseService.search` (relevance), or `searchPreferred` when the mode is "preferred" and an order is stored.
- **Sanitising** (`sanitizeFTS`): keep Unicode letters, marks, digits and spaces, then trim. An empty result returns nothing.
- **FTS query** (`Search.ftsQuery`): the query is folded with `Search.foldGreek`, which must match `normalize_greek` scalar for scalar. If folding changes nothing, the MATCH is `q*`. Otherwise it is `(raw*) OR (folded*)`. Several tokens are ANDed.
- **Arabic**: there is no query-side normalisation. A bare query matches the harakat-free `word_normalized`.
- **Ranking**:
  1. an exact `word_normalized` match on the folded or raw key (NOCASE);
  2. a prefix `LIKE` match;
  3. FTS `rank`.

  Results are capped at 50.
- **Enabled sources**: `SettingsService.enabledSources` becomes `source IN (...)`. `nil` means no filter.
- **Preferred dictionary first** (#6, #92): one query per pair group in Dictionary Order (`DictionaryGrouping.sourceGroups`), taking the top 4 of each (`Search.preferredDictionaryTopN`). A relevance tail over all enabled sources follows, minus the rows already taken. The pure `Search.assemble` combines them.
- **Re-runs**: Search `onAppear` re-runs the query to pick up Settings changes, and each committed unpack source triggers a re-run (300 ms debounce).

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

- [Localizable.xcstrings](../../DictApp/DictApp/Resources/Localizable.xcstrings) has 91 keys, all translated into en, ru, es, ar and el. `knownRegions` is en, Base, ru, es, ar, el. [SupportedLocales.json](../../DictApp/DictApp/Resources/SupportedLocales.json) lists the picker languages: code, catalog key and native name.
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
| Search, ranking, filters | `DictAppTests`, `SearchAssembleTests` | `SearchFlowTests`, `DictionaryFilterTests`, `SearchHighlightTests` |
| Greek and Arabic search | `GreekFoldAndBadgeTests`, `DictAppTests` (#10, #87) | `GreekDictionaryTests`, `ArabicLocalizationTests` |
| Seed unpack and update | `DictAppTests` (#108, #111) | `BackgroundUnpackTests` |
| History, bookmarks | `DictAppTests`, `HistoryTimestampTests` | `HistoryFlowTests`, `BookmarkFlowTests` |
| Preferences, pairs, order | `SettingsServiceTests`, `DictionaryGroupingTests`, `DictionaryDefaultsTests`, `SettingsViewModelPairTests` | `DictionaryPairGroupingTests`, `DictionaryOrderDefaultTests`, `DictionaryOrderReorderTests`, `DictionaryOrderRefreshTests` |
| Dictionary info, import | `DictionaryInfoDetailTests`, `SettingsViewModelPairTests` (#105), `DictAppTests` | `DictionaryInfoTests`, `ImportDictionaryTests` |
| Localization | `DictAppTests` (#88), `ArabicBidiOrderTests` | `SpanishLocalizationTests`, `ArabicLocalizationTests`, `GreekLocalizationTests` |
| Reading Mode, review, version | `ReadingModeServiceTests`, `ReviewRequestServiceTests`, `DictAppTests` | `ReadingModeTests`, `VersionDisplayTests`, `ReportBugFlowTests` |
| Navigation, iPad | — | `NavigationTests`, `iPadSpecificTests` |

### Unit tests

There are 235 tests in 12 classes, all in [DictAppTests.swift](../../DictApp/DictAppTests/DictAppTests.swift), target `DictAppTests`. The real app hosts the tests. A class that swaps the shared database first calls `DictAppTests.waitForHostAppLaunch()`, then `setup(path:)` on a temp file. Test seams:
- `seedIfNeeded(bundledSeedURL:)` and `syncBundledSources`;
- `unpackFailureAfterInsert`;
- `InMemoryKeyValueStore`;
- `FakeIdleTimer`.

The unit tests do not run in parallel (see [DictApp.xctestplan](../../DictApp/DictApp.xctestplan)).

### UI tests

- There are 21 suites with 95 tests in `DictAppUITests/TestCases/`, plus the 2 Xcode template launch tests. They use the page objects in `PageObjects/`, the ids in [AccessibilityIdentifiers.swift](../../DictApp/DictAppUITests/TestHelpers/AccessibilityIdentifiers.swift), the data in `TestData.swift` and the helpers in [UITestHelpers.swift](../../DictApp/DictAppUITests/TestHelpers/UITestHelpers.swift).
- Launch arguments:

  | Argument | Effect |
  |---|---|
  | `-resetData` | Clears bookmarks, history, enabled sources, the order, the review counters and the in-app language. Imported entries stay (DEBUG only) |
  | `-disableReviewPrompt` | Turns off the review prompt |
  | `-resetDatabase` | Deletes the database (DEBUG only) |
  | `-unpackSourceDelay <s>` | Waits between unpacked sources (DEBUG only) |
  | `-clearFixtureImports` | Removes entries imported from the test fixture (DEBUG only) |
  | `-importFixtureViaCallback:json` or `:sqlite` | Skips the file picker and imports the bundled fixture (DEBUG only) |
  | `-AppleLanguages` / `-AppleLocale` | Set the language in the language suites |

  Five log-heavy suites set `OS_ACTIVITY_MODE=disable` so XCTest logging cannot crash the app on iOS 17.5 (#125): DictionaryInfo, DictionaryPairGrouping, DictionaryOrderRefresh and the two Greek suites.
- Every suite creates `TabBarPage` right after launch. Its initialiser waits in `waitForDictionariesReady()` until the Search screen is up and the unpack bar is gone (120 s on a fresh install).
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

- #129 Dictionaries as one read-only file: removes the bundled unpack and the `built_at` marker. User data (history, imports, learning) moves to a separate user database. A migration carries 1.x data over (#139). Affects Database, Launch and Imported dictionaries.
- #131 Learning with spaced repetition: a Learn tab replaces Bookmarks, giving the tabs Search · Learn · History · Settings. Bookmarks migrate into a "My words" list, and the Definition bookmark becomes "Learn".
- #136 Word forms: search by any inflected form (Greek from Wiktionary, English through WordNet morphy) and inflection tables on Definition. Affects Search, Definition and the seed pipeline.
- #146 Quick dictionary chips on Search, in Dictionary Order sequence. Affects Search and Preferences.
- #130 Word lists by level and list import · #166 Learning statistics · #132 Greek conjugation drill · #133 Grammar reference · #134 Example sentences.
- Elsewhere: #196 archive guard (v1.4.1); #73 iCloud preference sync (v2.1.0).

## Open questions

1. TTS reads every headword with the `en-US` voice (`SpeechService.speak`), including Russian, Spanish, Arabic and Greek. Should it use the entry's language?
2. History reopens a word by exact lookup in any source. It ignores the stored `source` and the enabled set, so the opened entry can come from a different dictionary than the row's stripe. Is that intended, or should it be fixed with #129?

## History

- 2026-10-26: First version, describing master `f0f806e` (1.4.0).
- 2026-10-27: Approved by Kirill.
- 2026-10-27: Open questions 3–5 resolved and moved to Decisions on record (#203): the launch test hooks are DEBUG only, `AppVersion.verboseString` is gone, two stale root documents are deleted, and the agent prompts name the right unit-test target.
