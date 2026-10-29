# Changelog

All notable changes to **LibreDict** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- [#138] Every dictionary is searchable right after install, with no "Preparing dictionaries" bar: the app reads the bundled dictionaries in place and keeps your history, saved words and imports in a small database of their own.

### Fixed
- [#138] History and Recent words reopen a word in the dictionary it was read in.
- [#202] The speaker button reads each word in its own language (Russian, Spanish, Arabic, Greek or English) and is hidden when the device has no voice for that language.

### Tests / CI
- [#203] Release builds ignore the UI-test launch arguments, and unused version code and stale developer docs are removed.

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
