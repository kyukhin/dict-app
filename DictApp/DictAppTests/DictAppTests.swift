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
                        INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
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
                        INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
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
        try await db.addToHistory(word: "apple")
        try await db.addToHistory(word: "banana")
        try await db.addToHistory(word: "apple") // duplicate

        let history = try await db.fetchHistory()
        let appleCount = history.filter { $0.word == "apple" }.count
        XCTAssertEqual(appleCount, 1, "History must not contain duplicate words")

        let count = try await db.historyCount()
        XCTAssertEqual(count, 2, "Total history count should be 2 (apple + banana)")
    }

    /// Verifies that re-adding a word to history updates its timestamp (most recent first).
    func testHistoryOrderUpdatedOnRevisit() async throws {
        try await db.addToHistory(word: "alpha")
        try await db.addToHistory(word: "beta")
        // Re-add alpha so it becomes the most recent.
        try await db.addToHistory(word: "alpha")

        let history = try await db.fetchHistory()
        XCTAssertEqual(history.first?.word, "alpha", "Most recently added word should be first")
    }

    /// Verifies clear history works.
    func testClearHistory() async throws {
        try await db.addToHistory(word: "test")
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

    // MARK: - Issue #25: Build version information
    //
    // `AppVersion` is a pure value type with no UIKit/SwiftUI dependencies,
    // so we exercise it by injecting a controlled `Bundle` and an explicit
    // `ReleaseChannel` instead of relying on runtime detection.

    /// `displayString` must drop the `-unreleased` suffix only for the
    /// `.appStore` channel; every other channel must include it.
    func testAppVersionDisplayStringSuffixByChannel() throws {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "2"
        ]

        // App Store is the *only* channel that hides the suffix.
        let appStore = AppVersion(infoDictionary: info, channel: .appStore)
        XCTAssertEqual(appStore.displayString, "1.1.0",
                       "App Store builds must display the bare marketing version")

        // All other channels must include the suffix — pin every one of
        // them so a future case added without an `isUnreleased` update is
        // caught here.
        let unreleased: [ReleaseChannel] = [.debug, .testFlight, .development]
        for channel in unreleased {
            let av = AppVersion(infoDictionary: info, channel: channel)
            XCTAssertEqual(
                av.displayString, "1.1.0-unreleased",
                "Channel \(channel) must display with the '-unreleased' suffix"
            )
        }
    }

    /// `verboseString` must always include the build number in
    /// parentheses, e.g. `"1.1.0-unreleased (build 2)"`.
    func testAppVersionVerboseStringIncludesBuild() throws {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "2"
        ]

        let unreleased = AppVersion(infoDictionary: info, channel: .debug)
        XCTAssertEqual(
            unreleased.verboseString, "1.1.0-unreleased (build 2)",
            "Non-App-Store verboseString must include the suffix AND the build number"
        )

        let released = AppVersion(infoDictionary: info, channel: .appStore)
        XCTAssertEqual(
            released.verboseString, "1.1.0 (build 2)",
            "App Store verboseString must drop the suffix but keep the build number"
        )

        // Multi-digit build — guard against any "single-character only"
        // formatting bug.
        let bigBuild: [String: Any] = [
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "1024"
        ]
        XCTAssertEqual(
            AppVersion(infoDictionary: bigBuild, channel: .appStore).verboseString,
            "2.0.0 (build 1024)"
        )
    }

    /// Missing `CFBundleShortVersionString` and `CFBundleVersion`
    /// fall back to `"unknown"` and `"0"` respectively rather than
    /// crashing or returning empty strings.
    func testAppVersionFallsBackWhenInfoPlistMissing() throws {
        // Case 1: infoDictionary is nil (no Info.plist at all).
        let nilVersion = AppVersion(infoDictionary: nil, channel: .appStore)
        XCTAssertEqual(nilVersion.marketingVersion, "unknown",
                       "Missing CFBundleShortVersionString must fall back to 'unknown'")
        XCTAssertEqual(nilVersion.buildNumber, "0",
                       "Missing CFBundleVersion must fall back to '0'")
        XCTAssertEqual(nilVersion.displayString, "unknown",
                       "displayString on appStore channel must still surface the fallback marketing string")
        XCTAssertEqual(nilVersion.verboseString, "unknown (build 0)",
                       "verboseString must compose cleanly with the fallback values")

        // Case 2: infoDictionary exists but the keys we care about are absent.
        let emptyVersion = AppVersion(infoDictionary: [:], channel: .debug)
        XCTAssertEqual(emptyVersion.marketingVersion, "unknown")
        XCTAssertEqual(emptyVersion.buildNumber, "0")

        // Case 3: keys exist but the values aren't strings (wrong types in
        // a malformed plist). The lookup is `info?[...] as? String`, so we
        // expect the fallback to kick in rather than a runtime crash.
        let wrongType: [String: Any] = [
            "CFBundleShortVersionString": 1.0,
            "CFBundleVersion": 42
        ]
        let wrongTypeVersion = AppVersion(infoDictionary: wrongType, channel: .appStore)
        XCTAssertEqual(wrongTypeVersion.marketingVersion, "unknown",
                       "Non-string CFBundleShortVersionString must fall back to 'unknown', not crash")
        XCTAssertEqual(wrongTypeVersion.buildNumber, "0",
                       "Non-string CFBundleVersion must fall back to '0', not crash")
    }

    /// `AppVersion.current.marketingVersion` matches the live
    /// `CFBundleShortVersionString` in `Bundle.main.infoDictionary`,
    /// guarding against future refactors that drop the lookup.
    func testAppVersionCurrentMatchesBundle() throws {
        // The host app bundle holds the real marketing version. The unit
        // test target is hosted by the app, so resolve robustly.
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

        // AppVersion.current reads `Bundle.main`, which for the unit-test
        // process is the host app (DictApp.app) — the same bundle whose
        // CFBundleShortVersionString we just read.
        let current = AppVersion(bundle: hostBundle)
        XCTAssertEqual(current.marketingVersion, bundleVersion,
                       "AppVersion.marketingVersion must mirror the bundle's CFBundleShortVersionString")
        XCTAssertEqual(current.buildNumber, bundleBuild,
                       "AppVersion.buildNumber must mirror the bundle's CFBundleVersion")

        // The shared `AppVersion.current` instance must agree with a freshly
        // constructed one against the same bundle — proves the singleton
        // hasn't been replaced with a stale snapshot.
        XCTAssertEqual(AppVersion.current.marketingVersion, current.marketingVersion,
                       "AppVersion.current must equal a fresh AppVersion(bundle:) reading the same plist")
        XCTAssertEqual(AppVersion.current.buildNumber, current.buildNumber)
    }

    /// `ReleaseChannel.isUnreleased` is true for every channel except
    /// `.appStore` — pins the display rule the rest of the system
    /// depends on.
    func testReleaseChannelIsUnreleasedRule() throws {
        XCTAssertTrue(ReleaseChannel.debug.isUnreleased,
                      "Debug channel must be marked unreleased")
        XCTAssertTrue(ReleaseChannel.testFlight.isUnreleased,
                      "TestFlight channel must be marked unreleased")
        XCTAssertTrue(ReleaseChannel.development.isUnreleased,
                      "Development/Ad-Hoc/Enterprise channel must be marked unreleased")
        XCTAssertFalse(ReleaseChannel.appStore.isUnreleased,
                       "App Store channel is the *only* released channel")
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
