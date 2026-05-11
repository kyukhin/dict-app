# Changelog

All notable changes to **LibreDict** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- [Issue #7] Incorrect app display name. Added `INFOPLIST_KEY_CFBundleDisplayName = LibreDict` to the `DictApp` target's Debug and Release build configurations so the app installs on the home screen as **LibreDict**. Updated the in-app About section in `DictionaryManagerView` to show "LibreDict" instead of "DictApp". Added unit test `testAppDisplayNameIsLibreDict` in `DictAppTests` (passes on iOS 17.5 simulator) and also fixed a pre-existing GRDB async-overload build break in `seedEntries(count:)` (`pool.write { … }` → `try await pool.writeWithoutTransaction { … }`) that prevented the test target from compiling.
- App launch failed with `Database Error: SQLite error 26: file is not a database` on freshly-cloned working trees. Root cause: `DictApp/DictApp/Resources/seed.sqlite` is tracked via Git-LFS (`.gitattributes` declares `*.sqlite filter=lfs`); without `git lfs pull` the working-tree file is a 133-byte LFS pointer stub, which Xcode happily bundles into `DictApp.app`. At launch GRDB opens it and SQLite returns `SQLITE_NOTADB (26)`. Materialized the real 65 MB seed via `git lfs install && git lfs pull` (192,953 entries: wordnet + openrussian). Added regression test `testBundledSeedIsRealSQLite` in `DictAppTests` that validates the bundled seed file's magic header, size, and that `SELECT COUNT(*) FROM entries > 0` — this will fail loudly in CI if the LFS object is ever missing again.
