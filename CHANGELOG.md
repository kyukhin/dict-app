# Changelog

All notable changes to **LibreDict** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- [#296] A lesson closed early is kept for the day: the Today button reads "Continue lesson · 7 left" and resumes at the next unanswered question with its progress bar, and each answer still counts once. The next day starts a new lesson.
- [#141] The dictionary file now carries Greek word forms and inflection tables from a pinned Wiktionary snapshot, checked by a QA report on every build.
- [#142] Search finds a Greek word from any of its inflected forms, with or without accents: έγραψα shows γράφω right after the exact matches, captioned "aorist 1sg of γράφω". About 89% of the 5,000 most frequent Greek words are now findable, up from 39%.
- [#144] A Greek word's Definition screen shows its conjugation or declension table, with "All forms" for the rest of a verb's forms; Credits names Wiktionary as their source.
- [#143] Search finds an English word from its inflected forms through WordNet's morphy rules, such as went → go ("form of go") and mice → mouse ("plural of mouse").
- [#145] Dictionary chips under the Search field switch dictionaries on and off in one tap, in the Dictionary Order sequence; a long press offers "Only this" and "All" turns every one back on. The chips and the Settings switches are one setting, and results refresh at once.
- [#151] Word lists get their data model: built-in, imported and My words lists share one model, words link to their dictionary entry (also through word forms), and new words come by level, then by frequency with a light shuffle. No screen uses it yet.
- [#240, #241] Every dictionary file has the grammar and example sentence tables, empty until their data lands, and the pack catalog lists the language pairs to learn, Greek via Russian as a limited one.
- [#157] The learning engine's data: every word gets a recognition and a production card on a fixed 1–90-day ladder, graded by the answer and logged, with learning kept per language, each learned through a language pair offered by the dictionaries ("Greek via English"), and a day starting at 4 AM.
- [#152] The Greek pack carries Kirill Yukhin's Greek word lists A1, A2 and B1 (4,648 words, 88% linked to a dictionary entry) with frequency ranks from FrequencyWords, so new words come most frequent first. A QA report checks every build, and Credits names both sources.
- [#163] Learning statistics data: each day keeps the daily goal in force when it ended, and the app computes on the device the streak with up to 3 freezes, today's numbers, the 30-day series, accuracy by direction and tense, the hardest words and verbs, and each list's progress with a forecast.
- [#242] A language pack downloads from GitHub Releases only when the user asks, is checked against its pinned sha256 and size, and becomes searchable without a restart; a failed, cancelled or interrupted download installs nothing and can be tried again.
- [#171] The build turns grammar topics written in Markdown into the Greek pack, with verb and noun tables rendered from the Wiktionary forms, gates that fail a malformed or unreviewed topic, and a review document. No topic ships yet.
- [#173] The Greek pack carries the 17 Greek A1 grammar topics in English and in Russian, the Russian ones with the mistakes Russian speakers make, drafted with AI and reviewed by Kirill Yukhin. Their forms tables show each cell's first form and its -ουνε or -ανε variant, and one set of endings for -άω verbs.
- [#153] The English lists pack carries the English word lists A1 to C2 from CEFR-J and Octanove (8,647 words, 98.6% linked to an English dictionary) with English frequency ranks; Credits cites both lists.
- [#167] The Greek conjugation drill gets its question logic: tenses by ΚΕΓ level, the verbs of the checked Greek lists with their meanings in the language of Greek's learning pair, and four real forms of the verb per question with exactly one right. No screen uses it yet.
- [#177] The Greek pack and the English lists pack carry up to five Tatoeba example sentences per word, with direct translations and their authors, built from a pinned export and filtered by Tatoeba's tags. 429 of the 500 most frequent Greek verbs have three or more, as do 6,662 English list words. No screen shows them yet.
- [#159] Recognition and Production trainers on the Learn tab: choose a word's meaning from four, or choose or type the word, with meanings in the language of the chosen pair (English for Greek via Russian) and typed answers graded strictly or leniently on accents. Every answer is graded at once, with the right option highlighted, a haptic and a short sound.
- [#161] Start on the Learn tab runs the daily session: due words first, then new words from My words and the checked lists within the daily limit, each asked twice in groups of three, with wrong answers asked again at the end. A summary shows the session's numbers and the daily goal, and "Practise mistakes" asks the words answered wrong in the last 7 days until they are right.
- [#162] Settings gets a Learning section: the learned languages (add one, stop one, change the language it is learned through), new words per day, the daily goal, the new words order, typed answers, sounds, haptics and a daily reminder. The reminder is opt-in, asks for notification permission only when turned on, skips days whose goal is met, and its tap opens the Learn tab.
- [#160] Match the pairs on the Learn tab: five words and their meanings in two columns with a timer, where a right pair disappears and a wrong one flashes red. Each word counts as a recognition answer toward the daily goal, and the trainer needs 5 words to learn.
- [#154] The Learn tab gets word lists: a Lists screen with the lists of the languages you learn, their word counts and progress, a list's screen with each word's meaning in the language of the learning pair and "Learn this list", and "New words from", on the Learn home and in Settings, where you check the lists new words come from. My words is now one of the lists.
- [#169] The conjugation drill gets spaced repetition: one card per verb, tense and voice on the learning ladder, started by its first answer and kept apart from word learning, and 15-question runs with due cards first, weaker tenses more often and a wrong answer asked once more. No screen uses it yet.
- [#164] Learn → Statistics shows today's numbers, the streak with a 5-week calendar, a 30-day chart, list progress with a forecast, accuracy, the hardest words and the conjugation block, per learned language except the shared goal, streak and chart. The Learn home gets a daily goal ring and a streak flame that open it. Charts read as one VoiceOver summary and mirror in Arabic.
- [#165] A word in learning shows its status under the part of speech on the Definition screen: new, learning or learned with the next review, each card's stage and the mistakes so far.
- [#243] Settings → Dictionaries → Languages downloads, updates and removes each language with its size and progress, and Dictionary Order links to it; removing a language warns when learning needs it.
- [#178] Greek words and words of the English lists show up to five Tatoeba example sentences on the Definition screen, the word's form highlighted, with a translation in the UI language (else English) and their authors. In learning, a new word's first answer opens a sheet with up to three examples translated into the pair's language, and every feedback bar offers them through an Example button. Credits names Tatoeba (CC BY 2.0 FR).
- [#245] The first launch offers the other languages in one sheet, with the UI and device languages checked (after an update from 1.x, those that were on), their progress, Not now and a link to import one's own dictionary. A History or My words word, or a Greek, Cyrillic or Arabic query, whose language is not downloaded offers its download.
- [#155] Word lists import from a CSV, TSV or TXT file (Kirill's lists and Anki's "Notes in Plain Text" too) or from text pasted from Quizlet, with a preview of the words, the merged duplicates and every broken row before anything is saved. Imported words link to the dictionaries like the built-in lists, a list of a language not learned yet asks "Learn … via …?" first, and a Formats screen shows the three formats.
- [#168] Learn → Conjugation drills the verbs of the checked Greek lists: "Tenses up to" A1–B2, 15 questions of four forms, the whole tense after each answer and a summary by tense. Practise under a Greek verb's table on the Definition screen drills that verb, asking "Learn Greek via English?" first when needed. Tenses are named as the grammar topics name them ("Future: simple form").
- [#172] Learn → Grammar lists the 17 Greek A1 topics by level, explained in the language Greek is learned through (Russian for Greek via Russian, else English). A topic shows its rule, tables, examples and typical mistakes, its words with their meanings and related topics, with Reading Mode, a 700 pt column on iPad and left-to-right text in Arabic. Practise on a tense topic runs the conjugation drill for those tenses, asking to learn Greek or to pick lists first when needed.
- [#174] A Greek word's Definition screen lists the grammar topics that apply to it, by the word or by its table (a verb's conjugation and tenses, a noun, an adjective). In the conjugation drill, Rule after each answer opens the topic of the question's tense in a sheet without Practise.
- [#29] The libredict.app website: a home page, the privacy policy and support in five languages, published from `site/` by GitHub Pages, with no scripts, cookies or trackers.
- [#299] A wrong choice also shows what the chosen option means, in the feedback bar ("You chose: water · νερό"), under the pairs in match the pairs and with its tense and person in the conjugation drill.
- [#300] Learning has its own playful sounds, synthesized in code: right, wrong, pairs right and wrong, and a chime when a daily lesson ends or the daily goal is reached; Sounds in Settings still turns them all off.
- [#293] The Learn tab has one flag tab per learned pair (a big flag for the language, a small one for its via; the full name under the strip), added with "+", reordered by dragging, hidden behind "…" when they do not fit, and stopped with a long press on the tab, then Stop learning; the streak and the goal are the same on every tab.
- [#295] Each pair tab holds only its language: Today, mistakes, the trainers, a Grammar section with the topics and the Greek conjugation drill, its lists, its My words and its Statistics.
- [#297] The Grammar list shows no level header while only A1 exists, gives the level in its subtitle ("17 topics · A1") and ends with an "A2 · Coming soon" row that opens nothing.
- [#298] "New words from" is now "Learning from" in five languages, and its row on the Learn tab shows the checked lists ("Greek A1, A2").

### Changed
- [#138] Every dictionary is searchable right after install, with no "Preparing dictionaries" bar: the app reads the bundled dictionaries in place and keeps your history, saved words and imports in a small database of their own.
- [#139] Upgrading from 1.x keeps your bookmarks (now My words), history and imported dictionaries, and frees about 138 MB.
- [#240, #241] The app bundles English only (56 MB instead of 152 MB); every other language is a pack, built byte for byte by `Scripts/cut_packs.py`, that Search, Definition, History and My words read next to the bundle once installed.
- [#158] The Learn tab replaces Bookmarks: it asks which language you want to learn and through which ("Greek via English"), then shows today's words and My words, and a word's star becomes a Learn button that adds it to My words and starts learning it.
- [#244] An update from 1.x or the 2.0 alpha keeps History, My words and imports without turning the old copy of each language's dictionaries into imports, keeps their place and switch in Dictionary Order until their pack is installed, and decides which packs the first launch offers (those of the dictionaries that were enabled).
- [#131] Choosing a language pair to learn downloads the packs it needs, with their size in the picker, the download's progress on the Learn home and Try again after a failure. Greek meanings prefer the FreeDict Greek–English dictionary over WordNet's, English via English skips list words WordNet does not define (he, us, or), and the learning screens get small fixes from review.
- [#180] Credits, now right under the version in Settings, names every data source with its license, WordNet's too, credits GRDB.swift with its MIT license text, and the Licenses section lists each license with a link to its text instead of a placeholder.
- [#182] After an update from 1.x, the welcome sheet says My words appear in Learn once a language to learn is chosen, instead of promising them right away.
- [#306] Search orders a word's exact matches and the words it is a form of: the word spelt exactly as typed first, then words with that exact form, then by frequency, so "ματια" shows μάτι (eyes) before ματιά (glance) and "better" stays first. Proper nouns no longer show as forms.
- [#307] The Search dictionary chips now scroll away with the search field and come back at the top of the list.

### Fixed
- [#138] History and Recent words reopen a word in the dictionary it was read in.
- [#202] The speaker button reads each word in its own language (Russian, Spanish, Arabic, Greek or English) and is hidden when the device has no voice for that language.
- [#213] Search, imports and My words keep working when the system invalidates the open dictionary file.
- [#281] Answer tones no longer freeze the screen while the audio system starts.
- [#281] The Learn home no longer shows "Learn a few words first" under the Conjugation row, which works without learned words.
- [#281] The Conjugation screen opens twice as fast with all three Greek lists checked.
- [#281] A list import shows every row that a quote left open swallows as a broken row instead of dropping it silently, and a preview change that fails keeps the pickers on the preview shown.
- [#281] In the drill, Rule also opens the topic that lists a verb with passive forms only: έρχομαι's aorist opens Irregular aorists.
- [#181] Localization pass for 2.0: the typed answer's placeholder writes the language in lower case ("στα ελληνικά"), the Russian Import and the Greek Paste screens no longer truncate their titles, the Languages rows and the Learning steppers stack at the largest text sizes instead of breaking words, and the Spanish daily goal, the Greek "learning" badge and the Arabic strict-accents option use the app's own terms.

### Tests / CI
- [#203] Release builds ignore the UI-test launch arguments, and unused version code and stale developer docs are removed.
- [#140] The bundled dictionaries are one file, `dictionaries.sqlite`, rebuilt byte for byte from pinned sources with build checks and a `--verify` mode.
- [#216] The dictionary build uses NLTK 3.10.4, which fixes its security advisories, and still produces the same file byte for byte.

## [1.4.1] - 2026-10-27

### Fixed
- [#196] Settings shows the app's real version again (1.4.0 showed "1.3.0-20-gbd22843"): an App Store archive now fails unless its commit carries the release tag.

### Tests / CI
- [#197] Builds declare no non-exempt encryption, so App Store Connect no longer stops each upload at the export-compliance question.

## [1.4.0] - 2026-10-23

### Added
- [#5, #127] Reading Mode: an open-book toggle in the Search and Definition toolbars keeps the screen awake. Per session; turns off when the app goes to background.
- [#91] Dictionary Order rows have an (i) button that opens the pair's details. Each underlying dictionary shows its provider, direction, version, entry count and license.
- [#87] Greek–English dictionaries (Greek WordNet via OMW and FreeDict, both directions) as one "Greek – English" pair, with Greek search that ignores accents, case and final sigma in headwords and in English → Greek translations.
- [#89, #109, #110] App Store Connect metadata: Greek localization, refreshed en/ru/es/ar listings and screenshots, Greek keywords.
- [#88] Greek (Ελληνικά) interface language, with Greek number formatting and the Greek – English dictionaries first on a fresh Greek install; import result messages now follow the in-app language.

### Changed
- [#74] First-launch dictionary order now puts the UI language's dictionaries first (e.g. `openrussian` on Russian); a user-configured order is never overridden. `-resetData` now also clears the persisted UI language (test hook).
- [#92] Dictionary Order shows one row per language pair (e.g. "Spanish – English") with a single toggle and drag slot covering both directions; existing per-source preferences migrate as enabled-if-any. "Preferred dictionary first" now ranks per pair.
- [#87] Source badges show direction and provider (e.g. "Es–En · WN", "En–Es · FD") and have a full VoiceOver label.
- [#111] LibreDict opens in seconds on first launch and after updates. Dictionaries are prepared in the background, with progress shown on Search; each one is searchable as soon as it is ready.

### Fixed
- [#105] A newly imported dictionary appears in Dictionary Order right away, without restarting the app, and is switched on even if other dictionaries were turned off.
- [#106] Dictionary details and Credits show the correct license for FreeDict English–Spanish (CC BY-SA 3.0, not GPL-3.0) and Arabic WordNet (CC BY-SA 3.0, not CC BY 3.0).
- [#108] FreeDict dictionaries keep every translation of an entry instead of only the first one (English–Spanish gains about 56,000 translations), and existing installs get them on update with bookmarks kept.
- [#88] Changing the interface language in Settings no longer crashes the app on iOS 17.
- [#114] History shows each lookup in your local time and the app's language ("Today, 8:41 PM"), following your device's region and 24-hour setting, instead of a raw UTC timestamp.
- [#119] In Arabic, language pairs, translation directions, History times and the unsupported-file message now read in the right order.
- [#120] On iPad with iPadOS 26, the tabs stay visible while the Search field holds a word, so you can switch tabs and come back to the same results.
- [#123] On iPad with iPadOS 26, the Dictionary Order title stays in the navigation bar and no longer covers the first row or swallows a tap on its (i) button.

### Tests / CI
- [#102, #104] UI tests switch tabs reliably on iPhone iOS 17 and iPadOS 26 through one shared tab lookup that dismisses the keyboard, pops to Search and checks the switch landed.
- [#125] DictionaryPairGroupingTests no longer crash on iPadOS 17.5: XCTest logging is silenced like in DictionaryInfoTests.

## [1.3.0] - 2026-06-25

### Added
- [#24] English–Spanish dictionary (FreeDict `eng-spa`, ~64k headwords). Build in `Scripts/build_freedict_eng_spa.py`; new `freedict-eng-spa` source, no data-layer changes.
- [#42] Spanish–English dictionary (Spanish WordNet via OMW). Build in `Scripts/build_spanish_wordnet.py`; new `wordnet-spa-eng` source. Corrects `wordnet` metadata version 3.1 → 3.0.
- [#40, #23] Spanish (`es`) support + UI localization. Resource-only: full `Localizable.xcstrings` + `SupportedLocales.json` + `knownRegions`.
- [#45, #9] Arabic (`ar`) support + UI localization — first RTL language. App root derives `\.layoutDirection` from language char direction. Western digits only.
- [#10] Arabic↔English dictionary (~17,785 headwords, Arabic WordNet via OMW), diacritic-insensitive search. **Schema migration**: `entries.word_normalized` FTS5 key via `PRAGMA user_version` gate; build-side normalizer `Scripts/arabic_normalize.py`. Imported Arabic dicts stay diacritic-sensitive.
- [#6] Per-dictionary colour stripe in search + History; "Result sorting" picker (Relevance default / Preferred-dictionary-first) and drag-to-reorder list. Prefs routed through new `KeyValueStore` seam in `SettingsService` (same keys, no migration; preps #73 iCloud). **Schema migration**: `history.source`. Badge stays primary a11y signal; palette provisional.
- [#12] Native App Store review prompt, heuristic-gated (≥5 definitions + active foreground time, escalating 30s/10m/60m, once/session). `-disableReviewPrompt` for tests; counters via `KeyValueStore`.
- [#81] "Write a review" link in Settings → Support (on-demand App Store review page).
- [#41, #46, #79] App Store Connect metadata: Spanish + Arabic localizations, per-locale keywords.
- [#19] UI test suite for core user flows (Page Object Model).

### Fixed
- [#39] Settings → Version showed wrong `-unreleased` suffix. Now stamps real `git describe` at build time (`Scripts/generate_build_info.sh` → xcconfig → `GIT_DESCRIBE` → `AppVersion`); build phase fails on missing `.git` / stale value.
- [#60] SwiftUI `List` dropped long-definition result cells on iOS 18.5 sim.
- [#56] `SearchPage` `waitForExistence` timing races on Intel x86_64 sim.
- [#59] `getResultsCount` stable-count guard (latent race unmasked by #56).
- [#55] Settings toggle-tap flake under expanded source list.
- [#67] `HistoryFlowTests` isolation failure on arm64 (Xcode 26 / iPhone 15 Pro sim).

### Changed
- [#28] Switched to PR-based development (no direct pushes to master).
- [#57] Unified `IPHONEOS_DEPLOYMENT_TARGET` to 17.0 across all targets.

### Tests / CI
- [#64] All UI tests green on Intel x86_64 Mac mini.
- [#76] iPhone core-flow UITest suites pass on iPad regular size class.
- [#52] Stabilized `HistoryFlowTests` under warm/sequential runs.
- [#65] Force portrait in UI test `setUp` (Intel landscape no-ops `swipeUp`).
- [#54, #62, #66] Bumped cold-seed tab-bar timeouts (Spanish/Arabic suites).

## [1.2.0] - 2026-05-25

### Added
- [Issue #25] Settings → Version now shows the real marketing version from `MARKETING_VERSION` / `CFBundleShortVersionString`, with a `-unreleased` suffix appended on every build that isn't an App-Store-distributed binary (Debug, TestFlight, Ad-Hoc/Enterprise/Developer-export). Channel detection is layered runtime signals (`#if DEBUG`, sandbox receipt path, embedded provisioning profile) so no manual archive-time flag flip is required. A new `AppVersion` value type is the single source of truth for the displayed string, exposing `displayString` for UI and `verboseString` for telemetry consumers.
- [Issue #8] Basic bug reporting via the native iOS Mail compose sheet. The "Report a Bug" button in Settings now opens a pre-filled message to the support address with subject, greeting, and a delimited English telemetry block (app version, build, iOS version, device model, UI language, system locale). Falls back to `mailto:` for devices without Mail configured, and to a copy-address alert when no mail client is available.
- [Issue #19] Comprehensive UI tests for end-to-end user workflows using XCUITest framework with Page Object pattern for maintainability.
- [Issue #22] Added UI language choice section to Settings tab with English as initial option, preparing for future internationalization.
- [Issue #15] Added Learning Mode, Reading Mode, and Support stub sections to SettingsView. Support section includes a disabled "Report a Bug" button and a Credits navigation link showing static attribution text.
- [Issue #2] Dictionary enable/disable toggles in Settings → Dictionaries. Each source has a persistent toggle; disabled sources are excluded from FTS search results. Disabling all sources returns an empty result set immediately without querying the database.
- [Issue #2] Test coverage for per-dictionary toggle behavior: unit tests for `DatabaseService.search` source filtering (nil / empty / specific set) and `SettingsService` persistence; XCUI tests (`DictionaryFilterTests`) verifying that disabling one dictionary hides its search results, disabling all dictionaries returns empty results, and re-enabling restores them.
- [Issue #26] Grouped dictionary-management UI under Settings → Dictionaries. The per-dictionary on/off toggles stay on the Settings screen; the Import Dictionary and Supported Formats sections move behind a new "Manage Dictionaries" navigation row at the bottom of the Dictionaries section. Import state moves out of `SettingsViewModel` into a new `ManageDictionariesViewModel`, leaving the future remote-download work from #11 with a clean home.
- UI tests for the dictionary-import flow (`ImportDictionaryTests`): reachability of Manage Dictionaries from Settings, presence and interactivity of the Import button, system-picker presentation, and end-to-end JSON and SQLite imports verified by searching for fixture-only words. Wires up `ManageDictionariesViewModel.handleImport` to actually call `DatabaseService.importJSON` / `importSQLite` (previously a stub) and adds two bundled fixtures plus a `-clearFixtureImports` launch flag for repeatable runs.
- [Issue #1] Russian localization and a scalable i18n architecture. Strings migrate to a String Catalog (`Localizable.xcstrings`) with CLDR plural variants for the entries count and the import-result message. Supported languages are declared in `Resources/SupportedLocales.json` and resolved at runtime by a new `LocalizationManager`, so adding a new language is a resource change — no Swift edits, no `switch` over the locale. Switching language in Settings takes effect immediately via `\.locale` plus a root-view `.id(...)` rebuild.

### Fixed
- [Issue #2] Search returned no results regardless of toggle state because `DatabaseService.search()` bound 6 positional arguments to a 4-placeholder statement (the MATCH clause was over-supplied with three values instead of one). The thrown GRDB error was silently caught by `SearchViewModel`, leaving `results` empty.
- [Issue #20] Bookmark flow tests failing due to data contamination between test runs. Implemented data isolation with `-resetData` command line argument support and `clearAllBookmarks()` method to ensure clean test state for reliable, repeatable test execution.

[1.1.0] - 2026-05-11

### Fixed
- [Issue #4] iPad showed a blank white screen at launch. The `DictApp` target was iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so UIKit launched the app in "Designed for iPhone" letterbox mode on iPad and never attached a window for the iPad idiom. Set `TARGETED_DEVICE_FAMILY = "1,2"` in both Debug and Release configurations, which produces `UIDeviceFamily = (1, 2)` in the built `Info.plist`. Added unit test `testAppSupportsIPhoneAndIPad` and verified the app launches natively on iPad Pro 11-inch (M4) iOS 26.4 simulator.
- [Issue #7] Incorrect app display name. Added `INFOPLIST_KEY_CFBundleDisplayName = LibreDict` to the `DictApp` target's Debug and Release build configurations so the app installs on the home screen as **LibreDict**. Updated the in-app About section in `DictionaryManagerView` to show "LibreDict" instead of "DictApp". Added unit test `testAppDisplayNameIsLibreDict` in `DictAppTests` (passes on iOS 17.5 simulator) and also fixed a pre-existing GRDB async-overload build break in `seedEntries(count:)` (`pool.write { … }` → `try await pool.writeWithoutTransaction { … }`) that prevented the test target from compiling.
- App launch failed with `Database Error: SQLite error 26: file is not a database` on freshly-cloned working trees. Root cause: `DictApp/DictApp/Resources/seed.sqlite` is tracked via Git-LFS (`.gitattributes` declares `*.sqlite filter=lfs`); without `git lfs pull` the working-tree file is a 133-byte LFS pointer stub, which Xcode happily bundles into `DictApp.app`. At launch GRDB opens it and SQLite returns `SQLITE_NOTADB (26)`. Materialized the real 65 MB seed via `git lfs install && git lfs pull` (192,953 entries: wordnet + openrussian). Added regression test `testBundledSeedIsRealSQLite` in `DictAppTests` that validates the bundled seed file's magic header, size, and that `SELECT COUNT(*) FROM entries > 0` — this will fail loudly in CI if the LFS object is ever missing again.
