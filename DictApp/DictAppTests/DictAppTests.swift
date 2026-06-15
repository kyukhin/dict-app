// DictAppTests.swift
// Unit tests and performance tests for the dictionary app.

import XCTest
@testable import DictApp
import GRDB
import MessageUI

final class DictAppTests: XCTestCase {

    private var db: DatabaseService!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        db = DatabaseService.shared
        let path = tempDir.appendingPathComponent("test.sqlite").path
        try await db.setup(path: path)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Helper: bulk insert

    private func seedEntries(count: Int) async throws {
        // Directly write to the test database via a temporary GRDB pool.
        let path = tempDir.appendingPathComponent("test.sqlite").path
        let pool = try DatabasePool(path: path)
        try await pool.writeWithoutTransaction { dbConn in
            for i in 0..<count {
                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "word\(i)",
                        // FTS indexes `word_normalized` (Issue #10); for these
                        // Latin test words it equals `word` (normalization is a no-op).
                        "word\(i)",
                        "Definition for word number \(i). This is a sample definition.",
                        "/wɜːrd/",
                        "noun",
                        "test"
                    ]
                )
            }
        }
    }

    /// Seeds a fixed set of words for the given source, used by the per-source
    /// filter tests in issue #2. Word prefix is namespaced so concurrent
    /// sources don't collide on the (word, source) unique index.
    private func seedSourcedEntries(source: String, words: [String]) async throws {
        let path = tempDir.appendingPathComponent("test.sqlite").path
        let pool = try DatabasePool(path: path)
        try await pool.writeWithoutTransaction { dbConn in
            for word in words {
                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        word,
                        // FTS indexes `word_normalized` (Issue #10); == word here.
                        word,
                        "Definition of \(word) in \(source).",
                        "",
                        "noun",
                        source
                    ]
                )
            }
        }
    }

    // MARK: - Unit Tests

    /// Verifies a search returns the correct definition for a known entry.
    func testSearchReturnsCorrectDefinition() async throws {
        try await seedEntries(count: 10)

        let results = try await db.search(query: "word5")
        XCTAssertFalse(results.isEmpty, "Search should return at least one result for 'word5'")

        let match = results.first { $0.word == "word5" }
        XCTAssertNotNil(match, "Should find exact entry 'word5'")
        XCTAssertTrue(
            match!.definition.contains("word number 5"),
            "Definition should contain the expected text"
        )
    }

    /// Verifies exact lookup works.
    func testExactLookup() async throws {
        try await seedEntries(count: 5)

        let entry = try await db.lookup(word: "word3")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.word, "word3")
    }

    /// Verifies that history does not contain duplicate entries.
    func testHistoryNoDuplicates() async throws {
        try await db.addToHistory(word: "apple", source: "wordnet")
        try await db.addToHistory(word: "banana", source: "wordnet")
        try await db.addToHistory(word: "apple", source: "wordnet") // duplicate

        let history = try await db.fetchHistory()
        let appleCount = history.filter { $0.word == "apple" }.count
        XCTAssertEqual(appleCount, 1, "History must not contain duplicate words")

        let count = try await db.historyCount()
        XCTAssertEqual(count, 2, "Total history count should be 2 (apple + banana)")
    }

    /// Verifies that re-adding a word to history updates its timestamp (most recent first).
    func testHistoryOrderUpdatedOnRevisit() async throws {
        try await db.addToHistory(word: "alpha", source: "wordnet")
        try await db.addToHistory(word: "beta", source: "wordnet")
        // Re-add alpha so it becomes the most recent.
        try await db.addToHistory(word: "alpha", source: "wordnet")

        let history = try await db.fetchHistory()
        XCTAssertEqual(history.first?.word, "alpha", "Most recently added word should be first")
    }

    /// Verifies clear history works.
    func testClearHistory() async throws {
        try await db.addToHistory(word: "test", source: "wordnet")
        try await db.clearHistory()

        let count = try await db.historyCount()
        XCTAssertEqual(count, 0)
    }

    /// Verifies bookmark add / check / remove cycle.
    func testBookmarkCycle() async throws {
        try await seedEntries(count: 1)

        let entry = try await db.lookup(word: "word0")
        let entryId = try XCTUnwrap(entry?.id)

        // Add bookmark.
        try await db.addBookmark(entryId: entryId)
        var isBookmarked = try await db.isBookmarked(entryId: entryId)
        XCTAssertTrue(isBookmarked)

        // Remove bookmark.
        try await db.removeBookmark(entryId: entryId)
        isBookmarked = try await db.isBookmarked(entryId: entryId)
        XCTAssertFalse(isBookmarked)
    }

    /// Verifies prefix search returns multiple matches.
    func testPrefixSearch() async throws {
        try await seedEntries(count: 100)

        // "word1" should match word1, word10, word11, ..., word19.
        let results = try await db.search(query: "word1")
        XCTAssertGreaterThanOrEqual(results.count, 11, "Prefix search for 'word1' should match >= 11 entries")
    }

    // MARK: - Bundled Resources Tests

    /// Regression test for the "Database Error: SQLite error 26: file is not a database"
    /// crash that occurred when `seed.sqlite` was shipped as a Git-LFS pointer stub
    /// instead of the real database. Fails loudly if the bundled resource is missing,
    /// too small, or isn't a real SQLite file (e.g. an LFS pointer header).
    func testBundledSeedIsRealSQLite() throws {
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()

        let seedURL = try XCTUnwrap(
            hostBundle.url(forResource: "seed", withExtension: "sqlite")
                ?? Bundle.main.url(forResource: "seed", withExtension: "sqlite"),
            "Bundled seed.sqlite is missing from the app bundle."
        )

        let data = try Data(contentsOf: seedURL, options: .alwaysMapped)
        // SQLite files start with the 16-byte magic header "SQLite format 3\0".
        // Git-LFS pointer stubs start with "version https://git-lfs.github.com/".
        let header = data.prefix(16)
        let headerString = String(data: header, encoding: .utf8) ?? ""

        XCTAssertFalse(
            headerString.hasPrefix("version https://git-lfs"),
            "seed.sqlite is a Git-LFS pointer stub. Run `git lfs install && git lfs pull` before building."
        )
        XCTAssertGreaterThan(
            data.count, 1024,
            "seed.sqlite is suspiciously small (\(data.count) bytes) — likely not the real database."
        )
        XCTAssertEqual(
            headerString, "SQLite format 3\u{0000}",
            "seed.sqlite does not have a valid SQLite header."
        )

        // And it must actually open and contain entries.
        let queue = try DatabaseQueue(path: seedURL.path)
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") ?? 0
        }
        XCTAssertGreaterThan(count, 0, "Bundled seed.sqlite must contain entries.")
    }

    // MARK: - App Metadata Tests

    /// Issue #4: Verifies the app declares support for both iPhone (1) and iPad (2)
    /// in `UIDeviceFamily`. Until this was fixed the bundle was iPhone-only
    /// (TARGETED_DEVICE_FAMILY=1), which caused a blank-white screen on iPad
    /// because UIKit launched the app in the "Designed for iPhone" compatibility
    /// chrome and `UIApplicationSceneManifest` defaults wouldn't attach a window
    /// for the iPad idiom.
    func testAppSupportsIPhoneAndIPad() throws {
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()

        let info = hostBundle.infoDictionary ?? Bundle.main.infoDictionary ?? [:]

        // UIDeviceFamily — synthesized by Xcode from TARGETED_DEVICE_FAMILY.
        // 1 = iPhone, 2 = iPad. We require both.
        let family = info["UIDeviceFamily"] as? [Int] ?? []
        XCTAssertTrue(
            family.contains(1),
            "Info.plist UIDeviceFamily must include iPhone (1); got \(family)"
        )
        XCTAssertTrue(
            family.contains(2),
            "Info.plist UIDeviceFamily must include iPad (2); got \(family)"
        )
    }

    /// Issue #7: Verifies the app's CFBundleDisplayName is "LibreDict".
    /// Loads Info.plist directly from the host app bundle to validate the
    /// shipped value (rather than the test bundle's own plist).
    func testAppDisplayNameIsLibreDict() throws {
        // The unit-test target is hosted by the app under test, so
        // Bundle.main is the host (DictApp.app). Resolve robustly.
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()

        let displayName =
            hostBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String

        XCTAssertEqual(
            displayName,
            "LibreDict",
            "CFBundleDisplayName must be 'LibreDict' (got \(displayName ?? "nil"))"
        )
    }

    // MARK: - Issue #2: Per-source enable/disable filter

    /// Search with `enabledSources = nil` should return results from all sources
    /// (first-launch default behavior).
    func testSearchWithNilEnabledSourcesReturnsAll() async throws {
        try await seedSourcedEntries(source: "alpha", words: ["sharedterm", "alphaword"])
        try await seedSourcedEntries(source: "beta",  words: ["sharedterm", "betaword"])

        let results = try await db.search(query: "sharedterm", enabledSources: nil)

        let sources = Set(results.map { $0.source })
        XCTAssertTrue(sources.contains("alpha"), "nil enabledSources must include 'alpha' results")
        XCTAssertTrue(sources.contains("beta"),  "nil enabledSources must include 'beta' results")
        XCTAssertEqual(results.count, 2, "Expected one match per source for 'sharedterm'; got \(results.count)")
    }

    /// Search with an empty `enabledSources` set must return an empty array
    /// without hitting the database.
    func testSearchWithEmptyEnabledSourcesReturnsEmpty() async throws {
        try await seedSourcedEntries(source: "alpha", words: ["sharedterm"])
        try await seedSourcedEntries(source: "beta",  words: ["sharedterm"])

        let results = try await db.search(query: "sharedterm", enabledSources: [])

        XCTAssertTrue(results.isEmpty, "Empty enabledSources must yield no results; got \(results.count)")
    }

    /// Search with a specific set of enabled sources must return only entries
    /// whose `source` is in that set.
    /// Note: FTS5's `unicode61` tokenizer treats non-alphanumeric chars as
    /// separators and `sanitizeFTS` strips them, so test words must be pure
    /// alphanumerics (no underscores, hyphens, etc.).
    func testSearchFiltersBySpecificEnabledSources() async throws {
        try await seedSourcedEntries(source: "alpha", words: ["sharedterm", "alphaword"])
        try await seedSourcedEntries(source: "beta",  words: ["sharedterm", "betaword"])

        // Only alpha enabled: both query terms must come only from alpha.
        let alphaShared = try await db.search(query: "sharedterm", enabledSources: ["alpha"])
        XCTAssertEqual(alphaShared.count, 1)
        XCTAssertEqual(alphaShared.first?.source, "alpha")

        let alphaOnly = try await db.search(query: "alphaword", enabledSources: ["alpha"])
        XCTAssertEqual(alphaOnly.count, 1, "alphaword must be found when alpha is enabled")
        XCTAssertEqual(alphaOnly.first?.source, "alpha")

        // betaword is in beta; with alpha-only filter it must be invisible.
        let betaOnlyFromAlpha = try await db.search(query: "betaword", enabledSources: ["alpha"])
        XCTAssertTrue(betaOnlyFromAlpha.isEmpty, "betaword must be filtered out when only alpha is enabled")
    }

    /// `SettingsService.isEnabled(source:)` must return true for any source
    /// before the user has explicitly toggled anything (first-launch default).
    func testSettingsServiceFirstLaunchAllEnabled() throws {
        let service = SettingsService.shared
        // Reset to first-launch state.
        service.enabledSources = nil
        defer { service.enabledSources = nil }

        XCTAssertTrue(service.isEnabled(source: "wordnet"),
                      "First-launch default must treat every source as enabled")
        XCTAssertTrue(service.isEnabled(source: "openrussian"))
        XCTAssertTrue(service.isEnabled(source: "anything_not_yet_known"),
                      "Unknown sources must also be enabled on first launch")
    }

    /// Toggling a source off then on must round-trip through UserDefaults
    /// and be reflected in subsequent `isEnabled` calls.
    func testSettingsServiceTogglePersists() throws {
        let service = SettingsService.shared
        service.enabledSources = nil
        defer { service.enabledSources = nil }

        let known: Set<String> = ["wordnet", "openrussian"]

        // Disable wordnet — openrussian must stay enabled.
        service.setEnabled(false, for: "wordnet", knownSources: known)
        XCTAssertFalse(service.isEnabled(source: "wordnet"),
                       "wordnet must report disabled after setEnabled(false)")
        XCTAssertTrue(service.isEnabled(source: "openrussian"),
                      "openrussian must remain enabled when only wordnet was toggled")

        // Round-trip through UserDefaults: re-read raw and assert it's persisted.
        let stored = service.enabledSources
        XCTAssertNotNil(stored, "After any setEnabled call, the key must be present")
        XCTAssertFalse(stored?.contains("wordnet") ?? true)
        XCTAssertTrue(stored?.contains("openrussian") ?? false)

        // Re-enable wordnet — must be reflected immediately.
        service.setEnabled(true, for: "wordnet", knownSources: known)
        XCTAssertTrue(service.isEnabled(source: "wordnet"),
                      "wordnet must report enabled after setEnabled(true)")
        XCTAssertTrue(service.isEnabled(source: "openrussian"))
    }

    // MARK: - Issue #26: Manage Dictionaries grouping

    /// `ManageDictionariesViewModel` must default to "not importing", with no
    /// surfaced import-result message.
    @MainActor
    func testManageDictionariesViewModelDefaultState() throws {
        let vm = ManageDictionariesViewModel()
        XCTAssertFalse(vm.isImporting, "VM must default to not-importing")
        XCTAssertNil(vm.importResult, "VM must default to no surfaced import-result")
    }

    /// `.success([])` (file picker dismissed without choosing) must be a
    /// no-op: no async import is spawned, no state changes, no error surfaces.
    @MainActor
    func testManageDictionariesViewModelHandleImportEmptySelectionIsNoOp() throws {
        let vm = ManageDictionariesViewModel()
        vm.handleImport(result: .success([]))
        XCTAssertFalse(vm.isImporting,
                       "Empty selection must not flip isImporting to true")
        XCTAssertNil(vm.importResult,
                     "Empty selection must not surface an importResult message")
    }

    /// `handleImport(.success([jsonURL]))` must insert the fixture's entries
    /// into the active DB and surface an "Imported N entries" message.
    /// Verifies the end-to-end ViewModel → DatabaseService path; the URL
    /// resolves to the bundled `test_import_fixture.json` (10 entries).
    @MainActor
    func testHandleImportJSONFixtureInsertsEntries() async throws {
        let vm = ManageDictionariesViewModel()
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "test_import_fixture", withExtension: "json"),
            "Bundled JSON fixture must exist"
        )

        vm.handleImport(result: .success([url]))

        // handleImport spawns an async Task; poll for completion (importResult
        // becomes non-nil and isImporting flips back to false).
        try await waitForImportToFinish(vm: vm)

        let message = try XCTUnwrap(vm.importResult)
        XCTAssertTrue(message.contains("Imported"),
                      "Success message must read 'Imported N …'; got: \(message)")

        // Verify the unique fixture word is actually searchable in the DB.
        let results = try await db.search(query: "qaflux")
        XCTAssertGreaterThan(results.count, 0,
                             "Fixture entry 'qaflux' must be searchable after import")
    }

    /// `handleImport(.success([sqliteURL]))` must drain the external SQLite
    /// file into the active DB. Uses the bundled `test_import_fixture.sqlite`
    /// (10 entries) and asserts the unique word "zarboom" becomes searchable.
    @MainActor
    func testHandleImportSQLiteFixtureInsertsEntries() async throws {
        let vm = ManageDictionariesViewModel()
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "test_import_fixture", withExtension: "sqlite"),
            "Bundled SQLite fixture must exist"
        )

        vm.handleImport(result: .success([url]))
        try await waitForImportToFinish(vm: vm)

        let message = try XCTUnwrap(vm.importResult)
        XCTAssertTrue(message.contains("Imported"),
                      "Success message must read 'Imported N …'; got: \(message)")

        let results = try await db.search(query: "zarboom")
        XCTAssertGreaterThan(results.count, 0,
                             "Fixture entry 'zarboom' must be searchable after import")
    }

    /// Polls `vm.importResult` until set or 10s elapses. `handleImport`
    /// spawns an async Task that we cannot directly await, so the test loop
    /// observes the published state instead.
    @MainActor
    private func waitForImportToFinish(vm: ManageDictionariesViewModel,
                                       timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.importResult == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(vm.importResult, "Import did not complete within \(timeout)s")
        XCTAssertFalse(vm.isImporting, "isImporting must flip back to false on completion")
    }

    /// `handleImport(.failure(...))` must surface the error's
    /// `localizedDescription` via `importResult`.
    @MainActor
    func testManageDictionariesViewModelHandleImportFailureSurfacesError() throws {
        let vm = ManageDictionariesViewModel()

        struct ImportFailure: LocalizedError {
            var errorDescription: String? { "file is not a recognized dictionary" }
        }
        let failure = ImportFailure()

        vm.handleImport(result: .failure(failure))

        XCTAssertEqual(vm.importResult, failure.localizedDescription,
                       "Failure path must surface the error's localizedDescription")
        XCTAssertFalse(vm.isImporting,
                       "Failure path must not leave isImporting stuck on true")

        // A second, distinct failure must overwrite the previous message rather
        // than concatenating or being ignored.
        struct OtherFailure: LocalizedError {
            var errorDescription: String? { "permission denied" }
        }
        let other = OtherFailure()
        vm.handleImport(result: .failure(other))
        XCTAssertEqual(vm.importResult, other.localizedDescription,
                       "Second failure must replace the earlier importResult")
    }

    /// `SettingsViewModel` no longer carries import state after the
    /// issue-#26 split — the `isImporting` / `importResult` properties were
    /// removed. This is a structural guard, not a behavior test.
    @MainActor
    func testSettingsViewModelNoLongerOwnsImportState() throws {
        let vm = SettingsViewModel()
        let labels = Mirror(reflecting: vm).children.compactMap { $0.label }

        // @Published property wrappers manifest as `_propertyName` in Mirror,
        // so guard against both naming conventions.
        let leakedImportState = labels.filter {
            ["isImporting", "_isImporting",
             "importResult", "_importResult"].contains($0)
        }
        XCTAssertTrue(leakedImportState.isEmpty,
                      "SettingsViewModel must not own import state after issue #26; found: \(leakedImportState)")
    }

    // MARK: - Issue #1: Localization architecture

    /// `SupportedLocales.json` must decode into a non-empty list and contain
    /// both `en` and `ru` after the issue-#1 work ships.
    func testSupportedLocalesManifestLoads() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "SupportedLocales", withExtension: "json"),
            "SupportedLocales.json must be bundled with the app"
        )
        let data = try Data(contentsOf: url)
        let languages = try JSONDecoder().decode([UILanguage].self, from: data)

        XCTAssertFalse(languages.isEmpty, "Manifest must declare at least one language")

        let en = try XCTUnwrap(
            languages.first(where: { $0.code == "en" }),
            "Manifest must include English (code 'en')"
        )
        XCTAssertEqual(en.nativeName, "English",
                       "English nativeName must be 'English'")

        let ru = try XCTUnwrap(
            languages.first(where: { $0.code == "ru" }),
            "Manifest must include Russian (code 'ru')"
        )
        XCTAssertEqual(ru.nativeName, "Русский",
                       "Russian nativeName must be 'Русский' (Cyrillic), not a transliteration")

        // Each record must point at a localized key — without a displayKey
        // the Settings picker would render an empty string.
        for lang in languages {
            XCTAssertFalse(lang.displayKey.isEmpty,
                           "Language '\(lang.code)' must have a non-empty displayKey")
            XCTAssertFalse(lang.nativeName.isEmpty,
                           "Language '\(lang.code)' must have a non-empty nativeName")
        }
    }

    /// `LocalizationManager` must default to English when no preference is
    /// persisted and the device's preferred languages aren't in the
    /// supported list. We exercise the pure resolver directly.
    @MainActor
    func testLocalizationManagerDefaultsToEnglish() throws {
        let supported = [
            UILanguage(code: "ja", displayKey: "language.ja.name", nativeName: "日本語"),
            UILanguage(code: "fr", displayKey: "language.fr.name", nativeName: "Français"),
            UILanguage(code: "en", displayKey: "language.en.name", nativeName: "English"),
        ]
        let result = LocalizationManager.resolveInitialLanguage(
            persistedCode: nil,
            supported: supported
        )
        XCTAssertEqual(result.code, "en",
                       "With no persisted preference, default must be English")

        // Edge case: supported list without English at all — resolver must
        // still return *something* (first entry) rather than crashing on an
        // optional unwrap.
        let supportedNoEnglish = [
            UILanguage(code: "ja", displayKey: "language.ja.name", nativeName: "日本語"),
        ]
        let fallback = LocalizationManager.resolveInitialLanguage(
            persistedCode: nil,
            supported: supportedNoEnglish
        )
        XCTAssertEqual(fallback.code, "ja",
                       "When English is absent, resolver must fall back to first supported entry")
    }

    /// `LocalizationManager.setLanguage(...)` must update `currentLocale`,
    /// `currentLanguage`, and persist the code through `SettingsService`.
    @MainActor
    func testLocalizationManagerSetLanguagePersists() throws {
        // Don't bleed test state into the shared singleton or other tests.
        let originalCode = SettingsService.shared.selectedUILanguageCode
        addTeardownBlock { @MainActor in
            SettingsService.shared.selectedUILanguageCode = originalCode
        }
        SettingsService.shared.selectedUILanguageCode = nil

        let manager = LocalizationManager()
        XCTAssertEqual(manager.currentLanguage.code, "en",
                       "Pre-condition: a fresh manager with no persisted code starts at English")

        let russian = UILanguage(code: "ru", displayKey: "language.ru.name", nativeName: "Русский")
        manager.setLanguage(russian)

        XCTAssertEqual(manager.currentLanguage.code, "ru",
                       "currentLanguage must reflect the new selection")
        XCTAssertEqual(manager.currentLocale.identifier, "ru",
                       "currentLocale must update to match the new selection")
        XCTAssertEqual(SettingsService.shared.selectedUILanguageCode, "ru",
                       "Selection must be persisted through SettingsService")

        // A language not in the supported list must be ignored (the public
        // API documents this as a no-op).
        let unsupported = UILanguage(code: "zz-fake", displayKey: "x", nativeName: "Fake")
        manager.setLanguage(unsupported)
        XCTAssertEqual(manager.currentLanguage.code, "ru",
                       "Unsupported languages must be rejected, current selection unchanged")
        XCTAssertEqual(SettingsService.shared.selectedUILanguageCode, "ru",
                       "Persisted code must remain on last valid selection after rejected setLanguage")
    }

    /// Switching to Russian and back to English must round-trip cleanly,
    /// with each step persisting the choice and updating both
    /// `currentLanguage` and `currentLocale`. A second freshly-constructed
    /// manager must observe the persisted code on init.
    @MainActor
    func testLocalizationManagerLanguageRoundTrips() throws {
        let originalCode = SettingsService.shared.selectedUILanguageCode
        addTeardownBlock { @MainActor in
            SettingsService.shared.selectedUILanguageCode = originalCode
        }
        SettingsService.shared.selectedUILanguageCode = nil

        let manager = LocalizationManager()
        let english = UILanguage(code: "en", displayKey: "language.en.name", nativeName: "English")
        let russian = UILanguage(code: "ru", displayKey: "language.ru.name", nativeName: "Русский")

        XCTAssertEqual(manager.currentLanguage.code, "en", "Round-trip starts at English")

        manager.setLanguage(russian)
        XCTAssertEqual(manager.currentLanguage.code, "ru")
        XCTAssertEqual(manager.currentLocale.identifier, "ru")
        XCTAssertEqual(SettingsService.shared.selectedUILanguageCode, "ru")

        manager.setLanguage(english)
        XCTAssertEqual(manager.currentLanguage.code, "en",
                       "Switching back to English must restore the English record")
        XCTAssertEqual(manager.currentLocale.identifier, "en")
        XCTAssertEqual(SettingsService.shared.selectedUILanguageCode, "en")

        // A fresh manager built after the round-trip must observe the
        // persisted code — proves the persistence layer round-trips, not
        // just the in-memory state.
        let revived = LocalizationManager()
        XCTAssertEqual(revived.currentLanguage.code, "en",
                       "A second manager must pick up the persisted code on init")
    }

    /// The Russian plural form of `dictionary.entries.count` must produce
    /// `запись` for 1, `записи` for 3, and `записей` for 7 — CLDR plural
    /// classes one/few/many. Validates that the xcstrings catalog's
    /// plural variations made it through the Xcode compile step into the
    /// runtime localized resources.
    ///
    /// We pass the `ru.lproj` bundle explicitly. `String(localized:locale:)`
    /// alone is not enough: that initializer looks the format up in the
    /// *current* bundle's locale (development language = en) and only uses
    /// `locale:` for plural-rule selection on the resulting English string.
    /// Forcing the bundle ensures we get the Russian catalog entry.
    func testRussianPluralFormsForEntriesCount() throws {
        let ruBundle = try Self.lprojBundle(forLocale: "ru")
        let ru = Locale(identifier: "ru")

        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(1)", bundle: ruBundle, locale: ru),
            "1 запись",
            "Russian CLDR 'one' (1) must render with the 'запись' form"
        )
        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(3)", bundle: ruBundle, locale: ru),
            "3 записи",
            "Russian CLDR 'few' (2-4) must render with the 'записи' form"
        )
        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(7)", bundle: ruBundle, locale: ru),
            "7 записей",
            "Russian CLDR 'many' (5+) must render with the 'записей' form"
        )

        // Sanity check: English plurals also work — guards against the
        // catalog being wired up but the English variations getting dropped
        // in a future refactor. en.lproj is technically Bundle.main since
        // development language is English, but we look it up the same way
        // for symmetry with the Russian path.
        let enBundle = try Self.lprojBundle(forLocale: "en")
        let en = Locale(identifier: "en")
        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(1)", bundle: enBundle, locale: en),
            "1 entry",
            "English 'one' must use the singular form"
        )
        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(5)", bundle: enBundle, locale: en),
            "5 entries",
            "English 'other' must use the plural form"
        )
    }

    /// Resolves the per-locale resource bundle (e.g. `ru.lproj`) inside
    /// `Bundle.main`. Falls back to `Bundle.main` when the lproj isn't
    /// found, with an explicit XCTFail so the test reports a missing
    /// catalog compile rather than a misleading assertion failure later.
    private static func lprojBundle(forLocale code: String) throws -> Bundle {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            XCTFail("Expected '\(code).lproj' in app bundle — verify the xcstrings catalog compiles for '\(code)'")
            return .main
        }
        return bundle
    }

    // MARK: - Issue #23: Spanish UI localization

    /// `SupportedLocales.json` must now include Spanish (`es`) so the
    /// in-app language picker offers it. Verifies the manifest entry's
    /// code, native name, and display key, and that the three shipped UI
    /// languages all coexist.
    func testSupportedLocalesManifestIncludesSpanish() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "SupportedLocales", withExtension: "json"),
            "SupportedLocales.json must be bundled with the app"
        )
        let languages = try JSONDecoder().decode([UILanguage].self, from: Data(contentsOf: url))

        let es = try XCTUnwrap(
            languages.first(where: { $0.code == "es" }),
            "Manifest must include Spanish (code 'es') after Issue #23"
        )
        XCTAssertEqual(es.nativeName, "Español",
                       "Spanish nativeName must be 'Español' in its own (accented) script")
        XCTAssertEqual(es.displayKey, "language.es.name",
                       "Spanish displayKey must point at the 'language.es.name' catalog key")

        // The three shipped UI languages must all be offered, none dropped.
        let codes = Set(languages.map(\.code))
        XCTAssertTrue(codes.isSuperset(of: ["en", "ru", "es"]),
                      "Manifest must offer en, ru, and es; got \(codes.sorted())")
    }

    /// The shared `LocalizationManager` must surface Spanish among its
    /// supported languages (loaded from the bundled manifest), and the
    /// pure resolver must select Spanish when it is the persisted choice.
    @MainActor
    func testLocalizationManagerSupportsSpanish() throws {
        let supported = LocalizationManager.shared.supportedLanguages
        XCTAssertTrue(
            supported.contains(where: { $0.code == "es" }),
            "Shared LocalizationManager must load Spanish from SupportedLocales.json"
        )

        let resolved = LocalizationManager.resolveInitialLanguage(
            persistedCode: "es",
            supported: supported
        )
        XCTAssertEqual(resolved.code, "es",
                       "A persisted 'es' preference must resolve to Spanish")

        // Sanity: an unsupported persisted code must NOT masquerade as
        // Spanish — guards the resolver's match logic.
        let fallback = LocalizationManager.resolveInitialLanguage(
            persistedCode: "zz-not-real",
            supported: supported
        )
        XCTAssertNotEqual(fallback.code, "es",
                          "An unsupported code must not accidentally resolve to Spanish")
    }

    /// The xcstrings catalog must actually compile Spanish into `es.lproj`.
    /// Force-load the es bundle and assert a spread of keys across every
    /// major screen render their Spanish values — catching both a missing
    /// compile and any untranslated (English-leak) key.
    func testSpanishStringsCompiledIntoLproj() throws {
        let esBundle = try Self.lprojBundle(forLocale: "es")
        let es = Locale(identifier: "es")

        let cases: [(key: String, spanish: String)] = [
            ("tab.search", "Buscar"),
            ("tab.history", "Historial"),
            ("tab.bookmarks", "Marcadores"),
            ("tab.settings", "Ajustes"),
            ("settings.title", "Ajustes"),
            ("settings.language.section", "Idioma de la interfaz"),
            ("settings.language.picker", "Idioma"),
            ("settings.dictionaries.section", "Diccionarios"),
            ("settings.support.section", "Soporte"),
            ("settings.support.reportBug", "Informar de un error"),
            ("settings.support.credits", "Créditos"),
            ("settings.manageDictionaries", "Gestionar diccionarios"),
            ("about.section", "Acerca de"),
            ("common.loading", "Cargando…"),
            ("common.comingSoon", "Próximamente"),
            ("language.es.name", "Español"),
            ("language.en.name", "Inglés"),
            ("language.ru.name", "Ruso"),
        ]

        for (key, spanish) in cases {
            let value = String(localized: String.LocalizationValue(key), bundle: esBundle, locale: es)
            XCTAssertEqual(
                value, spanish,
                "Key '\(key)' must render its Spanish translation from es.lproj"
            )
        }

        // No-leak guard: the Spanish render must differ from the English
        // source for a translated key. If es.lproj silently fell back to
        // English, this catches it.
        let enBundle = try Self.lprojBundle(forLocale: "en")
        let en = Locale(identifier: "en")
        let enSearch = String(localized: "tab.search", bundle: enBundle, locale: en)
        let esSearch = String(localized: "tab.search", bundle: esBundle, locale: es)
        XCTAssertEqual(enSearch, "Search", "English control value must be 'Search'")
        XCTAssertNotEqual(esSearch, enSearch,
                          "Spanish 'tab.search' must not fall back to the English string")
    }

    /// Spanish CLDR plural forms for `dictionary.entries.count`: Spanish
    /// has `one` (n == 1) and `other`. Validates the plural variations
    /// compiled into es.lproj, mirroring the Russian plural test.
    func testSpanishPluralFormsForEntriesCount() throws {
        let esBundle = try Self.lprojBundle(forLocale: "es")
        let es = Locale(identifier: "es")

        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(1)", bundle: esBundle, locale: es),
            "1 entrada",
            "Spanish 'one' (1) must use the singular 'entrada'"
        )
        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(5)", bundle: esBundle, locale: es),
            "5 entradas",
            "Spanish 'other' (5) must use the plural 'entradas'"
        )
        XCTAssertEqual(
            String(localized: "dictionary.entries.count \(0)", bundle: esBundle, locale: es),
            "0 entradas",
            "Spanish 'other' (0) must use the plural 'entradas'"
        )
    }

    // MARK: - Issue #39: Build version from `git describe`
    //
    // `AppVersion` is a pure value type with no UIKit/SwiftUI dependencies.
    // The `init(describeOutput:)` seam feeds synthetic `git describe` strings
    // (no live git, no bundle), so we test the deterministic half — shape
    // classification (`isCleanTag`) and `displayString` — for each case the
    // build script can produce.

    /// The describe-shape classifier and display rule, across every case the
    /// build script (`generate_build_info.sh`) can emit. `displayString`
    /// returns the describe verbatim except for a single stripped leading `v`
    /// (App Store / iOS Settings convention).
    func testAppVersionClassifiesDescribeShapes() throws {
        // Clean tag — HEAD exactly on a semantic-version tag. This is also the
        // "uncommitted changes on a tagged commit" case: the script omits
        // `--dirty`, so it yields the same bare tag input.
        let cleanTag = AppVersion(describeOutput: "v1.3.0")
        XCTAssertTrue(cleanTag.isCleanTag, "'v1.3.0' is a clean semantic-version tag")
        XCTAssertEqual(cleanTag.displayString, "1.3.0",
                       "Clean tag must display verbatim with the leading 'v' stripped")

        // Tag without a leading 'v' — still clean, still displayed bare.
        let cleanNoV = AppVersion(describeOutput: "1.3.0")
        XCTAssertTrue(cleanNoV.isCleanTag, "'1.3.0' (no v) is a clean tag")
        XCTAssertEqual(cleanNoV.displayString, "1.3.0")

        // Post-tag dev build — full `git describe` with the -<N>-g<sha> suffix.
        let postTag = AppVersion(describeOutput: "v1.2.0-22-g27714a2")
        XCTAssertFalse(postTag.isCleanTag, "A -<N>-g<sha> describe suffix is not a clean tag")
        XCTAssertEqual(postTag.displayString, "1.2.0-22-g27714a2",
                       "Dev build must display the full describe (leading 'v' stripped)")

        // No-tags dev build — a bare abbreviated commit SHA.
        let bareSHA = AppVersion(describeOutput: "27714a2")
        XCTAssertFalse(bareSHA.isCleanTag, "A bare commit SHA is not a clean tag")
        XCTAssertEqual(bareSHA.displayString, "27714a2",
                       "A no-tags build displays the bare SHA verbatim")
    }

    /// `verboseString` must always append the build number in parentheses,
    /// e.g. `"1.2.0-22-g27714a2 (build 3)"`.
    func testAppVersionVerboseStringIncludesBuild() throws {
        let dev = AppVersion(describeOutput: "v1.2.0-22-g27714a2", buildNumber: "3")
        XCTAssertEqual(
            dev.verboseString, "1.2.0-22-g27714a2 (build 3)",
            "verboseString must be '<displayString> (build <n>)'"
        )

        let clean = AppVersion(describeOutput: "v1.3.0", buildNumber: "1")
        XCTAssertEqual(clean.verboseString, "1.3.0 (build 1)")

        // Multi-digit build — guard against any "single-character only" bug.
        let bigBuild = AppVersion(describeOutput: "v2.0.0", buildNumber: "1024")
        XCTAssertEqual(bigBuild.verboseString, "2.0.0 (build 1024)")
    }

    /// Missing keys fall back visibly: `gitDescribe` empty → `displayString`
    /// uses `marketingVersion`; `CFBundleShortVersionString`/`CFBundleVersion`
    /// fall back to `"unknown"`/`"0"` rather than crashing or returning empty.
    func testAppVersionFallsBackWhenInfoPlistMissing() throws {
        // Case 1: infoDictionary is nil (no Info.plist at all).
        let nilVersion = AppVersion(infoDictionary: nil)
        XCTAssertEqual(nilVersion.gitDescribe, "",
                       "Missing GIT_DESCRIBE must read as empty")
        XCTAssertEqual(nilVersion.marketingVersion, "unknown",
                       "Missing CFBundleShortVersionString must fall back to 'unknown'")
        XCTAssertEqual(nilVersion.buildNumber, "0",
                       "Missing CFBundleVersion must fall back to '0'")
        XCTAssertEqual(nilVersion.displayString, "unknown",
                       "Empty gitDescribe must fall back to the marketing version")
        XCTAssertEqual(nilVersion.verboseString, "unknown (build 0)",
                       "verboseString must compose cleanly with the fallback values")
        XCTAssertFalse(nilVersion.isCleanTag, "An empty describe is not a clean tag")

        // Case 2: infoDictionary exists but the keys we care about are absent.
        let emptyVersion = AppVersion(infoDictionary: [:])
        XCTAssertEqual(emptyVersion.marketingVersion, "unknown")
        XCTAssertEqual(emptyVersion.buildNumber, "0")
        XCTAssertEqual(emptyVersion.gitDescribe, "")

        // Case 3: GIT_DESCRIBE present, so displayString uses it even when the
        // marketing version is also present — gitDescribe is the source of truth.
        let withDescribe = AppVersion(infoDictionary: [
            "GIT_DESCRIBE": "v1.2.0-8-gc7238e0",
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "3"
        ])
        XCTAssertEqual(withDescribe.displayString, "1.2.0-8-gc7238e0",
                       "A present GIT_DESCRIBE must drive displayString, not the marketing version")

        // Case 4: keys exist but the values aren't strings (malformed plist).
        // The lookup is `info?[...] as? String`, so the fallback kicks in
        // rather than crashing.
        let wrongType: [String: Any] = [
            "GIT_DESCRIBE": 99,
            "CFBundleShortVersionString": 1.0,
            "CFBundleVersion": 42
        ]
        let wrongTypeVersion = AppVersion(infoDictionary: wrongType)
        XCTAssertEqual(wrongTypeVersion.gitDescribe, "",
                       "Non-string GIT_DESCRIBE must fall back to empty, not crash")
        XCTAssertEqual(wrongTypeVersion.marketingVersion, "unknown",
                       "Non-string CFBundleShortVersionString must fall back to 'unknown', not crash")
        XCTAssertEqual(wrongTypeVersion.buildNumber, "0",
                       "Non-string CFBundleVersion must fall back to '0', not crash")
    }

    /// `AppVersion.current` mirrors the live values in the host bundle's
    /// Info.plist — guarding against future refactors that drop a lookup.
    func testAppVersionCurrentMatchesBundle() throws {
        // The host app bundle holds the real values. The unit-test target is
        // hosted by the app, so resolve robustly.
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()

        let bundleVersion = hostBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let bundleBuild = hostBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        XCTAssertNotNil(bundleVersion,
                        "Host bundle must expose CFBundleShortVersionString (guarded by GENERATE_INFOPLIST_FILE)")
        XCTAssertNotNil(bundleBuild,
                        "Host bundle must expose CFBundleVersion")

        let current = AppVersion(bundle: hostBundle)
        XCTAssertEqual(current.marketingVersion, bundleVersion,
                       "AppVersion.marketingVersion must mirror the bundle's CFBundleShortVersionString")
        XCTAssertEqual(current.buildNumber, bundleBuild,
                       "AppVersion.buildNumber must mirror the bundle's CFBundleVersion")

        // The git-describe read path is pinned regardless of whether the build
        // wiring is in place yet: AppVersion must surface exactly the bundle's
        // GIT_DESCRIBE (an empty string until the Info.plist substitution is
        // wired; the real describe once it is).
        let bundleDescribe = hostBundle.object(forInfoDictionaryKey: "GIT_DESCRIBE") as? String ?? ""
        XCTAssertEqual(current.gitDescribe, bundleDescribe,
                       "AppVersion.gitDescribe must mirror the bundle's GIT_DESCRIBE key")

        // Issue #39 PM decision: `displayString` is the describe string with a
        // single leading `v` stripped (App Store / iOS Settings convention).
        // Pin it against the *live* bundle so a regression in the strip rule or
        // the substitution chain is caught. A scheme-built test bundle carries
        // a real describe because the Build pre-action runs for `test` too.
        XCTAssertFalse(bundleDescribe.isEmpty,
                       "A scheme-built test bundle must carry a non-empty GIT_DESCRIBE (the pre-action must run for the test scheme)")
        XCTAssertFalse(current.displayString.hasPrefix("v"),
                       "displayString must not carry a leading 'v' (got '\(current.displayString)')")
        let strippedDescribe = bundleDescribe.hasPrefix("v") ? String(bundleDescribe.dropFirst()) : bundleDescribe
        XCTAssertEqual(current.displayString, strippedDescribe,
                       "displayString must equal GIT_DESCRIBE with an optional leading 'v' removed")

        // The shared `AppVersion.current` instance must agree with a freshly
        // constructed one against the same bundle — proves the singleton
        // hasn't been replaced with a stale snapshot.
        XCTAssertEqual(AppVersion.current.marketingVersion, current.marketingVersion,
                       "AppVersion.current must equal a fresh AppVersion(bundle:) reading the same plist")
        XCTAssertEqual(AppVersion.current.buildNumber, current.buildNumber)
    }


    // MARK: - Issue #8: Bug-report flow (SupportService)
    //
    // SupportService is @MainActor and reads Bundle.main / UIDevice /
    // LocalizationManager.shared at call time, so the tests run on the
    // main actor and any language toggles are restored in teardown.

    /// Subject must start with a `[LibreDict <version> b<build>]` prefix
    /// and include the localized "LibreDict bug report" tail.
    @MainActor
    func testSupportServiceSubjectIncludesBuildPrefix() throws {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let subject = SupportService.shared.subject()

        let expectedPrefix = "[LibreDict \(appVersion) b\(buildNumber)]"
        XCTAssertTrue(
            subject.hasPrefix(expectedPrefix),
            "Subject must begin with the machine-readable build prefix '\(expectedPrefix)'; got '\(subject)'"
        )

        // The localized tail must follow the prefix. We force the lookup
        // through the active LocalizationManager (the same path SupportService
        // uses) so the assertion stays valid regardless of UI language.
        let localizedTail = LocalizationManager.shared.localized("support.email.subject")
        XCTAssertTrue(
            subject.hasSuffix(localizedTail),
            "Subject must end with the localized 'bug report' tail; got '\(subject)'"
        )
        XCTAssertNotEqual(
            localizedTail, "support.email.subject",
            "Localization key did not resolve — check xcstrings contains 'support.email.subject'"
        )
    }

    /// Body template must end with a delimited telemetry block containing
    /// app version, build, iOS version, device model, UI language, and
    /// system locale.
    @MainActor
    func testSupportServiceBodyContainsTelemetryBlock() throws {
        let body = SupportService.shared.bodyTemplate()

        // Delimited by '---' lines.
        XCTAssertTrue(body.hasSuffix("---"),
                      "Telemetry block must terminate with a '---' delimiter")
        let delimiterCount = body.components(separatedBy: "---").count - 1
        XCTAssertEqual(delimiterCount, 2,
                       "Telemetry block must be wrapped by exactly two '---' delimiters; got \(delimiterCount)")

        // Required field markers (English by design — see next test for the
        // language-independence guarantee).
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        XCTAssertTrue(body.contains("LibreDict \(appVersion) (build \(buildNumber))"),
                      "Telemetry block must include 'LibreDict <version> (build <build>)'")
        XCTAssertTrue(body.contains("iOS \(UIDevice.current.systemVersion)"),
                      "Telemetry block must include 'iOS <systemVersion>'")
        XCTAssertTrue(body.contains("Device:"),
                      "Telemetry block must include a 'Device:' line")
        XCTAssertTrue(body.contains("UI language: \(LocalizationManager.shared.currentLanguage.code)"),
                      "Telemetry block must include the active 'UI language: <code>'")
        XCTAssertTrue(body.contains("System locale: \(Locale.current.identifier)"),
                      "Telemetry block must include the 'System locale: <identifier>'")

        // The greeting must come *before* the telemetry block — the user's
        // free-text area sits between greeting and telemetry.
        let greeting = LocalizationManager.shared.localized("support.email.bodyGreeting")
        let greetingRange = try XCTUnwrap(body.range(of: greeting),
                                          "Body must start with the localized greeting")
        let telemetryRange = try XCTUnwrap(body.range(of: "---"),
                                           "Body must contain the '---' delimiter")
        XCTAssertLessThan(greetingRange.lowerBound, telemetryRange.lowerBound,
                          "Greeting must precede the telemetry block")
    }

    /// Telemetry block must remain in English regardless of the active UI
    /// language (English markers like `UI language:`, `Device:`).
    @MainActor
    func testSupportServiceTelemetryBlockIsEnglish() throws {
        // Save and restore the active language so we don't bleed Russian
        // selection into other tests.
        let manager = LocalizationManager.shared
        let originalLanguage = manager.currentLanguage
        let originalPersistedCode = SettingsService.shared.selectedUILanguageCode
        addTeardownBlock { @MainActor in
            manager.setLanguage(originalLanguage)
            SettingsService.shared.selectedUILanguageCode = originalPersistedCode
        }

        let russian = manager.supportedLanguages.first(where: { $0.code == "ru" })
            ?? UILanguage(code: "ru", displayKey: "language.ru.name", nativeName: "Русский")
        manager.setLanguage(russian)

        let block = SupportService.shared.telemetryBlock()

        // English markers must survive a UI language change.
        XCTAssertTrue(block.contains("LibreDict "),
                      "Telemetry block must keep the literal 'LibreDict' product marker in English")
        XCTAssertTrue(block.contains("(build "),
                      "Telemetry block must keep the English '(build N)' marker")
        XCTAssertTrue(block.contains("iOS "),
                      "Telemetry block must keep the English 'iOS' marker")
        XCTAssertTrue(block.contains("Device: "),
                      "Telemetry block must keep the English 'Device:' marker")
        XCTAssertTrue(block.contains("UI language: "),
                      "Telemetry block must keep the English 'UI language:' marker")
        XCTAssertTrue(block.contains("System locale: "),
                      "Telemetry block must keep the English 'System locale:' marker")

        // The value of UI language must reflect the *active* choice ("ru"),
        // even though the marker stays English — this is the dual signal
        // the triage human needs.
        XCTAssertTrue(block.contains("UI language: ru"),
                      "Active UI language code must be reported in the telemetry block")

        // Sanity: no Cyrillic letters leaked into the structured markers.
        // (Locale identifier values are safe; markers must be ASCII.)
        let cyrillicMarkers = ["Устройство", "Язык", "Локаль", "Сборка"]
        for marker in cyrillicMarkers {
            XCTAssertFalse(block.contains(marker),
                           "Telemetry block must not contain translated marker '\(marker)'")
        }
    }

    /// `mailtoURL()` must produce a valid `mailto:` URL whose path equals
    /// the configured recipient and whose query contains URL-encoded
    /// subject and body.
    @MainActor
    func testSupportServiceMailtoURLEncodesSubjectAndBody() throws {
        let service = SupportService.shared
        let url = try XCTUnwrap(service.mailtoURL(),
                                "mailtoURL() must produce a URL for a valid recipient")

        XCTAssertEqual(url.scheme, "mailto",
                       "mailtoURL must use the 'mailto' scheme; got '\(url.scheme ?? "nil")'")

        // URLComponents parsing gives us decoded values, which lets us
        // assert content equivalence without depending on a specific
        // percent-encoding scheme.
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false),
                                       "mailto URL must be parseable as URLComponents")

        // For mailto URLs, the recipient lives in the opaque/path portion.
        XCTAssertEqual(components.path, service.recipient,
                       "mailto path must equal the recipient address")

        let items = components.queryItems ?? []
        let subjectItem = items.first { $0.name == "subject" }
        let bodyItem = items.first { $0.name == "body" }

        XCTAssertEqual(subjectItem?.value, service.subject(),
                       "mailto query 'subject' must equal SupportService.subject()")
        XCTAssertEqual(bodyItem?.value, service.bodyTemplate(),
                       "mailto query 'body' must equal SupportService.bodyTemplate()")

        // The raw string must actually be percent-encoded (spaces from the
        // subject prefix, newlines in the body) — a regression here would
        // mean the mail client opens with garbled content.
        let raw = url.absoluteString
        XCTAssertFalse(raw.contains(" "),
                       "Raw mailto URL must not contain unencoded spaces; got '\(raw.prefix(120))…'")
        XCTAssertFalse(raw.contains("\n"),
                       "Raw mailto URL must not contain unencoded newlines")
    }

    /// `SupportService.recipient` must be a syntactically valid email
    /// address (one `@`, non-empty local and domain parts, no whitespace).
    /// Guards against accidentally committing a placeholder.
    @MainActor
    func testSupportServiceRecipientIsValidEmail() throws {
        let recipient = SupportService.shared.recipient

        XCTAssertFalse(recipient.isEmpty, "recipient must not be empty")
        XCTAssertNil(recipient.rangeOfCharacter(from: .whitespacesAndNewlines),
                     "recipient must not contain whitespace; got '\(recipient)'")

        let parts = recipient.split(separator: "@", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 2,
                       "recipient must contain exactly one '@' separator; got '\(recipient)'")
        XCTAssertFalse(parts[0].isEmpty, "recipient must have a non-empty local part")
        XCTAssertFalse(parts[1].isEmpty, "recipient must have a non-empty domain part")
        XCTAssertTrue(parts[1].contains("."),
                      "recipient domain must include a '.'; got '\(parts[1])'")

        // Guard against the most common placeholder typos.
        let lowered = recipient.lowercased()
        for placeholder in ["example.com", "todo", "fixme", "your-email", "changeme"] {
            XCTAssertFalse(lowered.contains(placeholder),
                           "recipient looks like a placeholder ('\(placeholder)'): '\(recipient)'")
        }
    }

    // MARK: - Issue #8: SupportViewModel

    /// Initial state: neither sheet nor alert is presented. Guards against
    /// the VM accidentally surfacing UI before the user taps anything.
    @MainActor
    func testSupportViewModelDefaultState() throws {
        let vm = SupportViewModel()
        XCTAssertFalse(vm.isPresentingMail,
                       "VM must default with no mail sheet presented")
        XCTAssertNil(vm.mailUnavailableAlert,
                     "VM must default with no mail-unavailable alert pending")
    }

    /// `handleMailDidFinish` flips `isPresentingMail` back to false for
    /// every `MFMailComposeResult` case. We don't surface any further UI
    /// from the callback — its only job is to retract the sheet flag.
    @MainActor
    func testSupportViewModelHandleMailDidFinishDismissesSheet() throws {
        let vm = SupportViewModel()

        let results: [MFMailComposeResult] = [.cancelled, .saved, .sent, .failed]
        for result in results {
            vm.isPresentingMail = true
            vm.handleMailDidFinish(result, error: nil)
            XCTAssertFalse(
                vm.isPresentingMail,
                "isPresentingMail must drop to false after result \(result.rawValue)"
            )
            XCTAssertNil(
                vm.mailUnavailableAlert,
                "handleMailDidFinish must not surface a fallback alert for result \(result.rawValue)"
            )
        }
    }

    /// `MailUnavailableReason.noMailClient` must be Identifiable (the
    /// SwiftUI `.alert(item:)` modifier requires it) and map to a real
    /// localization key so the alert body isn't blank.
    @MainActor
    func testSupportViewModelMailUnavailableReasonIsLocalized() throws {
        let reason = SupportViewModel.MailUnavailableReason.noMailClient
        XCTAssertEqual(reason.id, "noMailClient",
                       "Identifiable id must be stable for SwiftUI .alert(item:)")

        // Resolve the LocalizedStringKey through the active LocalizationManager
        // bundle (same path SwiftUI uses for Text(LocalizedStringKey)).
        let key = "support.mailUnavailable.body.noClient"
        let resolved = LocalizationManager.shared.localized(key)
        XCTAssertNotEqual(resolved, key,
                          "Localization for '\(key)' must resolve to a translated string")
        XCTAssertFalse(resolved.isEmpty,
                       "Localized body for noMailClient must not be empty")
    }


    // MARK: - Issue #24: FreeDict English–Spanish bundle
    //
    // The dictionary content itself lives in the bundled `seed.sqlite`,
    // so coverage spans two surfaces:
    //   1. Cosmetic Swift (`sourceLabel`, Settings toggle wiring) —
    //      independent of the seed contents.
    //   2. Bundled data (metadata row + searchable headwords) — the
    //      tests query the host bundle's `seed.sqlite` directly via
    //      GRDB, identical to the pattern in `testBundledSeedIsRealSQLite`.
    //      If the maintainer hasn't yet regenerated `seed.sqlite` with
    //      the new source these tests will fail loudly — that's the
    //      signal that the data step of #24 is incomplete.

    /// The canonical source identifier for the new dictionary. Centralised
    /// here so a future rename (e.g. moving to ISO-639-3 `eng-spa`
    /// codepoints) only requires one edit.
    private static let freeDictEngSpaSource = "freedict-eng-spa"

    /// `DictionaryEntry.sourceLabel` must return the terse "En–Es"
    /// badge for the new source identifier, not the raw capitalised
    /// fallback (e.g. "Freedict-Eng-Spa").
    func testFreeDictSourceLabelIsTerseEnEs() throws {
        let entry = DictionaryEntry(
            id: 1,
            word: "house",
            definition: "**noun**\n1. casa",
            phonetic: "haʊs",
            pos: "noun",
            source: Self.freeDictEngSpaSource,
            createdAt: nil
        )
        XCTAssertEqual(
            entry.sourceLabel, "En–Es",
            "freedict-eng-spa must render as the terse 'En–Es' badge, not the .capitalized fallback"
        )

        // Negative control: the unknown-source fallback (`.capitalized`)
        // still produces the wrong-looking 'Freedict-Eng-Spa'. We assert
        // this here so the test fails if anyone ever removes the switch
        // case entirely.
        let fallback = DictionaryEntry(
            id: nil, word: "x", definition: "", phonetic: "",
            pos: "", source: Self.freeDictEngSpaSource, createdAt: nil
        )
        XCTAssertNotEqual(
            fallback.sourceLabel, Self.freeDictEngSpaSource.capitalized,
            "freedict-eng-spa source must short-circuit the .capitalized fallback"
        )

        // Existing sources must keep their labels (regression guard).
        let wordnet = DictionaryEntry(
            id: nil, word: "x", definition: "", phonetic: "",
            pos: "", source: "wordnet", createdAt: nil
        )
        XCTAssertEqual(wordnet.sourceLabel, "WordNet")

        let openRussian = DictionaryEntry(
            id: nil, word: "x", definition: "", phonetic: "",
            pos: "", source: "openrussian", createdAt: nil
        )
        XCTAssertEqual(openRussian.sourceLabel, "OpenRussian")

        // An entirely unknown source still flows through .capitalized.
        let unknown = DictionaryEntry(
            id: nil, word: "x", definition: "", phonetic: "",
            pos: "", source: "kaikki", createdAt: nil
        )
        XCTAssertEqual(unknown.sourceLabel, "Kaikki",
                       "Unknown sources must fall back to .capitalized")
    }

    /// The bundled `seed.sqlite` must contain a `dict_metadata` row for
    /// `freedict-eng-spa` with every contract column populated. We open
    /// the seed directly (read-only) — the per-test `DatabaseService`
    /// instance points at a fresh tempDir DB and won't see bundled data.
    ///
    /// FAILS LOUDLY if the seed hasn't been regenerated with the new
    /// source. That's the gate that catches a half-shipped #24.
    func testFreeDictMetadataRowIsPopulated() throws {
        let queue = try Self.openBundledSeedReadOnly()

        let row = try queue.read { db -> Row? in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT source, display_name, version, license, url, description, word_count
                    FROM dict_metadata
                    WHERE source = ?
                    """,
                arguments: [Self.freeDictEngSpaSource]
            )
        }

        let unwrapped = try XCTUnwrap(
            row,
            "Bundled seed.sqlite has no dict_metadata row for '\(Self.freeDictEngSpaSource)'. Regenerate via `python Scripts/build_seed.py` before merging Issue #24."
        )

        let displayName: String = unwrapped["display_name"]
        let version: String = unwrapped["version"]
        let license: String = unwrapped["license"]
        let url: String = unwrapped["url"]
        let description: String = unwrapped["description"]
        let wordCount: Int = unwrapped["word_count"]

        XCTAssertFalse(displayName.isEmpty,
                       "dict_metadata.display_name must be non-empty")
        XCTAssertFalse(version.isEmpty,
                       "dict_metadata.version must capture the upstream FreeDict release tag")
        XCTAssertFalse(url.isEmpty,
                       "dict_metadata.url must point at FreeDict's project page")
        XCTAssertTrue(url.contains("freedict"),
                      "dict_metadata.url should reference 'freedict.org'; got '\(url)'")
        XCTAssertFalse(description.isEmpty,
                       "dict_metadata.description must explain the source")

        // GPL text is a hard contract — the bundle ships GPL'd data and
        // must surface the license text in-app (DictionaryDetailView).
        XCTAssertFalse(license.isEmpty,
                       "dict_metadata.license must contain the full GPL text")
        XCTAssertTrue(license.uppercased().contains("GPL") || license.contains("GNU GENERAL PUBLIC LICENSE"),
                      "License text must mention GPL — required for GPL compliance; got first 80 chars: \(license.prefix(80))")

        // Success criterion #3 from the design doc: ≥ 50,000 entries.
        XCTAssertGreaterThanOrEqual(
            wordCount, 50_000,
            "FreeDict eng-spa should contribute ≥ 50,000 entries (success criterion #3); got \(wordCount)"
        )
    }

    /// At least one *common* English headword from the eng-spa pair must
    /// be present in the bundled seed under `source = 'freedict-eng-spa'`.
    /// We try several candidates so the test isn't pinned to a single
    /// word that could be missing in an upstream release.
    func testFreeDictHeadwordIsSearchable() throws {
        let queue = try Self.openBundledSeedReadOnly()

        // Sanity: the source must have a presence in the entries table.
        let total = try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM entries WHERE source = ?",
                arguments: [Self.freeDictEngSpaSource]
            ) ?? 0
        }
        XCTAssertGreaterThan(
            total, 0,
            "Bundled seed has no entries with source='\(Self.freeDictEngSpaSource)'. Regenerate via `python Scripts/build_seed.py`."
        )

        // Pick everyday words that every general-purpose English-Spanish
        // dictionary covers. At least one must hit.
        let candidates = ["house", "water", "book", "time", "love", "day"]
        var hits: [String: Int] = [:]
        try queue.read { db in
            for word in candidates {
                let count = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM entries
                        WHERE source = ? AND word = ? COLLATE NOCASE
                        """,
                    arguments: [Self.freeDictEngSpaSource, word]
                ) ?? 0
                hits[word] = count
            }
        }
        let foundWords = hits.filter { $0.value > 0 }.map { $0.key }.sorted()
        // Halt the test if no candidates hit — continuing would just
        // emit an index-out-of-range crash on `foundWords[0]`.
        let probeWord = try XCTUnwrap(
            foundWords.first,
            "None of the candidate headwords \(candidates) were found in '\(Self.freeDictEngSpaSource)'. The dictionary is either too small, mis-cased, or mis-tagged. Hits: \(hits)"
        )

        // Verify the row is fully populated — `definition` non-empty
        // (sense aggregation worked) and `source` exactly matches (tags
        // weren't truncated/renamed).
        let entry = try queue.read { db -> Row? in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT word, definition, source, pos
                    FROM entries
                    WHERE source = ? AND word = ? COLLATE NOCASE
                    LIMIT 1
                    """,
                arguments: [Self.freeDictEngSpaSource, probeWord]
            )
        }
        let unwrapped = try XCTUnwrap(entry,
                                      "Lookup for '\(probeWord)' in '\(Self.freeDictEngSpaSource)' returned no row")
        let definition: String = unwrapped["definition"]
        XCTAssertFalse(definition.isEmpty,
                       "FreeDict entries must have a non-empty definition; '\(probeWord)' was empty")
        let actualSource: String = unwrapped["source"]
        XCTAssertEqual(actualSource, Self.freeDictEngSpaSource,
                       "Source identifier must match the canonical 'freedict-eng-spa'")
    }

    /// `SettingsService.isEnabled(source:)` must report the new source as
    /// enabled on first launch (no UserDefaults entry), persist a toggle
    /// to off, and persist a toggle back to on — same shape as the
    /// existing `testSettingsServiceTogglePersists`, scoped to the new id.
    func testFreeDictSourceTogglePersists() throws {
        let service = SettingsService.shared

        // Snapshot + restore so we don't bleed state into adjacent tests.
        let originalEnabled = service.enabledSources
        addTeardownBlock {
            service.enabledSources = originalEnabled
        }

        // First-launch state.
        service.enabledSources = nil
        XCTAssertTrue(
            service.isEnabled(source: Self.freeDictEngSpaSource),
            "Unknown / first-launch state must treat \(Self.freeDictEngSpaSource) as enabled"
        )

        let known: Set<String> = ["wordnet", "openrussian", Self.freeDictEngSpaSource]

        // Toggle off.
        service.setEnabled(false, for: Self.freeDictEngSpaSource, knownSources: known)
        XCTAssertFalse(
            service.isEnabled(source: Self.freeDictEngSpaSource),
            "After setEnabled(false), freedict-eng-spa must report disabled"
        )
        // Other sources must remain enabled (the user toggled exactly one).
        XCTAssertTrue(service.isEnabled(source: "wordnet"),
                      "Disabling freedict-eng-spa must not affect other sources")
        XCTAssertTrue(service.isEnabled(source: "openrussian"))

        // Persisted set must contain the other two and exclude ours.
        let stored = service.enabledSources
        XCTAssertNotNil(stored, "Persisted enabledSources must exist after any setEnabled call")
        XCTAssertFalse(stored?.contains(Self.freeDictEngSpaSource) ?? true,
                       "Persisted set must not contain freedict-eng-spa after toggling it off")
        XCTAssertTrue(stored?.contains("wordnet") ?? false)
        XCTAssertTrue(stored?.contains("openrussian") ?? false)

        // Toggle back on.
        service.setEnabled(true, for: Self.freeDictEngSpaSource, knownSources: known)
        XCTAssertTrue(
            service.isEnabled(source: Self.freeDictEngSpaSource),
            "Re-enabling freedict-eng-spa must be visible immediately"
        )
        XCTAssertTrue(service.enabledSources?.contains(Self.freeDictEngSpaSource) ?? false,
                      "Re-enable must round-trip through UserDefaults")
    }

    /// Opens the bundled `seed.sqlite` read-only via GRDB so the FreeDict
    /// tests can probe it without touching the per-test database. Mirrors
    /// the host-bundle resolution used by `testBundledSeedIsRealSQLite`.
    private static func openBundledSeedReadOnly() throws -> DatabaseQueue {
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()

        let seedURL = try XCTUnwrap(
            hostBundle.url(forResource: "seed", withExtension: "sqlite")
                ?? Bundle.main.url(forResource: "seed", withExtension: "sqlite"),
            "Bundled seed.sqlite is missing from the app bundle"
        )

        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: seedURL.path, configuration: config)
    }

    // MARK: - Issue #42: Spanish WordNet (Spanish–English) bundle
    //
    // Content lives in the bundled `seed.sqlite` under source
    // `wordnet-spa-eng`, so coverage mirrors the #24 FreeDict tests:
    //   1. Cosmetic Swift (sourceLabel, Settings toggle) — independent of
    //      the seed contents.
    //   2. Bundled data (metadata row + searchable headwords) — queried
    //      directly via `openBundledSeedReadOnly()`. These fail loudly if
    //      the maintainer hasn't regenerated `seed.sqlite` with the new
    //      source, which is the signal that the data step of #42 is
    //      incomplete.

    /// Canonical source identifier for Spanish WordNet (spa→eng). Follows
    /// the #24 `provider-srclang-tgtlang` convention. Centralised so a
    /// future rename is a one-line edit.
    private static let spanishWordNetSource = "wordnet-spa-eng"

    /// `DictionaryEntry.sourceLabel` must return the terse "Es–En" badge
    /// for the Spanish WordNet source identifier, not the raw
    /// capitalised fallback.
    func testSpanishWordNetSourceLabelIsTerseEsEn() throws {
        let entry = DictionaryEntry(
            id: 1, word: "casa",
            definition: "**noun**\n1. house, home — a dwelling…",
            phonetic: "", pos: "noun",
            source: Self.spanishWordNetSource, createdAt: nil
        )
        XCTAssertEqual(
            entry.sourceLabel, "Es–En",
            "wordnet-spa-eng must render as the terse 'Es–En' badge, not the .capitalized fallback"
        )

        // The .capitalized fallback would produce 'Wordnet-Spa-Eng'. The
        // switch case must short-circuit it.
        XCTAssertNotEqual(
            entry.sourceLabel, Self.spanishWordNetSource.capitalized,
            "wordnet-spa-eng source must short-circuit the .capitalized fallback"
        )

        // Regression guards: existing sources keep their labels, and the
        // sibling bilingual source from #24 is not confused with this one.
        XCTAssertEqual(
            DictionaryEntry(id: nil, word: "x", definition: "", phonetic: "",
                            pos: "", source: "wordnet", createdAt: nil).sourceLabel,
            "WordNet",
            "Plain 'wordnet' must stay 'WordNet', not collide with the spa-eng label"
        )
        XCTAssertEqual(
            DictionaryEntry(id: nil, word: "x", definition: "", phonetic: "",
                            pos: "", source: "freedict-eng-spa", createdAt: nil).sourceLabel,
            "En–Es",
            "The #24 eng-spa source must keep its 'En–Es' badge (opposite direction)"
        )
    }

    /// The bundled DB must carry a `dict_metadata` row for
    /// `wordnet-spa-eng` with non-empty license, display_name, version
    /// (accurately naming the WordNet/OMW version), url, and description.
    ///
    /// FAILS LOUDLY if the seed hasn't been regenerated with the new
    /// source — the gate that catches a half-shipped #42.
    func testSpanishWordNetMetadataRowIsPopulated() throws {
        let queue = try Self.openBundledSeedReadOnly()

        let row = try queue.read { db -> Row? in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT source, display_name, version, license, url, description, word_count
                    FROM dict_metadata
                    WHERE source = ?
                    """,
                arguments: [Self.spanishWordNetSource]
            )
        }

        let unwrapped = try XCTUnwrap(
            row,
            "Bundled seed.sqlite has no dict_metadata row for '\(Self.spanishWordNetSource)'. Regenerate via `python Scripts/build_seed.py` before merging Issue #42."
        )

        let displayName: String = unwrapped["display_name"]
        let version: String = unwrapped["version"]
        let license: String = unwrapped["license"]
        let url: String = unwrapped["url"]
        let description: String = unwrapped["description"]
        let wordCount: Int = unwrapped["word_count"]

        XCTAssertFalse(displayName.isEmpty,
                       "dict_metadata.display_name must be non-empty")
        XCTAssertFalse(url.isEmpty,
                       "dict_metadata.url must point at the MCR / OMW project page")
        XCTAssertFalse(description.isEmpty,
                       "dict_metadata.description must explain the source")

        // The design doc's central correctness point: the version must
        // *accurately* name the WordNet/OMW version used (the English
        // wordnet row's "3.1" is a known mislabel). Require a version-like
        // token so a blank or stub value fails.
        XCTAssertFalse(version.isEmpty,
                       "dict_metadata.version must state the WordNet/OMW version used")
        XCTAssertTrue(
            version.range(of: #"\d"#, options: .regularExpression) != nil,
            "dict_metadata.version should contain a version number (e.g. 'OMW 1.4 / WordNet 3.0'); got '\(version)'"
        )

        // License text is a hard contract — the bundle ships licensed data
        // and surfaces the text in DictionaryDetailView. Guard against an
        // empty or stub value.
        XCTAssertGreaterThan(
            license.count, 50,
            "dict_metadata.license must contain real license text, not a stub; got \(license.count) chars"
        )

        // Success criterion #1 from the design doc: ≥ 30,000 entries.
        XCTAssertGreaterThanOrEqual(
            wordCount, 30_000,
            "Spanish WordNet should contribute ≥ 30,000 entries (design doc success criterion); got \(wordCount)"
        )
    }

    /// A common Spanish headword must be present under `wordnet-spa-eng`,
    /// and its definition must lead with the correct English translation —
    /// which also verifies the synset mapping resolved Spanish→English to
    /// the *right* synset (the design doc's "Critical Risk").
    func testSpanishWordNetHeadwordIsSearchable() throws {
        let queue = try Self.openBundledSeedReadOnly()

        // Sanity: the source must have a presence in the entries table.
        let total = try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM entries WHERE source = ?",
                arguments: [Self.spanishWordNetSource]
            ) ?? 0
        }
        XCTAssertGreaterThan(
            total, 0,
            "Bundled seed has no entries with source='\(Self.spanishWordNetSource)'. Regenerate via `python Scripts/build_seed.py`."
        )

        // Spanish headword → an English translation lemma that the correct
        // synset must contain. These are the sampled mappings the design
        // doc calls out (casa→house, perro→dog, agua→water). Probing
        // several guards against any single lemma being absent upstream.
        let expectedTranslations: [String: String] = [
            "casa": "house",
            "perro": "dog",
            "agua": "water",
            "libro": "book",
            "gato": "cat"
        ]

        var probed: [String: String] = [:]   // spanish -> its definition (when found)
        try queue.read { db in
            for spanish in expectedTranslations.keys {
                if let def = try String.fetchOne(
                    db,
                    sql: """
                        SELECT definition FROM entries
                        WHERE source = ? AND word = ?
                        LIMIT 1
                        """,
                    arguments: [Self.spanishWordNetSource, spanish]
                ) {
                    probed[spanish] = def
                }
            }
        }

        // Require at least one candidate present (guards against an empty
        // or missing source), then validate the synset alignment for
        // *every* probed hit — not just the first — so a single wrong
        // mapping can't slip through behind a correct one.
        XCTAssertFalse(
            probed.isEmpty,
            "None of the candidate Spanish headwords \(expectedTranslations.keys.sorted()) were found in '\(Self.spanishWordNetSource)'. The dictionary is too small or mis-tagged."
        )

        for (spanish, definition) in probed {
            XCTAssertFalse(
                definition.isEmpty,
                "Spanish WordNet entry '\(spanish)' must have a non-empty definition"
            )
            // The synset must have mapped to the correct English word —
            // the alignment-correctness check, not just "some text exists".
            let expectedEnglish = expectedTranslations[spanish]!
            XCTAssertTrue(
                definition.range(of: expectedEnglish, options: .caseInsensitive) != nil,
                "Definition for Spanish '\(spanish)' must contain the English translation '\(expectedEnglish)' (synset alignment); got: \(definition.prefix(160))"
            )
        }
    }

    /// `SettingsService.isEnabled(source: "wordnet-spa-eng")` must follow
    /// the first-launch-all-enabled then toggle-persists contract,
    /// paralleling the other per-source toggle tests.
    func testSpanishWordNetSourceTogglePersists() throws {
        let service = SettingsService.shared

        // Snapshot + restore so we don't bleed state into adjacent tests.
        let originalEnabled = service.enabledSources
        addTeardownBlock {
            service.enabledSources = originalEnabled
        }

        // First-launch state: every source enabled, including unknown ones.
        service.enabledSources = nil
        XCTAssertTrue(
            service.isEnabled(source: Self.spanishWordNetSource),
            "First-launch state must treat \(Self.spanishWordNetSource) as enabled"
        )

        let known: Set<String> = ["wordnet", "openrussian", "freedict-eng-spa", Self.spanishWordNetSource]

        // Toggle off — siblings must remain enabled.
        service.setEnabled(false, for: Self.spanishWordNetSource, knownSources: known)
        XCTAssertFalse(
            service.isEnabled(source: Self.spanishWordNetSource),
            "After setEnabled(false), wordnet-spa-eng must report disabled"
        )
        XCTAssertTrue(service.isEnabled(source: "freedict-eng-spa"),
                      "Disabling wordnet-spa-eng must not affect the eng-spa source")
        XCTAssertTrue(service.isEnabled(source: "wordnet"))

        // Persisted set must exclude ours and keep the others.
        let stored = service.enabledSources
        XCTAssertNotNil(stored, "Persisted enabledSources must exist after any setEnabled call")
        XCTAssertFalse(stored?.contains(Self.spanishWordNetSource) ?? true,
                       "Persisted set must not contain wordnet-spa-eng after toggling it off")
        XCTAssertTrue(stored?.contains("freedict-eng-spa") ?? false)

        // Toggle back on.
        service.setEnabled(true, for: Self.spanishWordNetSource, knownSources: known)
        XCTAssertTrue(
            service.isEnabled(source: Self.spanishWordNetSource),
            "Re-enabling wordnet-spa-eng must be visible immediately"
        )
        XCTAssertTrue(service.enabledSources?.contains(Self.spanishWordNetSource) ?? false,
                      "Re-enable must round-trip through UserDefaults")
    }

    // MARK: - Issue #10: Arabic dictionary (normalized search column)
    //
    // The riskiest unverified path in #10 is the v1.2.x → v1.3.0 client
    // migration in `DatabaseService.applySchema`: it ALTERs `entries`, backfills
    // `word_normalized`, and DROP/CREATE/rebuilds the FTS index so it points at
    // the new column. Fresh install is exercised on every run; the upgrade path
    // is not. These tests build a pre-#10 database by hand and drive the real
    // migration through `setup(path:)`.

    /// Source identifiers used by the migration fixtures (representative of the
    /// en / ru / es data that exists on a pre-#10 install).
    private static let preV10Sources = ["wordnet", "openrussian", "wordnet-spa-eng"]

    /// The exact `entries` / `entries_fts` schema that shipped *before* #10:
    /// no `word_normalized` column, FTS indexes `word`, triggers reference
    /// `new.word`. `dict_metadata` is created without the `description` column
    /// too, so the migration's pre-existing `description` ALTER also runs.
    private static let preV10Schema = """
        CREATE TABLE entries (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            word        TEXT    NOT NULL,
            definition  TEXT    NOT NULL,
            phonetic    TEXT    DEFAULT '',
            pos         TEXT    DEFAULT '',
            source      TEXT    DEFAULT 'default',
            created_at  TEXT    DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX idx_entries_word_source
            ON entries(word COLLATE NOCASE, source);
        CREATE VIRTUAL TABLE entries_fts USING fts5(
            word, definition,
            content='entries', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts(rowid, word, definition)
                VALUES (new.id, new.word, new.definition);
        END;
        CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, word, definition)
                VALUES ('delete', old.id, old.word, old.definition);
        END;
        CREATE TRIGGER entries_au AFTER UPDATE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, word, definition)
                VALUES ('delete', old.id, old.word, old.definition);
            INSERT INTO entries_fts(rowid, word, definition)
                VALUES (new.id, new.word, new.definition);
        END;
        CREATE TABLE history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            word        TEXT    NOT NULL UNIQUE,
            looked_at   TEXT    DEFAULT (datetime('now'))
        );
        CREATE TABLE bookmarks (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id    INTEGER NOT NULL UNIQUE REFERENCES entries(id) ON DELETE CASCADE,
            created_at  TEXT    DEFAULT (datetime('now'))
        );
        CREATE TABLE dict_metadata (
            source       TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            version      TEXT NOT NULL DEFAULT '',
            license      TEXT NOT NULL DEFAULT '',
            url          TEXT NOT NULL DEFAULT '',
            word_count   INTEGER NOT NULL DEFAULT 0,
            built_at     TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """

    /// Representative pre-#10 rows. Latin/Cyrillic only (no Arabic exists
    /// pre-#10), so every row's normalized form is exactly its `word`.
    private static let preV10Rows: [(word: String, source: String)] = [
        ("house", "wordnet"), ("water", "wordnet"), ("book", "wordnet"),
        ("дом", "openrussian"), ("вода", "openrussian"),
        ("casa", "wordnet-spa-eng"), ("agua", "wordnet-spa-eng"),
    ]

    /// Builds a standalone pre-#10 database at `path`, seeded with the rows
    /// above and `user_version = 0`. The connection is closed before return
    /// (the local queue deallocates) so `DatabaseService` can open it cleanly.
    private func buildPreV10Database(at path: String) throws {
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: Self.preV10Schema)
            for (word, source) in Self.preV10Rows {
                try db.execute(
                    sql: "INSERT INTO entries(word, definition, phonetic, pos, source) VALUES (?, ?, '', 'noun', ?)",
                    arguments: [word, "Definition of \(word).", source]
                )
            }
            // Pre-#10 installs were never user_version-stamped.
            try db.execute(sql: "PRAGMA user_version = 0")
        }
    }

    /// Opens a fresh GRDB connection on `path` for schema introspection
    /// (PRAGMAs, sqlite_master) without disturbing the service's pool.
    private func openQueue(at path: String) throws -> DatabaseQueue {
        try DatabaseQueue(path: path)
    }

    /// Migration v1 (#10): a pre-#10 database upgraded via `setup(path:)` must
    /// gain a populated `word_normalized`, repoint FTS at it, preserve every
    /// row, and remain searchable. This is the upgrade path no other test covers.
    func testMigrationFromPreV10SchemaUpgradesAndPreservesData() async throws {
        let path = tempDir.appendingPathComponent("legacy.sqlite").path
        try buildPreV10Database(at: path)

        // Drive the real migration (Schema.sql IF NOT EXISTS no-ops on the old
        // tables, then `migrate` does the ALTER + FTS drop/recreate/rebuild).
        try await db.setup(path: path)

        // --- Schema post-conditions (raw introspection) ---
        let introspect = try openQueue(at: path)
        try await introspect.read { conn in
            // user_version stamped to 1.
            let version = try Int.fetchOne(conn, sql: "PRAGMA user_version") ?? -1
            XCTAssertEqual(version, 1, "Migration must stamp PRAGMA user_version = 1")

            // entries has a NOT NULL word_normalized column.
            let cols = try Row.fetchAll(conn, sql: "PRAGMA table_info(entries)")
            let wn = cols.first { ($0["name"] as String) == "word_normalized" }
            let wnCol = try XCTUnwrap(wn, "entries must have a word_normalized column after migration")
            XCTAssertEqual(wnCol["notnull"] as Int, 1, "word_normalized must be NOT NULL")

            // Every row's word_normalized is populated and (pre-#10 data) == word.
            let unpopulated = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM entries WHERE word_normalized IS NULL OR word_normalized = ''") ?? -1
            XCTAssertEqual(unpopulated, 0, "Backfill must populate word_normalized for every existing row")
            let mismatched = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM entries WHERE word_normalized <> word") ?? -1
            XCTAssertEqual(mismatched, 0, "Pre-#10 rows must backfill word_normalized = word exactly")

            // FTS was recreated against word_normalized.
            let ftsSQL = try String.fetchOne(
                conn, sql: "SELECT sql FROM sqlite_master WHERE name = 'entries_fts'") ?? ""
            XCTAssertTrue(ftsSQL.contains("word_normalized"),
                          "entries_fts must be recreated indexing word_normalized; got: \(ftsSQL)")
        }

        // --- Data survived: per-source counts unchanged ---
        for source in Self.preV10Sources {
            let expected = Self.preV10Rows.filter { $0.source == source }.count
            let actual = try await db.entryCount(source: source)
            XCTAssertEqual(actual, expected,
                           "Source '\(source)' must keep all \(expected) rows through migration; got \(actual)")
        }

        // --- FTS rebuild worked: a known word is searchable, and the
        //     content matches (proves the rebuild indexed real content) ---
        let houseResults = try await db.search(query: "house")
        XCTAssertTrue(houseResults.contains { $0.word == "house" },
                      "A pre-existing English word must be searchable after the FTS rebuild")
        let cyrillic = try await db.search(query: "дом")
        XCTAssertTrue(cyrillic.contains { $0.word == "дом" },
                      "A pre-existing Cyrillic word must be searchable after the FTS rebuild")
    }

    /// Running the migration twice must be a no-op the second time: no error,
    /// user_version stays 1, and no rows or FTS entries are duplicated.
    func testMigrationIsIdempotent() async throws {
        let path = tempDir.appendingPathComponent("legacy_idem.sqlite").path
        try buildPreV10Database(at: path)

        try await db.setup(path: path)               // first migration
        let countAfterFirst = try await db.entryCount()
        try await db.setup(path: path)               // second run — must skip

        // Row count unchanged (no double-insert).
        let countAfterSecond = try await db.entryCount()
        XCTAssertEqual(countAfterSecond, countAfterFirst,
                       "Re-running the migration must not change the row count")
        XCTAssertEqual(countAfterSecond, Self.preV10Rows.count,
                       "Row count must equal the original fixture size")

        let introspect = try openQueue(at: path)
        try await introspect.read { conn in
            // Still stamped exactly 1.
            XCTAssertEqual(try Int.fetchOne(conn, sql: "PRAGMA user_version") ?? -1, 1,
                           "user_version must remain 1 after a second run (no re-stamp loop)")
            // FTS row count must equal entries row count — a double rebuild or
            // duplicate trigger fire would inflate the external-content index.
            let entriesCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries") ?? -1
            let ftsCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries_fts") ?? -2
            XCTAssertEqual(ftsCount, entriesCount,
                           "entries_fts must hold exactly one row per entry (no duplicates from a second migration)")
        }

        // And search still returns exactly one match for a unique word.
        let results = try await db.search(query: "house")
        XCTAssertEqual(results.filter { $0.word == "house" }.count, 1,
                       "A unique word must match exactly once (no duplicate FTS rows)")
    }

    // MARK: - Issue #10: Arabic search symmetry (§1 / §2)

    /// Inserts one row with an explicit `word_normalized` (mimicking what the
    /// Python build does for Arabic), via a direct connection so the value
    /// isn't overwritten by the `= word` custom-import policy.
    private func insertNormalizedEntry(word: String, normalized: String,
                                       definition: String, source: String) async throws {
        let path = tempDir.appendingPathComponent("test.sqlite").path
        let pool = try DatabasePool(path: path)
        try await pool.writeWithoutTransaction { conn in
            try conn.execute(
                sql: """
                    INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                    VALUES (?, ?, ?, '', 'noun', ?)
                    """,
                arguments: [word, normalized, definition, source])
        }
    }

    /// §1 (the load-bearing AC: "Arabic terms searchable *without* diacritics"),
    /// through the real Swift `search` path: a vocalized Arabic headword whose
    /// stored `word_normalized` is the bare form must be found when the user
    /// types the **bare** form.
    ///
    /// FINDING (corrects DESIGN_DOC §1): §1 claims `sanitizeFTS` strips the
    /// harakat from the query ("a user typing … كِتَاب, which sanitize
    /// de-vocalizes"). It does **not** — the harakat are Unicode category Mn,
    /// and `CharacterSet.alphanumerics` (which `sanitizeFTS` keeps) *includes*
    /// M* marks, so they survive sanitisation. The FTS `remove_diacritics 2`
    /// tokenizer also leaves Arabic harakat intact (verified: `MATCH 'كِتَاب'`
    /// finds nothing against an indexed bare `كتاب`). Diacritic-insensitivity
    /// therefore rests **entirely** on the Python build pre-normalising
    /// `word_normalized` to the bare form, matched bare-to-bare — exactly the
    /// AC's "search without diacritics". A *fully vocalized query* is NOT
    /// guaranteed to match; that is outside the AC and asserted only as the
    /// bare-query behaviour below.
    func testArabicBareQueryMatchesVocalizedHeadword() async throws {
        // كِتَاب (vocalized display) stored with word_normalized = كتاب (bare key).
        try await insertNormalizedEntry(
            word: "كِتَاب", normalized: "كتاب",
            definition: "**noun**\n1. book — a written work.", source: "wordnet-arb-eng")

        let bare = try await db.search(query: "كتاب")
        XCTAssertTrue(bare.contains { $0.word == "كِتَاب" },
                      "Bare 'كتاب' must find the vocalized headword 'كِتَاب' — the load-bearing diacritic-free search AC")
    }

    /// §1, against the **shipped** seed: at least one real wordnet-arb-eng row
    /// whose `word` carries harakat must be reachable by its bare form. This is
    /// the load-bearing path — 69% of Arabic lemmas are vocalized.
    func testArabicDiacriticInsensitiveSearchAgainstSeed() async throws {
        let queue = try Self.openBundledSeedReadOnly()

        // Mirror the app's search SQL (MATCH bare 'كتاب', prefix) against the seed.
        let rows: [Row] = try await queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT e.word AS word, e.word_normalized AS wn
                FROM entries_fts fts JOIN entries e ON e.id = fts.rowid
                WHERE entries_fts MATCH ? AND e.source = 'wordnet-arb-eng'
                LIMIT 50
                """, arguments: ["كتاب*"])
        }
        XCTAssertFalse(rows.isEmpty,
                       "Bare 'كتاب' must match real Arabic rows in the seed (diacritic-insensitive search)")

        // The harakat code points the build strips (DESIGN_DOC §1).
        let harakat = Set(0x064B...0x065F).union([0x0670])
        let hasVocalizedHit = rows.contains { row in
            let word = row["word"] as String? ?? ""
            return word.unicodeScalars.contains { harakat.contains(Int($0.value)) }
        }
        XCTAssertTrue(hasVocalizedHit,
                      "At least one bare-'كتاب' match must be a *vocalized* headword — proving harakat-stripped reachability")
    }

    /// §2 ORDER BY change: a row whose `word_normalized` equals the query
    /// exactly must rank above a row that only contains the term in its
    /// `definition`. Without the `word_normalized`-based boost (the design's
    /// one required `search` change) the exact Arabic headword would not win.
    func testArabicNormalizedExactMatchRanksAboveDefinitionMatch() async throws {
        // Exact normalized headword.
        try await insertNormalizedEntry(
            word: "كِتاب", normalized: "كتاب",
            definition: "**noun**\n1. book — a written work.", source: "wordnet-arb-eng")
        // A different headword that merely mentions كتاب in its definition.
        try await insertNormalizedEntry(
            word: "مكتبة", normalized: "مكتبة",
            definition: "**noun**\n1. library — a place holding many كتاب.", source: "wordnet-arb-eng")

        let results = try await db.search(query: "كتاب")
        XCTAssertGreaterThanOrEqual(results.count, 2,
                                    "Both the headword and the definition-only match should be returned")
        XCTAssertEqual(results.first?.word, "كِتاب",
                       "The normalized-exact headword must rank first (the §2 word_normalized boost)")
    }

    // MARK: - Performance Tests

    /// Measures FTS5 search time on a 100,000-entry database. Target: < 16ms.
    func testSearchPerformance100K() async throws {
        try await seedEntries(count: 100_000)

        let entryCount = try await db.entryCount()
        XCTAssertEqual(entryCount, 100_000, "Database should contain 100k entries")

        // Warm up the database cache.
        _ = try await db.search(query: "word50000")

        let start = CFAbsoluteTimeGetCurrent()
        let results = try await db.search(query: "word99999")
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000 // ms

        XCTAssertFalse(results.isEmpty, "Should find results for 'word99999'")
        print("⏱ FTS5 search on 100k entries: \(String(format: "%.2f", elapsed))ms")
        XCTAssertLessThan(elapsed, 16.0, "Search must complete in under 16ms (got \(elapsed)ms)")
    }

    // MARK: - Issue #6: Preferred-dictionary search (integration)

    /// Order [B, A] on a known seed → top-N of B, then top-N of A, then a
    /// relevance tail; no duplicate IDs (§3b/§7).
    func testSearchPreferredBucketsByOrderThenTail() async throws {
        let topN = Search.preferredDictionaryTopN
        // Each source has > topN matches for the stem "term" so buckets fill
        // and a tail remains. (unicode61 splits "term_aN" into tokens "term"+"aN",
        // so the prefix query "term*" matches every row.)
        try await seedSourcedEntries(source: "srcA", words: (0..<(topN + 2)).map { "term_a\($0)" })
        try await seedSourcedEntries(source: "srcB", words: (0..<(topN + 2)).map { "term_b\($0)" })

        let results = try await db.searchPreferred(
            query: "term", order: ["srcB", "srcA"], enabledSources: ["srcA", "srcB"]
        )

        XCTAssertGreaterThanOrEqual(results.count, topN * 2, "Both buckets should fill")
        XCTAssertTrue(results.prefix(topN).allSatisfy { $0.source == "srcB" },
            "First \(topN) must be source B (first in order); got \(results.prefix(topN).map(\.source))")
        XCTAssertTrue(results.dropFirst(topN).prefix(topN).allSatisfy { $0.source == "srcA" },
            "Next \(topN) must be source A; got \(results.dropFirst(topN).prefix(topN).map(\.source))")
        let ids = results.compactMap(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Results must contain no duplicate IDs")
    }

    /// An explicit empty enabled set returns nothing (mirrors `search`).
    func testSearchPreferredEmptyEnabledReturnsEmpty() async throws {
        try await seedSourcedEntries(source: "srcA", words: ["term_a1"])
        let results = try await db.searchPreferred(query: "term", order: ["srcA"], enabledSources: [])
        XCTAssertTrue(results.isEmpty)
    }

    /// `addToHistory` records the viewed source; last-viewed source wins (§5).
    func testHistorySourceRecordedAndUpdated() async throws {
        try await db.addToHistory(word: "book", source: "wordnet")
        var history = try await db.fetchHistory()
        XCTAssertEqual(history.first(where: { $0.word == "book" })?.source, "wordnet")
        try await db.addToHistory(word: "book", source: "wordnet-arb-eng")
        history = try await db.fetchHistory()
        XCTAssertEqual(history.first(where: { $0.word == "book" })?.source, "wordnet-arb-eng",
                       "Re-viewing should update the recorded source")
    }

    /// Uses XCTest's built-in measure block for repeated performance measurement.
    func testSearchPerformanceRepeated() async throws {
        try await seedEntries(count: 100_000)

        measure {
            let expectation = self.expectation(description: "search")
            Task {
                _ = try await self.db.search(query: "word42000")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}

// MARK: - Issue #6: KeyValueStore seam + SettingsService

/// In-memory `KeyValueStore` for injecting into `SettingsService` under test.
final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Any] = [:]
    func data(forKey key: String) -> Data? { storage[key] as? Data }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
    func string(forKey key: String) -> String? { storage[key] as? String }
    func set(_ string: String?, forKey key: String) { storage[key] = string }
    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
}

final class SettingsServiceTests: XCTestCase {
    private func service() -> (SettingsService, InMemoryKeyValueStore) {
        let store = InMemoryKeyValueStore()
        return (SettingsService(store: store), store)
    }

    func testResultSortModeDefaultsToRelevance() {
        let (s, _) = service()
        XCTAssertEqual(s.resultSortMode, .relevance)
    }

    func testResultSortModeRoundTrips() {
        let (s, _) = service()
        s.resultSortMode = .preferredDictionary
        XCTAssertEqual(s.resultSortMode, .preferredDictionary)
    }

    func testDictionaryOrderRoundTrips() {
        let (s, _) = service()
        XCTAssertNil(s.dictionaryOrder)
        s.dictionaryOrder = ["b", "a", "c"]
        XCTAssertEqual(s.dictionaryOrder, ["b", "a", "c"])
        s.dictionaryOrder = nil
        XCTAssertNil(s.dictionaryOrder)
    }

    // Watchpoint 1: existing prefs still flow through the new seam.
    func testEnabledSourcesThroughSeam() {
        let (s, _) = service()
        XCTAssertNil(s.enabledSources, "nil = all enabled (first launch)")
        s.setEnabled(false, for: "x", knownSources: ["x", "y"])
        XCTAssertFalse(s.isEnabled(source: "x"))
        XCTAssertTrue(s.isEnabled(source: "y"))
    }

    func testSelectedUILanguageThroughSeam() {
        let (s, _) = service()
        XCTAssertNil(s.selectedUILanguageCode)
        s.selectedUILanguageCode = "es"
        XCTAssertEqual(s.selectedUILanguageCode, "es")
        s.selectedUILanguageCode = nil
        XCTAssertNil(s.selectedUILanguageCode)
    }

    // Migration-safety (#73): the exact UserDefaults key strings are preserved,
    // so swapping the adapter needs no data migration.
    func testUserDefaultsKeyStringsUnchanged() {
        let (s, store) = service()
        s.selectedUILanguageCode = "ru"
        s.setEnabled(false, for: "x", knownSources: ["x"])
        s.dictionaryOrder = ["x"]
        s.resultSortMode = .preferredDictionary
        XCTAssertNotNil(store.string(forKey: "ui_language"))
        XCTAssertNotNil(store.data(forKey: "enabled_sources"))
        XCTAssertNotNil(store.data(forKey: "dictionary_order"))
        XCTAssertNotNil(store.string(forKey: "result_sort_mode"))
    }
}

final class SearchAssembleTests: XCTestCase {
    private func entry(_ id: Int64, _ source: String) -> DictionaryEntry {
        DictionaryEntry(id: id, word: "w\(id)", definition: "", phonetic: "",
                        pos: "", source: source, createdAt: nil)
    }

    func testAssembleOrdersBucketsThenTail() {
        let out = Search.assemble(
            buckets: ["A": [entry(1, "A"), entry(2, "A")], "B": [entry(3, "B")]],
            tail: [entry(4, "A"), entry(5, "C")],
            order: ["B", "A"]
        )
        XCTAssertEqual(out.map(\.id), [3, 1, 2, 4, 5])
    }

    func testAssembleDedupsById() {
        let dup = entry(1, "A")
        let out = Search.assemble(buckets: ["A": [dup]], tail: [dup, entry(2, "B")], order: ["A"])
        XCTAssertEqual(out.map(\.id), [1, 2], "An ID already bucketed must not repeat in the tail")
    }

    func testAssembleSkipsMissingOrderKeys() {
        let out = Search.assemble(buckets: ["A": [entry(1, "A")]], tail: [], order: ["X", "A"])
        XCTAssertEqual(out.map(\.id), [1])
    }

    func testPreferredDictionaryTopNIsFour() {
        XCTAssertEqual(Search.preferredDictionaryTopN, 4)
    }
}

// MARK: - Issue #12: ReviewRequestService heuristic

/// Verifies the smart-trigger logic without invoking the actual review prompt
/// (the prompt lives in the view layer; the service only decides whether).
final class ReviewRequestServiceTests: XCTestCase {
    private func make(args: [String] = []) -> ReviewRequestService {
        ReviewRequestService(store: InMemoryKeyValueStore(), launchArguments: args)
    }
    private func searches(_ n: Int, on s: ReviewRequestService) {
        for _ in 0..<n { s.recordDefinitionView() }
    }

    func testDoesNotFireOnFirstLaunch() {
        XCTAssertFalse(make().shouldRequestReview())
    }

    func testDoesNotFireBelowForegroundThreshold() {
        let s = make()
        searches(5, on: s)
        s.recordForeground(duration: 29)
        XCTAssertFalse(s.shouldRequestReview(), "29s < 30s threshold")
    }

    func testDoesNotFireBelowSearchThreshold() {
        let s = make()
        searches(4, on: s)
        s.recordForeground(duration: 30)
        XCTAssertFalse(s.shouldRequestReview(), "4 < 5 searches")
    }

    func testFiresAtFirstThresholdOnceSearchesReached() {
        let s = make()
        searches(5, on: s)
        s.recordForeground(duration: 30)
        XCTAssertTrue(s.shouldRequestReview())
    }

    func testDoesNotFireTwiceInSameSession() {
        let s = make()
        searches(5, on: s)
        s.recordForeground(duration: 30)
        XCTAssertTrue(s.shouldRequestReview())
        s.markPromptFired()
        XCTAssertFalse(s.shouldRequestReview(), "once per session")
        s.recordForeground(duration: 3600)   // even past the higher thresholds
        XCTAssertFalse(s.shouldRequestReview())
    }

    func testLaunchArgGateSuppressesPrompt() {
        let s = make(args: ["-disableReviewPrompt"])
        searches(10, on: s)
        s.recordForeground(duration: 7200)
        XCTAssertFalse(s.shouldRequestReview())
    }

    func testCountersPersistAcrossInstances() {
        let store = InMemoryKeyValueStore()
        let s1 = ReviewRequestService(store: store, launchArguments: [])
        searches(5, on: s1)
        s1.recordForeground(duration: 30)
        // A fresh instance (= relaunch) on the same store sees persisted counters.
        let s2 = ReviewRequestService(store: store, launchArguments: [])
        XCTAssertEqual(s2.successfulSearchCount, 5)
        XCTAssertEqual(s2.cumulativeForegroundSeconds, 30, accuracy: 0.001)
        XCTAssertTrue(s2.shouldRequestReview(),
                      "promptFiredThisSession is per-session, so a fresh session at threshold fires")
    }

    // Interpretation B (PM Decisions: once per session; Apple's annual cap for
    // long-term): up to three attempts across the install at escalating
    // thresholds, latched after the third.
    func testSecondAttemptFiresInLaterSessionAtHigherThreshold() {
        let store = InMemoryKeyValueStore()
        searches(5, on: ReviewRequestService(store: store, launchArguments: []))
        let s1 = ReviewRequestService(store: store, launchArguments: [])
        s1.recordForeground(duration: 30)
        XCTAssertTrue(s1.shouldRequestReview())
        s1.markPromptFired()
        let s2 = ReviewRequestService(store: store, launchArguments: [])
        s2.recordForeground(duration: 30)   // cumulative 60
        XCTAssertFalse(s2.shouldRequestReview(), "attempt 1 already consumed; 60s < 600s")
        s2.recordForeground(duration: 600)  // cumulative 660 ≥ 600
        XCTAssertTrue(s2.shouldRequestReview(), "attempt 2 at the 10-minute threshold")
    }

    func testLatchesAfterThreeAttempts() {
        let store = InMemoryKeyValueStore()
        searches(5, on: ReviewRequestService(store: store, launchArguments: []))
        for threshold in ReviewRequestService.foregroundThresholds {
            let s = ReviewRequestService(store: store, launchArguments: [])
            s.recordForeground(duration: threshold)
            XCTAssertTrue(s.shouldRequestReview())
            s.markPromptFired()
        }
        let s4 = ReviewRequestService(store: store, launchArguments: [])
        s4.recordForeground(duration: 99999)
        XCTAssertFalse(s4.shouldRequestReview(), "once-per-install latch after the 3-attempt schedule")
    }

    func testResetClearsPersistedState() {
        let store = InMemoryKeyValueStore()
        let s = ReviewRequestService(store: store, launchArguments: [])
        searches(5, on: s)
        s.recordForeground(duration: 30)
        s.resetPersistedState()
        XCTAssertEqual(s.successfulSearchCount, 0)
        XCTAssertEqual(s.cumulativeForegroundSeconds, 0, accuracy: 0.001)
        XCTAssertFalse(s.shouldRequestReview())
    }

    // Regression (CodeRabbit, PR #80): the in-progress active interval must count
    // toward the threshold even while the app stays active — otherwise a user who
    // never backgrounds the app never passes the time gate.
    func testInProgressForegroundCountsWithoutBackgrounding() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let s = ReviewRequestService(store: InMemoryKeyValueStore(),
                                     launchArguments: [], now: { clock })
        searches(5, on: s)
        s.foregroundDidBecomeActive()
        XCTAssertFalse(s.shouldRequestReview(), "0s elapsed")
        clock = clock.addingTimeInterval(30)   // 30s pass, still active (no background)
        XCTAssertTrue(s.shouldRequestReview(),
                      "in-progress 30s must count even without resigning active")
    }

    func testResignActiveBanksTheInterval() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let store = InMemoryKeyValueStore()
        let s = ReviewRequestService(store: store, launchArguments: [], now: { clock })
        searches(5, on: s)
        s.foregroundDidBecomeActive()
        clock = clock.addingTimeInterval(30)
        s.foregroundDidResignActive()          // banks 30s
        XCTAssertEqual(s.cumulativeForegroundSeconds, 30, accuracy: 0.001,
                       "banked time survives once the interval ends")
        XCTAssertTrue(s.shouldRequestReview())
    }

    // Regression (PR #80 manual smoke): `-resetData` calls `resetPersistedState()`
    // during app init — AFTER the app root's `.task` started the foreground
    // interval. Reset must clear persisted counters WITHOUT nuking the running
    // in-memory interval, else foreground time never accrues (scene stays active,
    // no later edge restarts it) and the prompt never fires.
    func testResetPersistedStateKeepsRunningForegroundInterval() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let s = ReviewRequestService(store: InMemoryKeyValueStore(),
                                     launchArguments: [], now: { clock })
        s.foregroundDidBecomeActive()          // app root .task started the interval
        s.resetPersistedState()                // -resetData during init
        searches(5, on: s)
        clock = clock.addingTimeInterval(30)   // 30s of foreground elapse
        XCTAssertTrue(s.shouldRequestReview(),
                      "foreground must keep accruing after a -resetData reset")
    }
}
