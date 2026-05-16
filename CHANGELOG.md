# Changelog

All notable changes to **LibreDict** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- [Issue #19] Comprehensive UI tests for end-to-end user workflows using XCUITest framework with Page Object pattern for maintainability.
- [Issue #22] Added UI language choice section to Settings tab with English as initial option, preparing for future internationalization.
- [Issue #15] Added Learning Mode, Reading Mode, and Support stub sections to SettingsView. Support section includes a disabled "Report a Bug" button and a Credits navigation link showing static attribution text.
- [Issue #2] Dictionary enable/disable toggles in Settings → Dictionaries. Each source has a persistent toggle; disabled sources are excluded from FTS search results. Disabling all sources returns an empty result set immediately without querying the database.
- [Issue #2] Test coverage for per-dictionary toggle behavior: unit tests for `DatabaseService.search` source filtering (nil / empty / specific set) and `SettingsService` persistence; XCUI tests (`DictionaryFilterTests`) verifying that disabling one dictionary hides its search results, disabling all dictionaries returns empty results, and re-enabling restores them.

### Fixed
- [Issue #2] Search returned no results regardless of toggle state because `DatabaseService.search()` bound 6 positional arguments to a 4-placeholder statement (the MATCH clause was over-supplied with three values instead of one). The thrown GRDB error was silently caught by `SearchViewModel`, leaving `results` empty.
- [Issue #20] Bookmark flow tests failing due to data contamination between test runs. Implemented data isolation with `-resetData` command line argument support and `clearAllBookmarks()` method to ensure clean test state for reliable, repeatable test execution.

[1.1.0] - 2026-05-11

### Fixed
- [Issue #4] iPad showed a blank white screen at launch. The `DictApp` target was iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so UIKit launched the app in "Designed for iPhone" letterbox mode on iPad and never attached a window for the iPad idiom. Set `TARGETED_DEVICE_FAMILY = "1,2"` in both Debug and Release configurations, which produces `UIDeviceFamily = (1, 2)` in the built `Info.plist`. Added unit test `testAppSupportsIPhoneAndIPad` and verified the app launches natively on iPad Pro 11-inch (M4) iOS 26.4 simulator.
- [Issue #7] Incorrect app display name. Added `INFOPLIST_KEY_CFBundleDisplayName = LibreDict` to the `DictApp` target's Debug and Release build configurations so the app installs on the home screen as **LibreDict**. Updated the in-app About section in `DictionaryManagerView` to show "LibreDict" instead of "DictApp". Added unit test `testAppDisplayNameIsLibreDict` in `DictAppTests` (passes on iOS 17.5 simulator) and also fixed a pre-existing GRDB async-overload build break in `seedEntries(count:)` (`pool.write { … }` → `try await pool.writeWithoutTransaction { … }`) that prevented the test target from compiling.
- App launch failed with `Database Error: SQLite error 26: file is not a database` on freshly-cloned working trees. Root cause: `DictApp/DictApp/Resources/seed.sqlite` is tracked via Git-LFS (`.gitattributes` declares `*.sqlite filter=lfs`); without `git lfs pull` the working-tree file is a 133-byte LFS pointer stub, which Xcode happily bundles into `DictApp.app`. At launch GRDB opens it and SQLite returns `SQLITE_NOTADB (26)`. Materialized the real 65 MB seed via `git lfs install && git lfs pull` (192,953 entries: wordnet + openrussian). Added regression test `testBundledSeedIsRealSQLite` in `DictAppTests` that validates the bundled seed file's magic header, size, and that `SELECT COUNT(*) FROM entries > 0` — this will fail loudly in CI if the LFS object is ever missing again.

