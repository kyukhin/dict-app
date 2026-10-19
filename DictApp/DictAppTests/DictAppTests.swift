// DictAppTests.swift
// Unit tests and performance tests for the dictionary app.

import XCTest
@testable import DictApp
import GRDB
import MessageUI
import Combine

final class DictAppTests: XCTestCase {

    private var db: DatabaseService!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        await Self.waitForHostAppLaunch()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        db = DatabaseService.shared
        let path = tempDir.appendingPathComponent("test.sqlite").path
        try await db.setup(path: path)
    }

    override func tearDown() async throws {
        // Issue #111: never leak a background unpack (it holds the
        // single-flight slot and writes into `tempDir`) or a test seam into
        // the next test.
        await DatabaseService.shared.waitForBundledUnpack()
        DatabaseService.unpackFailureAfterInsert = nil
        Self.setUnpackSourceDelay(nil)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Test host launch

    @MainActor private static var hostLaunchSettled = false

    /// The test host is the real app: its launch-time `initializeDatabase`
    /// (setup, prepareBundledSeed, the test hooks) runs on
    /// `DatabaseService.shared` while the first tests run, and its later steps
    /// re-read the `dbPool` that each `setUp` swaps in, so they can write into
    /// (and lock) a test's DB. Since Issue #111 the host then unpacks the
    /// bundled dictionaries in the background (on the pool it started with)
    /// and holds the single-flight unpack slot until done. Wait once per run,
    /// before the first swap, until the host shows its tab bar (set only after
    /// `isReady`) and its unpack is idle. Every test class that swaps the
    /// shared database calls this first, so test order does not matter.
    @MainActor
    static func waitForHostAppLaunch(timeout: TimeInterval = 120) async {
        guard !hostLaunchSettled else { return }
        hostLaunchSettled = true
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hostShowsTabBar() && DictionaryUnpackStatus.shared.phase == .idle { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        print("DictAppTests: the host app was not ready and idle within \(Int(timeout)) s; continuing")
    }

    @MainActor
    private static func hostShowsTabBar() -> Bool {
        func controllerHasTabBar(_ vc: UIViewController?) -> Bool {
            guard let vc else { return false }
            if vc is UITabBarController { return true }
            return vc.children.contains { controllerHasTabBar($0) } || controllerHasTabBar(vc.presentedViewController)
        }
        func viewHasTabBar(_ view: UIView) -> Bool {
            view is UITabBar || view.subviews.contains { viewHasTabBar($0) }
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { controllerHasTabBar($0.rootViewController) || viewHasTabBar($0) }
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
        // In-memory prefs: since #105 a successful import writes the enabled
        // set / order, which must not leak into the host app's UserDefaults.
        let vm = englishImportViewModel()
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "test_import_fixture", withExtension: "json"),
            "Bundled JSON fixture must exist"
        )

        vm.handleImport(result: .success([url]))

        // handleImport spawns an async Task; poll for completion (importResult
        // becomes non-nil and isImporting flips back to false).
        try await waitForImportToFinish(vm: vm)

        let message = try XCTUnwrap(vm.importResult)
        XCTAssertEqual(message, "Imported 10 entries from test_import_fixture",
                       "Success message must read 'Imported N entries from <file>'")

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
        let vm = englishImportViewModel()
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "test_import_fixture", withExtension: "sqlite"),
            "Bundled SQLite fixture must exist"
        )

        vm.handleImport(result: .success([url]))
        try await waitForImportToFinish(vm: vm)

        let message = try XCTUnwrap(vm.importResult)
        XCTAssertEqual(message, "Imported 10 entries from test_import_fixture",
                       "Success message must read 'Imported N entries from <file>'")

        let results = try await db.search(query: "zarboom")
        XCTAssertGreaterThan(results.count, 0,
                             "Fixture entry 'zarboom' must be searchable after import")
    }

    /// An import view model on in-memory prefs whose in-app language is pinned
    /// to English. Since #88 the result message follows the in-app language,
    /// so `LocalizationManager.shared` (which reads the host's persisted
    /// choice) would make the expected text depend on earlier runs.
    @MainActor
    private func englishImportViewModel() -> ManageDictionariesViewModel {
        let settings = SettingsService(store: InMemoryKeyValueStore())
        settings.selectedUILanguageCode = "en"
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        XCTAssertEqual(localization.currentLanguage.code, "en", "precondition: in-app language is English")
        return ManageDictionariesViewModel(settingsService: settings, localization: localization)
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

    /// `DictionaryEntry.sourceLabel` must return the terse "En–Es · FD"
    /// badge (direction + provider, Issue #87) for the new source
    /// identifier, not the raw capitalised fallback (e.g. "Freedict-Eng-Spa").
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
            entry.sourceLabel, "En\u{2013}Es \u{00B7} FD",
            "freedict-eng-spa must render as the terse 'En–Es · FD' badge, not the .capitalized fallback"
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

        // License text is a hard contract — the bundle ships CC BY-SA data
        // (WikDict, #106; it was mislabelled GPL before #87) and must surface
        // the license text in-app (DictionaryDetailView).
        XCTAssertFalse(license.isEmpty,
                       "dict_metadata.license must contain the license text")
        XCTAssertTrue(license.contains("Attribution-ShareAlike 3.0"),
                      "License text must name CC BY-SA 3.0 (#106); got first 80 chars: \(license.prefix(80))")

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

    /// `DictionaryEntry.sourceLabel` must return the terse "Es–En · WN"
    /// badge (direction + provider, Issue #87) for the Spanish WordNet
    /// source identifier, not the raw capitalised fallback.
    func testSpanishWordNetSourceLabelIsTerseEsEn() throws {
        let entry = DictionaryEntry(
            id: 1, word: "casa",
            definition: "**noun**\n1. house, home — a dwelling…",
            phonetic: "", pos: "noun",
            source: Self.spanishWordNetSource, createdAt: nil
        )
        XCTAssertEqual(
            entry.sourceLabel, "Es\u{2013}En \u{00B7} WN",
            "wordnet-spa-eng must render as the terse 'Es–En · WN' badge, not the .capitalized fallback"
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
            "En\u{2013}Es \u{00B7} FD",
            "The #24 eng-spa source must keep its 'En–Es · FD' badge (opposite direction)"
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
    /// `decomposeGreekDefinition` stores the definition through
    /// `decomposeGreek`, as the build does for the four Greek sources (#87).
    private func insertNormalizedEntry(word: String, normalized: String,
                                       definition: String, source: String,
                                       decomposeGreekDefinition: Bool = false) async throws {
        let path = tempDir.appendingPathComponent("test.sqlite").path
        let pool = try DatabasePool(path: path)
        let stored = decomposeGreekDefinition ? Self.decomposeGreek(definition) : definition
        try await pool.writeWithoutTransaction { conn in
            try conn.execute(
                sql: """
                    INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                    VALUES (?, ?, ?, '', 'noun', ?)
                    """,
                arguments: [word, normalized, stored, source])
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
            query: "term", groups: [["srcB"], ["srcA"]], enabledSources: ["srcA", "srcB"]
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
        let results = try await db.searchPreferred(query: "term", groups: [["srcA"]], enabledSources: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Issue #92: Language-pair grouping (DatabaseService integration)
    //
    // `searchPreferred(query:groups:…)` runs ONE capped query per pair group.
    // The seeds below exploit the bucket's ORDER BY — `(exact) DESC,
    // (word_normalized LIKE 'term%') DESC, rank` — to tell "one merged bucket"
    // apart from "one bucket per member": a headword like "x term_a0" still
    // FTS-matches `term*` (unicode61 tokenises it as "x" + "term" + "a0", and
    // the definition text contains "term" too) but fails the LIKE prefix
    // boost, so it must sort BELOW any sibling's "term_bN" rows inside a
    // shared bucket, regardless of member order in the group.

    /// Inserts a `dict_metadata` row the way `build_seed.py` does for bundled
    /// sources (custom imports never get one).
    private func insertMetadata(source: String, displayName: String,
                                license: String, version: String) async throws {
        let path = tempDir.appendingPathComponent("test.sqlite").path
        let pool = try DatabasePool(path: path)
        try await pool.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO dict_metadata(source, display_name, license, version) VALUES (?, ?, ?, ?)",
                arguments: [source, displayName, license, version]
            )
        }
    }

    /// groups `[[srcA, srcB], [srcC]]`, each source with > topN matches →
    /// first `topN` rows ⊆ {A, B} ranked by the shared ORDER BY (not A-then-B),
    /// next `topN` all C, no duplicate IDs.
    func testSearchPreferredMergesPairMembersIntoOneBucket() async throws {
        let topN = Search.preferredDictionaryTopN
        // A is listed FIRST in its group but its rows miss the prefix boost;
        // B's rows satisfy it. Per-source buckets would put A's rows first.
        try await seedSourcedEntries(source: "srcA", words: (0..<(topN + 2)).map { "x term_a\($0)" })
        try await seedSourcedEntries(source: "srcB", words: (0..<(topN + 2)).map { "term_b\($0)" })
        try await seedSourcedEntries(source: "srcC", words: (0..<(topN + 2)).map { "term_c\($0)" })

        let results = try await db.searchPreferred(
            query: "term", groups: [["srcA", "srcB"], ["srcC"]],
            enabledSources: ["srcA", "srcB", "srcC"]
        )

        XCTAssertEqual(results.count, 3 * (topN + 2),
                       "every seeded row matches 'term*' and fits under the default limit")

        let pairBucket = results.prefix(topN).map(\.source)
        XCTAssertTrue(pairBucket.allSatisfy { ["srcA", "srcB"].contains($0) },
                      "first \(topN) rows must come from the pair group; got \(pairBucket)")
        XCTAssertEqual(pairBucket, Array(repeating: "srcB", count: topN),
                       "the pair's directions share ONE ORDER BY: B's prefix matches outrank A's "
                       + "non-prefix matches even though A is listed first in the group; got \(pairBucket)")

        let secondBucket = results.dropFirst(topN).prefix(topN).map(\.source)
        XCTAssertEqual(secondBucket, Array(repeating: "srcC", count: topN),
                       "the next \(topN) rows must be the second group's bucket; got \(secondBucket)")

        // A got no bucket slot, so all of its rows surface via the relevance tail only.
        XCTAssertEqual(results.filter { $0.source == "srcA" }.count, topN + 2,
                       "A's rows are still returned (tail), not dropped")
        XCTAssertNil(results.prefix(2 * topN).first { $0.source == "srcA" },
                     "A must not appear before both buckets are exhausted")

        let ids = results.compactMap(\.id)
        XCTAssertEqual(ids.count, results.count, "every row carries an id")
        XCTAssertEqual(ids.count, Set(ids).count, "no duplicate IDs across buckets and tail")
    }

    /// A custom ID equal to a pair's joined members must not overwrite that
    /// pair's bucket (PR #100 review: keys were `members.joined("|")`).
    func testSearchPreferredBucketKeysDoNotCollide() async throws {
        let topN = Search.preferredDictionaryTopN
        try await seedSourcedEntries(source: "srcA", words: (0..<(topN + 2)).map { "term_a\($0)" })
        try await seedSourcedEntries(source: "srcB", words: (0..<(topN + 2)).map { "term_b\($0)" })
        try await seedSourcedEntries(source: "srcA|srcB", words: (0..<(topN + 2)).map { "term_c\($0)" })

        let results = try await db.searchPreferred(
            query: "term", groups: [["srcA", "srcB"], ["srcA|srcB"]],
            enabledSources: ["srcA", "srcB", "srcA|srcB"]
        )

        let first = results.prefix(topN).map(\.source)
        XCTAssertTrue(first.allSatisfy { ["srcA", "srcB"].contains($0) },
                      "the pair's bucket must lead; got \(first)")
        let second = results.dropFirst(topN).prefix(topN).map(\.source)
        XCTAssertEqual(second, Array(repeating: "srcA|srcB", count: topN),
                       "the custom group keeps its own bucket; got \(second)")
    }

    /// A two-source pair yields at most `topN` bucket rows, never `2·topN`.
    func testSearchPreferredTopNIsPerPairNotPerSource() async throws {
        let topN = Search.preferredDictionaryTopN
        try await seedSourcedEntries(source: "srcA", words: (0..<(topN + 2)).map { "term_a\($0)" })
        try await seedSourcedEntries(source: "srcB", words: (0..<(topN + 2)).map { "term_b\($0)" })

        // `limit == topN` leaves no room for the relevance tail (`remaining`
        // is 0), so every returned row is a bucket row.
        let paired = try await db.searchPreferred(
            query: "term", groups: [["srcA", "srcB"]], enabledSources: ["srcA", "srcB"],
            topN: topN, limit: topN
        )
        XCTAssertEqual(paired.count, topN,
                       "one bucket per PAIR: a two-member group is capped at topN, not 2·topN; got \(paired.map(\.source))")
        XCTAssertTrue(paired.allSatisfy { ["srcA", "srcB"].contains($0.source) })
        XCTAssertEqual(Set(paired.compactMap(\.id)).count, topN, "no duplicates inside the bucket")

        // Control: the same two sources as separate groups DO get a bucket each.
        let separate = try await db.searchPreferred(
            query: "term", groups: [["srcA"], ["srcB"]], enabledSources: ["srcA", "srcB"],
            topN: topN, limit: 2 * topN
        )
        XCTAssertEqual(separate.count, 2 * topN)
        XCTAssertEqual(separate.prefix(topN).map(\.source), Array(repeating: "srcA", count: topN))
        XCTAssertEqual(separate.dropFirst(topN).map(\.source), Array(repeating: "srcB", count: topN))

        // A custom topN is honoured per pair as well.
        let small = try await db.searchPreferred(
            query: "term", groups: [["srcA", "srcB"]], enabledSources: ["srcA", "srcB"],
            topN: 1, limit: 1
        )
        XCTAssertEqual(small.count, 1)
    }

    /// group `[srcA, srcB]`, enabled `{srcB}` → bucket holds only B.
    func testSearchPreferredSkipsDisabledMembersWithinGroup() async throws {
        let topN = Search.preferredDictionaryTopN
        // Give the DISABLED member the better-ranked rows (prefix matches): if
        // it were not filtered out of the bucket, A would win every slot.
        try await seedSourcedEntries(source: "srcA", words: (0..<(topN + 2)).map { "term_a\($0)" })
        try await seedSourcedEntries(source: "srcB", words: (0..<(topN + 2)).map { "x term_b\($0)" })

        let results = try await db.searchPreferred(
            query: "term", groups: [["srcA", "srcB"]], enabledSources: ["srcB"],
            topN: topN, limit: topN
        )
        XCTAssertEqual(results.count, topN, "the group still gets its bucket from the enabled member")
        XCTAssertEqual(results.map(\.source), Array(repeating: "srcB", count: topN),
                       "a disabled member must contribute nothing to its pair's bucket; got \(results.map(\.source))")

        // With a tail allowed, the disabled member must stay absent there too.
        let withTail = try await db.searchPreferred(
            query: "term", groups: [["srcA", "srcB"]], enabledSources: ["srcB"]
        )
        XCTAssertEqual(withTail.count, topN + 2)
        XCTAssertTrue(withTail.allSatisfy { $0.source == "srcB" })

        // A group whose members are ALL disabled yields no bucket; the
        // remaining group's bucket is unaffected.
        let groupOff = try await db.searchPreferred(
            query: "term", groups: [["srcA"], ["srcB"]], enabledSources: ["srcB"],
            topN: topN, limit: topN
        )
        XCTAssertEqual(groupOff.map(\.source), Array(repeating: "srcB", count: topN))

        // Enabled sources absent from `groups` (e.g. a fresh import before
        // reconciliation) get no bucket but still surface through the tail.
        try await seedSourcedEntries(source: "srcNew", words: ["term_new"])
        let unlisted = try await db.searchPreferred(
            query: "term", groups: [["srcB"]], enabledSources: ["srcB", "srcNew"], topN: 1
        )
        XCTAssertEqual(unlisted.first?.source, "srcB", "bucket first")
        XCTAssertTrue(unlisted.contains { $0.source == "srcNew" }, "unlisted enabled source reaches the tail")
    }

    /// Source with a metadata row → `license` / `version` populated;
    /// custom source (no metadata row) → `""`.
    func testFetchSourceStatsCarriesLicenseAndVersion() async throws {
        // Distinct counts (3 > 2 > 1) so the count-desc order is deterministic.
        try await seedSourcedEntries(source: "wordnet", words: ["alpha", "beta", "delta"])
        try await seedSourcedEntries(source: "freedict-eng-spa", words: ["gato", "perro"])
        try await seedSourcedEntries(source: "test_import_fixture", words: ["gamma"])
        try await insertMetadata(source: "wordnet", displayName: "WordNet",
                                 license: "WordNet 3.0 License", version: "3.0")
        try await insertMetadata(source: "freedict-eng-spa", displayName: "English – Spanish (FreeDict)",
                                 license: "GPL", version: "2023.05.23")

        let stats = try await db.fetchSourceStats()
        XCTAssertEqual(stats.map(\.source), ["wordnet", "freedict-eng-spa", "test_import_fixture"],
                       "count-desc order is unchanged by the extra columns")
        let bySource = Dictionary(uniqueKeysWithValues: stats.map { ($0.source, $0) })

        let wordnet = try XCTUnwrap(bySource["wordnet"])
        XCTAssertEqual(wordnet.displayName, "WordNet")
        XCTAssertEqual(wordnet.license, "WordNet 3.0 License")
        XCTAssertEqual(wordnet.version, "3.0")
        XCTAssertEqual(wordnet.count, 3)
        XCTAssertEqual(wordnet.provider, "wordnet")
        XCTAssertNil(wordnet.direction, "monolingual WordNet has no direction")

        let freedict = try XCTUnwrap(bySource["freedict-eng-spa"])
        XCTAssertEqual(freedict.license, "GPL")
        XCTAssertEqual(freedict.version, "2023.05.23")
        XCTAssertEqual(freedict.provider, "freedict")
        XCTAssertEqual(freedict.direction?.from, "eng")
        XCTAssertEqual(freedict.direction?.to, "spa")

        let custom = try XCTUnwrap(bySource["test_import_fixture"])
        XCTAssertEqual(custom.displayName, "test_import_fixture",
                       "no metadata row → COALESCE falls back to the source ID")
        XCTAssertEqual(custom.license, "", "no metadata row → empty, never nil or a crash")
        XCTAssertEqual(custom.version, "")
        XCTAssertEqual(custom.count, 1)
        XCTAssertEqual(custom.provider, "test_import_fixture")
        XCTAssertNil(custom.direction)
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
/// Also a write spy (Issue #92): `writeLog` records every `set` / `remove` by
/// key so tests can prove `normalizeDictionaryPreferences` does not churn the
/// store, and `keys` lets them assert no new preference key ever appears.
final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Any] = [:]
    private(set) var writeLog: [String] = []
    var keys: Set<String> { Set(storage.keys) }
    func data(forKey key: String) -> Data? { storage[key] as? Data }
    func set(_ data: Data?, forKey key: String) { storage[key] = data; writeLog.append(key) }
    func string(forKey key: String) -> String? { storage[key] as? String }
    func set(_ string: String?, forKey key: String) { storage[key] = string; writeLog.append(key) }
    func removeObject(forKey key: String) { storage.removeValue(forKey: key); writeLog.append(key) }
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
    // so swapping the adapter needs no data migration. Issue #92 extends this:
    // the pair layer writes through the SAME two dictionary keys — pair keys
    // are runtime-only and never persisted — so no new key may appear.
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

        let allKeys: Set<String> = ["ui_language", "enabled_sources", "dictionary_order", "result_sort_mode"]
        XCTAssertEqual(store.keys, allKeys)

        // Issue #92: pair-level writes and normalisation reuse the same keys.
        let known = ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "x"]
        s.setEnabled(false, forSources: ["freedict-eng-spa", "wordnet-spa-eng"], knownSources: Set(known))
        s.dictionaryOrder = ["wordnet", "freedict-eng-spa", "x", "wordnet-spa-eng"]
        s.normalizeDictionaryPreferences(knownSources: known)
        XCTAssertEqual(store.keys, allKeys, "no new preference key after the #92 pair layer ran")
        XCTAssertTrue(store.writeLog.allSatisfy(allKeys.contains),
                      "every write went to a pre-existing key; got \(store.writeLog)")
        // …and the stored shapes are unchanged: a JSON array of source IDs.
        let enabled = try? JSONDecoder().decode([String].self, from: store.data(forKey: "enabled_sources") ?? Data())
        // `x` was disabled from a materialised {x} above, so the set is `{}`
        // and stays `{}` (normalisation never switches anything on).
        XCTAssertEqual(enabled, [])
        let order = try? JSONDecoder().decode([String].self, from: store.data(forKey: "dictionary_order") ?? Data())
        XCTAssertEqual(order, ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "x"],
                       "order is persisted as source IDs, grouped — never as pair keys")
    }

    // MARK: - Issue #92: Language-pair grouping (SettingsService)

    /// `setEnabled(_:forSources:knownSources:)` materialises from `knownSources`
    /// and removes / adds both IDs in one write.
    func testSetEnabledForSourcesWritesAllMembers() {
        let (s, store) = service()
        let known: Set<String> = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng"]
        XCTAssertNil(s.enabledSources, "precondition: nothing stored yet (all enabled)")

        // Disabling a pair materialises the set from `knownSources` minus BOTH
        // members, in a single write.
        s.setEnabled(false, forSources: ["freedict-eng-spa", "wordnet-spa-eng"], knownSources: known)
        XCTAssertEqual(s.enabledSources, ["wordnet", "openrussian"])
        XCTAssertFalse(s.isEnabled(source: "freedict-eng-spa"))
        XCTAssertFalse(s.isEnabled(source: "wordnet-spa-eng"))
        XCTAssertTrue(s.isEnabled(source: "wordnet"))
        XCTAssertTrue(s.isEnabled(source: "openrussian"))
        XCTAssertEqual(store.writeLog, ["enabled_sources"], "both members removed in ONE write")

        // Re-enabling adds both back; the other sources are untouched.
        s.setEnabled(true, forSources: ["freedict-eng-spa", "wordnet-spa-eng"], knownSources: known)
        XCTAssertEqual(s.enabledSources, known)
        XCTAssertEqual(store.writeLog, ["enabled_sources", "enabled_sources"])

        // An ID outside `knownSources` (e.g. a freshly-imported dictionary) is
        // stored verbatim, nothing else is invented.
        s.setEnabled(true, forSources: ["my_import"], knownSources: known)
        XCTAssertTrue(s.isEnabled(source: "my_import"))
        XCTAssertEqual(s.enabledSources, known.union(["my_import"]))

        // Disabling an already-disabled pair is stable (set semantics).
        s.setEnabled(false, forSources: ["freedict-eng-spa", "wordnet-spa-eng"], knownSources: known)
        s.setEnabled(false, forSources: ["freedict-eng-spa", "wordnet-spa-eng"], knownSources: known)
        XCTAssertEqual(s.enabledSources, ["wordnet", "openrussian", "my_import"])

        // An empty member list leaves the set as it is.
        s.setEnabled(false, forSources: [], knownSources: known)
        XCTAssertEqual(s.enabledSources, ["wordnet", "openrussian", "my_import"])

        // The single-source variant delegates to the same code path.
        s.setEnabled(false, for: "wordnet", knownSources: known)
        XCTAssertEqual(s.enabledSources, ["openrussian", "my_import"])

        // Once a stored set exists, `knownSources` is no longer consulted.
        s.setEnabled(true, forSources: ["wordnet"], knownSources: ["wordnet", "ghost"])
        XCTAssertEqual(s.enabledSources, ["openrussian", "my_import", "wordnet"])
        XCTAssertFalse(s.isEnabled(source: "ghost"))
    }

    /// nil/nil → store untouched; partial pair → `enabled_sources` rewritten;
    /// already-grouped input → no write (spy on the store).
    func testNormalizeWritesOnlyWhenChanged() {
        let known = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"]

        // 1) Fresh install: nil / nil → no-op, not a single write.
        do {
            let (s, store) = service()
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertNil(s.enabledSources)
            XCTAssertNil(s.dictionaryOrder)
            XCTAssertEqual(store.writeLog, [], "nil/nil must not touch the store")
            XCTAssertEqual(store.keys, [])
        }

        // 2) Legacy 1.3.x prefs (§2b worked example): FreeDict disabled while
        //    its sibling is enabled, and the pair interleaved in the order →
        //    each value rewritten exactly once, then idempotent.
        do {
            let (s, store) = service()
            s.enabledSources = ["wordnet", "openrussian", "wordnet-spa-eng", "wordnet-arb-eng"]
            s.dictionaryOrder = ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-arb-eng", "wordnet-spa-eng"]
            let seeded = store.writeLog.count

            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(s.enabledSources,
                           ["wordnet", "openrussian", "wordnet-spa-eng", "wordnet-arb-eng", "freedict-eng-spa"],
                           "enabled-if-any: FreeDict joins its enabled sibling")
            XCTAssertEqual(s.dictionaryOrder,
                           ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "openrussian", "wordnet-arb-eng"],
                           "the pair joins its earliest member")
            XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["enabled_sources", "dictionary_order"],
                           "one write per changed value, nothing else")

            let afterFirst = store.writeLog.count
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(store.writeLog.count, afterFirst, "already-normalised prefs must not be rewritten")
            XCTAssertEqual(s.enabledSources?.count, 5)
        }

        // 3) Only the enabled set needs fixing → the order key is not written.
        do {
            let (s, store) = service()
            s.enabledSources = ["freedict-eng-spa"]
            s.dictionaryOrder = ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "openrussian", "wordnet-arb-eng"]
            let seeded = store.writeLog.count
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["enabled_sources"])
            XCTAssertEqual(s.enabledSources, ["freedict-eng-spa", "wordnet-spa-eng"])
        }

        // 4) Only the order needs fixing → the enabled key is not written and
        //    nil (all enabled) stays nil.
        do {
            let (s, store) = service()
            s.dictionaryOrder = ["wordnet-spa-eng", "wordnet", "freedict-eng-spa"]
            let seeded = store.writeLog.count
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["dictionary_order"])
            XCTAssertEqual(s.dictionaryOrder, ["wordnet-spa-eng", "freedict-eng-spa", "wordnet"])
            XCTAssertNil(s.enabledSources)
            XCTAssertNil(store.data(forKey: "enabled_sources"))
        }

        // 5) Fully-disabled pair stays disabled and `{}` stays `{}` — no write.
        do {
            let (s, store) = service()
            s.enabledSources = ["wordnet", "openrussian", "wordnet-arb-eng"]
            let seeded = store.writeLog.count
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(s.enabledSources, ["wordnet", "openrussian", "wordnet-arb-eng"])
            XCTAssertEqual(store.writeLog.count, seeded)

            s.enabledSources = []
            let emptied = store.writeLog.count
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(s.enabledSources, [], "everything-off is a valid, stable state")
            XCTAssertEqual(store.writeLog.count, emptied)
        }

        // 6) A removed source lingering in prefs is preserved, not scrubbed
        //    (pre-existing tolerance), and does not force a rewrite by itself.
        do {
            let (s, store) = service()
            s.enabledSources = ["wordnet", "ghost"]
            s.dictionaryOrder = ["ghost", "wordnet"]
            let seeded = store.writeLog.count
            s.normalizeDictionaryPreferences(knownSources: known)
            XCTAssertEqual(s.enabledSources, ["wordnet", "ghost"])
            XCTAssertEqual(s.dictionaryOrder, ["ghost", "wordnet"])
            XCTAssertEqual(store.writeLog.count, seeded)
        }
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

// MARK: - Issue #5: ReadingModeService

/// Records every write through the `IdleTimerControlling` seam so tests can
/// assert not only the final flag but that the service never touches the idle
/// timer spuriously (idempotency, no-op background from the off state).
final class FakeIdleTimer: IdleTimerControlling {
    var writes: [Bool] = []
    var isIdleTimerDisabled = false {
        didSet { writes.append(isIdleTimerDisabled) }
    }
}

/// `ReadingModeService` is the only writer of `UIApplication.isIdleTimerDisabled`;
/// these tests drive a fresh instance on a fake seam. `ReadingModeService.shared`
/// (bound to the live `UIApplication`) is deliberately never referenced here.
@MainActor
final class ReadingModeServiceTests: XCTestCase {
    private var fake: FakeIdleTimer!
    private var service: ReadingModeService!

    override func setUp() {
        super.setUp()
        fake = FakeIdleTimer()
        service = ReadingModeService(idleTimer: fake)
    }

    override func tearDown() {
        service = nil
        fake = nil
        super.tearDown()
    }

    func testDefaultsOffAndDoesNotTouchSeam() {
        XCTAssertFalse(service.isEnabled, "reading mode must start off")
        XCTAssertFalse(fake.isIdleTimerDisabled, "the idle timer must not be disabled on init")
        XCTAssertTrue(fake.writes.isEmpty, "init must not write to the seam at all; got \(fake.writes)")
    }

    func testToggleOnFlipsSeam() {
        service.toggle()
        XCTAssertTrue(service.isEnabled)
        XCTAssertTrue(fake.isIdleTimerDisabled, "enabling must disable the idle timer")
        XCTAssertEqual(fake.writes, [true], "exactly one seam write on enable")
    }

    func testToggleTwiceRestoresSeam() {
        service.toggle()
        service.toggle()
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(fake.isIdleTimerDisabled, "disabling must re-arm the idle timer")
        XCTAssertEqual(fake.writes, [true, false])
    }

    func testSetEnabledIsIdempotent() {
        service.setEnabled(true)
        service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(fake.writes, [true], "a repeated setEnabled(true) must not re-write the seam")

        service.setEnabled(false)
        service.setEnabled(false)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(fake.writes, [true, false], "a repeated setEnabled(false) must not re-write the seam")
    }

    func testBackgroundTurnsOffAndReleasesSeam() {
        service.toggle()
        XCTAssertTrue(fake.isIdleTimerDisabled, "precondition: mode armed")

        service.sceneDidEnterBackground()
        XCTAssertFalse(service.isEnabled, "backgrounding must turn reading mode off")
        XCTAssertFalse(fake.isIdleTimerDisabled, "a backgrounded app must never hold the device awake")
        XCTAssertEqual(fake.writes, [true, false])

        // Second background edge (e.g. .background after a brief foreground
        // without re-enabling) must be a pure no-op.
        service.sceneDidEnterBackground()
        XCTAssertEqual(fake.writes, [true, false], "background from the off state must not write")
    }

    func testBackgroundWhenOffIsNoOp() {
        service.sceneDidEnterBackground()
        service.sceneDidEnterBackground()
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(fake.isIdleTimerDisabled)
        XCTAssertTrue(fake.writes.isEmpty, "no seam write when nothing changes; got \(fake.writes)")
    }

    func testReEnableAfterBackgroundArmsSeamAgain() {
        service.toggle()
        service.sceneDidEnterBackground()
        service.toggle()
        XCTAssertTrue(service.isEnabled, "the user can deliberately re-enable after a background reset")
        XCTAssertTrue(fake.isIdleTimerDisabled)
        XCTAssertEqual(fake.writes, [true, false, true])
    }

    func testTogglePublishesOncePerEffectiveChange() {
        var publishes = 0
        let cancellable = service.objectWillChange.sink { _ in publishes += 1 }
        defer { cancellable.cancel() }

        service.toggle()                    // off → on: publish
        service.setEnabled(true)            // unchanged: no publish
        service.sceneDidEnterBackground()   // on → off: publish
        service.sceneDidEnterBackground()   // unchanged: no publish

        XCTAssertEqual(publishes, 2, "objectWillChange must fire exactly once per effective change")
        XCTAssertEqual(fake.writes, [true, false], "publish count must track seam writes 1:1")
    }

    func testInstancesAreIndependent() {
        let otherFake = FakeIdleTimer()
        let other = ReadingModeService(idleTimer: otherFake)

        service.toggle()

        XCTAssertFalse(other.isEnabled, "state is per instance, not global")
        XCTAssertTrue(otherFake.writes.isEmpty, "a second seam must not observe another instance's writes")
        XCTAssertEqual(fake.writes, [true])
    }
}

// MARK: - Issue #74: Default dictionary order by UI language

/// `DictionaryDefaults.defaultOrder(for:sources:)` is pure (language + full
/// source list → ordered list), so the mapping cases need no mocking. The
/// "stored order wins" / "nil → language default" cases go through the real
/// `SettingsViewModel.loadDictionaries()` against a throwaway SQLite file
/// opened on `DatabaseService.shared` (same pattern as `DictAppTests`), with an
/// `InMemoryKeyValueStore`-backed `SettingsService` and a `LocalizationManager`
/// pinned to a chosen language via the persisted `ui_language` key.
final class DictionaryDefaultsTests: XCTestCase {
    /// Count-desc order as `fetchSourceStats()` returns it for the bundled seed.
    private let bundledSources = [
        "wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng",
    ]

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await DictAppTests.waitForHostAppLaunch()
        try await DatabaseService.shared.setup(path: dbPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private var dbPath: String { tempDir.appendingPathComponent("test.sqlite").path }

    private func language(_ code: String) -> UILanguage {
        UILanguage(code: code, displayKey: "language.\(code)", nativeName: code)
    }

    /// Inserts `count` distinct rows for `source` so `fetchSourceStats()` ranks
    /// sources by descending row count. Words are namespaced per source so the
    /// (word, source) unique index never collides across sources.
    private func seed(source: String, count: Int) async throws {
        let pool = try DatabasePool(path: dbPath)
        try await pool.writeWithoutTransaction { db in
            for i in 0..<count {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: ["\(source)-w\(i)", "\(source)-w\(i)", "def \(i)", "", "noun", source]
                )
            }
        }
    }

    /// Asserts `result` is exactly a reordering of `input`: same length, same
    /// multiset, no duplicates, no invented IDs.
    private func assertPermutation(_ result: [String], of input: [String],
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.count, input.count,
                       "length must match input; got \(result)", file: file, line: line)
        XCTAssertEqual(result.sorted(), input.sorted(),
                       "must contain exactly the input IDs; got \(result)", file: file, line: line)
        XCTAssertEqual(Set(result).count, result.count,
                       "must not contain duplicates; got \(result)", file: file, line: line)
    }

    // MARK: - Per-language mappings (pure function)

    func testEnglishKeepsWordnetFirst() {
        // Bundled order already has wordnet first → identity.
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("en"), sources: bundledSources),
                       bundledSources)

        // Wordnet buried in the middle must still be promoted, everything else
        // keeps its relative order.
        let shuffled = ["openrussian", "wordnet-arb-eng", "wordnet", "freedict-eng-spa"]
        let result = DictionaryDefaults.defaultOrder(for: language("en"), sources: shuffled)
        XCTAssertEqual(result, ["wordnet", "openrussian", "wordnet-arb-eng", "freedict-eng-spa"])
        assertPermutation(result, of: shuffled)
    }

    func testRussianPromotesOpenRussian() {
        let result = DictionaryDefaults.defaultOrder(for: language("ru"), sources: bundledSources)
        XCTAssertEqual(result, ["openrussian", "wordnet", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"])
        XCTAssertEqual(result.first, "openrussian", "AC: Russian device → openrussian first")
        assertPermutation(result, of: bundledSources)
    }

    func testSpanishPromotesBothSpanishSources() {
        // In the bundled (count-desc) order freedict-eng-spa precedes
        // wordnet-spa-eng; the mapping order must win over the incoming order.
        let result = DictionaryDefaults.defaultOrder(for: language("es"), sources: bundledSources)
        XCTAssertEqual(result, ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian", "wordnet-arb-eng"])
        XCTAssertEqual(Array(result.prefix(2)), ["wordnet-spa-eng", "freedict-eng-spa"],
                       "es must put BOTH Spanish dictionaries first, wordnet-spa-eng before freedict-eng-spa")
        assertPermutation(result, of: bundledSources)
    }

    func testArabicPromotesArabicWordnet() {
        let result = DictionaryDefaults.defaultOrder(for: language("ar"), sources: bundledSources)
        XCTAssertEqual(result, ["wordnet-arb-eng", "wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng"])
        assertPermutation(result, of: bundledSources)
    }

    /// The mapping must only reference IDs that actually ship in the seed;
    /// a typo here would silently degrade to "no promotion" at runtime.
    func testPreferredSourcesReferenceOnlyBundledIDs() throws {
        // Issue #87: the four Greek sources are bundled too (fixture above
        // keeps the five pre-Greek IDs for the order tests).
        let shipped = Set(bundledSources).union(DictAppTests.greekSourceIDs)
        for (code, ids) in DictionaryDefaults.preferredSources {
            XCTAssertFalse(ids.isEmpty, "mapping for \(code) must not be empty")
            XCTAssertEqual(Set(ids).count, ids.count, "mapping for \(code) has duplicates: \(ids)")
            for id in ids {
                XCTAssertTrue(shipped.contains(id),
                              "mapping for \(code) references unknown source id '\(id)'")
            }
        }
        // Exactly the shipped UI languages (SupportedLocales.json) have a
        // mapping: a new UI language needs one, and no mapping is dead code.
        let manifestCodes = Set(try DictAppTests.shippedUILanguages().map(\.code))
        XCTAssertTrue(manifestCodes.contains("el"), "Greek is a shipped UI language since #88")
        XCTAssertEqual(Set(DictionaryDefaults.preferredSources.keys), manifestCodes,
                       "preferredSources must have one mapping per SupportedLocales.json code, no more, no less")
    }

    // MARK: - Edge cases

    func testUnknownLanguageLeavesOrderUnchanged() {
        for code in ["de", "zh-Hans", "", "RU"] {   // RU: lookup is case-sensitive, no sloppy match
            XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language(code), sources: bundledSources),
                           bundledSources, "unmapped code '\(code)' must return input verbatim")
            XCTAssertEqual(DictionaryDefaults.defaultOrder(forLanguageCode: code, sources: bundledSources),
                           bundledSources)
        }
        // Empty input must not crash and must stay empty for any language.
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("ru"), sources: []), [])
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("xx"), sources: []), [])
    }

    func testPreferredSourceMissingFromListIsSkipped() {
        // ru mapping present, but openrussian not installed → verbatim, not invented.
        let noRussian = ["wordnet", "freedict-eng-spa", "wordnet-arb-eng"]
        let ru = DictionaryDefaults.defaultOrder(for: language("ru"), sources: noRussian)
        XCTAssertEqual(ru, noRussian)
        XCTAssertFalse(ru.contains("openrussian"), "must never invent an ID absent from sources")

        // es mapping lists two IDs; only the second is installed → it alone is
        // promoted, the missing first one is skipped (no gap, no nil, no crash).
        let onlyFreedict = ["wordnet", "openrussian", "freedict-eng-spa"]
        let es = DictionaryDefaults.defaultOrder(for: language("es"), sources: onlyFreedict)
        XCTAssertEqual(es, ["freedict-eng-spa", "wordnet", "openrussian"])
        assertPermutation(es, of: onlyFreedict)

        // Single-source list that IS the preferred one → unchanged singleton.
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("ar"), sources: ["wordnet-arb-eng"]),
                       ["wordnet-arb-eng"])
    }

    func testRemainingSourcesKeepRelativeOrder() {
        // Preferred sits in the middle; the non-preferred subsequence must be
        // untouched (this is what distinguishes "promote" from "re-sort").
        let input = ["freedict-eng-spa", "wordnet-arb-eng", "openrussian", "wordnet", "wordnet-spa-eng"]
        let result = DictionaryDefaults.defaultOrder(for: language("ru"), sources: input)
        XCTAssertEqual(result.first, "openrussian")
        XCTAssertEqual(Array(result.dropFirst()), input.filter { $0 != "openrussian" },
                       "non-preferred sources must keep their incoming relative order")
        assertPermutation(result, of: input)
    }

    // MARK: - Integration: SettingsViewModel.loadDictionaries() branch

    /// Builds a VM whose `LocalizationManager` is pinned to `languageCode`
    /// (via the persisted `ui_language` key) and whose `dictionaryOrder`
    /// starts as `storedOrder`. Returns the VM and its settings service.
    @MainActor
    private func makeViewModel(languageCode: String,
                               storedOrder: [String]?) -> (SettingsViewModel, SettingsService) {
        let settings = SettingsService(store: InMemoryKeyValueStore())
        settings.selectedUILanguageCode = languageCode
        settings.dictionaryOrder = storedOrder
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        XCTAssertEqual(localization.currentLanguage.code, languageCode,
                       "precondition: LocalizationManager must resolve the pinned language")
        return (SettingsViewModel(settingsService: settings, localization: localization), settings)
    }

    @MainActor
    func testStoredOrderIsNotOverriddenByLanguageDefault() async throws {
        // Count-desc from the DB: wordnet(3) > openrussian(2) > wordnet-arb-eng(1).
        try await seed(source: "wordnet", count: 3)
        try await seed(source: "openrussian", count: 2)
        try await seed(source: "wordnet-arb-eng", count: 1)

        // A user-configured order that is neither count-desc nor the ru default.
        let userOrder = ["wordnet-arb-eng", "wordnet", "openrussian"]
        let (vm, settings) = makeViewModel(languageCode: "ru", storedOrder: userOrder)

        await vm.loadDictionaries()

        XCTAssertEqual(settings.dictionaryOrder, userOrder,
                       "a persisted order must survive loadDictionaries() even when the UI language is ru")
        // Issue #92: rows are language pairs, keyed by pair id.
        XCTAssertEqual(vm.dictionaries.map(\.id), ["arb-eng", "eng", "eng-rus"],
                       "the published list must reflect the stored order, not the language default")
        XCTAssertNotEqual(vm.dictionaries.first?.id, "eng-rus",
                          "guard: the ru default would have put openrussian first — it must not apply here")
    }

    @MainActor
    func testNilStoredOrderProducesRussianDefaultAndPersistsIt() async throws {
        try await seed(source: "wordnet", count: 3)
        try await seed(source: "openrussian", count: 2)
        try await seed(source: "wordnet-arb-eng", count: 1)

        let (vm, settings) = makeViewModel(languageCode: "ru", storedOrder: nil)
        XCTAssertNil(settings.dictionaryOrder, "precondition: first launch has no stored order")

        await vm.loadDictionaries()

        let expected = ["openrussian", "wordnet", "wordnet-arb-eng"]
        // Issue #92: rows are language pairs, keyed by pair id.
        let expectedPairs = ["eng-rus", "eng", "arb-eng"]
        XCTAssertEqual(vm.dictionaries.map(\.id), expectedPairs,
                       "first launch on ru must promote openrussian above the count-desc base order")
        XCTAssertEqual(settings.dictionaryOrder, expected,
                       "the derived default must be persisted so later launches take the stored branch")
        XCTAssertEqual(vm.dictionaries.map(\.count), [2, 3, 1],
                       "row counts must travel with their source through the reorder")

        // Second load now hits the stored branch and must be idempotent.
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), expectedPairs)
    }

    @MainActor
    func testNilStoredOrderWithoutMappedSourcesKeepsCountDescOrder() async throws {
        // Spanish UI, but no Spanish dictionary installed → base order is kept.
        try await seed(source: "wordnet", count: 2)
        try await seed(source: "openrussian", count: 1)

        let (vm, settings) = makeViewModel(languageCode: "es", storedOrder: nil)
        await vm.loadDictionaries()

        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-rus"])
        XCTAssertEqual(settings.dictionaryOrder, ["wordnet", "openrussian"])
    }
}

// MARK: - Issue #92: Language-pair grouping

/// `DictionaryGrouping` is pure (source IDs → pairs / grouped order / expanded
/// enabled set), so these need no database or mocking. Contracts in
/// DESIGN_DOC.md §1a, §1d and §7a; PM decisions #1–#3 at the end of the doc.
final class DictionaryGroupingTests: XCTestCase {
    /// The five bundled IDs in the seed's count-desc order (= the `en` default).
    private let bundled = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"]
    private let bundledKeys: Set<String> = ["eng", "eng-rus", "eng-spa", "arb-eng"]

    private func stat(_ source: String, count: Int = 1) -> SourceStat {
        SourceStat(source: source, displayName: source.uppercased(), count: count)
    }

    /// The five bundled IDs → `eng`, `eng-rus`, `eng-spa`, `eng-spa`, `arb-eng` (§1b).
    func testPairKeyForBundledSources() {
        let keys = bundled.map(DictionaryGrouping.pairKey(forSource:))
        XCTAssertEqual(keys, ["eng", "eng-rus", "eng-spa", "eng-spa", "arb-eng"])
        XCTAssertEqual(Set(keys), bundledKeys, "five sources → four pairs")
        XCTAssertEqual(DictionaryGrouping.pairKey(forSource: "wordnet"), "eng",
                       "legacy bare monolingual ID → single-language key, not 'eng-eng'")
        XCTAssertEqual(DictionaryGrouping.pairKey(forSource: "openrussian"), "eng-rus",
                       "legacy bare bilingual ID → sorted codes ('eng' < 'rus'), not translation order")
        XCTAssertEqual(DictionaryGrouping.pairKey(forSource: "wordnet-arb-eng"), "arb-eng",
                       "'arb' sorts before 'eng', so English is not always first in the key")
        XCTAssertFalse(keys.contains { $0.hasPrefix("custom:") }, "no bundled source is custom")
    }

    /// `pairKey("wordnet-spa-eng") == pairKey("freedict-eng-spa")`.
    func testPairKeyIsDirectionAgnostic() {
        XCTAssertEqual(DictionaryGrouping.pairKey(forSource: "wordnet-spa-eng"),
                       DictionaryGrouping.pairKey(forSource: "freedict-eng-spa"))
        XCTAssertEqual(DictionaryGrouping.pairKey(forSource: "wordnet-spa-eng"), "eng-spa")
        // Only seed-registered IDs merge. A convention-named import (its ID
        // is the file name) stays its own row (PM decision #2, PR #100 review).
        for id in ["freedict-spa-eng", "wordnet-eng-spa", "freedict-eng-rus", "wordnet-eng-eng", "freedict-deu-eng"] {
            XCTAssertTrue(DictionaryGrouping.parse(sourceID: id).isCustom, id)
            XCTAssertEqual(DictionaryGrouping.pairKey(forSource: id), "custom:" + id)
        }
        XCTAssertNotEqual(DictionaryGrouping.pairKey(forSource: "freedict-eng-rus"),
                          DictionaryGrouping.pairKey(forSource: "openrussian"))
    }

    /// `test_import_fixture`, `my dict`, `eng`, `eng-spa`, `mydict-eng-spa`,
    /// `wordnet-es-en` → each `custom:<id>`, all distinct, none equal to a bundled key.
    func testCustomSourcesAreOwnGroups() {
        let custom = [
            "test_import_fixture",   // the UI-test import fixture
            "my dict",               // whitespace, no convention at all
            "eng",                   // a file named like a pair KEY
            "eng-spa",               // a file named like a pair KEY
            "mydict-eng-spa",        // convention-shaped but unknown provider (PM decision #2)
            "wordnet-es-en",         // bundled provider but alpha-2 codes
            "wordnet--eng-spa",      // empty provider segment → provider "wordnet-"
            "wordnet-ENG-SPA",       // upper-case codes are not ^[a-z]{3}$
            "freedict-eng",          // too few segments
            "wordnet-eng-spa-extra", // trailing segment: "spa"/"extra" are not both alpha-3
            "",                      // degenerate
        ]
        let keys = custom.map(DictionaryGrouping.pairKey(forSource:))
        for (id, key) in zip(custom, keys) {
            XCTAssertEqual(key, "custom:\(id)", "'\(id)' must be its own group")
            XCTAssertFalse(bundledKeys.contains(key), "'\(id)' must never collide with a bundled key")
            let parsed = DictionaryGrouping.parse(sourceID: id)
            XCTAssertTrue(parsed.isCustom, "'\(id)' must parse as custom")
            XCTAssertEqual(parsed.provider, id, "custom provider is the raw ID")
            XCTAssertEqual(parsed.languages, [], "custom sources carry no languages")
        }
        XCTAssertEqual(Set(keys).count, custom.count, "all distinct")

        // PM decision #2, spelled out: a custom import named like a bundled
        // pair stays separate from that pair.
        XCTAssertNotEqual(DictionaryGrouping.pairKey(forSource: "mydict-eng-spa"),
                          DictionaryGrouping.pairKey(forSource: "freedict-eng-spa"))
        XCTAssertNotEqual(DictionaryGrouping.pairKey(forSource: "eng-spa"), "eng-spa")
        XCTAssertNotEqual(DictionaryGrouping.pairKey(forSource: "eng"), "eng")
        XCTAssertEqual(DictionaryGrouping.sourceGroups(order: ["freedict-eng-spa", "mydict-eng-spa", "wordnet-spa-eng"]),
                       [["freedict-eng-spa", "wordnet-spa-eng"], ["mydict-eng-spa"]])
    }

    /// `freedict-eng-spa` → (freedict, eng→spa); `openrussian` → (openrussian, rus→eng);
    /// `wordnet` → direction nil; custom → direction nil.
    func testParseExposesProviderAndDirection() {
        let fd = DictionaryGrouping.parse(sourceID: "freedict-eng-spa")
        XCTAssertEqual(fd.provider, "freedict")
        XCTAssertEqual(fd.languages, ["eng", "spa"])
        XCTAssertFalse(fd.isCustom)

        let wn = DictionaryGrouping.parse(sourceID: "wordnet-spa-eng")
        XCTAssertEqual(wn.provider, "wordnet")
        XCTAssertEqual(wn.languages, ["spa", "eng"],
                       "`languages` keeps translation direction; only the pair KEY is sorted")

        let ru = DictionaryGrouping.parse(sourceID: "openrussian")
        XCTAssertEqual(ru.provider, "openrussian")
        XCTAssertEqual(ru.languages, ["rus", "eng"])
        XCTAssertFalse(ru.isCustom)

        let en = DictionaryGrouping.parse(sourceID: "wordnet")
        XCTAssertEqual(en.provider, "wordnet")
        XCTAssertEqual(en.languages, ["eng"])
        XCTAssertFalse(en.isCustom)

        let custom = DictionaryGrouping.parse(sourceID: "test_import_fixture")
        XCTAssertTrue(custom.isCustom)
        XCTAssertEqual(custom.provider, "test_import_fixture")
        XCTAssertEqual(custom.languages, [])

        // The bilingual allowlist matches the seed's dict_metadata exactly
        // (seven bilingual IDs since the four Greek sources of #87).
        XCTAssertEqual(DictionaryGrouping.bundledSourceIDs,
                       ["wordnet-spa-eng", "freedict-eng-spa", "wordnet-arb-eng",
                        "wordnet-ell-eng", "wordnet-eng-ell", "freedict-ell-eng", "freedict-eng-ell"],
                       "allowlist is the one place a future bundled dictionary is added")

        // `SourceStat` surfaces the same facts for the #91 detail.
        XCTAssertEqual(stat("freedict-eng-spa").provider, "freedict")
        XCTAssertEqual(stat("freedict-eng-spa").direction?.from, "eng")
        XCTAssertEqual(stat("freedict-eng-spa").direction?.to, "spa")
        XCTAssertEqual(stat("wordnet-spa-eng").direction?.from, "spa")
        XCTAssertEqual(stat("wordnet-spa-eng").direction?.to, "eng")
        XCTAssertEqual(stat("openrussian").direction?.from, "rus")
        XCTAssertEqual(stat("openrussian").direction?.to, "eng")
        XCTAssertNil(stat("wordnet").direction, "monolingual → no direction")
        XCTAssertNil(stat("test_import_fixture").direction, "custom → no direction")
        XCTAssertEqual(stat("test_import_fixture").provider, "test_import_fixture")
        XCTAssertEqual(stat("wordnet").license, "", "defaulted stored fields keep the memberwise init source-compatible")
        XCTAssertEqual(stat("wordnet").version, "")
    }

    /// §2b worked example; result is a permutation; idempotent; already-grouped
    /// input unchanged; `[]` → `[]`.
    func testGroupedOrderPullsLaterMembersUpToEarliest() {
        let before = ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-arb-eng", "wordnet-spa-eng"]
        let after = ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "openrussian", "wordnet-arb-eng"]
        let grouped = DictionaryGrouping.groupedOrder(before)
        XCTAssertEqual(grouped, after)
        XCTAssertEqual(grouped.sorted(), before.sorted(), "permutation: nothing added or dropped")
        XCTAssertEqual(Set(grouped).count, grouped.count, "no duplicates")
        XCTAssertEqual(DictionaryGrouping.groupedOrder(grouped), grouped, "idempotent")
        XCTAssertEqual(DictionaryGrouping.groupedOrder(after), after, "already-grouped input unchanged")
        XCTAssertEqual(DictionaryGrouping.groupedOrder(bundled), bundled, "the en default is already grouped")
        XCTAssertEqual(DictionaryGrouping.groupedOrder([]), [])
        XCTAssertEqual(DictionaryGrouping.groupedOrder(["wordnet"]), ["wordnet"])

        // The EARLIEST member wins the slot whichever direction it is, and the
        // later member keeps its place inside the pair.
        XCTAssertEqual(DictionaryGrouping.groupedOrder(["wordnet-spa-eng", "wordnet", "openrussian", "freedict-eng-spa"]),
                       ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian"])
        // A convention-named import is not pulled into the bundled pair.
        XCTAssertEqual(DictionaryGrouping.groupedOrder(["freedict-eng-spa", "a", "wordnet-spa-eng", "b", "freedict-spa-eng"]),
                       ["freedict-eng-spa", "wordnet-spa-eng", "a", "b", "freedict-spa-eng"])
        // Custom IDs never join a bundled pair, even when interleaved with it.
        XCTAssertEqual(DictionaryGrouping.groupedOrder(["freedict-eng-spa", "mydict-eng-spa", "wordnet-spa-eng"]),
                       ["freedict-eng-spa", "wordnet-spa-eng", "mydict-eng-spa"])
        // Unknown / single-member IDs are left where they stand.
        XCTAssertEqual(DictionaryGrouping.groupedOrder(["zzz", "wordnet", "openrussian"]), ["zzz", "wordnet", "openrussian"])
    }

    /// `[wordnet, freedict-eng-spa, openrussian, wordnet-spa-eng]` →
    /// `[[wordnet], [freedict-eng-spa, wordnet-spa-eng], [openrussian]]`.
    func testSourceGroupsSplitByFirstOccurrence() {
        XCTAssertEqual(DictionaryGrouping.sourceGroups(order: ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-spa-eng"]),
                       [["wordnet"], ["freedict-eng-spa", "wordnet-spa-eng"], ["openrussian"]])
        XCTAssertEqual(DictionaryGrouping.sourceGroups(order: []), [])
        XCTAssertEqual(DictionaryGrouping.sourceGroups(order: ["wordnet-spa-eng"]), [["wordnet-spa-eng"]])
        // Members keep their relative order from `order` (canonical member order, §2c).
        XCTAssertEqual(DictionaryGrouping.sourceGroups(order: ["wordnet-spa-eng", "wordnet", "freedict-eng-spa"]),
                       [["wordnet-spa-eng", "freedict-eng-spa"], ["wordnet"]])
        // Groups line up with pair keys (search keys buckets by group index).
        let groups = DictionaryGrouping.sourceGroups(order: bundled)
        XCTAssertEqual(groups.map { DictionaryGrouping.pairKey(forSource: $0[0]) }, ["eng", "eng-rus", "eng-spa", "arb-eng"])
        XCTAssertEqual(groups.flatMap { $0 }, DictionaryGrouping.groupedOrder(bundled),
                       "groupedOrder is exactly the flattened groups")
        // Every member of a group shares one key; no key appears in two groups.
        for group in groups {
            XCTAssertEqual(Set(group.map(DictionaryGrouping.pairKey(forSource:))).count, 1, "mixed group \(group)")
        }
        XCTAssertEqual(Set(groups.map { DictionaryGrouping.pairKey(forSource: $0[0]) }).count, groups.count)
    }

    /// `{wordnet-spa-eng}` + the five known → contains `freedict-eng-spa`;
    /// nil → nil; `{}` → `{}`; unknown ID preserved; fully-disabled pair stays disabled.
    func testEnabledIfAnyExpandsPartialPair() {
        let known = bundled

        // Partial pair → the sibling joins; nothing else is switched on.
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["wordnet-spa-eng"], knownSources: known),
                       ["wordnet-spa-eng", "freedict-eng-spa"])
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["freedict-eng-spa", "wordnet"], knownSources: known),
                       ["freedict-eng-spa", "wordnet-spa-eng", "wordnet"])

        // nil → nil (all enabled, first launch); {} → {} (everything off).
        XCTAssertNil(DictionaryGrouping.enabledIfAny(nil, knownSources: known))
        XCTAssertEqual(DictionaryGrouping.enabledIfAny([], knownSources: known), [])

        // An ID present in `enabled` but unknown is preserved verbatim
        // (removed-source tolerance) and does not drag anything else in.
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["ghost", "openrussian"], knownSources: known),
                       ["ghost", "openrussian"])

        // A fully-disabled pair stays disabled.
        let withoutSpanish: Set<String> = ["wordnet", "openrussian", "wordnet-arb-eng"]
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(withoutSpanish, knownSources: known), withoutSpanish)

        // Already-consistent input comes back equal (lets normalisation skip the write).
        let full = Set(known)
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(full, knownSources: known), full)

        // Empty known universe: only the enabled IDs themselves survive.
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["wordnet-spa-eng"], knownSources: []), ["wordnet-spa-eng"])

        // A custom import named like the pair is NOT pulled in (PM decision #2),
        // and an enabled custom import does not pull the bundled pair in either.
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["wordnet-spa-eng"], knownSources: known + ["mydict-eng-spa"]),
                       ["wordnet-spa-eng", "freedict-eng-spa"])
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["mydict-eng-spa"], knownSources: known + ["mydict-eng-spa"]),
                       ["mydict-eng-spa"])
    }

    /// Five stats → four pairs; `eng-spa.count` is the sum; members in `order`
    /// order; IDs missing from stats are dropped.
    func testPairsFromStatsSumCountsAndKeepMemberOrder() throws {
        let stats = [
            stat("wordnet", count: 100), stat("openrussian", count: 50),
            stat("freedict-eng-spa", count: 30), stat("wordnet-spa-eng", count: 20),
            stat("wordnet-arb-eng", count: 10),
        ]
        // The `es` first-launch order: Spanish WordNet above FreeDict.
        let order = ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian", "wordnet-arb-eng"]
        let pairs = DictionaryGrouping.pairs(from: stats, order: order)

        XCTAssertEqual(pairs.map(\.id), ["eng-spa", "eng", "eng-rus", "arb-eng"], "five stats → four pairs")
        XCTAssertEqual(pairs.map(\.count), [50, 100, 50, 10], "eng-spa = 30 + 20")
        XCTAssertEqual(pairs.map(\.isCustom), [false, false, false, false])
        XCTAssertEqual(pairs.map(\.languages), [["eng", "spa"], ["eng"], ["eng", "rus"], ["arb", "eng"]], "sorted codes")

        let spanish = try XCTUnwrap(pairs.first)
        XCTAssertEqual(spanish.sourceIDs, ["wordnet-spa-eng", "freedict-eng-spa"], "members in `order` order")
        XCTAssertEqual(spanish.sources.map(\.count), [20, 30])
        XCTAssertEqual(spanish.sources.map(\.displayName), ["WORDNET-SPA-ENG", "FREEDICT-ENG-SPA"],
                       "#91 API: the full SourceStat per member, untouched")
        XCTAssertEqual(spanish.sources.map(\.provider), ["wordnet", "freedict"])

        // Reversed member order in `order` → reversed members, same pair id and count.
        let reversed = DictionaryGrouping.pairs(from: stats, order: bundled)
        XCTAssertEqual(reversed.map(\.id), ["eng", "eng-rus", "eng-spa", "arb-eng"])
        XCTAssertEqual(reversed[2].sourceIDs, ["freedict-eng-spa", "wordnet-spa-eng"])
        XCTAssertEqual(reversed[2].count, 50)

        // IDs in `order` but missing from stats are dropped; a group with no
        // resolvable member yields no pair at all.
        let dropped = DictionaryGrouping.pairs(from: stats, order: ["ghost", "wordnet-spa-eng", "freedict-eng-spa", "wordnet"])
        XCTAssertEqual(dropped.map(\.id), ["eng-spa", "eng"])
        let partialStats = stats.filter { $0.source != "wordnet-spa-eng" }
        let partial = DictionaryGrouping.pairs(from: partialStats, order: order)
        XCTAssertEqual(partial.map(\.id), ["eng-spa", "eng", "eng-rus", "arb-eng"])
        XCTAssertEqual(partial[0].sourceIDs, ["freedict-eng-spa"], "the missing member is dropped, the pair survives")
        XCTAssertEqual(partial[0].count, 30)

        // Stats absent from `order` are not invented (reconciliation is the VM's job).
        XCTAssertEqual(DictionaryGrouping.pairs(from: stats, order: ["wordnet"]).map(\.id), ["eng"])

        // Custom → own pair, no languages, raw stat kept.
        let custom = DictionaryGrouping.pairs(from: [stat("test_import_fixture", count: 7)], order: ["test_import_fixture"])
        XCTAssertEqual(custom.map(\.id), ["custom:test_import_fixture"])
        XCTAssertEqual(custom.first?.isCustom, true)
        XCTAssertEqual(custom.first?.languages, [])
        XCTAssertEqual(custom.first?.count, 7)
        XCTAssertEqual(custom.first?.sources.first?.displayName, "TEST_IMPORT_FIXTURE")

        // Empty inputs.
        XCTAssertEqual(DictionaryGrouping.pairs(from: [], order: order), [])
        XCTAssertEqual(DictionaryGrouping.pairs(from: stats, order: []), [])

        // `DictionaryItem` derives id / count from the pair.
        let item = DictionaryItem(pair: spanish, displayName: "Spanish – English", isEnabled: true)
        XCTAssertEqual(item.id, "eng-spa")
        XCTAssertEqual(item.count, 50)
    }

    /// #74 interplay: for every `DictionaryDefaults.preferredSources` list,
    /// `Set(ids.map(pairKey)).count == 1`.
    func testPreferredSourcesMembersCollapseToSinglePair() {
        XCTAssertFalse(DictionaryDefaults.preferredSources.isEmpty)
        for (lang, ids) in DictionaryDefaults.preferredSources {
            let keys = Set(ids.map(DictionaryGrouping.pairKey(forSource:)))
            XCTAssertEqual(keys.count, 1,
                           "preferredSources[\(lang)] = \(ids) must all belong to one pair; got \(keys)")
            XCTAssertFalse(keys.contains { $0.hasPrefix("custom:") },
                           "preferredSources[\(lang)] must reference bundled IDs only")
        }
        // The #74 default for every shipped UI language already satisfies I2,
        // so the first-launch order is never reshuffled by grouping.
        for lang in ["en", "ru", "es", "ar", "el"] {
            let d = DictionaryDefaults.defaultOrder(forLanguageCode: lang, sources: bundled)
            XCTAssertEqual(DictionaryGrouping.groupedOrder(d), d, "\(lang) default must already be grouped")
        }
        // And a preferred list naming only ONE member still promotes the whole
        // pair once grouped (bonus property, §2c).
        let partialPreferred = DictionaryGrouping.groupedOrder(["freedict-eng-spa"] + bundled.filter { $0 != "freedict-eng-spa" })
        XCTAssertEqual(Array(partialPreferred.prefix(2)), ["freedict-eng-spa", "wordnet-spa-eng"])
    }
}

/// `SettingsViewModel` pair-level integration (pattern of
/// `DictionaryDefaultsTests`: throwaway SQLite on `DatabaseService.shared`,
/// in-memory settings, `LocalizationManager` pinned via `ui_language`), seeded
/// with the five bundled IDs plus custom sources. DESIGN_DOC.md §7a,
/// "SettingsViewModel integration".
final class SettingsViewModelPairTests: XCTestCase {
    /// Count-desc as `fetchSourceStats()` returns the bundled seed (= the `en`
    /// default order). Counts are distinct so the DB order is deterministic.
    private let bundledSources = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"]
    private let counts: [String: Int] = [
        "wordnet": 7, "openrussian": 6, "freedict-eng-spa": 5, "wordnet-spa-eng": 4, "wordnet-arb-eng": 3,
        "mydict-eng-spa": 2, "test_import_fixture": 1,
    ]

    private var tempDir: URL!
    private var dbPath: String { tempDir.appendingPathComponent("test.sqlite").path }

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await DictAppTests.waitForHostAppLaunch()
        try await DatabaseService.shared.setup(path: dbPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func seed(source: String) async throws {
        let count = try XCTUnwrap(counts[source], "no seed count for \(source)")
        let pool = try DatabasePool(path: dbPath)
        try await pool.writeWithoutTransaction { db in
            for i in 0..<count {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: ["\(source)-w\(i)", "\(source)-w\(i)", "def \(i)", "", "noun", source]
                )
            }
        }
    }

    private func seedBundled() async throws {
        for source in bundledSources { try await seed(source: source) }
    }

    private func insertMetadata(source: String, displayName: String) async throws {
        let pool = try DatabasePool(path: dbPath)
        try await pool.write { db in
            try db.execute(sql: "INSERT INTO dict_metadata(source, display_name) VALUES (?, ?)",
                           arguments: [source, displayName])
        }
    }

    /// Builds a VM whose `LocalizationManager` is pinned to `languageCode` and
    /// whose stored prefs start as given. Returns the VM, its settings
    /// service and the spy store behind it.
    @MainActor
    private func makeViewModel(languageCode: String, storedOrder: [String]? = nil,
                               storedEnabled: Set<String>? = nil)
        -> (SettingsViewModel, SettingsService, InMemoryKeyValueStore) {
        let store = InMemoryKeyValueStore()
        let settings = SettingsService(store: store)
        settings.selectedUILanguageCode = languageCode
        settings.dictionaryOrder = storedOrder
        settings.enabledSources = storedEnabled
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        XCTAssertEqual(localization.currentLanguage.code, languageCode,
                       "precondition: LocalizationManager must resolve the pinned language")
        return (SettingsViewModel(settingsService: settings, localization: localization), settings, store)
    }

    private func assertGrouped(_ order: [String]?, permutationOf expected: [String],
                               file: StaticString = #filePath, line: UInt = #line) {
        let order = order ?? []
        XCTAssertEqual(order.sorted(), expected.sorted(), "must be a permutation of the live sources; got \(order)",
                       file: file, line: line)
        XCTAssertEqual(DictionaryGrouping.groupedOrder(order), order, "pair members must be contiguous; got \(order)",
                       file: file, line: line)
    }

    /// 7 sources → 6 items; `map(\.id)`; `eng-spa` count = sum; custom items
    /// `custom:<id>` with the raw display name (metadata name or source ID).
    @MainActor
    func testLoadDictionariesGroupsBundledPairs() async throws {
        try await seedBundled()
        try await seed(source: "mydict-eng-spa")        // custom named like a bundled pair
        try await seed(source: "test_import_fixture")   // custom without a metadata row
        try await insertMetadata(source: "mydict-eng-spa", displayName: "My Spanish Dict")
        try await insertMetadata(source: "freedict-eng-spa", displayName: "English – Spanish (FreeDict)")

        let (vm, settings, _) = makeViewModel(languageCode: "en")
        await vm.loadDictionaries()

        XCTAssertEqual(vm.dictionaries.map(\.id),
                       ["eng", "eng-rus", "eng-spa", "arb-eng", "custom:mydict-eng-spa", "custom:test_import_fixture"],
                       "7 sources → 6 rows: the two Spanish directions share one row, customs stay apart")
        XCTAssertEqual(vm.dictionaries.map(\.displayName),
                       ["English", "Russian – English", "Spanish – English", "Arabic – English",
                        "My Spanish Dict", "test_import_fixture"],
                       "pair titles are localised language names; customs show their raw name (PM #2/#3)")
        XCTAssertEqual(vm.dictionaries.map(\.count), [7, 6, 9, 3, 2, 1], "eng-spa = 5 + 4")
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled), "fresh install: every row ON")

        let spanish = try XCTUnwrap(vm.dictionaries.first { $0.id == "eng-spa" })
        XCTAssertEqual(spanish.pair.sourceIDs, ["freedict-eng-spa", "wordnet-spa-eng"])
        XCTAssertEqual(spanish.pair.sources.map(\.count), [5, 4])
        XCTAssertEqual(spanish.pair.sources.map(\.displayName), ["English – Spanish (FreeDict)", "wordnet-spa-eng"],
                       "#91 API: per-source stats stay available behind the row")
        XCTAssertEqual(spanish.pair.languages, ["eng", "spa"])

        let custom = try XCTUnwrap(vm.dictionaries.first { $0.id == "custom:mydict-eng-spa" })
        XCTAssertTrue(custom.pair.isCustom)
        XCTAssertEqual(custom.pair.sourceIDs, ["mydict-eng-spa"])
        XCTAssertEqual(custom.pair.languages, [])

        // Persistence stays source-level: order materialised as source IDs, enabled left nil.
        XCTAssertEqual(settings.dictionaryOrder,
                       ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng",
                        "mydict-eng-spa", "test_import_fixture"])
        XCTAssertNil(settings.enabledSources, "nil (all enabled) is not materialised by a load")
        XCTAssertEqual(vm.orderedDictionaries.map(\.id), vm.dictionaries.map(\.id))
    }

    /// Toggle `eng-spa` → `isEnabled(source:)` false for both members; toggling
    /// back restores both.
    @MainActor
    func testTogglePairDisablesBothDirections() async throws {
        try await seedBundled()
        let (vm, settings, store) = makeViewModel(languageCode: "en")
        await vm.loadDictionaries()
        XCTAssertNil(settings.enabledSources, "precondition")

        let writesBeforeToggle = store.writeLog.filter { $0 == "enabled_sources" }.count
        vm.togglePair(id: "eng-spa")

        XCTAssertFalse(settings.isEnabled(source: "freedict-eng-spa"))
        XCTAssertFalse(settings.isEnabled(source: "wordnet-spa-eng"))
        XCTAssertEqual(settings.enabledSources, ["wordnet", "openrussian", "wordnet-arb-eng"],
                       "materialised from the live sources minus BOTH members")
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, true, false, true])
        XCTAssertFalse(vm.binding(for: "eng-spa").wrappedValue)
        XCTAssertEqual(store.writeLog.filter { $0 == "enabled_sources" }.count, writesBeforeToggle + 1,
                       "one write for the pair")

        // The persisted state survives a reload (what the order screen shows
        // after navigating away and back).
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, true, false, true])

        // Toggling back through the SwiftUI binding restores both members.
        vm.binding(for: "eng-spa").wrappedValue = true
        XCTAssertTrue(settings.isEnabled(source: "freedict-eng-spa"))
        XCTAssertTrue(settings.isEnabled(source: "wordnet-spa-eng"))
        XCTAssertEqual(settings.enabledSources, Set(bundledSources))
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled))

        // Setting the binding to its current value is a no-op (no extra write).
        let writes = store.writeLog.count
        vm.binding(for: "eng-spa").wrappedValue = true
        XCTAssertEqual(store.writeLog.count, writes)

        // Unknown pair id: no crash, no write; its binding reads false.
        vm.togglePair(id: "custom:ghost")
        XCTAssertEqual(store.writeLog.count, writes)
        XCTAssertFalse(vm.binding(for: "custom:ghost").wrappedValue)

        // A single-source pair toggles exactly its one member.
        vm.togglePair(id: "eng-rus")
        XCTAssertEqual(settings.enabledSources, ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"])
    }

    /// After a move, `dictionaryOrder` has pair members contiguous and is a
    /// permutation of existing.
    @MainActor
    func testMovePairPersistsGroupedSourceOrder() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "en")
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-rus", "eng-spa", "arb-eng"], "precondition")

        // Spanish pair (row 2) to the top: both members move as one slot.
        vm.movePair(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng-spa", "eng", "eng-rus", "arb-eng"])
        XCTAssertEqual(settings.dictionaryOrder,
                       ["freedict-eng-spa", "wordnet-spa-eng", "wordnet", "openrussian", "wordnet-arb-eng"])
        assertGrouped(settings.dictionaryOrder, permutationOf: bundledSources)

        // Then to the bottom (`toOffset == count` moves past the last row).
        vm.movePair(from: IndexSet(integer: 0), to: vm.dictionaries.count)
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-rus", "arb-eng", "eng-spa"])
        XCTAssertEqual(settings.dictionaryOrder,
                       ["wordnet", "openrussian", "wordnet-arb-eng", "freedict-eng-spa", "wordnet-spa-eng"])
        assertGrouped(settings.dictionaryOrder, permutationOf: bundledSources)

        // Reload reads the persisted order back: same rows, members still in
        // their canonical (FreeDict-first) order.
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-rus", "arb-eng", "eng-spa"])
        XCTAssertEqual(vm.dictionaries.last?.pair.sourceIDs, ["freedict-eng-spa", "wordnet-spa-eng"])
        XCTAssertEqual(settings.dictionaryOrder,
                       ["wordnet", "openrussian", "wordnet-arb-eng", "freedict-eng-spa", "wordnet-spa-eng"])

        // A no-op move keeps everything in place.
        vm.movePair(from: IndexSet(integer: 1), to: 1)
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-rus", "arb-eng", "eng-spa"])
    }

    /// Pre-store `{wordnet-spa-eng}` only → after load the row is ON and
    /// `enabled_sources` contains `freedict-eng-spa`.
    @MainActor
    func testLegacyPartialPairMigratesEnabledIfAny() async throws {
        try await seedBundled()

        // 1.3.x user who had FreeDict OFF but Spanish WordNet ON (the §2b example).
        let legacyEnabled: Set<String> = ["wordnet", "openrussian", "wordnet-spa-eng", "wordnet-arb-eng"]
        let legacyOrder = ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-arb-eng", "wordnet-spa-eng"]
        let (vm, settings, store) = makeViewModel(languageCode: "en", storedOrder: legacyOrder, storedEnabled: legacyEnabled)
        let seededWrites = store.writeLog.count
        await vm.loadDictionaries()

        let spanish = try XCTUnwrap(vm.dictionaries.first { $0.id == "eng-spa" })
        XCTAssertTrue(spanish.isEnabled, "enabled-if-any: the row is ON because one direction was ON")
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled))
        XCTAssertEqual(settings.enabledSources, Set(bundledSources),
                       "the stored set now holds BOTH directions — relevance search needs no change")
        XCTAssertTrue(settings.isEnabled(source: "freedict-eng-spa"))
        XCTAssertEqual(store.writeLog.dropFirst(seededWrites).filter { $0 == "enabled_sources" }.count, 1,
                       "migrated once; a load must not churn the enabled set")

        // Second load: already migrated → no further enabled-set write.
        let afterFirst = store.writeLog.filter { $0 == "enabled_sources" }.count
        await vm.loadDictionaries()
        XCTAssertEqual(store.writeLog.filter { $0 == "enabled_sources" }.count, afterFirst)

        // Contrast: a user who had the WHOLE Spanish pair off (and Russian off)
        // stays off — migration never switches a fully-disabled pair on.
        let (vm2, settings2, _) = makeViewModel(languageCode: "en", storedOrder: legacyOrder,
                                                storedEnabled: ["wordnet", "wordnet-arb-eng"])
        await vm2.loadDictionaries()
        XCTAssertEqual(vm2.dictionaries.map(\.id), ["eng", "eng-spa", "eng-rus", "arb-eng"])
        XCTAssertEqual(vm2.dictionaries.map(\.isEnabled), [true, false, false, true])
        XCTAssertEqual(settings2.enabledSources, ["wordnet", "wordnet-arb-eng"])
    }

    /// Pre-store the §2b "before" order → persisted "after" order.
    @MainActor
    func testLegacyInterleavedOrderIsGroupedOnLoad() async throws {
        try await seedBundled()
        let before = ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-arb-eng", "wordnet-spa-eng"]
        let after = ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "openrussian", "wordnet-arb-eng"]
        let (vm, settings, _) = makeViewModel(languageCode: "en", storedOrder: before)

        await vm.loadDictionaries()

        XCTAssertEqual(settings.dictionaryOrder, after, "pair joins its earliest member; everything else keeps its order")
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-spa", "eng-rus", "arb-eng"])
        XCTAssertEqual(vm.dictionaries[1].pair.sourceIDs, ["freedict-eng-spa", "wordnet-spa-eng"],
                       "FreeDict was the earliest member, so it leads the pair")
        assertGrouped(settings.dictionaryOrder, permutationOf: bundledSources)

        // Idempotent on the next load.
        await vm.loadDictionaries()
        XCTAssertEqual(settings.dictionaryOrder, after)
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng", "eng-spa", "eng-rus", "arb-eng"])

        // A stored order that references a removed source and misses a new
        // one is reconciled first, then grouped: the stale ID is dropped and
        // the newcomer appended — with its sibling pulled up beside it.
        let (vm2, settings2, _) = makeViewModel(languageCode: "en",
                                                storedOrder: ["ghost", "wordnet-spa-eng", "wordnet", "openrussian"])
        await vm2.loadDictionaries()
        XCTAssertEqual(settings2.dictionaryOrder,
                       ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian", "wordnet-arb-eng"])
        XCTAssertEqual(vm2.dictionaries.map(\.id), ["eng-spa", "eng", "eng-rus", "arb-eng"])
    }

    /// #74: nil order, `es` → ids `[eng-spa, eng, eng-rus, arb-eng]`, members
    /// `wordnet-spa-eng` before `freedict-eng-spa`; second load idempotent.
    @MainActor
    func testFirstLaunchSpanishPutsSpanishPairFirst() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "es")

        await vm.loadDictionaries()

        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng-spa", "eng", "eng-rus", "arb-eng"])
        XCTAssertEqual(settings.dictionaryOrder,
                       ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian", "wordnet-arb-eng"],
                       "the #74 es default is persisted unchanged — it is already grouped")
        XCTAssertEqual(vm.dictionaries.first?.pair.sourceIDs, ["wordnet-spa-eng", "freedict-eng-spa"],
                       "Spanish WordNet stacks above FreeDict (the #91 detail order)")
        XCTAssertEqual(vm.dictionaries.map(\.displayName),
                       ["Español – Inglés", "Inglés", "Ruso – Inglés", "Árabe – Inglés"],
                       "titles follow the in-app UI language, not the process locale")
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled))

        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), ["eng-spa", "eng", "eng-rus", "arb-eng"], "second load idempotent")
        XCTAssertEqual(settings.dictionaryOrder,
                       ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian", "wordnet-arb-eng"])

        // The other shipped languages, same seed (table in DESIGN_DOC §2c).
        let (ru, _, _) = makeViewModel(languageCode: "ru")
        await ru.loadDictionaries()
        XCTAssertEqual(ru.dictionaries.map(\.id), ["eng-rus", "eng", "eng-spa", "arb-eng"])
        XCTAssertEqual(ru.dictionaries.map(\.displayName),
                       ["Русский – Английский", "Английский", "Испанский – Английский", "Арабский – Английский"])
        let ar = makeViewModel(languageCode: "ar").0
        await ar.loadDictionaries()
        XCTAssertEqual(ar.dictionaries.map(\.id), ["arb-eng", "eng", "eng-rus", "eng-spa"])
        // RTL: Foundation wraps each format argument in bidi isolates
        // (U+2068 FSI … U+2069 PDI) so the names never reorder across the dash.
        XCTAssertEqual(ar.dictionaries.first?.displayName, "\u{2068}العربية\u{2069} – \u{2068}الإنجليزية\u{2069}")
    }

    /// Static, no DB: `eng-spa` → "Spanish – English" (en) /
    /// "Испанский – Английский" (ru); `eng` → "English"; custom → raw name;
    /// unknown `deu` → "German" (ICU resolves alpha-3; pinned here).
    func testDisplayNamesPerLocale() {
        func pair(_ id: String, _ languages: [String], _ sources: [String], custom: Bool = false) -> DictionaryPair {
            DictionaryPair(id: id, languages: languages, isCustom: custom,
                           sources: sources.map { SourceStat(source: $0, displayName: "Raw \($0)", count: 1) })
        }
        let spanish = pair("eng-spa", ["eng", "spa"], ["freedict-eng-spa", "wordnet-spa-eng"])
        let english = pair("eng", ["eng"], ["wordnet"])
        let russian = pair("eng-rus", ["eng", "rus"], ["openrussian"])
        let arabic = pair("arb-eng", ["arb", "eng"], ["wordnet-arb-eng"])
        let custom = pair("custom:test_import_fixture", [], ["test_import_fixture"], custom: true)
        let en = Locale(identifier: "en"), ru = Locale(identifier: "ru")
        let es = Locale(identifier: "es"), ar = Locale(identifier: "ar")
        let el = Locale(identifier: "el")

        // English UI.
        XCTAssertEqual(SettingsViewModel.displayName(for: spanish, locale: en), "Spanish – English")
        XCTAssertEqual(SettingsViewModel.displayName(for: russian, locale: en), "Russian – English")
        XCTAssertEqual(SettingsViewModel.displayName(for: arabic, locale: en), "Arabic – English",
                       "the non-English language leads even though 'arb' sorts before 'eng' in the key")
        XCTAssertEqual(SettingsViewModel.displayName(for: english, locale: en), "English",
                       "PM decision #1: never 'English – English'")
        XCTAssertTrue(SettingsViewModel.displayName(for: spanish, locale: en).contains("\u{2013}"),
                      "U+2013 en dash with spaces, matching the seed's display names")
        XCTAssertFalse(SettingsViewModel.displayName(for: spanish, locale: en).contains("("),
                       "PM decision #3: no provider parenthetical in the row title")

        // Other shipped UI languages use the catalog names.
        XCTAssertEqual(SettingsViewModel.displayName(for: spanish, locale: ru), "Испанский – Английский")
        XCTAssertEqual(SettingsViewModel.displayName(for: english, locale: ru), "Английский")
        XCTAssertEqual(SettingsViewModel.displayName(for: arabic, locale: ru), "Арабский – Английский")
        XCTAssertEqual(SettingsViewModel.displayName(for: spanish, locale: es), "Español – Inglés")
        XCTAssertEqual(SettingsViewModel.displayName(for: english, locale: es), "Inglés")
        XCTAssertEqual(SettingsViewModel.displayName(for: spanish, locale: ar),
                       "\u{2068}الإسبانية\u{2069} – \u{2068}الإنجليزية\u{2069}",
                       "Arabic: catalog names, each bidi-isolated by Foundation's RTL formatting")
        XCTAssertEqual(SettingsViewModel.displayName(for: english, locale: ar), "الإنجليزية")

        // Greek UI (Issue #88): catalog names from el.lproj, LTR, no isolates.
        let greek = pair("ell-eng", ["ell", "eng"], DictAppTests.greekSourceIDs)
        XCTAssertEqual(SettingsViewModel.displayName(for: greek, locale: el), "Ελληνικά – Αγγλικά")
        XCTAssertEqual(SettingsViewModel.displayName(for: spanish, locale: el), "Ισπανικά – Αγγλικά")
        XCTAssertEqual(SettingsViewModel.displayName(for: russian, locale: el), "Ρωσικά – Αγγλικά")
        XCTAssertEqual(SettingsViewModel.displayName(for: arabic, locale: el), "Αραβικά – Αγγλικά")
        XCTAssertEqual(SettingsViewModel.displayName(for: english, locale: el), "Αγγλικά")
        XCTAssertEqual(SettingsViewModel.displayName(for: greek, locale: en), "Greek – English")
        XCTAssertFalse(SettingsViewModel.displayName(for: greek, locale: el).contains("\u{2068}"),
                       "Greek is LTR: Foundation adds no bidi isolates")

        // Custom → raw metadata name, never a pair title, in every locale.
        for locale in [en, ru, es, ar, el] {
            XCTAssertEqual(SettingsViewModel.displayName(for: custom, locale: locale), "Raw test_import_fixture")
        }
        let namedLikePair = pair("custom:mydict-eng-spa", [], ["mydict-eng-spa"], custom: true)
        XCTAssertEqual(SettingsViewModel.displayName(for: namedLikePair, locale: en), "Raw mydict-eng-spa")
        let noSources = DictionaryPair(id: "custom:ghost", languages: [], isCustom: true, sources: [])
        XCTAssertEqual(SettingsViewModel.displayName(for: noSources, locale: en), "custom:ghost",
                       "a custom pair with no resolvable source falls back to its id")

        // Unknown ISO-639-3 code. Pinned behaviour of
        // `Locale.localizedString(forLanguageCode:)` on this toolchain: ICU
        // accepts alpha-3 and resolves it to the display name (verified on
        // iOS 26 / Xcode 26.4). If a future SDK stops resolving alpha-3, the
        // production fallback is the raw code and this expectation moves to it.
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "deu", locale: en), "German")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "deu", locale: ru), "немецкий")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "fra", locale: es), "francés")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "zzz", locale: en), "zzz",
                       "an unresolvable code degrades to the raw code — never empty, never a crash")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "", locale: en), "")
        let german = pair("deu-eng", ["deu", "eng"], ["freedict-deu-eng"])
        XCTAssertEqual(SettingsViewModel.displayName(for: german, locale: en), "German – English")
        let frenchGerman = pair("deu-fra", ["deu", "fra"], ["freedict-fra-deu"])
        XCTAssertEqual(SettingsViewModel.displayName(for: frenchGerman, locale: en), "German – French",
                       "a pair without English keeps sorted-key order")

        // Shipped codes go through the catalog, not ICU (capitalisation differs).
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "rus", locale: ru), "Русский")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "spa", locale: es), "Español")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "arb", locale: ar), "العربية")
        XCTAssertEqual(SettingsViewModel.languageName(iso3: "eng", locale: en), "English")

        // Degenerate pair shapes never crash: 3+ languages fall back to the id.
        let odd = pair("deu-eng-fra", ["deu", "eng", "fra"], ["x"])
        XCTAssertEqual(SettingsViewModel.displayName(for: odd, locale: en), "deu-eng-fra")
        let empty = DictionaryPair(id: "eng", languages: [], isCustom: false, sources: [])
        XCTAssertEqual(SettingsViewModel.displayName(for: empty, locale: en), "eng")
    }
}

// MARK: - Issue #91: Dictionary info (i) detail

/// Pure presentation helpers behind the (i) detail (`SettingsViewModel`
/// statics) plus seed-backed license checks. Skeleton for QA, DESIGN_DOC §6a.
final class DictionaryInfoDetailTests: XCTestCase {

    // MARK: Fixtures

    private let en = Locale(identifier: "en")
    private let ru = Locale(identifier: "ru")
    private let es = Locale(identifier: "es")
    private let ar = Locale(identifier: "ar")
    private let el = Locale(identifier: "el")

    private let bundledSourceIDs = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng",
                                    "freedict-ell-eng", "wordnet-ell-eng", "freedict-eng-ell", "wordnet-eng-ell"]

    private func stat(_ source: String, count: Int = 1, license: String = "", version: String = "") -> SourceStat {
        SourceStat(source: source, displayName: "Raw \(source)", count: count, license: license, version: version)
    }

    private func pair(_ id: String, _ languages: [String], _ sources: [SourceStat], custom: Bool = false) -> DictionaryPair {
        DictionaryPair(id: id, languages: languages, isCustom: custom, sources: sources)
    }

    /// Foundation wraps format arguments in bidi isolates (U+2068 … U+2069)
    /// for RTL locales; strip them to compare the visible text.
    private func stripIsolates(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
    }

    // MARK: infoSources

    /// `eng-spa` with sources [freedict-eng-spa, wordnet-spa-eng] → WordNet
    /// first; reversed input gives the same result.
    func testInfoSourcesPutTitleDirectionFirst() throws {
        let freedict = stat("freedict-eng-spa", count: 58_946, license: "GPL", version: "2023")
        let wordnet = stat("wordnet-spa-eng", count: 36_371, license: "WN", version: "1.0")

        // en/ru/ar default member order (count-desc): FreeDict first.
        let enOrder = pair("eng-spa", ["eng", "spa"], [freedict, wordnet])
        XCTAssertEqual(SettingsViewModel.infoSources(for: enOrder).map(\.source),
                       ["wordnet-spa-eng", "freedict-eng-spa"],
                       "title-direction (Spanish → English) block first, regardless of user order")
        // es default member order: WordNet first — same detail order.
        let esOrder = pair("eng-spa", ["eng", "spa"], [wordnet, freedict])
        XCTAssertEqual(SettingsViewModel.infoSources(for: esOrder).map(\.source),
                       ["wordnet-spa-eng", "freedict-eng-spa"],
                       "detail order must not depend on the member order")

        // The full SourceStat values travel unchanged (no field is dropped).
        let first = try XCTUnwrap(SettingsViewModel.infoSources(for: enOrder).first)
        XCTAssertEqual(first, wordnet)

        // Rank 3: a source without a direction (monolingual / custom) goes
        // after both directions. Bundled IDs are an exact allowlist, so a
        // custom import never parses as a direction.
        let stray = stat("mydict-eng-spa")
        let mixed = pair("eng-spa", ["eng", "spa"], [stray, freedict, wordnet])
        XCTAssertEqual(SettingsViewModel.infoSources(for: mixed).map(\.source),
                       ["wordnet-spa-eng", "freedict-eng-spa", "mydict-eng-spa"])

        // Arabic: key `arb-eng` sorts arb first and the title is Arabic –
        // English, so the arb → eng source ranks as the title direction.
        let arabic = pair("arb-eng", ["arb", "eng"], [stray, stat("wordnet-arb-eng")])
        XCTAssertEqual(SettingsViewModel.infoSources(for: arabic).map(\.source),
                       ["wordnet-arb-eng", "mydict-eng-spa"])
    }

    /// Single-source, monolingual and custom pairs unchanged; output is a
    /// permutation of the input.
    func testInfoSourcesIsStablePermutation() throws {
        let english = pair("eng", ["eng"], [stat("wordnet")])
        XCTAssertEqual(SettingsViewModel.infoSources(for: english).map(\.source), ["wordnet"])

        let russian = pair("eng-rus", ["eng", "rus"], [stat("openrussian")])
        XCTAssertEqual(SettingsViewModel.infoSources(for: russian).map(\.source), ["openrussian"],
                       "legacy bare-ID bilingual source survives untouched")

        let custom = pair("custom:test_import_fixture", [], [stat("test_import_fixture")], custom: true)
        XCTAssertEqual(SettingsViewModel.infoSources(for: custom).map(\.source), ["test_import_fixture"])

        // Empty pair: no crash, no invented source.
        let empty = pair("custom:ghost", [], [], custom: true)
        XCTAssertTrue(SettingsViewModel.infoSources(for: empty).isEmpty)

        // Stability among equal ranks: sources without a direction keep
        // their relative order behind the two directions.
        let x = stat("custom_x"), y = stat("custom_y")
        let freedict = stat("freedict-eng-spa"), wordnet = stat("wordnet-spa-eng")
        let cases: [([SourceStat], [String])] = [
            ([x, freedict, y, wordnet], ["wordnet-spa-eng", "freedict-eng-spa", "custom_x", "custom_y"]),
            ([y, wordnet, x, freedict], ["wordnet-spa-eng", "freedict-eng-spa", "custom_y", "custom_x"]),
            ([wordnet, freedict, x, y], ["wordnet-spa-eng", "freedict-eng-spa", "custom_x", "custom_y"]),
        ]
        for (input, expected) in cases {
            let output = SettingsViewModel.infoSources(for: pair("eng-spa", ["eng", "spa"], input))
            XCTAssertEqual(output.map(\.source), expected, "input \(input.map(\.source))")
            XCTAssertEqual(output.count, input.count, "never adds or drops a source")
            XCTAssertEqual(Set(output), Set(input), "output is a permutation of the input")
        }
    }

    // MARK: providerName / infoBlockTitle

    /// wordnet* → "WordNet", freedict-eng-spa → "FreeDict", openrussian →
    /// "OpenRussian", custom → nil; `infoBlockTitle` falls back to the source ID.
    func testProviderNameBrands() throws {
        let expected: [String: String] = [
            "wordnet": "WordNet",
            "wordnet-spa-eng": "WordNet",
            "wordnet-arb-eng": "WordNet",
            "freedict-eng-spa": "FreeDict",
            "openrussian": "OpenRussian",
        ]
        for (source, brand) in expected {
            XCTAssertEqual(SettingsViewModel.providerName(for: stat(source)), brand, source)
            XCTAssertEqual(SettingsViewModel.infoBlockTitle(for: stat(source)), brand,
                           "PM decision #4: header is the brand, not the seed display_name")
        }

        // Custom imports: no provider, header is the raw source ID (never
        // the metadata display name, which may carry a parenthetical).
        for source in ["test_import_fixture", "mydict-eng-spa", "WordNet"] {
            let custom = SourceStat(source: source, displayName: "Fancy (Provider)", count: 3)
            XCTAssertNil(SettingsViewModel.providerName(for: custom), "'\(source)' is custom")
            XCTAssertEqual(SettingsViewModel.infoBlockTitle(for: custom), source)
        }

        // The brand is independent of the seed's display_name.
        let seeded = SourceStat(source: "freedict-eng-spa", displayName: "English – Spanish (FreeDict)", count: 1)
        XCTAssertEqual(SettingsViewModel.infoBlockTitle(for: seeded), "FreeDict")
        XCTAssertFalse(SettingsViewModel.infoBlockTitle(for: seeded).contains("("))
    }

    // MARK: languageSummary

    /// en/ru direction strings ("Spanish → English", "Испанский → Английский"),
    /// monolingual → language name, custom → nil.
    func testLanguageSummaryPerLocale() throws {
        let freedict = stat("freedict-eng-spa")
        let wordnetSpa = stat("wordnet-spa-eng")
        let openrussian = stat("openrussian")
        let wordnet = stat("wordnet")
        let custom = stat("test_import_fixture")

        XCTAssertEqual(SettingsViewModel.languageSummary(for: freedict, locale: en), "English → Spanish")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnetSpa, locale: en), "Spanish → English")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: openrussian, locale: en), "Russian → English")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnet, locale: en), "English",
                       "monolingual → just the language name, no arrow")

        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnetSpa, locale: ru), "Испанский → Английский",
                       "resolved through ru.lproj, not the test host's device language")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: freedict, locale: ru), "Английский → Испанский")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnet, locale: ru), "Английский")

        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnetSpa, locale: es), "Español → Inglés")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnet, locale: es), "Inglés")

        XCTAssertEqual(SettingsViewModel.languageSummary(for: stat("wordnet-ell-eng"), locale: el), "Ελληνικά → Αγγλικά")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: stat("freedict-eng-ell"), locale: el), "Αγγλικά → Ελληνικά")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnetSpa, locale: el), "Ισπανικά → Αγγλικά")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: wordnet, locale: el), "Αγγλικά")

        for locale in [en, ru, es, ar, el] {
            XCTAssertNil(SettingsViewModel.languageSummary(for: custom, locale: locale),
                         "custom import has no direction row in \(locale.identifier)")
            XCTAssertNil(SettingsViewModel.languageSummary(for: stat("mydict-eng-spa"), locale: locale),
                         "a custom ID that merely looks like a pair is still custom")
        }
    }

    /// `wordnet-arb-eng` with `ar` contains "←" and no "→"; Arabic names.
    func testLanguageSummaryArabicUsesLeftArrow() throws {
        let arabic = try XCTUnwrap(SettingsViewModel.languageSummary(for: stat("wordnet-arb-eng"), locale: ar))
        XCTAssertTrue(arabic.contains("\u{2190}"), "Arabic uses U+2190 ←; got \(arabic)")
        XCTAssertFalse(arabic.contains("\u{2192}"), "no → in RTL; got \(arabic)")
        XCTAssertEqual(stripIsolates(arabic), "العربية ← الإنجليزية",
                       "from-language first in logical order, both names Arabic")

        let spanish = try XCTUnwrap(SettingsViewModel.languageSummary(for: stat("freedict-eng-spa"), locale: ar))
        XCTAssertEqual(stripIsolates(spanish), "الإنجليزية ← الإسبانية")

        // The LTR locales keep →, never ←.
        for locale in [en, ru, es, el] {
            let summary = try XCTUnwrap(SettingsViewModel.languageSummary(for: stat("wordnet-arb-eng"), locale: locale))
            XCTAssertTrue(summary.contains("\u{2192}"), "\(locale.identifier): \(summary)")
            XCTAssertFalse(summary.contains("\u{2190}"), "\(locale.identifier): \(summary)")
        }
        XCTAssertEqual(SettingsViewModel.languageSummary(for: stat("wordnet-arb-eng"), locale: en), "Arabic → English")
    }

    // MARK: Catalog

    /// Every `dictionaryInfo.*` key resolves in en/ru/es/ar/el lproj.
    func testDictionaryInfoKeysResolveInAllLocales() throws {
        let keys = [
            "dictionaryInfo.button.accessibilityLabel %@",
            "dictionaryInfo.direction",
            "dictionaryInfo.direction.value %@ %@",
            "dictionaryInfo.language",
            "dictionaryInfo.sourceID",
            "dictionaryInfo.version",
            "dictionaryInfo.entries",
            "dictionaryInfo.license",
            "dictionaryInfo.noMetadata",
        ]
        // Keys whose value is legitimately identical across locales.
        let sameAsEnglishAllowed: Set<String> = ["dictionaryInfo.direction.value %@ %@"]

        var english: [String: String] = [:]
        for code in ["en", "ru", "es", "ar", "el"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"),
                                     "'\(code).lproj' must be compiled into the app bundle")
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "\u{0}MISSING", table: nil)
                XCTAssertNotEqual(value, "\u{0}MISSING", "'\(key)' missing in \(code).lproj")
                XCTAssertNotEqual(value, key, "'\(key)' renders the raw key in \(code).lproj")
                XCTAssertFalse(value.isEmpty, "'\(key)' is empty in \(code).lproj")
                if code == "en" {
                    english[key] = value
                } else if !sameAsEnglishAllowed.contains(key) {
                    XCTAssertNotEqual(value, english[key], "'\(key)' in \(code).lproj falls back to English")
                }
                // The SwiftUI view resolves plain labels through this helper.
                if !key.contains("%") {
                    XCTAssertEqual(SettingsViewModel.localizedString(key, locale: Locale(identifier: code)), value,
                                   "in-app-language helper must read \(code).lproj for '\(key)'")
                }
            }
        }

        // The retired provider row key and the old view's literal keys are gone.
        let enPath = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let enBundle = try XCTUnwrap(Bundle(path: enPath))
        for removed in ["dictionaryInfo.provider", "Full Name", "Word Count",
                        "No detailed metadata available for this dictionary."] {
            XCTAssertEqual(enBundle.localizedString(forKey: removed, value: "\u{0}MISSING", table: nil), "\u{0}MISSING",
                           "'\(removed)' must no longer be in the catalog")
        }

        // Spot-check concrete values the UI shows.
        XCTAssertEqual(SettingsViewModel.localizedString("dictionaryInfo.license", locale: ru), "Лицензия")
        XCTAssertEqual(SettingsViewModel.localizedString("dictionaryInfo.license", locale: es), "Licencia")
        XCTAssertEqual(SettingsViewModel.localizedString("dictionaryInfo.license", locale: ar), "الترخيص")
        XCTAssertEqual(SettingsViewModel.localizedString("dictionaryInfo.license", locale: el), "Άδεια χρήσης")
        XCTAssertEqual(SettingsViewModel.localizedString("dictionaryInfo.entries", locale: el), "Λήμματα")
        XCTAssertEqual(SettingsViewModel.infoButtonLabel(for: "Spanish – English", locale: en),
                       "Details for Spanish – English")
        XCTAssertEqual(SettingsViewModel.infoButtonLabel(for: "Испанский – Английский", locale: ru),
                       "Подробнее: Испанский – Английский")
        XCTAssertEqual(SettingsViewModel.infoButtonLabel(for: "Español – Inglés", locale: es),
                       "Detalles de Español – Inglés")
        XCTAssertEqual(stripIsolates(SettingsViewModel.infoButtonLabel(for: "العربية", locale: ar)), "تفاصيل العربية")
        XCTAssertEqual(SettingsViewModel.infoButtonLabel(for: "Ελληνικά – Αγγλικά", locale: el),
                       "Λεπτομέρειες: Ελληνικά – Αγγλικά")
        // An unshipped locale falls back to the base table, never the raw key.
        XCTAssertEqual(SettingsViewModel.localizedString("dictionaryInfo.license", locale: Locale(identifier: "de")),
                       "License")
    }

    // MARK: DictionaryItem

    /// Items differing only in `isEnabled` are unequal; equal items hash equal.
    func testDictionaryItemIsHashable() throws {
        let spanish = pair("eng-spa", ["eng", "spa"], [stat("freedict-eng-spa"), stat("wordnet-spa-eng")])
        let on = DictionaryItem(pair: spanish, displayName: "Spanish – English", isEnabled: true)
        let onCopy = DictionaryItem(pair: spanish, displayName: "Spanish – English", isEnabled: true)
        let off = DictionaryItem(pair: spanish, displayName: "Spanish – English", isEnabled: false)

        XCTAssertEqual(on, onCopy)
        XCTAssertEqual(on.hashValue, onCopy.hashValue, "equal items must hash equal")
        XCTAssertNotEqual(on, off, "isEnabled participates in equality")
        XCTAssertEqual(on.id, off.id, "…but the Identifiable id is the pair key")

        let renamed = DictionaryItem(pair: spanish, displayName: "Español – Inglés", isEnabled: true)
        XCTAssertNotEqual(on, renamed)
        let reorderedMembers = DictionaryItem(
            pair: pair("eng-spa", ["eng", "spa"], [stat("wordnet-spa-eng"), stat("freedict-eng-spa")]),
            displayName: "Spanish – English", isEnabled: true)
        XCTAssertNotEqual(on, reorderedMembers, "member order is part of the pair value")

        let set: Set<DictionaryItem> = [on, onCopy, off]
        XCTAssertEqual(set.count, 2, "usable as a navigationDestination(item:) value")
    }

    // MARK: Seed-backed

    private var tempDir: URL?

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
        try await super.tearDown()
    }

    /// Clones the bundled seed (APFS clone, so no 100 MB copy) and opens it
    /// on `DatabaseService.shared`, so the real `fetchSourceStats()` SQL runs
    /// against the shipped metadata.
    private func seedSourceStats() async throws -> [SourceStat] {
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        let copy = dir.appendingPathComponent("seed.sqlite")
        try FileManager.default.copyItem(at: seedURL, to: copy)
        await DictAppTests.waitForHostAppLaunch()
        try await DatabaseService.shared.setup(path: copy.path)
        return try await DatabaseService.shared.fetchSourceStats()
    }

    /// Seed: each of the nine bundled sources has `license.count > 50` and a
    /// non-empty `version`.
    func testEveryBundledSourceStatCarriesLicenseAndVersion() async throws {
        let stats = try await seedSourceStats()
        let bySource = Dictionary(uniqueKeysWithValues: stats.map { ($0.source, $0) })
        XCTAssertEqual(Set(stats.map(\.source)), Set(bundledSourceIDs),
                       "the seed ships exactly the nine bundled sources (#87)")
        for source in bundledSourceIDs {
            let s = try XCTUnwrap(bySource[source], "\(source) missing from fetchSourceStats()")
            XCTAssertGreaterThan(s.license.count, 50, "\(source): license must be real text (AC 4)")
            XCTAssertFalse(s.version.isEmpty, "\(source): version")
            XCTAssertGreaterThan(s.count, 0, "\(source): entries")
            XCTAssertNotNil(SettingsViewModel.providerName(for: s), "\(source): bundled → has a provider")
            XCTAssertNotNil(SettingsViewModel.languageSummary(for: s, locale: en), "\(source): bundled → direction/language")
        }
    }

    /// Seed: `eng-spa` has two sources, `infoSources` → WordNet then FreeDict,
    /// both licenses non-empty, FreeDict names CC BY-SA 3.0 (#106).
    func testSpanishPairInfoHasBothSourcesWithLicenses() async throws {
        let stats = try await seedSourceStats()
        for code in ["en", "ru", "es", "ar", "el"] {
            let order = DictionaryGrouping.groupedOrder(
                DictionaryDefaults.defaultOrder(forLanguageCode: code, sources: stats.map(\.source)))
            let pairs = DictionaryGrouping.pairs(from: stats, order: order)
            XCTAssertEqual(Set(pairs.map(\.id)), ["eng", "eng-rus", "eng-spa", "arb-eng", "ell-eng"], code)
            let spanish = try XCTUnwrap(pairs.first { $0.id == "eng-spa" }, code)
            XCTAssertEqual(Set(spanish.sourceIDs), ["wordnet-spa-eng", "freedict-eng-spa"], code)

            let info = SettingsViewModel.infoSources(for: spanish)
            XCTAssertEqual(info.map(\.source), ["wordnet-spa-eng", "freedict-eng-spa"],
                           "\(code): WordNet (title direction) above FreeDict, whatever the member order")
            XCTAssertEqual(info.map { SettingsViewModel.infoBlockTitle(for: $0) }, ["WordNet", "FreeDict"], code)
            for s in info {
                XCTAssertFalse(s.license.isEmpty, "\(code): \(s.source) license")
            }
            XCTAssertTrue(info[1].license.contains("Attribution-ShareAlike 3.0"),
                          "FreeDict ships under CC BY-SA 3.0 (#106); got: \(info[1].license.prefix(120))")
            XCTAssertNotEqual(info[0].license, info[1].license, "each block carries its own license")

            // Single-source pairs carry exactly their one licensed source.
            for (id, source) in [("eng", "wordnet"), ("eng-rus", "openrussian"), ("arb-eng", "wordnet-arb-eng")] {
                let p = try XCTUnwrap(pairs.first { $0.id == id })
                let only = SettingsViewModel.infoSources(for: p)
                XCTAssertEqual(only.map(\.source), [source], "\(code): \(id)")
                XCTAssertFalse(only.first?.license.isEmpty ?? true, "\(code): \(source) license")
            }
        }
    }
}

// MARK: - Issue #105: Dictionary order refresh
//
// DESIGN_DOC.md §7a plus PM decisions 2 and 3. Same-file extensions, so the
// bodies can use each class's private helpers. Imports go through the real
// user path: `ManageDictionariesViewModel(settingsService:)` + `await
// performImport(url:)` with the bundled `test_import_fixture` (.json = 10
// rows, .sqlite = 10 other rows, both source `test_import_fixture`), sharing
// the `SettingsService` of the VM under test. Reload the SAME
// `SettingsViewModel`; a fresh one is a relaunch.

extension SettingsServiceTests {
    /// §3b, nil case: `nil` means "all enabled". An import must not
    /// materialise it, or today's source list would be frozen into the store.
    func testEnableImportedSourceLeavesNilUntouched() throws {
        let (s, store) = service()
        XCTAssertNil(s.enabledSources, "precondition: nothing stored (all enabled)")

        s.enableImportedSource("x")

        XCTAssertNil(s.enabledSources, "nil stays nil")
        XCTAssertTrue(s.isEnabled(source: "x"), "the import is ON through the nil default")
        XCTAssertTrue(s.isEnabled(source: "wordnet"), "and so is every other source")
        XCTAssertEqual(store.writeLog, [], "no store write at all")
        XCTAssertTrue(store.keys.isEmpty, "no key materialised; got \(store.keys)")
    }

    /// PR #107 review: an import named like one direction of a bundled pair
    /// switches the whole pair on, so search never sees half a pair.
    func testEnableImportedSourceNamedLikeBundledEnablesWholePair() throws {
        let (s, store) = service()
        s.enabledSources = ["wordnet"]
        let seeded = store.writeLog.count

        s.enableImportedSource("wordnet-spa-eng")
        XCTAssertEqual(s.enabledSources, ["wordnet", "wordnet-spa-eng", "freedict-eng-spa"])
        XCTAssertFalse(s.isEnabled(source: "openrussian"), "other pairs stay OFF")
        XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["enabled_sources"], "exactly one write")

        s.enableImportedSource("freedict-eng-spa")
        XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["enabled_sources"], "no churn when the pair is already on")
    }

    /// §3b, non-nil case: `{"wordnet"}` + "x" → `{"wordnet", "x"}` in exactly
    /// one `["enabled_sources"]` write; a repeat call and an already-present
    /// ID write nothing; `dictionary_order` is never written.
    func testEnableImportedSourceAddsToMaterialisedSet() throws {
        let (s, store) = service()
        s.enabledSources = ["wordnet"]
        let seeded = store.writeLog.count

        s.enableImportedSource("x")
        XCTAssertEqual(s.enabledSources, ["wordnet", "x"])
        XCTAssertTrue(s.isEnabled(source: "x"))
        XCTAssertFalse(s.isEnabled(source: "openrussian"), "a source the user had OFF stays OFF")
        XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["enabled_sources"], "exactly one write")

        // Idempotent: a repeat call and an ID already in the set write nothing.
        s.enableImportedSource("x")
        s.enableImportedSource("wordnet")
        XCTAssertEqual(s.enabledSources, ["wordnet", "x"])
        XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["enabled_sources"], "no churn on a repeat")

        // The enable rule never touches the order.
        XCTAssertFalse(store.writeLog.contains("dictionary_order"), "got \(store.writeLog)")
        XCTAssertNil(s.dictionaryOrder)

        // Edge: every dictionary OFF (`[]`) is a materialised set too; the
        // import turns on itself and nothing else.
        s.enabledSources = []
        let emptied = store.writeLog.count
        s.enableImportedSource("y")
        XCTAssertEqual(s.enabledSources, ["y"])
        XCTAssertFalse(s.isEnabled(source: "wordnet"))
        XCTAssertEqual(Array(store.writeLog.dropFirst(emptied)), ["enabled_sources"])
        // The stored shape is unchanged: a JSON array of source IDs.
        let raw = try JSONDecoder().decode([String].self, from: XCTUnwrap(store.data(forKey: "enabled_sources")))
        XCTAssertEqual(raw, ["y"])
    }

    /// PM decision 3, nil case: `appendImportedSourceToOrder("x")` keeps
    /// `dictionaryOrder` nil and writes nothing.
    func testAppendImportedSourceToOrderLeavesNilUntouched() throws {
        let (s, store) = service()
        XCTAssertNil(s.dictionaryOrder, "precondition: no order stored yet")

        s.appendImportedSourceToOrder("x")

        XCTAssertNil(s.dictionaryOrder, "the first Settings load derives the default, not the import")
        XCTAssertEqual(store.writeLog, [])
        XCTAssertTrue(store.keys.isEmpty, "no key materialised; got \(store.keys)")

        // A materialised enabled set changes nothing, and is not touched.
        s.enabledSources = ["wordnet"]
        let seeded = store.writeLog.count
        s.appendImportedSourceToOrder("x")
        XCTAssertNil(s.dictionaryOrder)
        XCTAssertEqual(s.enabledSources, ["wordnet"])
        XCTAssertEqual(store.writeLog.count, seeded, "got \(store.writeLog.dropFirst(seeded))")
    }

    /// PM decision 3, non-nil case: a stored order lacking "x" gets it at the
    /// end in exactly one `["dictionary_order"]` write; a repeat call and an
    /// already-present ID write nothing; `enabled_sources` is never written.
    func testAppendImportedSourceToOrderAppendsOnceAtEnd() throws {
        let (s, store) = service()
        let bundled = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"]
        s.dictionaryOrder = bundled
        let seeded = store.writeLog.count

        s.appendImportedSourceToOrder("x")
        XCTAssertEqual(s.dictionaryOrder, bundled + ["x"], "appended after every pair")
        XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["dictionary_order"], "exactly one write")

        s.appendImportedSourceToOrder("x")
        s.appendImportedSourceToOrder("openrussian")
        XCTAssertEqual(s.dictionaryOrder, bundled + ["x"], "no duplicate, nothing moves")
        XCTAssertEqual(Array(store.writeLog.dropFirst(seeded)), ["dictionary_order"], "no churn on a repeat")

        // A second import lands after the first (import order, not count).
        s.appendImportedSourceToOrder("y")
        XCTAssertEqual(s.dictionaryOrder, bundled + ["x", "y"])

        XCTAssertFalse(store.writeLog.contains("enabled_sources"), "got \(store.writeLog)")
        XCTAssertNil(s.enabledSources)

        // Edge: a file named like a missing bundled direction joins its pair
        // (I2 via `groupedOrder`) instead of landing at the end.
        s.dictionaryOrder = ["wordnet", "freedict-eng-spa", "openrussian"]
        s.appendImportedSourceToOrder("wordnet-spa-eng")
        XCTAssertEqual(s.dictionaryOrder, ["wordnet", "freedict-eng-spa", "wordnet-spa-eng", "openrussian"],
                       "pair members stay contiguous")
    }
}

extension SettingsViewModelPairTests {
    private var fixtureSource: String { "test_import_fixture" }
    private var fixturePair: String { "custom:test_import_fixture" }
    /// The four bundled rows in the `en` default order.
    private var bundledPairs: [String] { ["eng", "eng-rus", "eng-spa", "arb-eng"] }
    /// What a user who switched Russian OFF has stored.
    private var allButRussian: Set<String> { Set(bundledSources).subtracting(["openrussian"]) }

    /// `SettingsViewModel.init` starts a load in a `Task` nobody awaits. Wait
    /// until it has published before importing: a load whose fetch predates
    /// the import but whose prefs read follows it would briefly drop the
    /// import from the stored order. That is a test artefact; in the app the
    /// init load is long done by the time Manage Dictionaries is reachable.
    @MainActor
    private func waitForInitialLoad(_ vm: SettingsViewModel,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(10)
        while vm.dictionaries.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(vm.dictionaries.isEmpty, "the init load must publish the bundled rows",
                       file: file, line: line)
    }

    /// A new VM over the SAME stored prefs: what a relaunch builds.
    @MainActor
    private func relaunchedViewModel(over settings: SettingsService) async throws -> SettingsViewModel {
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        let vm = SettingsViewModel(settingsService: settings, localization: localization)
        try await waitForInitialLoad(vm)
        return vm
    }

    /// Imports the bundled fixture through the Manage Dictionaries view model
    /// (the real user path) and checks it succeeded.
    @MainActor
    private func importFixture(_ ext: String, into settings: SettingsService,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "test_import_fixture", withExtension: ext),
                                "bundled .\(ext) fixture", file: file, line: line)
        let manage = ManageDictionariesViewModel(
            settingsService: settings,
            localization: LocalizationManager(settingsService: settings, bundle: .main)
        )
        await manage.performImport(url: url)
        XCTAssertEqual(manage.importResult, "Imported 10 entries from test_import_fixture",
                       "the .\(ext) import must succeed", file: file, line: line)
        XCTAssertFalse(manage.isImporting, file: file, line: line)
    }

    /// Runs `query` through the real `SearchViewModel` and waits for the
    /// debounced search to finish.
    @MainActor
    private func searchResults(_ search: SearchViewModel, for query: String,
                               file: StaticString = #filePath, line: UInt = #line) async throws -> [DictionaryEntry] {
        search.query = query
        search.onQueryChanged()
        let deadline = Date().addingTimeInterval(5)
        while search.isSearching, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(search.isSearching, "search for '\(query)' did not finish", file: file, line: line)
        XCTAssertNil(search.errorMessage, file: file, line: line)
        return search.results
    }

    /// PM decision 2, non-nil case, JSON and SQLite: stored set = bundled
    /// minus `openrussian`; load; import; the set gains `test_import_fixture`
    /// and still lacks `openrussian`; reload the same VM: custom row ON,
    /// `eng-rus` OFF.
    @MainActor
    func testImportEnablesSourceWhenUserHasDisabledOthers() async throws {
        try await seedBundled()
        for ext in ["json", "sqlite"] {
            // Fresh prefs and no fixture rows for each run.
            try await DatabaseService.shared.clearEntries(fromSource: fixtureSource)
            let (vm, settings, store) = makeViewModel(languageCode: "en", storedOrder: bundledSources,
                                                      storedEnabled: allButRussian)
            try await waitForInitialLoad(vm)
            XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "[\(ext)] precondition: no custom row")
            XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true], "[\(ext)] Russian OFF")
            let beforeImport = store.writeLog.count

            try await importFixture(ext, into: settings)

            XCTAssertEqual(settings.enabledSources, allButRussian.union([fixtureSource]),
                           "[\(ext)] the import is ON, Russian stays OFF")
            XCTAssertEqual(store.writeLog.dropFirst(beforeImport).filter { $0 == "enabled_sources" }.count, 1,
                           "[\(ext)] one enabled-set write")
            XCTAssertEqual(settings.dictionaryOrder, bundledSources + [fixtureSource],
                           "[\(ext)] appended to the stored order (PM decision 3)")

            await vm.loadDictionaries()   // the order screen's `.task`, same VM

            XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs + [fixturePair], "[\(ext)]")
            XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true, true],
                           "[\(ext)] custom row ON, eng-rus still OFF")
            XCTAssertEqual(vm.dictionaries.last?.count, 10, "[\(ext)] all fixture rows counted")
            XCTAssertEqual(settings.enabledSources, allButRussian.union([fixtureSource]),
                           "[\(ext)] the reload's normalisation keeps it")
            XCTAssertFalse(settings.isEnabled(source: "openrussian"), "[\(ext)]")
        }
    }

    /// PM decision 2, nil case: load, import (JSON), reload: custom row ON,
    /// `enabledSources` still nil, no `enabled_sources` in `writeLog`.
    @MainActor
    func testImportLeavesAllEnabledNil() async throws {
        try await seedBundled()
        let (vm, settings, store) = makeViewModel(languageCode: "en")
        try await waitForInitialLoad(vm)
        XCTAssertNil(settings.enabledSources, "precondition: all enabled")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources, "precondition: the init load stored the default")
        let afterLoad = store.writeLog.count

        try await importFixture("json", into: settings)
        let importWrites = Array(store.writeLog.dropFirst(afterLoad))
        XCTAssertEqual(importWrites, ["dictionary_order"],
                       "the import only appends to the order (PM decision 3) and never materialises nil")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources + [fixtureSource])
        let afterImport = store.writeLog.count

        await vm.loadDictionaries()

        let custom = try XCTUnwrap(vm.dictionaries.first { $0.id == fixturePair }, "the reload lists the import")
        XCTAssertTrue(custom.isEnabled)
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled))
        XCTAssertNil(settings.enabledSources, "nil stays nil: nothing frozen into the store")
        XCTAssertTrue(settings.isEnabled(source: fixtureSource))
        XCTAssertEqual(store.writeLog.count, afterImport,
                       "the reload writes nothing; got \(store.writeLog.dropFirst(afterImport))")
    }

    /// Unsupported `.txt`, a missing `.json`, a malformed `.json` and a
    /// `.sqlite` that is not a database: `enabledSources` and
    /// `dictionaryOrder` unchanged, no store writes, `importResult` set.
    @MainActor
    func testFailedImportDoesNotEnable() async throws {
        try await seedBundled()
        let (vm, settings, store) = makeViewModel(languageCode: "en", storedOrder: bundledSources,
                                                  storedEnabled: allButRussian)
        try await waitForInitialLoad(vm)
        let before = store.writeLog.count
        let manage = ManageDictionariesViewModel(
            settingsService: settings,
            localization: LocalizationManager(settingsService: settings, bundle: .main)
        )

        // 1) Unsupported extension: rejected before any read.
        let txt = tempDir.appendingPathComponent("test_import_fixture.txt")
        try Data("qaflux,a word".utf8).write(to: txt)
        await manage.performImport(url: txt)
        XCTAssertEqual(manage.importResult, "Unsupported file type: .txt")

        // 2) A .json that does not exist: `importJSON` throws on read.
        await manage.performImport(url: tempDir.appendingPathComponent("test_import_fixture.json"))
        let missing = try XCTUnwrap(manage.importResult, "a missing file must surface an error")
        XCTAssertFalse(missing.contains("Imported"), "got \(missing)")
        XCTAssertNotEqual(missing, "Unsupported file type: .txt", "the message is replaced")

        // 3) A .json that is not a word array: decoding throws.
        let malformed = tempDir.appendingPathComponent("malformed_dict.json")
        try Data(#"{"word": "qaflux"}"#.utf8).write(to: malformed)
        await manage.performImport(url: malformed)
        let decodeError = try XCTUnwrap(manage.importResult)
        XCTAssertFalse(decodeError.contains("Imported"), "got \(decodeError)")

        // 4) A .sqlite that is not a database.
        let notADB = tempDir.appendingPathComponent("not_a_db.sqlite")
        try Data("plain text, not SQLite".utf8).write(to: notADB)
        await manage.performImport(url: notADB)
        let sqliteError = try XCTUnwrap(manage.importResult)
        XCTAssertFalse(sqliteError.contains("Imported"), "got \(sqliteError)")

        XCTAssertFalse(manage.isImporting, "no failure leaves the spinner on")
        XCTAssertEqual(settings.enabledSources, allButRussian, "no failed import enables anything")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources, "no failed import touches the order")
        XCTAssertEqual(store.writeLog.count, before, "no store write; got \(store.writeLog.dropFirst(before))")

        // Nothing reached the database, so the reload lists no new row.
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs)
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true])
    }

    /// Edge: a JSON import with zero rows succeeds and enables its ID, but the
    /// reload lists no row for it and drops it from the order again (no
    /// entries → not a live source). Nothing else changes.
    @MainActor
    func testZeroRowImportListsNoRow() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "en", storedOrder: bundledSources,
                                              storedEnabled: allButRussian)
        try await waitForInitialLoad(vm)
        let empty = tempDir.appendingPathComponent("empty_dict.json")
        try Data("[]".utf8).write(to: empty)
        let manage = ManageDictionariesViewModel(
            settingsService: settings,
            localization: LocalizationManager(settingsService: settings, bundle: .main)
        )

        await manage.performImport(url: empty)

        XCTAssertEqual(manage.importResult, "Imported 0 entries from empty_dict")
        XCTAssertEqual(settings.enabledSources, allButRussian.union(["empty_dict"]), "harmless: an ID with no rows")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources + ["empty_dict"])

        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "no row for a source without entries")
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true])
        XCTAssertEqual(settings.dictionaryOrder, bundledSources, "the reload drops the empty source from the order")
    }

    /// Import, load, `togglePair("custom:test_import_fixture")` OFF, import
    /// again, reload: the row is ON.
    @MainActor
    func testReimportTurnsDisabledImportBackOn() async throws {
        try await seedBundled()
        let (vm, settings, store) = makeViewModel(languageCode: "en")
        try await waitForInitialLoad(vm)
        try await importFixture("json", into: settings)
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs + [fixturePair], "precondition")

        vm.togglePair(id: fixturePair)   // the user switches the import OFF
        XCTAssertEqual(settings.enabledSources, Set(bundledSources), "materialised without the import")
        XCTAssertEqual(vm.dictionaries.last?.isEnabled, false)
        let orderBefore = settings.dictionaryOrder
        let beforeReimport = store.writeLog.count

        try await importFixture("json", into: settings)   // the same file again

        XCTAssertTrue(settings.isEnabled(source: fixtureSource), "a re-import turns it back ON (PM decision 2)")
        XCTAssertEqual(settings.enabledSources, Set(bundledSources).union([fixtureSource]))
        XCTAssertEqual(Array(store.writeLog.dropFirst(beforeReimport)), ["enabled_sources"],
                       "one write; the order already holds the ID")
        XCTAssertEqual(settings.dictionaryOrder, orderBefore, "no duplicate in the order")

        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs + [fixturePair], "still one row, still last")
        XCTAssertEqual(vm.dictionaries.last?.isEnabled, true, "the reload shows it ON")
        XCTAssertEqual(vm.dictionaries.last?.count, 10, "rows are deduplicated (unique word + source)")
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled))
    }

    /// AC1 data level: load (no custom row), import, reload the same VM: ids
    /// `[eng, eng-rus, eng-spa, arb-eng, custom:test_import_fixture]`; row ON,
    /// `count == 10`, `displayName == "test_import_fixture"`;
    /// `dictionaryOrder` == bundled order + `["test_import_fixture"]`.
    @MainActor
    func testReloadAfterImportAppendsEnabledCustomRow() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "en")
        try await waitForInitialLoad(vm)
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "no custom row before the import")

        try await importFixture("json", into: settings)
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "nothing reloads until the order screen appears")

        await vm.loadDictionaries()

        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs + [fixturePair],
                       "appended last although its 10 rows outnumber every seeded source")
        XCTAssertEqual(vm.orderedDictionaries.map(\.id), vm.dictionaries.map(\.id))
        let custom = try XCTUnwrap(vm.dictionaries.last)
        XCTAssertTrue(custom.isEnabled)
        XCTAssertEqual(custom.count, 10)
        XCTAssertEqual(custom.displayName, fixtureSource)
        XCTAssertTrue(custom.pair.isCustom)
        XCTAssertEqual(custom.pair.sourceIDs, [fixtureSource])
        XCTAssertEqual(settings.dictionaryOrder, bundledSources + [fixtureSource])

        // The (i) detail data is there too (#91): one block titled by the
        // source ID, no provider, no license.
        let stat = try XCTUnwrap(custom.pair.sources.first)
        XCTAssertEqual(SettingsViewModel.infoSources(for: custom.pair).map(\.source), [fixtureSource])
        XCTAssertNil(SettingsViewModel.providerName(for: stat))
        XCTAssertEqual(SettingsViewModel.infoBlockTitle(for: stat), fixtureSource)
        XCTAssertEqual(stat.license, "")
    }

    /// (a) `enabled_sources` nil, (b) bundled minus `openrussian`. Each: load,
    /// import, reload the same VM, then load a fresh VM over the same
    /// `SettingsService`: identical `dictionaries` and `dictionaryOrder`,
    /// custom row ON in both.
    @MainActor
    func testReloadMatchesRelaunch() async throws {
        try await seedBundled()
        let cases: [(name: String, enabled: Set<String>?, states: [Bool])] = [
            ("nil", nil, [true, true, true, true, true]),
            ("Russian OFF", allButRussian, [true, false, true, true, true]),
        ]
        for c in cases {
            try await DatabaseService.shared.clearEntries(fromSource: fixtureSource)
            let (vm, settings, store) = makeViewModel(languageCode: "en", storedEnabled: c.enabled)
            try await waitForInitialLoad(vm)
            try await importFixture("json", into: settings)
            await vm.loadDictionaries()

            let inSession = vm.dictionaries
            let order = settings.dictionaryOrder
            let enabled = settings.enabledSources
            XCTAssertEqual(inSession.map(\.id), bundledPairs + [fixturePair], "[\(c.name)]")
            XCTAssertEqual(inSession.map(\.isEnabled), c.states, "[\(c.name)] custom row ON")
            let writesBeforeRelaunch = store.writeLog.count

            let relaunched = try await relaunchedViewModel(over: settings)

            XCTAssertEqual(relaunched.dictionaries, inSession, "[\(c.name)] same rows, states, counts")
            XCTAssertEqual(settings.dictionaryOrder, order, "[\(c.name)]")
            XCTAssertEqual(settings.enabledSources, enabled, "[\(c.name)]")
            XCTAssertEqual(store.writeLog.count, writesBeforeRelaunch,
                           "[\(c.name)] the relaunch load had nothing left to persist")
        }
    }

    /// AC2 data level (PM decision 1): import with a materialised set, load,
    /// `clearEntries(fromSource: "test_import_fixture")`, reload the same VM:
    /// row gone, ID dropped from `dictionaryOrder`, still in `enabledSources`;
    /// a fresh VM matches.
    @MainActor
    func testReloadAfterRemovalDropsRowLikeRelaunch() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "en", storedOrder: bundledSources,
                                              storedEnabled: allButRussian)
        try await waitForInitialLoad(vm)
        try await importFixture("json", into: settings)
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs + [fixturePair], "precondition: listed")
        XCTAssertEqual(settings.enabledSources?.contains(fixtureSource), true, "precondition: in the set")

        try await DatabaseService.shared.clearEntries(fromSource: fixtureSource)
        await vm.loadDictionaries()

        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "the row is gone without a relaunch")
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true], "other rows keep their state")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources, "the ID is dropped from the stored order")
        XCTAssertEqual(settings.enabledSources, allButRussian.union([fixtureSource]),
                       "kept in the enabled set (#92 tolerance for removed sources)")

        let relaunched = try await relaunchedViewModel(over: settings)
        XCTAssertEqual(relaunched.dictionaries, vm.dictionaries, "a relaunch shows the same rows")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources)

        // Importing it again brings the row back, last and ON.
        try await importFixture("json", into: settings)
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs + [fixturePair])
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true, true])
    }

    /// Load; `movePair` first → end and `togglePair("eng-spa")`; reload: ids,
    /// `isEnabled` and `dictionaryOrder` unchanged. In-flight variant: start
    /// the reload in a `Task`, `Task.yield()`, move + toggle, await: the move
    /// and toggle survive.
    @MainActor
    func testReloadDoesNotRevertReorderOrToggle() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "en")
        try await waitForInitialLoad(vm)
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "precondition")

        // Settled: move + toggle, then reload.
        vm.movePair(from: IndexSet(integer: 0), to: vm.dictionaries.count)
        vm.togglePair(id: "eng-spa")
        let movedIDs = ["eng-rus", "eng-spa", "arb-eng", "eng"]
        let movedOrder = ["openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng", "wordnet"]
        XCTAssertEqual(vm.dictionaries.map(\.id), movedIDs, "precondition")
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id), movedIDs, "a reload must not revert the move")
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, true, true], "nor the toggle")
        XCTAssertEqual(settings.dictionaryOrder, movedOrder)
        XCTAssertFalse(settings.isEnabled(source: "freedict-eng-spa"))
        XCTAssertFalse(settings.isEnabled(source: "wordnet-spa-eng"))

        // In flight: move + toggle while the reload's fetch is pending.
        let reload = Task { await vm.loadDictionaries() }
        await Task.yield()
        vm.movePair(from: IndexSet(integer: vm.dictionaries.count - 1), to: 0)   // English back on top
        vm.togglePair(id: "eng-rus")                                            // Russian OFF
        await reload.value

        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "the in-flight reload kept the move")
        XCTAssertEqual(vm.dictionaries.map(\.isEnabled), [true, false, false, true], "and both toggles")
        XCTAssertEqual(settings.dictionaryOrder, bundledSources)
        XCTAssertEqual(settings.enabledSources, ["wordnet", "wordnet-arb-eng"])
    }

    /// After the first load, a second load emits nothing on
    /// `vm.$dictionaries.dropFirst()` and adds nothing to `writeLog`.
    @MainActor
    func testReloadWithoutChangesIsSilent() async throws {
        try await seedBundled()
        let (vm, settings, store) = makeViewModel(languageCode: "en", storedEnabled: allButRussian)
        try await waitForInitialLoad(vm)

        var emissions: [[DictionaryItem]] = []
        let subscription = vm.$dictionaries.dropFirst().sink { emissions.append($0) }
        defer { subscription.cancel() }
        let writes = store.writeLog.count

        await vm.loadDictionaries()
        await vm.loadDictionaries()

        XCTAssertTrue(emissions.isEmpty, "an unchanged reload publishes nothing; got \(emissions.count)")
        XCTAssertEqual(store.writeLog.count, writes, "and writes nothing; got \(store.writeLog.dropFirst(writes))")

        // Control, so the spy is not vacuous: a real change publishes once.
        try await importFixture("json", into: settings)
        await vm.loadDictionaries()
        XCTAssertEqual(emissions.count, 1)
        XCTAssertEqual(emissions.last?.map(\.id), bundledPairs + [fixturePair])

        // …and the next reload is silent again.
        let writesAfterImport = store.writeLog.count
        await vm.loadDictionaries()
        XCTAssertEqual(emissions.count, 1)
        XCTAssertEqual(store.writeLog.count, writesAfterImport)
    }

    /// PM decision 3: `enabled_sources` nil + stored bundled order, import
    /// (no reload): `test_import_fixture` is last in `dictionaryOrder`, and
    /// `searchPreferred` with `groups: sourceGroups(order:)` and
    /// `enabledSources: Set(order)` (what `SearchViewModel` passes) finds a
    /// fixture word.
    @MainActor
    func testImportAppendsSourceToOrderForPreferredSearch() async throws {
        try await seedBundled()
        let (vm, settings, _) = makeViewModel(languageCode: "en", storedOrder: bundledSources)
        try await waitForInitialLoad(vm)
        XCTAssertNil(settings.enabledSources, "precondition: all enabled")
        func preferred(order: [String]) async throws -> [DictionaryEntry] {
            try await DatabaseService.shared.searchPreferred(
                query: "qaflux", groups: DictionaryGrouping.sourceGroups(order: order), enabledSources: Set(order)
            )
        }

        try await importFixture("json", into: settings)

        let order = try XCTUnwrap(settings.dictionaryOrder)
        XCTAssertEqual(order, bundledSources + [fixtureSource], "the import is last in the stored order")
        let found = try await preferred(order: order)
        XCTAssertEqual(found.first?.word, "qaflux")
        XCTAssertEqual(found.first?.source, fixtureSource)
        // Control: the order without the append misses the import entirely.
        let missed = try await preferred(order: bundledSources)
        XCTAssertTrue(missed.isEmpty, "without decision 3 preferred mode cannot see it; got \(missed.map(\.word))")
        XCTAssertEqual(vm.dictionaries.map(\.id), bundledPairs, "no Settings reload happened")
    }

    /// AC (PM decision 3): a fresh import is found by the real
    /// `SearchViewModel` right away, in relevance AND preferred mode, for a
    /// nil and a materialised enabled set, and Dictionary order is never
    /// reloaded in between.
    @MainActor
    func testImportedWordFoundInBothSortModesWithoutReload() async throws {
        try await seedBundled()
        let modes: [ResultSortMode] = [.relevance, .preferredDictionary]
        for storedEnabled in [nil, allButRussian] as [Set<String>?] {
            let label = storedEnabled == nil ? "nil set" : "Russian OFF"
            try await DatabaseService.shared.clearEntries(fromSource: fixtureSource)
            let (settingsVM, settings, _) = makeViewModel(languageCode: "en", storedEnabled: storedEnabled)
            try await waitForInitialLoad(settingsVM)
            let search = SearchViewModel(db: .shared, settings: settings)

            for mode in modes {
                settings.resultSortMode = mode
                let before = try await searchResults(search, for: "qaflux")
                XCTAssertTrue(before.isEmpty, "[\(label), \(mode)] precondition: not imported yet")
            }

            try await importFixture("json", into: settings)

            for mode in modes {
                settings.resultSortMode = mode
                let results = try await searchResults(search, for: "qaflux")
                XCTAssertEqual(results.first?.word, "qaflux", "[\(label), \(mode)] found right after the import")
                XCTAssertEqual(results.first?.source, fixtureSource, "[\(label), \(mode)]")
            }
            // A bundled word is still found next to it (nothing else was filtered out).
            settings.resultSortMode = .preferredDictionary
            let bundledHit = try await searchResults(search, for: "wordnet")
            XCTAssertEqual(bundledHit.first?.source, "wordnet", "[\(label)] English bucket still first")
            XCTAssertEqual(settingsVM.dictionaries.map(\.id), bundledPairs, "[\(label)] Dictionary order never reloaded")
        }
    }
}

// MARK: - Issue #87: Greek ↔ English dictionaries
//
// DESIGN_DOC.md §8a, plus the data fixes that ride the same seed rebuild:
// #106 (license labels) and #108 (FreeDict kept only the first translation).
// The fold parity vectors are a straight port of `PARITY_FOLDS` /
// `PARITY_IDENTITY` in `Scripts/build_greek.py` (keep the two lists in sync).

/// Fixtures and seed-backed / temp-DB tests. An extension, so the bodies can
/// use `db`, `tempDir`, `insertNormalizedEntry` and `openBundledSeedReadOnly`.
extension DictAppTests {

    // MARK: Fixtures

    /// The four Greek sources, in (i) detail order (§5.1).
    static let greekSourceIDs = ["freedict-ell-eng", "wordnet-ell-eng", "freedict-eng-ell", "wordnet-eng-ell"]
    /// All nine bundled sources (§8a "The seed ships exactly nine sources").
    static let allBundledSourceIDs = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng",
                                      "wordnet-arb-eng"] + greekSourceIDs

    /// Mirror of `decompose_greek` in `Scripts/build_greek.py`: every Greek
    /// code point becomes its NFD decomposition (ά → α + U+0301); every other
    /// code point stays byte-identical. Lets a fixture store a definition the
    /// way the build stores the Greek sources'.
    static func decomposeGreek(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: Search.isGreek) else { return s }
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if Search.isGreek(scalar) {
                out.append(contentsOf: String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// `word|source` keys of a result list. `String` hashing is canonical-
    /// equivalence aware, so an NFC fixture word matches an NFC row.
    private static func hitKeys(_ rows: [DictionaryEntry]) -> Set<String> {
        Set(rows.map { "\($0.word)|\($0.source)" })
    }

    /// The four rows every spelling of σκύλος must reach (§4.3).
    private static let dogHits: Set<String> = [
        "dog|wordnet-eng-ell", "dog|freedict-eng-ell", "σκύλος|freedict-ell-eng", "σκύλος|wordnet-ell-eng",
    ]

    /// "dog" in both En→El sources with the Greek of its definition stored
    /// decomposed (as the build does), the `σκύλος` headwords of both El→En
    /// sources with a folded `word_normalized`, and a Greek distractor that
    /// must never match `σκυλ*`.
    private func insertGreekDogFixtures() async throws {
        try await insertNormalizedEntry(
            word: "dog", normalized: "dog",
            definition: "**noun**\n1. σκύλος γένους Canis familiaris — a member of the genus Canis",
            source: "wordnet-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "dog", normalized: "dog", definition: "1. σκύλος",
            source: "freedict-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "σκύλος", normalized: "σκυλοσ", definition: "**noun**\n1. dog, hound, canine",
            source: "freedict-ell-eng")
        try await insertNormalizedEntry(
            word: "σκύλος", normalized: "σκυλοσ",
            definition: "**noun**\n1. working dog — any of several breeds of usually large powerful dogs",
            source: "wordnet-ell-eng")
        try await insertNormalizedEntry(
            word: "cat", normalized: "cat", definition: "1. γάτα — feline mammal",
            source: "wordnet-eng-ell", decomposeGreekDefinition: true)
    }

    /// The stored `definition` of one fixture row, read back raw.
    private func storedDefinition(word: String, source: String) async throws -> String {
        let pool = try DatabasePool(path: tempDir.appendingPathComponent("test.sqlite").path)
        return try await pool.read { conn in
            try String.fetchOne(conn, sql: "SELECT definition FROM entries WHERE word = ? AND source = ?",
                                arguments: [word, source]) ?? ""
        }
    }

    /// The bundled seed's URL (same host-bundle resolution as
    /// `openBundledSeedReadOnly`).
    private static func greekSeedURL() throws -> URL {
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()
        return try XCTUnwrap(
            hostBundle.url(forResource: "seed", withExtension: "sqlite")
                ?? Bundle.main.url(forResource: "seed", withExtension: "sqlite"),
            "Bundled seed.sqlite is missing from the app bundle")
    }

    /// Clones the bundled seed into `tempDir` (APFS clone, no 130 MB copy) and
    /// points `db` at it, so the app's real `search` SQL runs on shipped rows.
    private func useSeedClone() async throws {
        let copy = tempDir.appendingPathComponent("seed-clone.sqlite")
        try FileManager.default.copyItem(at: try Self.greekSeedURL(), to: copy)
        try await db.setup(path: copy.path)
    }

    /// One seed row's definition (NFC, for contains-checks: Greek-source
    /// definitions are stored decomposed).
    private static func seedDefinition(_ queue: DatabaseQueue, word: String, source: String) throws -> String {
        let raw = try queue.read { conn in
            try String.fetchOne(conn, sql: "SELECT definition FROM entries WHERE word = ? AND source = ?",
                                arguments: [word, source])
        }
        return try XCTUnwrap(raw, "seed row '\(word)' / \(source) missing").precomposedStringWithCanonicalMapping
    }

    private static func seedLicense(_ queue: DatabaseQueue, _ source: String) throws -> String {
        let raw = try queue.read { conn in
            try String.fetchOne(conn, sql: "SELECT license FROM dict_metadata WHERE source = ?", arguments: [source])
        }
        return try XCTUnwrap(raw, "dict_metadata row for \(source) missing")
    }

    // MARK: Search integration (temp DB)

    /// `σκυλος` → "dog" from `wordnet-eng-ell` (`σκύλος γένους Canis
    /// familiaris — …`) and `freedict-eng-ell` (`1. σκύλος`), both stored
    /// decomposed, plus the `σκύλος` headwords of both El→En sources: all four,
    /// and nothing else.
    func testGreekAccentFreeQueryFindsDogInAllFourSources() async throws {
        try await insertGreekDogFixtures()

        // Precondition: the fixture really stores the definition decomposed
        // (otherwise this test would not exercise the NFD path at all).
        let stored = try await storedDefinition(word: "dog", source: "freedict-eng-ell")
        XCTAssertTrue(stored.unicodeScalars.contains("\u{0301}"),
                      "fixture definition must hold a combining tonos; got \(stored.unicodeScalars.map(\.value))")
        XCTAssertFalse(stored.unicodeScalars.contains("\u{03CD}"), "no precomposed ύ left in the stored definition")

        let hits = Self.hitKeys(try await db.search(query: "σκυλος"))
        XCTAssertEqual(hits, Self.dogHits,
                       "accent-free σκυλος must reach both El→En headwords and 'dog' in both En→El sources, and only them")
    }

    /// `σκύλος` returns the same four rows; an NFC accented custom-import row
    /// (`word_normalized = word`) is also found (raw branch). The accent-free
    /// query does not reach that custom row: custom imports stay accent-exact
    /// (the documented limit, §4.3).
    func testGreekAccentedQueryFindsDogAndAccentedCustomImport() async throws {
        try await insertGreekDogFixtures()
        try await insertNormalizedEntry(word: "σκύλος", normalized: "σκύλος",
                                        definition: "a custom Greek import", source: "my_greek_import")

        let accented = Self.hitKeys(try await db.search(query: "σκύλος"))
        XCTAssertEqual(accented, Self.dogHits.union(["σκύλος|my_greek_import"]),
                       "accented σκύλος: the four bundled rows via the folded branch + the custom NFC row via the raw branch")

        let bare = Self.hitKeys(try await db.search(query: "σκυλος"))
        XCTAssertEqual(bare, Self.dogHits,
                       "accent-free σκυλος finds no accented custom import (custom imports are accent-exact, §4.3)")
    }

    /// Same fixtures: `ΣΚΥΛΟΣ`, `ΣΚΎΛΟΣ`, `σκυλοσ`, the prefix `σκυλ`, and a
    /// query typed/pasted decomposed (NFD) all reach the same four rows; a
    /// different Greek stem reaches none of them.
    func testGreekCaseFinalSigmaAndPrefixVariants() async throws {
        try await insertGreekDogFixtures()

        let variants = ["ΣΚΥΛΟΣ", "ΣΚΎΛΟΣ", "σκυλοσ", "σκυλ", "Σκύλος", "σκύλος".decomposedStringWithCanonicalMapping]
        for query in variants {
            let hits = Self.hitKeys(try await db.search(query: query))
            XCTAssertEqual(hits, Self.dogHits, "query '\(query)' (\(query.unicodeScalars.map(\.value)))")
        }

        let other = try await db.search(query: "σκυλα")
        XCTAssertTrue(other.isEmpty, "σκυλα* is a different stem; got \(Self.hitKeys(other))")
        let cat = Self.hitKeys(try await db.search(query: "γατα"))
        XCTAssertEqual(cat, ["cat|wordnet-eng-ell"], "the distractor is reachable by its own Greek, accent-free")
    }

    /// `προιον` / `προϊόν` → "product"; `σαιτα` / `σαΐτα` → "arrow" (ΐ);
    /// `καταπραυνω` / `καταπραΰνω` → "allay" (ΰ). Greek in decomposed definitions.
    func testGreekDialytikaAndTonosFoldInDefinitions() async throws {
        try await insertNormalizedEntry(
            word: "product", normalized: "product", definition: "**noun**\n1. προϊόν — commodities offered for sale",
            source: "wordnet-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "product", normalized: "product", definition: "1. προϊόν, παράγωγο",
            source: "freedict-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "arrow", normalized: "arrow", definition: "**noun**\n1. βέλος, σαΐτα — a projectile with a straight thin shaft",
            source: "wordnet-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "allay", normalized: "allay", definition: "**verb**\n1. καταπραΰνω — lessen the intensity of",
            source: "wordnet-eng-ell", decomposeGreekDefinition: true)

        // ΐ and ΰ carry dialytika AND tonos: NFD keeps both as combining marks.
        let arrow = try await storedDefinition(word: "arrow", source: "wordnet-eng-ell")
        XCTAssertTrue(arrow.unicodeScalars.contains("\u{0308}") && arrow.unicodeScalars.contains("\u{0301}"),
                      "ΐ must be stored as ι + U+0308 + U+0301")

        let expectations: [(String, Set<String>)] = [
            ("προιον", ["product|wordnet-eng-ell", "product|freedict-eng-ell"]),
            ("προϊόν", ["product|wordnet-eng-ell", "product|freedict-eng-ell"]),
            ("ΠΡΟΪΟΝ", ["product|wordnet-eng-ell", "product|freedict-eng-ell"]),
            ("σαιτα", ["arrow|wordnet-eng-ell"]),
            ("σαΐτα", ["arrow|wordnet-eng-ell"]),
            ("καταπραυνω", ["allay|wordnet-eng-ell"]),
            ("καταπραΰνω", ["allay|wordnet-eng-ell"]),
        ]
        for (query, expected) in expectations {
            let hits = Self.hitKeys(try await db.search(query: query))
            XCTAssertEqual(hits, expected, "query '\(query)'")
        }
    }

    /// For an accented query the exact (folded) headword ranks first, then a
    /// headword that only starts with it (prefix boost), then rows that only
    /// match in their definitions — even though the definition rows were
    /// inserted first and mention the word several times. Both boosts use the
    /// folded `rankKey`; with the raw accented key neither would fire.
    func testGreekExactHeadwordOutranksDefinitionMatches() async throws {
        try await insertNormalizedEntry(
            word: "dog", normalized: "dog", definition: "1. σκύλος, σκύλος φύλακας, σκύλος κυνηγιού",
            source: "wordnet-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "hound", normalized: "hound", definition: "1. σκύλος, λαγωνικό",
            source: "freedict-eng-ell", decomposeGreekDefinition: true)
        try await insertNormalizedEntry(
            word: "σκυλόσπιτο", normalized: "σκυλοσπιτο", definition: "**noun**\n1. doghouse, kennel",
            source: "freedict-ell-eng")
        try await insertNormalizedEntry(
            word: "σκύλος", normalized: "σκυλοσ", definition: "**noun**\n1. dog, hound, canine",
            source: "freedict-ell-eng")

        for query in ["σκύλος", "ΣΚΎΛΟΣ", "σκυλος"] {
            let words = try await db.search(query: query).map(\.word)
            XCTAssertEqual(words.count, 4, "\(query): all four rows match; got \(words)")
            XCTAssertEqual(words.first, "σκύλος", "\(query): exact folded headword first; got \(words)")
            XCTAssertEqual(words.dropFirst().first, "σκυλόσπιτο", "\(query): prefix headword second; got \(words)")
            XCTAssertEqual(Set(words.dropFirst(2)), ["dog", "hound"], "\(query): definition-only matches last")
        }
    }

    /// Russian regression: fixture `йод` and `иод`; `search("йод")` returns
    /// `йод` and not `иод`, `search("иод")` returns `иод` and not `йод`. A fold
    /// leaking outside Greek (NFD + drop marks) would merge the two.
    func testRussianShortIDoesNotFoldIntoI() async throws {
        try await insertNormalizedEntry(word: "йод", normalized: "йод",
                                        definition: "**noun**\n1. iodine", source: "openrussian")
        try await insertNormalizedEntry(word: "иод", normalized: "иод",
                                        definition: "**noun**\n1. obsolete spelling", source: "openrussian")

        let short = try await db.search(query: "йод").map(\.word)
        let plain = try await db.search(query: "иод").map(\.word)
        let upper = try await db.search(query: "ЙОД").map(\.word)
        XCTAssertEqual(short, ["йод"], "й must stay й")
        XCTAssertEqual(plain, ["иод"], "и must not reach й")
        XCTAssertEqual(upper, ["йод"], "case folding still works for Cyrillic")
    }

    /// `searchPreferred`: the four Greek sources share one bucket. Member order
    /// puts both En→El sources first, so per-source buckets would surface their
    /// definition rows first; one shared bucket ranks the two exact `σκύλος`
    /// headwords first, holds exactly `topN` rows across all four sources, and
    /// the next group's bucket follows right after it.
    func testSearchPreferredGreekSourcesShareOneBucket() async throws {
        let topN = Search.preferredDictionaryTopN
        XCTAssertEqual(topN, 4, "fixture sized for topN == 4")
        let custom = "my_greek_import"
        let order = ["wordnet-eng-ell", "freedict-eng-ell", "wordnet-ell-eng", "freedict-ell-eng", custom]
        let groups = DictionaryGrouping.sourceGroups(order: order)
        XCTAssertEqual(groups, [Array(order.prefix(4)), [custom]], "the four Greek IDs form one group")

        for i in 1...3 {
            try await insertNormalizedEntry(
                word: "dog\(i)", normalized: "dog\(i)", definition: "1. σκύλος \(i)",
                source: "wordnet-eng-ell", decomposeGreekDefinition: true)
            try await insertNormalizedEntry(
                word: "hound\(i)", normalized: "hound\(i)", definition: "1. σκύλος \(i)",
                source: "freedict-eng-ell", decomposeGreekDefinition: true)
        }
        try await insertNormalizedEntry(word: "σκύλος", normalized: "σκυλοσ",
                                        definition: "1. working dog", source: "wordnet-ell-eng")
        try await insertNormalizedEntry(word: "σκύλος", normalized: "σκυλοσ",
                                        definition: "1. dog", source: "freedict-ell-eng")
        try await insertNormalizedEntry(word: "σκυλος", normalized: "σκυλος",
                                        definition: "custom", source: custom)

        let results = try await db.searchPreferred(query: "σκύλος", groups: groups, enabledSources: Set(order))
        let greek = Set(Self.greekSourceIDs)

        XCTAssertEqual(results.count, 9, "8 Greek rows + 1 custom row; got \(Self.hitKeys(results))")
        XCTAssertEqual(Set(results.prefix(2).map(\.source)), ["wordnet-ell-eng", "freedict-ell-eng"],
                       "one shared bucket: the exact headwords lead, whatever the member order")
        XCTAssertTrue(results.prefix(2).allSatisfy { $0.word == "σκύλος" })
        XCTAssertTrue(results.prefix(topN).allSatisfy { greek.contains($0.source) },
                      "the Greek bucket fills first; got \(results.prefix(topN).map(\.source))")
        XCTAssertEqual(results[topN].source, custom,
                       "the Greek bucket holds exactly topN rows in total, then the next group's bucket")
        XCTAssertTrue(results.dropFirst(topN + 1).allSatisfy { greek.contains($0.source) }, "tail: the remaining Greek rows")
        let ids = results.compactMap(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "no duplicate rows")
    }

    /// 100,000 rows, 10% with decomposed Greek definitions; `search("σκύλος")`
    /// (two-branch MATCH) under the `testSearchPerformance100K` budget of
    /// 16 ms. Median of five timed runs after a warm-up, so one scheduler
    /// hiccup does not fail the build. 20 definitions mention σκύλος (the real
    /// seed has 19 `σκυλ*` hits).
    func testGreekSearchPerformance100K() async throws {
        XCTAssertTrue(Search.ftsQuery(sanitized: "σκύλος").match.contains(" OR "),
                      "precondition: the measured query takes the two-branch path")
        let vocabulary = ["λόγος", "θάλασσα", "άνθρωπος", "προϊόν", "σαΐτα", "καταπραΰνω", "καλημέρα", "αύριο",
                          "γρήγορα", "βιβλίο", "νερό", "σπίτι", "γάτα", "δρόμος", "ουρανός", "ήλιος",
                          "φεγγάρι", "πόλη", "χώρα", "γλώσσα"]
        let pool = try DatabasePool(path: tempDir.appendingPathComponent("test.sqlite").path)
        try await pool.write { conn in
            let insert = try conn.makeStatement(sql: """
                INSERT INTO entries(word, word_normalized, definition, phonetic, pos, source)
                VALUES (?, ?, ?, '', 'noun', ?)
                """)
            for i in 0..<89_999 {
                try insert.execute(arguments: ["word\(i)", "word\(i)",
                                               "Definition for word number \(i). This is a sample definition.", "test"])
            }
            for i in 0..<10_000 {
                let a = vocabulary[i % vocabulary.count]
                let b = vocabulary[(i / vocabulary.count) % vocabulary.count]
                let mention = i % 500 == 0 ? ", σκύλος" : ""
                let definition = Self.decomposeGreek("**noun**\n1. \(a), \(b)\(mention) — gloss number \(i)")
                try insert.execute(arguments: ["gword\(i)", "gword\(i)", definition, "wordnet-eng-ell"])
            }
            try insert.execute(arguments: ["σκύλος", "σκυλοσ", "**noun**\n1. dog, hound", "freedict-ell-eng"])
        }
        let count = try await db.entryCount()
        XCTAssertEqual(count, 100_000, "Database should contain 100k entries")

        _ = try await db.search(query: "θάλασσα")   // warm-up, also two-branch
        var timings: [Double] = []
        var results: [DictionaryEntry] = []
        for _ in 0..<5 {
            let start = CFAbsoluteTimeGetCurrent()
            results = try await db.search(query: "σκύλος")
            timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let median = timings.sorted()[timings.count / 2]
        print("⏱ Greek FTS5 search on 100k entries: median \(String(format: "%.2f", median))ms of \(timings.map { String(format: "%.2f", $0) })")

        XCTAssertEqual(results.count, 21, "1 headword + 20 decomposed definitions")
        XCTAssertEqual(results.first?.word, "σκύλος", "the exact headword ranks first")
        XCTAssertLessThan(median, 16.0, "Greek search must complete in under 16ms (median \(median)ms)")
    }

    // MARK: Seed-backed
    //
    // Counts are read from the seed, never hard-coded; definitions are
    // compared after NFC with contains-checks (Greek-source definitions are
    // stored decomposed, and #108 appends translations to FreeDict lines).

    /// `Search.foldGreek(word) == word_normalized`, scalar for scalar, for every
    /// row of the four Greek sources (Swift/Python fold parity on real data).
    func testSeedGreekWordNormalizedMatchesFoldGreek() throws {
        let queue = try Self.openBundledSeedReadOnly()
        let placeholders = Self.greekSourceIDs.map { _ in "?" }.joined(separator: ", ")
        let rows = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT word, word_normalized, source FROM entries WHERE source IN (\(placeholders))",
                             arguments: StatementArguments(Self.greekSourceIDs))
        }
        XCTAssertGreaterThan(rows.count, 100_000, "the four Greek sources ship ~110k rows; got \(rows.count)")

        var mismatches: [String] = []
        var checked: [String: Int] = [:]
        for row in rows {
            let word: String = row["word"]
            let normalized: String = row["word_normalized"]
            let source: String = row["source"]
            checked[source, default: 0] += 1
            if !Search.foldGreek(word).unicodeScalars.elementsEqual(normalized.unicodeScalars) {
                mismatches.append("\(source): '\(word)' → '\(normalized)', Swift '\(Search.foldGreek(word))'")
            }
        }
        XCTAssertEqual(Set(checked.keys), Set(Self.greekSourceIDs), "every Greek source was checked")
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) parity mismatches, e.g. \(mismatches.prefix(5))")
    }

    /// No `definition` of a Greek source contains a precomposed Greek scalar
    /// that has a canonical decomposition; no `word` contains a combining mark
    /// and every `word` is NFC. Non-vacuous: thousands of definitions do carry
    /// a combining tonos.
    func testSeedGreekDefinitionsAreDecomposed() throws {
        // Greek scalars whose NFD differs from themselves (ά, ΐ, ΰ, ᾳ, …).
        var decomposable = Set<UInt32>()
        for value in Array(0x0370...0x03FF) + Array(0x1F00...0x1FFF) {
            guard let scalar = Unicode.Scalar(UInt32(value)) else { continue }
            let nfd = String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
            if !nfd.elementsEqual([scalar]) { decomposable.insert(scalar.value) }
        }
        XCTAssertTrue(decomposable.contains(0x03AC) && decomposable.contains(0x0390), "ά and ΐ are decomposable")

        let queue = try Self.openBundledSeedReadOnly()
        let placeholders = Self.greekSourceIDs.map { _ in "?" }.joined(separator: ", ")
        let rows = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT word, definition, source FROM entries WHERE source IN (\(placeholders))",
                             arguments: StatementArguments(Self.greekSourceIDs))
        }
        var precomposed: [String] = []
        var markedWords: [String] = []
        var withTonos = 0
        for row in rows {
            let word: String = row["word"]
            let definition: String = row["definition"]
            let source: String = row["source"]
            if definition.unicodeScalars.contains(where: { decomposable.contains($0.value) }) {
                precomposed.append("\(source): \(word)")
            }
            if definition.unicodeScalars.contains("\u{0301}") { withTonos += 1 }
            if word.unicodeScalars.contains(where: { $0.properties.generalCategory == .nonspacingMark })
                || !word.unicodeScalars.elementsEqual(word.precomposedStringWithCanonicalMapping.unicodeScalars) {
                markedWords.append("\(source): \(word)")
            }
        }
        XCTAssertTrue(precomposed.isEmpty, "\(precomposed.count) definitions keep precomposed Greek, e.g. \(precomposed.prefix(5))")
        XCTAssertTrue(markedWords.isEmpty, "\(markedWords.count) words are not NFC, e.g. \(markedWords.prefix(5))")
        XCTAssertGreaterThan(withTonos, 10_000, "decomposed accents must actually be present; got \(withTonos)")
    }

    /// `γρήγορα` headword only in `freedict-ell-eng`; `tomorrow` headword only
    /// in `freedict-eng-ell` among the Greek sources (OMW lacks both). Through
    /// the app's `search` on a seed clone: `γρηγορα` puts `γρήγορα` first and
    /// `tomorrow` returns the `freedict-eng-ell` row first among the Greek rows.
    func testSeedWordsOnlyInFreeDictGreekSources() async throws {
        let queue = try Self.openBundledSeedReadOnly()
        let placeholders = Self.greekSourceIDs.map { _ in "?" }.joined(separator: ", ")
        func greekSources(word: String) throws -> [String] {
            try queue.read { conn in
                try String.fetchAll(conn, sql: """
                    SELECT source FROM entries WHERE word = ? COLLATE NOCASE AND source IN (\(placeholders))
                    """, arguments: StatementArguments([word] + Self.greekSourceIDs))
            }
        }
        XCTAssertEqual(try greekSources(word: "γρήγορα"), ["freedict-ell-eng"])
        XCTAssertEqual(try greekSources(word: "tomorrow"), ["freedict-eng-ell"])
        XCTAssertTrue(try Self.seedDefinition(queue, word: "γρήγορα", source: "freedict-ell-eng").contains("quickly"))
        XCTAssertTrue(try Self.seedDefinition(queue, word: "tomorrow", source: "freedict-eng-ell").contains("αύριο"))

        try await useSeedClone()
        let quick = try await db.search(query: "γρηγορα")
        XCTAssertEqual(quick.first.map { "\($0.word)|\($0.source)" }, "γρήγορα|freedict-ell-eng",
                       "accent-free γρηγορα puts the FreeDict headword first")

        let tomorrowGreek = try await db.search(query: "tomorrow", enabledSources: Set(Self.greekSourceIDs))
        XCTAssertEqual(tomorrowGreek.first.map { "\($0.word)|\($0.source)" }, "tomorrow|freedict-eng-ell")
        let tomorrowAll = try await db.search(query: "tomorrow")
        let firstGreek = tomorrowAll.first { Self.greekSourceIDs.contains($0.source) }
        XCTAssertEqual(firstGreek.map { "\($0.word)|\($0.source)" }, "tomorrow|freedict-eng-ell",
                       "with every source on, the first Greek row is still the FreeDict headword")
        XCTAssertTrue(tomorrowAll.contains { $0.word == "tomorrow" && $0.source == "wordnet" }, "English WordNet keeps its row")
    }

    /// The AC on shipped data (PM follow-up 2): `σκυλος`, `σκύλος` and
    /// `ΣΚΥΛΟΣ` reach "dog" in BOTH En→El sources and `σκύλος` in BOTH El→En
    /// sources through the app's `search` (limit 50).
    func testSeedGreekQueriesFindDogInAllFourSources() async throws {
        try await useSeedClone()
        for query in ["σκυλος", "σκύλος", "ΣΚΥΛΟΣ"] {
            let hits = Self.hitKeys(try await db.search(query: query))
            XCTAssertTrue(Self.dogHits.isSubset(of: hits),
                          "\(query): missing \(Self.dogHits.subtracting(hits)) from the seed results")
        }
        // Non-Greek search is unaffected: English "dog" still finds WordNet first.
        let english = try await db.search(query: "dog")
        XCTAssertEqual(english.first?.word, "dog")
    }

    /// Merges: `λάτρης` (FreeDict El→En) keeps the suffix and the noun entry
    /// ("later", "worshipper"); `ad` (FreeDict En→El) contains
    /// "(AD) μετά Χριστόν" and "διαφήμηση"; `act` contains
    /// "παίζω (από ηθοποιό)"; `sea` has exactly two numbered lines.
    func testSeedFreeDictGreekHomographMerges() throws {
        let queue = try Self.openBundledSeedReadOnly()

        let latris = try Self.seedDefinition(queue, word: "λάτρης", source: "freedict-ell-eng")
        for part in ["**suffix**", "later", "**noun**", "worshipper"] {
            XCTAssertTrue(latris.contains(part), "λάτρης must keep '\(part)'; got \(latris)")
        }

        let ad = try Self.seedDefinition(queue, word: "ad", source: "freedict-eng-ell")
        XCTAssertTrue(ad.contains("(AD) μετά Χριστόν"), "AD/ad merge keeps the AD spelling in parentheses; got \(ad)")
        XCTAssertTrue(ad.contains("διαφήμηση"), "ad keeps its own translation; got \(ad)")

        let act = try Self.seedDefinition(queue, word: "act", source: "freedict-eng-ell")
        XCTAssertTrue(act.contains("παίζω (από ηθοποιό)"), "inline <note> rendered in parentheses; got \(act)")

        let sea = try Self.seedDefinition(queue, word: "sea", source: "freedict-eng-ell")
        let numbered = sea.split(separator: "\n").filter { $0.first?.isNumber == true }
        XCTAssertEqual(numbered.count, 2, "two source entries → two numbered lines; got \(sea)")
        XCTAssertTrue(sea.contains("θάλασσα"))
    }

    /// #108: FreeDict keeps every `<quote>` of a translation group, in file
    /// order. λάτρης keeps "worshipper", "aficionado", "buff" (only the first
    /// survived before); `freedict-eng-spa` "quickly" keeps "rápidamente"
    /// after "deprisa", and "dog" keeps "can" after "perro".
    func testSeedFreeDictKeepsEveryTranslation() throws {
        let queue = try Self.openBundledSeedReadOnly()

        let latris = try Self.seedDefinition(queue, word: "λάτρης", source: "freedict-ell-eng")
        XCTAssertTrue(latris.contains("worshipper, aficionado, buff"), "λάτρης keeps the whole group; got \(latris)")

        let quickly = try Self.seedDefinition(queue, word: "quickly", source: "freedict-eng-spa")
        for translation in ["deprisa", "rápido", "rápidamente", "velozmente"] {
            XCTAssertTrue(quickly.contains(translation), "quickly must keep '\(translation)'; got \(quickly)")
        }
        let first = try XCTUnwrap(quickly.range(of: "deprisa"))
        let later = try XCTUnwrap(quickly.range(of: "rápidamente"))
        XCTAssertLessThan(first.lowerBound, later.lowerBound, "file order kept")

        let dog = try Self.seedDefinition(queue, word: "dog", source: "freedict-eng-spa")
        XCTAssertTrue(dog.contains("perro, can"), "dog keeps its second translation; got \(dog)")
        // A group never repeats a translation (the merge drops duplicates).
        let firstLine = try XCTUnwrap(dog.split(separator: "\n").first { $0.hasPrefix("1. ") })
        let items = firstLine.dropFirst(3).components(separatedBy: ", ")
        XCTAssertEqual(items.count, Set(items).count, "no duplicate translation in '\(firstLine)'")
    }

    /// No duplicate `word COLLATE NOCASE` within any Greek source, the unique
    /// index that enforces it ships in the seed, and each source's
    /// `dict_metadata.word_count` equals its row count.
    func testSeedGreekSourcesHaveNoNocaseDuplicates() throws {
        let queue = try Self.openBundledSeedReadOnly()
        let placeholders = Self.greekSourceIDs.map { _ in "?" }.joined(separator: ", ")
        let duplicates = try queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT source, word, COUNT(*) AS n FROM entries WHERE source IN (\(placeholders))
                GROUP BY source, word COLLATE NOCASE HAVING n > 1 LIMIT 5
                """, arguments: StatementArguments(Self.greekSourceIDs))
        }
        XCTAssertTrue(duplicates.isEmpty, "NOCASE duplicates: \(duplicates)")

        let indexSQL = try queue.read { conn in
            try String.fetchOne(conn, sql: "SELECT sql FROM sqlite_master WHERE name = 'idx_entries_word_source'")
        }
        XCTAssertTrue(indexSQL?.contains("UNIQUE") == true && indexSQL?.contains("COLLATE NOCASE") == true,
                      "the unique NOCASE index ships in the seed; got \(indexSQL ?? "nil")")

        for source in Self.greekSourceIDs {
            let rows = try queue.read { conn in
                try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries WHERE source = ?", arguments: [source]) ?? 0
            }
            let declared = try queue.read { conn in
                try Int.fetchOne(conn, sql: "SELECT word_count FROM dict_metadata WHERE source = ?", arguments: [source]) ?? -1
            }
            XCTAssertEqual(rows, declared, "\(source): word_count must equal its row count")
        }
    }

    /// The seed ships exactly the nine bundled sources (`allBundledSourceIDs`),
    /// each with a `dict_metadata` row whose `word_count` matches its rows.
    /// Counts are read from the seed, never hard-coded (#108 may shift the
    /// FreeDict numbers); the five pre-Greek sources keep their row counts.
    func testSeedShipsExactlyNineSources() throws {
        let queue = try Self.openBundledSeedReadOnly()
        let counts = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT source, COUNT(*) AS n FROM entries GROUP BY source")
        }
        let bySource = Dictionary(uniqueKeysWithValues: counts.map { ($0["source"] as String, $0["n"] as Int) })
        XCTAssertEqual(Set(bySource.keys), Set(Self.allBundledSourceIDs), "entries hold exactly the nine sources")

        let metadata = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT source, word_count FROM dict_metadata")
        }
        let declared = Dictionary(uniqueKeysWithValues: metadata.map { ($0["source"] as String, $0["word_count"] as Int) })
        XCTAssertEqual(Set(declared.keys), Set(Self.allBundledSourceIDs), "one dict_metadata row per bundled source")
        for source in Self.allBundledSourceIDs {
            XCTAssertEqual(declared[source], bySource[source], "\(source): word_count vs rows")
            XCTAssertGreaterThan(bySource[source] ?? 0, 10_000, "\(source) is a real dictionary")
        }
        // §3.5 no-drift: the rebuild keeps the five existing sources' rows.
        let unchanged = ["wordnet": 147_306, "openrussian": 45_647, "freedict-eng-spa": 58_946,
                         "wordnet-spa-eng": 36_371, "wordnet-arb-eng": 17_785]
        for (source, rows) in unchanged {
            XCTAssertEqual(bySource[source], rows, "\(source) row count must not drift in the rebuild")
        }
    }

    /// Greek WordNet (both directions) carries the full Apache 2.0 text;
    /// `freedict-ell-eng` and `freedict-eng-spa` name CC BY-SA 3.0 (WikDict);
    /// `freedict-eng-ell` credits Freelang under CC BY-SA 3.0; #106:
    /// `wordnet-arb-eng` is CC BY-SA 3.0 (not CC BY 3.0) and `freedict-eng-spa`
    /// no longer claims the GPL.
    func testSeedLicenseTexts() throws {
        let queue = try Self.openBundledSeedReadOnly()

        for source in ["wordnet-ell-eng", "wordnet-eng-ell"] {
            let text = try Self.seedLicense(queue, source)
            for part in ["Apache License", "Version 2.0", "TERMS AND CONDITIONS", "END OF TERMS AND CONDITIONS",
                         "Princeton WordNet 3.0", "LibreDict converted"] {
                XCTAssertTrue(text.contains(part), "\(source) license must contain '\(part)'")
            }
            XCTAssertGreaterThan(text.count, 9_000, "\(source): the full Apache text ships (PM Q3)")
        }
        XCTAssertEqual(try Self.seedLicense(queue, "wordnet-ell-eng"), try Self.seedLicense(queue, "wordnet-eng-ell"))

        for source in ["freedict-ell-eng", "freedict-eng-spa"] {
            let text = try Self.seedLicense(queue, source)
            XCTAssertTrue(text.contains("Attribution-ShareAlike 3.0"), "\(source): CC BY-SA 3.0")
            XCTAssertTrue(text.contains("Wiktionary"), "\(source): credits Wiktionary contributors")
            XCTAssertFalse(text.contains("GNU General Public License") || text.contains("GPL"),
                           "\(source) must not claim the GPL (#106)")
        }

        let engEll = try Self.seedLicense(queue, "freedict-eng-ell")
        for part in ["Freelang", "Attribution-ShareAlike 3.0", "Piotr Bański"] {
            XCTAssertTrue(engEll.contains(part), "freedict-eng-ell license must contain '\(part)'")
        }

        let arabic = try Self.seedLicense(queue, "wordnet-arb-eng")
        XCTAssertTrue(arabic.contains("ShareAlike") && arabic.contains("CC BY-SA 3.0"), "Arabic WordNet is CC BY-SA 3.0 (#106)")
        XCTAssertFalse(arabic.contains("(CC BY 3.0)") || arabic.contains("Attribution 3.0"),
                       "the old CC BY 3.0 label is gone (#106)")
    }

    /// `fetchSourceStats()` (the Settings / Dictionary Order load) on the
    /// shipped seed returns one stat per source with the exact entry count and
    /// the `dict_metadata` license / version, count-desc — and returns fast.
    /// Regression found in #87 QA: with the metadata join inside the
    /// aggregate, the two ~9.8 KB Apache texts were re-read for every one of
    /// ~48k Greek WordNet rows, and the order screen stayed empty for 25+ s
    /// on an iPhone 15 Pro simulator (7.7 s even on the Mac host).
    func testFetchSourceStatsOnSeedIsCompleteAndFast() async throws {
        let queue = try Self.openBundledSeedReadOnly()
        var expectedCounts: [String: Int] = [:]
        for row in try await queue.read({ try Row.fetchAll($0, sql: "SELECT source, COUNT(*) AS n FROM entries GROUP BY source") }) {
            let source: String = row["source"]
            let n: Int = row["n"]
            expectedCounts[source] = n
        }
        var metadata: [String: (String, String, String)] = [:]
        for row in try await queue.read({ try Row.fetchAll($0, sql: "SELECT source, license, version, display_name FROM dict_metadata") }) {
            let source: String = row["source"]
            let license: String = row["license"]
            let version: String = row["version"]
            let name: String = row["display_name"]
            metadata[source] = (license, version, name)
        }

        try await useSeedClone()
        _ = try await db.entryCount()   // open the clone before timing
        let start = CFAbsoluteTimeGetCurrent()
        let stats = try await db.fetchSourceStats()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("⏱ fetchSourceStats on the seed: \(String(format: "%.3f", elapsed))s")

        XCTAssertEqual(stats.map(\.source).sorted(), Self.allBundledSourceIDs.sorted())
        XCTAssertEqual(stats.map(\.count), stats.map(\.count).sorted(by: >), "count-desc base order")
        for stat in stats {
            XCTAssertEqual(stat.count, expectedCounts[stat.source], "\(stat.source) count")
            let meta = try XCTUnwrap(metadata[stat.source], "\(stat.source) metadata")
            XCTAssertEqual(stat.license, meta.0, "\(stat.source) license is the full metadata text")
            XCTAssertEqual(stat.version, meta.1, "\(stat.source) version")
            XCTAssertEqual(stat.displayName, meta.2, "\(stat.source) display name")
        }
        XCTAssertLessThan(elapsed, 3.0, "Settings must not wait seconds for the source list (got \(elapsed)s)")
    }

    /// Versions, display names and URLs (§5.2).
    func testSeedGreekVersions() throws {
        let queue = try Self.openBundledSeedReadOnly()
        let rows = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT source, version, display_name, url FROM dict_metadata")
        }
        let meta = Dictionary(uniqueKeysWithValues: rows.map {
            ($0["source"] as String, ($0["version"] as String, $0["display_name"] as String, $0["url"] as String))
        })
        let expected: [String: (String, String, String)] = [
            "freedict-ell-eng": ("2025.11.23", "Greek – English (FreeDict)", "https://freedict.org/freedict-database/ell-eng/"),
            "wordnet-ell-eng": ("OMW 1.4 / WordNet 3.0", "Greek – English (WordNet)", "https://github.com/okfngr/wordnet"),
            "freedict-eng-ell": ("0.1.1", "English – Greek (FreeDict)", "https://freedict.org/freedict-database/eng-ell/"),
            "wordnet-eng-ell": ("OMW 1.4 / WordNet 3.0", "English – Greek (WordNet)", "https://github.com/okfngr/wordnet"),
        ]
        for (source, values) in expected {
            let actual = try XCTUnwrap(meta[source], "\(source) metadata")
            XCTAssertEqual(actual.0, values.0, "\(source) version")
            XCTAssertEqual(actual.1, values.1, "\(source) display_name")
            XCTAssertEqual(actual.2, values.2, "\(source) url")
        }
    }
}

/// Pure Greek fold / query helpers and the presentation contract (badges,
/// grouping, names, catalog). No database.
final class GreekFoldAndBadgeTests: XCTestCase {

    private let en = Locale(identifier: "en")
    private let ru = Locale(identifier: "ru")
    private let es = Locale(identifier: "es")
    private let ar = Locale(identifier: "ar")
    private let el = Locale(identifier: "el")

    /// Byte-level view: Swift `String ==` is canonical equivalence, which
    /// would hide an NFC/NFD difference.
    private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

    /// Foundation wraps format arguments in bidi isolates (U+2068 … U+2069)
    /// for RTL locales; strip them to compare the visible text.
    private func stripIsolates(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
    }

    private let bundledSources = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng",
                                  "freedict-ell-eng", "wordnet-ell-eng", "freedict-eng-ell", "wordnet-eng-ell"]

    // MARK: Fold parity (port of Scripts/build_greek.py)

    /// `PARITY_FOLDS`. The Python side builds the NFD input with
    /// `unicodedata.normalize("NFD", …)`; `decomposedStringWithCanonicalMapping`
    /// is the same transform.
    private let parityFolds: [(String, String)] = [
        ("Λόγος", "λογοσ"),
        ("ΆΝΘΡΩΠΟΣ", "ανθρωποσ"),
        ("προϊόν", "προιον"),
        ("ΐδιος", "ιδιοσ"),
        ("ΰπνος", "υπνοσ"),
        ("θάλασσα", "θαλασσα"),
        ("λόγος".decomposedStringWithCanonicalMapping, "λογοσ"),
        ("γένος Rudbeckia", "γενοσ Rudbeckia"),
        ("σκύλος", "σκυλοσ"),
        ("ΣΚΥΛΟΣ", "σκυλοσ"),
        ("σοφός σοφός", "σοφοσ σοφοσ"),
    ]

    /// `PARITY_IDENTITY`: left byte-identical; the NFD spellings prove that
    /// non-Greek text is not even re-normalised.
    private let parityIdentity: [String] = [
        "café", "йод", "ёлка", "niños", "كِتَاب", "كتاب", "apple",
        "йод".decomposedStringWithCanonicalMapping,
        "niños".decomposedStringWithCanonicalMapping,
        "café".decomposedStringWithCanonicalMapping,
    ]

    func testFoldGreekParityFolds() {
        for (raw, expected) in parityFolds {
            let folded = Search.foldGreek(raw)
            XCTAssertEqual(scalars(folded), scalars(expected), "fold(\(raw))")
            XCTAssertEqual(scalars(Search.foldGreek(folded)), scalars(folded), "idempotent for \(raw)")
        }
    }

    func testFoldGreekParityIdentity() {
        for text in parityIdentity {
            XCTAssertEqual(Array(Search.foldGreek(text).utf8), Array(text.utf8), "byte-identical: \(text)")
            XCTAssertEqual(Array(DictAppTests.decomposeGreek(text).utf8), Array(text.utf8),
                           "decomposeGreek is byte-identical on non-Greek: \(text)")
        }
    }

    /// Edge cases: empty input, Greek Extended (polytonic, iota subscript),
    /// and a mixed Greek + Cyrillic string whose Cyrillic half (й) must survive.
    func testFoldGreekEdgeCases() {
        XCTAssertEqual(Search.foldGreek(""), "")
        XCTAssertEqual(scalars(Search.foldGreek("ᾄδω")), scalars("αδω"), "Greek Extended: marks and ypogegrammeni dropped")
        XCTAssertEqual(scalars(Search.foldGreek("Ὅμηρος")), scalars("ομηροσ"), "polytonic breathing + accent dropped")
        XCTAssertEqual(scalars(Search.foldGreek("йод λόγος")), scalars("йод λογοσ"), "only the Greek half folds")
        XCTAssertEqual(scalars(Search.foldGreek("123")), scalars("123"))
    }

    // MARK: ftsQuery

    /// `йод`, `ёлка`, `niños`, `كتاب`, `apple`, `word99999` (and a multi-word
    /// and NFD spelling) → `match == q + "*"` and `rankKey == q`, byte for byte
    /// (Russian й and Spanish / Arabic regression guard).
    func testFtsQueryLeavesNonGreekQueriesByteIdentical() throws {
        let queries = ["йод", "ёлка", "niños", "كتاب", "كِتَاب", "apple", "word99999", "кошка собака", "café",
                       "niños".decomposedStringWithCanonicalMapping, "йод".decomposedStringWithCanonicalMapping]
        for q in queries {
            let fts = Search.ftsQuery(sanitized: q)
            XCTAssertEqual(Array(fts.match.utf8), Array((q + "*").utf8), "match for '\(q)' must be q*")
            XCTAssertEqual(Array(fts.rankKey.utf8), Array(q.utf8), "rankKey for '\(q)' must be q")
        }
    }

    /// `σκύλος` and `σκυλος` → `(q*) OR (σκυλοσ*)` with `rankKey == "σκυλοσ"`;
    /// an already-folded `σκυλοσ` stays single-branch; NFD input keeps its raw
    /// branch byte-identical; mixed Greek/Latin folds only the Greek.
    func testFtsQueryGreekUsesFoldedOrBranch() throws {
        let accented = Search.ftsQuery(sanitized: "σκύλος")
        XCTAssertEqual(scalars(accented.match), scalars("(σκύλος*) OR (σκυλοσ*)"))
        XCTAssertEqual(scalars(accented.rankKey), scalars("σκυλοσ"))

        let finalSigma = Search.ftsQuery(sanitized: "σκυλος")
        XCTAssertEqual(scalars(finalSigma.match), scalars("(σκυλος*) OR (σκυλοσ*)"), "ς differs from σ → two branches")
        XCTAssertEqual(scalars(finalSigma.rankKey), scalars("σκυλοσ"))

        let folded = Search.ftsQuery(sanitized: "σκυλοσ")
        XCTAssertEqual(scalars(folded.match), scalars("σκυλοσ*"), "already folded → single branch")
        XCTAssertEqual(scalars(folded.rankKey), scalars("σκυλοσ"))

        let nfd = "σκύλος".decomposedStringWithCanonicalMapping
        let nfdQuery = Search.ftsQuery(sanitized: nfd)
        XCTAssertEqual(scalars(nfdQuery.match), scalars("(" + nfd + "*) OR (σκυλοσ*)"), "raw branch keeps the typed bytes")

        let mixed = Search.ftsQuery(sanitized: "γένος Rudbeckia")
        XCTAssertEqual(scalars(mixed.match), scalars("(γένος Rudbeckia*) OR (γενοσ Rudbeckia*)"))
        XCTAssertEqual(scalars(mixed.rankKey), scalars("γενοσ Rudbeckia"))
    }

    // MARK: Badges

    private func entry(_ source: String) -> DictionaryEntry {
        DictionaryEntry(id: nil, word: "x", definition: "", phonetic: "", pos: "", source: source, createdAt: nil)
    }

    /// `sourceLabel` for all nine bundled IDs, exact strings with U+2013 and
    /// U+00B7 (§2); a custom source (including a look-alike of a bundled ID)
    /// stays `.capitalized`.
    func testSourceLabelForAllBundledSources() throws {
        let expected: [String: String] = [
            "freedict-ell-eng": "El\u{2013}En \u{00B7} FD",
            "wordnet-ell-eng": "El\u{2013}En \u{00B7} WN",
            "freedict-eng-ell": "En\u{2013}El \u{00B7} FD",
            "wordnet-eng-ell": "En\u{2013}El \u{00B7} WN",
            "freedict-eng-spa": "En\u{2013}Es \u{00B7} FD",
            "wordnet-spa-eng": "Es\u{2013}En \u{00B7} WN",
            "wordnet-arb-eng": "Ar\u{2013}En \u{00B7} WN",
            "wordnet": "WordNet",
            "openrussian": "OpenRussian",
        ]
        XCTAssertEqual(Set(expected.keys), Set(bundledSources))
        for (source, label) in expected {
            XCTAssertEqual(scalars(entry(source).sourceLabel), scalars(label), "\(source) badge")
        }
        // Byte-level shape of a bilingual badge: XX U+2013 YY U+0020 U+00B7 U+0020 ZZ.
        XCTAssertEqual(scalars(entry("freedict-ell-eng").sourceLabel),
                       [0x45, 0x6C, 0x2013, 0x45, 0x6E, 0x20, 0xB7, 0x20, 0x46, 0x44])

        XCTAssertEqual(entry("test_import_fixture").sourceLabel, "Test_Import_Fixture")
        XCTAssertEqual(entry("freedict-spa-eng").sourceLabel, "Freedict-Spa-Eng",
                       "an import named like a bundled ID is not bundled")
    }

    /// `badgeAccessibilityLabel` (en) for every bundled ID per §2; `nil` for a
    /// custom import (VoiceOver then reads the visible text).
    func testBadgeAccessibilityLabelEnglish() throws {
        let expected: [String: String] = [
            "freedict-ell-eng": "Greek to English, FreeDict",
            "wordnet-ell-eng": "Greek to English, WordNet",
            "freedict-eng-ell": "English to Greek, FreeDict",
            "wordnet-eng-ell": "English to Greek, WordNet",
            "freedict-eng-spa": "English to Spanish, FreeDict",
            "wordnet-spa-eng": "Spanish to English, WordNet",
            "wordnet-arb-eng": "Arabic to English, WordNet",
            "wordnet": "English, WordNet",
            "openrussian": "Russian to English, OpenRussian",
        ]
        for source in bundledSources {
            XCTAssertEqual(SettingsViewModel.badgeAccessibilityLabel(forSource: source, locale: en), expected[source],
                           "\(source) VoiceOver label")
        }
        XCTAssertNil(SettingsViewModel.badgeAccessibilityLabel(forSource: "test_import_fixture", locale: en))
        XCTAssertNil(SettingsViewModel.badgeAccessibilityLabel(forSource: "freedict-spa-eng", locale: en),
                     "a custom import with a bundled-looking name has no label")
    }

    /// `badgeAccessibilityLabel` resolves in ru / es / ar / el: exact values for the
    /// Greek pair, and for every bundled ID no raw key, no arrow, not the
    /// English text, and the localized language names plus the brand.
    func testBadgeAccessibilityLabelResolvesInAllLocales() throws {
        let exact: [(Locale, String, String)] = [
            (ru, "freedict-ell-eng", "Греческий – Английский, FreeDict"),
            (ru, "wordnet-eng-ell", "Английский – Греческий, WordNet"),
            (ru, "wordnet", "Английский, WordNet"),
            (es, "freedict-ell-eng", "Griego a Inglés, FreeDict"),
            (es, "wordnet-eng-ell", "Inglés a Griego, WordNet"),
            (es, "wordnet", "Inglés, WordNet"),
            (ar, "freedict-ell-eng", "اليونانية إلى الإنجليزية، FreeDict"),
            (ar, "wordnet-eng-ell", "الإنجليزية إلى اليونانية، WordNet"),
            (ar, "wordnet", "الإنجليزية، WordNet"),
            (el, "freedict-ell-eng", "Ελληνικά προς Αγγλικά, FreeDict"),
            (el, "wordnet-eng-ell", "Αγγλικά προς Ελληνικά, WordNet"),
            (el, "wordnet", "Αγγλικά, WordNet"),
        ]
        for (locale, source, value) in exact {
            let label = try XCTUnwrap(SettingsViewModel.badgeAccessibilityLabel(forSource: source, locale: locale))
            XCTAssertEqual(stripIsolates(label), value, "\(locale.identifier) \(source)")
        }

        for locale in [ru, es, ar, el] {
            for source in bundledSources {
                let label = try XCTUnwrap(SettingsViewModel.badgeAccessibilityLabel(forSource: source, locale: locale),
                                          "\(locale.identifier) \(source)")
                let visible = stripIsolates(label)
                XCTAssertFalse(visible.contains("sourceBadge"), "\(locale.identifier) \(source): raw key '\(visible)'")
                XCTAssertFalse(visible.contains("→") || visible.contains("←"), "no arrows for VoiceOver: '\(visible)'")
                XCTAssertNotEqual(visible, SettingsViewModel.badgeAccessibilityLabel(forSource: source, locale: en),
                                  "\(locale.identifier) \(source) must not fall back to English")
                let parsed = DictionaryGrouping.parse(sourceID: source)
                for iso in parsed.languages {
                    let name = SettingsViewModel.languageName(iso3: iso, locale: locale)
                    XCTAssertTrue(visible.contains(name), "\(locale.identifier) \(source): '\(visible)' lacks '\(name)'")
                }
                let brand = source.hasPrefix("freedict") ? "FreeDict" : (source == "openrussian" ? "OpenRussian" : "WordNet")
                XCTAssertTrue(visible.hasSuffix(brand), "\(locale.identifier) \(source): brand last in '\(visible)'")
            }
        }
    }

    // MARK: Grouping and names

    /// The four Greek IDs share pair key `ell-eng`; directions parse as
    /// ell→eng / eng→ell; providers `freedict` / `wordnet`; `pairs(from:)`
    /// yields one Greek pair with all four members. Look-alike imports stay
    /// custom.
    func testGreekSourcesShareEllEngPair() throws {
        let expected: [String: (String, [String])] = [
            "freedict-ell-eng": ("freedict", ["ell", "eng"]),
            "wordnet-ell-eng": ("wordnet", ["ell", "eng"]),
            "freedict-eng-ell": ("freedict", ["eng", "ell"]),
            "wordnet-eng-ell": ("wordnet", ["eng", "ell"]),
        ]
        for (source, (provider, languages)) in expected {
            let parsed = DictionaryGrouping.parse(sourceID: source)
            XCTAssertFalse(parsed.isCustom, source)
            XCTAssertEqual(parsed.provider, provider, source)
            XCTAssertEqual(parsed.languages, languages, source)
            XCTAssertEqual(DictionaryGrouping.pairKey(forSource: source), "ell-eng", source)
            let direction = try XCTUnwrap(SourceStat(source: source, displayName: source, count: 1).direction)
            XCTAssertEqual([direction.from, direction.to], languages, source)
        }
        for lookalike in ["wordnet-ell-eng-v2", "freedict-eng-el", "omw-ell-eng"] {
            XCTAssertEqual(DictionaryGrouping.pairKey(forSource: lookalike), "custom:" + lookalike)
        }

        let stats = DictAppTests.allBundledSourceIDs.map { SourceStat(source: $0, displayName: $0, count: 1) }
        let order = DictionaryGrouping.groupedOrder(stats.map(\.source))
        let pairs = DictionaryGrouping.pairs(from: stats, order: order)
        XCTAssertEqual(pairs.map(\.id).sorted(), ["arb-eng", "ell-eng", "eng", "eng-rus", "eng-spa"])
        let greek = try XCTUnwrap(pairs.first { $0.id == "ell-eng" })
        XCTAssertEqual(Set(greek.sourceIDs), Set(DictAppTests.greekSourceIDs))
        XCTAssertEqual(greek.languages, ["ell", "eng"])
        XCTAssertFalse(greek.isCustom)
        // I1: one enabled Greek member enables the whole pair; none stays none.
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["wordnet", "wordnet-eng-ell"], knownSources: order),
                       Set(["wordnet"] + DictAppTests.greekSourceIDs))
        XCTAssertEqual(DictionaryGrouping.enabledIfAny(["wordnet"], knownSources: order), ["wordnet"])
    }

    /// `defaultOrder(forLanguageCode: "el")` puts the four Greek IDs first, in
    /// `preferredSources["el"]` order; the rest keep their relative order; the
    /// result is a permutation. Without Greek sources (an old seed) it is a
    /// no-op, and other UI languages do not promote Greek.
    func testDefaultOrderForGreekPutsGreekSourcesFirst() throws {
        let seedOrder = ["wordnet", "freedict-eng-spa", "openrussian", "freedict-ell-eng", "wordnet-spa-eng",
                         "wordnet-eng-ell", "freedict-eng-ell", "wordnet-ell-eng", "wordnet-arb-eng"]
        let el = DictionaryDefaults.defaultOrder(forLanguageCode: "el", sources: seedOrder)
        XCTAssertEqual(Array(el.prefix(4)), DictionaryDefaults.preferredSources["el"])
        XCTAssertEqual(Array(el.prefix(4)), DictAppTests.greekSourceIDs)
        XCTAssertEqual(Array(el.dropFirst(4)), ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-spa-eng", "wordnet-arb-eng"])
        XCTAssertEqual(el.sorted(), seedOrder.sorted(), "permutation")

        let preGreek = ["wordnet", "freedict-eng-spa", "openrussian", "wordnet-spa-eng", "wordnet-arb-eng"]
        XCTAssertEqual(DictionaryDefaults.defaultOrder(forLanguageCode: "el", sources: preGreek), preGreek)

        let english = DictionaryDefaults.defaultOrder(forLanguageCode: "en", sources: seedOrder)
        XCTAssertEqual(english.first, "wordnet")
        XCTAssertEqual(DictionaryGrouping.sourceGroups(order: DictionaryGrouping.groupedOrder(english))
                           .first { $0.contains("freedict-ell-eng") }?.count, 4,
                       "grouping keeps the four Greek members contiguous")
    }

    /// `languageName(iso3: "ell")` is capitalised in en / ru / es / ar / el; pair
    /// title "Greek – English" (U+2013) in every locale; providers brand as
    /// "FreeDict" / "WordNet"; directions read "Greek → English" (ar: ←).
    func testGreekLanguageNameAndPairTitle() throws {
        let names: [(Locale, String)] = [(en, "Greek"), (ru, "Греческий"), (es, "Griego"), (ar, "اليونانية"),
                                         (el, "Ελληνικά")]
        for (locale, name) in names {
            XCTAssertEqual(SettingsViewModel.languageName(iso3: "ell", locale: locale), name, locale.identifier)
        }
        for locale in [en, ru, es, el] {
            XCTAssertEqual(SettingsViewModel.languageName(iso3: "ell", locale: locale).first?.isUppercase, true,
                           "\(locale.identifier): capitalised in a title")
        }

        let stats = DictAppTests.greekSourceIDs.map { SourceStat(source: $0, displayName: "Raw \($0)", count: 1) }
        let pair = DictionaryPair(id: "ell-eng", languages: ["ell", "eng"], isCustom: false, sources: stats)
        let titles: [(Locale, String)] = [(en, "Greek – English"), (ru, "Греческий – Английский"),
                                          (es, "Griego – Inglés"), (ar, "اليونانية – الإنجليزية"),
                                          (el, "Ελληνικά – Αγγλικά")]
        for (locale, title) in titles {
            XCTAssertEqual(stripIsolates(SettingsViewModel.displayName(for: pair, locale: locale)), title, locale.identifier)
        }

        XCTAssertEqual(stats.map(SettingsViewModel.infoBlockTitle(for:)), ["FreeDict", "WordNet", "FreeDict", "WordNet"])
        XCTAssertEqual(SettingsViewModel.languageSummary(for: stats[0], locale: en), "Greek → English")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: stats[2], locale: en), "English → Greek")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: stats[0], locale: el), "Ελληνικά → Αγγλικά")
        XCTAssertEqual(SettingsViewModel.languageSummary(for: stats[2], locale: el), "Αγγλικά → Ελληνικά")
        XCTAssertEqual(stripIsolates(SettingsViewModel.languageSummary(for: stats[0], locale: ar) ?? ""),
                       "اليونانية ← الإنجليزية")
    }

    /// `infoSources` gives `[freedict-ell-eng, wordnet-ell-eng,
    /// freedict-eng-ell, wordnet-eng-ell]` for all 24 member permutations; a
    /// custom member always goes last; Spanish keeps its #91 order.
    func testInfoSourcesGreekOrderForAllPermutations() throws {
        let expected = DictAppTests.greekSourceIDs
        func permutations(_ items: [String]) -> [[String]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i -> [[String]] in
                var rest = items
                let head = rest.remove(at: i)
                return permutations(rest).map { [head] + $0 }
            }
        }
        let all = permutations(expected)
        XCTAssertEqual(all.count, 24)
        XCTAssertEqual(Set(all.map { $0.joined(separator: ",") }).count, 24, "24 distinct member orders")
        for order in all {
            let pair = DictionaryPair(id: "ell-eng", languages: ["ell", "eng"], isCustom: false,
                                      sources: order.map { SourceStat(source: $0, displayName: $0, count: 1) })
            XCTAssertEqual(SettingsViewModel.infoSources(for: pair).map(\.source), expected, "members \(order)")
        }

        let stray = SourceStat(source: "mydict-ell-eng", displayName: "x", count: 1)
        let withStray = DictionaryPair(id: "ell-eng", languages: ["ell", "eng"], isCustom: false,
                                       sources: [stray] + expected.reversed().map { SourceStat(source: $0, displayName: $0, count: 1) })
        XCTAssertEqual(SettingsViewModel.infoSources(for: withStray).map(\.source), expected + ["mydict-ell-eng"])

        let spanish = DictionaryPair(id: "eng-spa", languages: ["eng", "spa"], isCustom: false,
                                     sources: ["freedict-eng-spa", "wordnet-spa-eng"].map { SourceStat(source: $0, displayName: $0, count: 1) })
        XCTAssertEqual(SettingsViewModel.infoSources(for: spanish).map(\.source), ["wordnet-spa-eng", "freedict-eng-spa"])
    }

    // MARK: Catalog

    /// `language.el.name`, `credits.dataSources.greekWordnet`, and the changed
    /// `credits.dataSources.freedict` (CC BY-SA 3.0, Freelang, no GPL) /
    /// `credits.dataSources.arabicWordnet` (CC BY-SA 3.0, not CC BY 3.0)
    /// resolve in en / ru / es / ar / el — the Credits half of #106.
    func testGreekCatalogKeysResolveInAllLocales() throws {
        let keys = ["language.el.name", "credits.dataSources.greekWordnet",
                    "credits.dataSources.freedict", "credits.dataSources.arabicWordnet"]
        var english: [String: String] = [:]
        for locale in [en, ru, es, ar, el] {
            for key in keys {
                let value = SettingsViewModel.localizedString(key, locale: locale)
                XCTAssertNotEqual(value, key, "\(locale.identifier): '\(key)' must resolve")
                XCTAssertFalse(value.isEmpty, "\(locale.identifier): '\(key)'")
                if locale == en { english[key] = value }
            }
            let freedict = SettingsViewModel.localizedString("credits.dataSources.freedict", locale: locale)
            XCTAssertTrue(freedict.contains("CC BY-SA 3.0"), "\(locale.identifier) FreeDict credit: \(freedict)")
            XCTAssertTrue(freedict.contains("Freelang"), "\(locale.identifier) FreeDict credit names the Freelang origin")
            XCTAssertTrue(freedict.contains("WikDict"), "\(locale.identifier) FreeDict credit names WikDict")
            XCTAssertFalse(freedict.contains("GPL"), "\(locale.identifier): no GPL in the FreeDict credit (#106)")

            let arabic = SettingsViewModel.localizedString("credits.dataSources.arabicWordnet", locale: locale)
            XCTAssertTrue(arabic.contains("CC BY-SA 3.0"), "\(locale.identifier) Arabic credit: \(arabic)")
            XCTAssertFalse(arabic.contains("CC BY 3.0"), "\(locale.identifier): old CC BY 3.0 label gone (#106)")

            let greek = SettingsViewModel.localizedString("credits.dataSources.greekWordnet", locale: locale)
            XCTAssertTrue(greek.contains("Apache 2.0") && greek.contains("Greek WordNet"), "\(locale.identifier): \(greek)")
        }
        for locale in [ru, es, ar, el] {
            for key in ["language.el.name", "credits.dataSources.freedict", "credits.dataSources.greekWordnet"] {
                XCTAssertNotEqual(SettingsViewModel.localizedString(key, locale: locale), english[key],
                                  "\(locale.identifier): '\(key)' is translated, not the English text")
            }
        }
    }
}

// MARK: - Issue #108: Existing installs get updated bundled data
//
// DESIGN_DOC_108 §6. The app DB is the `setUp` DB; the "bundle" is a tiny
// SQLite built from `DatabaseService.inlineSchema` (rollback journal, like the
// shipped seed) and passed through the `seedIfNeeded(bundledSeedURL:)` seam.

extension DictAppTests {

    /// Every column of one `entries` row, for byte-identical comparisons.
    struct SyncedRow: Equatable {
        var id: Int64
        var word: String
        var wordNormalized: String
        var definition: String
        var phonetic: String
        var pos: String
        var source: String
        var createdAt: String
    }

    private static let syncEngSpa = "freedict-eng-spa"
    private static let oldQuickly = "1. deprisa"
    private static let newQuickly = "1. deprisa, rápido, rápidamente, con prontitud, velozmente, con celeridad"

    private var syncAppPath: String { tempDir.appendingPathComponent("test.sqlite").path }

    /// Inserts `(word, definition, source)` rows (`word_normalized` = lowercased
    /// word) and, when `builtAt` is non-nil, one `dict_metadata` row per source.
    private static func insertSyncRows(_ rows: [(String, String, String)], builtAt: String?,
                                       into conn: Database) throws {
        for (word, definition, source) in rows {
            try conn.execute(
                sql: """
                    INSERT INTO entries(word, word_normalized, definition, phonetic, pos, source)
                    VALUES (?, ?, ?, '', 'adverb', ?)
                    """,
                arguments: [word, word.lowercased(), definition, source])
        }
        guard let builtAt else { return }
        for source in Set(rows.map { $0.2 }) {
            try conn.execute(
                sql: "INSERT OR REPLACE INTO dict_metadata(source, display_name, built_at) VALUES (?, ?, ?)",
                arguments: [source, source, builtAt])
        }
    }

    /// The fixture "bundle": `rows` plus metadata stamped `built_at = builtAt`.
    private func makeSyncBundle(_ rows: [(String, String, String)], builtAt: String = "new") throws -> URL {
        let url = tempDir.appendingPathComponent("bundle.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { conn in
            try conn.execute(sql: DatabaseService.inlineSchema)
            try Self.insertSyncRows(rows, builtAt: builtAt, into: conn)
        }
        try queue.close()
        return url
    }

    /// Writes rows to the app DB. `builtAt: nil` = a custom import (no metadata).
    private func seedSyncApp(_ rows: [(String, String, String)], builtAt: String? = "old") async throws {
        let pool = try DatabasePool(path: syncAppPath)
        try await pool.write { conn in try Self.insertSyncRows(rows, builtAt: builtAt, into: conn) }
    }

    private func syncRows(source: String, path: String? = nil) async throws -> [SyncedRow] {
        let pool = try DatabasePool(path: path ?? syncAppPath)
        return try await pool.read { conn in
            try Row.fetchAll(conn, sql: "SELECT * FROM entries WHERE source = ? ORDER BY id", arguments: [source])
                .map {
                    SyncedRow(id: $0["id"], word: $0["word"], wordNormalized: $0["word_normalized"],
                              definition: $0["definition"], phonetic: $0["phonetic"], pos: $0["pos"],
                              source: $0["source"], createdAt: $0["created_at"])
                }
        }
    }

    /// Throws (failing the test) if the external-content FTS index disagrees with `entries`.
    private func checkFTSIntegrity(path: String? = nil) async throws {
        let pool = try DatabasePool(path: path ?? syncAppPath)
        try await pool.write { conn in
            try conn.execute(sql: "INSERT INTO entries_fts(entries_fts, rank) VALUES('integrity-check', 1)")
        }
    }

    /// §6.1 Upgrade in place: new definition, same id, bookmark kept, FTS
    /// finds the new text and stays consistent.
    func testBundledSyncUpdatesExistingInstallInPlace() async throws {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa)])
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa)])
        let rowsBefore = try await syncRows(source: Self.syncEngSpa)
        let before = try XCTUnwrap(rowsBefore.first)
        try await db.addBookmark(entryId: before.id)
        let ftsBefore = try await db.search(query: "velozmente")
        XCTAssertTrue(ftsBefore.isEmpty, "precondition: the old definition lacks 'velozmente'")

        try await db.seedIfNeeded(bundledSeedURL: bundle)

        let rowsAfter = try await syncRows(source: Self.syncEngSpa)
        let after = try XCTUnwrap(rowsAfter.first)
        XCTAssertTrue(after.definition.contains("rápidamente"), "got \(after.definition)")
        XCTAssertEqual(after.id, before.id, "updated in place: the id is kept")
        let bookmarked = try await db.isBookmarked(entryId: before.id)
        XCTAssertTrue(bookmarked, "the bookmark survives the sync")
        let bookmarks = try await db.fetchBookmarkedEntries()
        XCTAssertEqual(bookmarks.compactMap(\.entry.id), [before.id])
        let hits = try await db.search(query: "velozmente")
        XCTAssertEqual(hits.map(\.word), ["quickly"], "entries_au re-indexed the new definition")
        try await checkFTSIntegrity()
    }

    /// §6.2 Idempotent: the sync closes the gate, and a forced re-run writes nothing.
    func testBundledSyncIsIdempotentAndClosesGate() async throws {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa)])
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa)])

        try await db.seedIfNeeded(bundledSeedURL: bundle)

        let meta = try await db.fetchMetadata(source: Self.syncEngSpa)
        XCTAssertEqual(meta?.builtAt, "new", "refreshMetadata copied the bundle's built_at (gate closed)")
        let again = try await db.syncBundledSources(from: bundle, sources: [Self.syncEngSpa])
        XCTAssertEqual(again.updated, 0, "nothing differs on a second run")
        XCTAssertEqual(again.inserted, 0)
    }

    /// §6.3 Gate: equal `built_at` means no sync, even if the content differs.
    func testBundledSyncSkippedWhenBuiltAtMatches() async throws {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa)], builtAt: "new")
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa)], builtAt: "new")

        try await db.seedIfNeeded(bundledSeedURL: bundle)

        let rows = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(rows.map(\.definition), [Self.oldQuickly], "closed gate: no sync on every launch")
    }

    /// §6.4 Custom imports are never touched, even with a colliding headword.
    func testBundledSyncLeavesCustomImportUntouched() async throws {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa)])
        try await seedSyncApp([("quickly", "my own quickly", "my_dict"),
                               ("velozmente", "my extra row", "my_dict")], builtAt: nil)
        let before = try await syncRows(source: "my_dict")
        let countBefore = try await db.entryCount(source: "my_dict")
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa)])

        try await db.seedIfNeeded(bundledSeedURL: bundle)

        let after = try await syncRows(source: "my_dict")
        XCTAssertEqual(after, before, "custom rows are byte-identical")
        let countAfter = try await db.entryCount(source: "my_dict")
        XCTAssertEqual(countAfter, countBefore)
        XCTAssertEqual(countAfter, 2)
        let engSpa = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(engSpa.map(\.definition), [Self.newQuickly], "the bundled source still synced")
    }

    /// §6.5 A new bundle headword is inserted and searchable; an app headword
    /// the bundle dropped is kept as it was.
    func testBundledSyncInsertsNewHeadwordAndKeepsDroppedOne() async throws {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa),
                               ("slowly", "1. despacio", Self.syncEngSpa)])
        let slowlyBefore = try await syncRows(source: Self.syncEngSpa).filter { $0.word == "slowly" }
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa),
                                         ("swiftly", "1. raudamente", Self.syncEngSpa)])

        try await db.seedIfNeeded(bundledSeedURL: bundle)

        let rows = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(Set(rows.map(\.word)), ["quickly", "slowly", "swiftly"])
        XCTAssertEqual(rows.filter { $0.word == "slowly" }, slowlyBefore, "dropped headword kept unchanged")
        let hits = try await db.search(query: "swiftly")
        XCTAssertEqual(hits.map(\.word), ["swiftly"], "the inserted headword is searchable")
        try await checkFTSIntegrity()
    }

    /// §6.6 One call imports a source missing from the app (rows + metadata)
    /// and syncs the stale one.
    func testSeedIfNeededImportsMissingSourceAndSyncsStaleOne() async throws {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa)])
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa),
                                         ("σκύλος", "1. dog", "freedict-ell-eng")])

        try await db.seedIfNeeded(bundledSeedURL: bundle)

        let greek = try await syncRows(source: "freedict-ell-eng")
        XCTAssertEqual(greek.map(\.definition), ["1. dog"], "missing source imported")
        let greekMeta = try await db.fetchMetadata(source: "freedict-ell-eng")
        XCTAssertEqual(greekMeta?.builtAt, "new", "missing source's metadata imported")
        let engSpa = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(engSpa.map(\.definition), [Self.newQuickly], "stale source synced in the same call")
        let engSpaMeta = try await db.fetchMetadata(source: Self.syncEngSpa)
        XCTAssertEqual(engSpaMeta?.builtAt, "new")
    }

    /// §6.7 Real seed as both the "old install" and the bundle: every source
    /// stale, ~20k eng-spa definitions differ. Simulator budget 10 s (Mac ~1.4 s).
    func testBundledSyncOnRealSeedIsFastAndComplete() async throws {
        try await useSeedClone()
        let clonePath = tempDir.appendingPathComponent("seed-clone.sqlite").path
        let pool = try DatabasePool(path: clonePath)
        try await pool.write { conn in
            try conn.execute(
                sql: "UPDATE entries SET definition = ? WHERE word = 'quickly' AND source = ?",
                arguments: ["**adverb**\n1. deprisa", Self.syncEngSpa])
            try conn.execute(
                sql: "UPDATE entries SET definition = definition || ' ' WHERE source = ? AND id % 3 = 0",
                arguments: [Self.syncEngSpa])
            try conn.execute(sql: "UPDATE dict_metadata SET built_at = 'stale'")
        }

        let start = CFAbsoluteTimeGetCurrent()
        try await db.seedIfNeeded(bundledSeedURL: try Self.greekSeedURL())
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("⏱ seedIfNeeded sync on the real seed: \(String(format: "%.3f", elapsed))s")

        let quickly = try await pool.read { conn in
            try String.fetchOne(conn, sql: "SELECT definition FROM entries WHERE word = 'quickly' AND source = ?",
                                arguments: [Self.syncEngSpa]) ?? ""
        }
        XCTAssertTrue(quickly.contains("rápidamente"), "got \(quickly)")
        let trailing = try await pool.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries WHERE source = ? AND substr(definition, -1) = ' '",
                             arguments: [Self.syncEngSpa]) ?? -1
        }
        XCTAssertEqual(trailing, 0, "every modified eng-spa definition was restored")
        XCTAssertLessThan(elapsed, 10.0, "sync must stay well inside the cold-start budget (got \(elapsed)s)")
    }

    // MARK: Issue #108 failure paths (PM decision 1)

    /// The app's eng-spa `quickly` (old definition, `built_at = "old"`),
    /// bookmarked. Returns the row as stored.
    private func seedBookmarkedOldQuickly() async throws -> SyncedRow {
        try await seedSyncApp([("quickly", Self.oldQuickly, Self.syncEngSpa)])
        let rows = try await syncRows(source: Self.syncEngSpa)
        let row = try XCTUnwrap(rows.first)
        try await db.addBookmark(entryId: row.id)
        return row
    }

    /// The old install is exactly as `before`: same eng-spa rows (ids and
    /// content), the bookmark on the same id, the old `built_at` (gate still
    /// open, so the next launch retries), no new text in FTS, FTS consistent.
    private func assertOldInstallIntact(_ before: SyncedRow, _ context: String,
                                        file: StaticString = #filePath, line: UInt = #line) async throws {
        let rows = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(rows, [before], "\(context): eng-spa rows unchanged", file: file, line: line)
        let bookmarks = try await db.fetchBookmarkedEntries()
        XCTAssertEqual(bookmarks.compactMap(\.entry.id), [before.id],
                       "\(context): bookmark kept on the same id", file: file, line: line)
        let meta = try await db.fetchMetadata(source: Self.syncEngSpa)
        XCTAssertEqual(meta?.builtAt, "old", "\(context): gate stays open for a retry", file: file, line: line)
        let hits = try await db.search(query: "velozmente")
        XCTAssertTrue(hits.isEmpty, "\(context): nothing new reached FTS, got \(hits.map(\.word))",
                      file: file, line: line)
        try await checkFTSIntegrity()
    }

    /// The next launch with a good bundle applies the sync: same id, new
    /// definition, bookmark kept, gate closed, FTS finds the new text.
    private func assertRetrySucceeds(_ before: SyncedRow, file: StaticString = #filePath,
                                     line: UInt = #line) async throws {
        let good = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa)])
        try await db.seedIfNeeded(bundledSeedURL: good)
        let rows = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(rows.map(\.id), [before.id], "retry updates in place", file: file, line: line)
        XCTAssertEqual(rows.map(\.definition), [Self.newQuickly], file: file, line: line)
        let bookmarked = try await db.isBookmarked(entryId: before.id)
        XCTAssertTrue(bookmarked, "bookmark survives the retry", file: file, line: line)
        let meta = try await db.fetchMetadata(source: Self.syncEngSpa)
        XCTAssertEqual(meta?.builtAt, "new", "retry closes the gate", file: file, line: line)
        let hits = try await db.search(query: "velozmente")
        XCTAssertEqual(hits.map(\.word), ["quickly"], file: file, line: line)
        try await checkFTSIntegrity()
    }

    /// A sync that fails inside its transaction does not throw out of
    /// `seedIfNeeded` (the app must still start), keeps the old data and the
    /// old `built_at`, and DETACHes the bundle: the retry ATTACHes the same
    /// alias on the same writer connection, which fails if it is still attached.
    /// The bundle's `entries` lacks `word_normalized`/`phonetic`/`pos`, so
    /// source discovery and the gate succeed but `UPDATE … FROM` cannot prepare.
    func testBundledSyncFailureIsNonFatalAndRetriesNextLaunch() async throws {
        let before = try await seedBookmarkedOldQuickly()
        let bad = tempDir.appendingPathComponent("bad-columns-bundle.sqlite")
        let queue = try DatabaseQueue(path: bad.path)
        try await queue.write { conn in
            try conn.execute(sql: """
                CREATE TABLE entries(id INTEGER PRIMARY KEY, word TEXT NOT NULL,
                                     definition TEXT NOT NULL, source TEXT);
                CREATE TABLE dict_metadata(source TEXT PRIMARY KEY, display_name TEXT NOT NULL,
                    version TEXT NOT NULL DEFAULT '', license TEXT NOT NULL DEFAULT '',
                    url TEXT NOT NULL DEFAULT '', word_count INTEGER NOT NULL DEFAULT 0,
                    built_at TEXT NOT NULL, description TEXT NOT NULL DEFAULT '');
                """)
            try conn.execute(sql: "INSERT INTO entries(word, definition, source) VALUES ('quickly', ?, ?)",
                             arguments: [Self.newQuickly, Self.syncEngSpa])
            try conn.execute(sql: "INSERT INTO dict_metadata(source, display_name, built_at) VALUES (?, 'Bad', 'new')",
                             arguments: [Self.syncEngSpa])
        }
        try queue.close()

        do {
            try await db.seedIfNeeded(bundledSeedURL: bad)
        } catch {
            XCTFail("a failed sync must not throw out of seeding: \(error)")
        }

        try await assertOldInstallIntact(before, "after a failed sync")
        let meta = try await db.fetchMetadata(source: Self.syncEngSpa)
        XCTAssertEqual(meta?.displayName, Self.syncEngSpa, "refreshMetadata skipped after a failed sync")
        try await assertRetrySucceeds(before)
    }

    /// The sync is one transaction: when its INSERT step aborts after the
    /// UPDATE step has already rewritten `quickly`, the UPDATE and its FTS
    /// re-index roll back too. The injected trigger fires only once `quickly`
    /// holds the new text, so an intact `quickly` proves a rollback, not a
    /// skipped UPDATE (a skipped UPDATE would let `swiftly` in and fail below).
    func testBundledSyncRollsBackUpdateWhenInsertStepFails() async throws {
        let before = try await seedBookmarkedOldQuickly()
        let bundle = try makeSyncBundle([("quickly", Self.newQuickly, Self.syncEngSpa),
                                         ("swiftly", "1. raudamente", Self.syncEngSpa)])
        let appPool = try DatabasePool(path: syncAppPath)
        try await appPool.write { conn in
            try conn.execute(sql: """
                CREATE TRIGGER qa_fail_insert BEFORE INSERT ON entries
                WHEN NEW.word = 'swiftly' AND (SELECT definition FROM entries
                    WHERE word = 'quickly' AND source = '\(Self.syncEngSpa)') LIKE '%velozmente%'
                BEGIN SELECT RAISE(ABORT, 'qa: injected failure after the UPDATE step'); END
                """)
        }

        do {
            try await db.seedIfNeeded(bundledSeedURL: bundle)
        } catch {
            XCTFail("a failed sync must not throw out of seeding: \(error)")
        }
        try await assertOldInstallIntact(before, "after a rolled-back sync")

        try await appPool.write { conn in try conn.execute(sql: "DROP TRIGGER qa_fail_insert") }
        try await db.seedIfNeeded(bundledSeedURL: bundle)
        let rows = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(rows.map(\.word), ["quickly", "swiftly"], "retry applies both steps")
        XCTAssertEqual(rows.first?.id, before.id)
        XCTAssertEqual(rows.first?.definition, Self.newQuickly)
        let bookmarked = try await db.isBookmarked(entryId: before.id)
        XCTAssertTrue(bookmarked)
        let meta = try await db.fetchMetadata(source: Self.syncEngSpa)
        XCTAssertEqual(meta?.builtAt, "new")
        try await checkFTSIntegrity()
    }

    /// A bundle that is not SQLite, or has no `entries` table, fails in source
    /// discovery before any write. That throw predates #108 (master does the
    /// same; a shipped bundle cannot be unreadable without a broken build), so
    /// it is asserted as is. What #108 must guarantee: the install is left
    /// exactly as it was, and a later good bundle still syncs.
    func testUnreadableBundleLeavesExistingInstallIntact() async throws {
        let before = try await seedBookmarkedOldQuickly()
        let notSQLite = tempDir.appendingPathComponent("not-sqlite.sqlite")
        try Data(String(repeating: "not an SQLite database\n", count: 200).utf8).write(to: notSQLite)
        let noEntries = tempDir.appendingPathComponent("no-entries.sqlite")
        let queue = try DatabaseQueue(path: noEntries.path)
        try await queue.write { conn in
            try conn.execute(sql: "CREATE TABLE dict_metadata(source TEXT PRIMARY KEY, built_at TEXT)")
            try conn.execute(sql: "INSERT INTO dict_metadata VALUES (?, 'new')", arguments: [Self.syncEngSpa])
        }
        try queue.close()

        for (name, url) in [("not SQLite", notSQLite), ("no entries table", noEntries)] {
            var threw = false
            do { try await db.seedIfNeeded(bundledSeedURL: url) } catch { threw = true }
            XCTAssertTrue(threw, "\(name): source discovery fails before the sync (pre-#108 behaviour)")
            try await assertOldInstallIntact(before, name)
        }
        try await assertRetrySucceeds(before)
    }
}

// MARK: - PR #113 review: rank custom Greek imports on the raw key too

extension DictAppTests {
    /// A custom import stores its accented headword as typed (NFC), while the
    /// folded key only matches bundled Greek rows. Ranking on both keys keeps
    /// the exact custom headword first; ranking on the folded key alone sorts
    /// it below rows that only mention the word in their definitions.
    func testAccentedCustomGreekHeadwordRanksFirst() async throws {
        try await insertNormalizedEntry(word: "σκύλος", normalized: "σκύλος",
                                        definition: "pet", source: "custom_gr")
        for i in 0..<3 {
            try await insertNormalizedEntry(word: "dog\(i)", normalized: "dog\(i)",
                                            definition: "σκύλος σκύλος σκύλος", source: "custom_gr")
        }

        let results = try await db.search(query: "σκύλος")
        XCTAssertEqual(results.first?.word, "σκύλος", "got \(results.map(\.word))")

        let preferred = try await db.searchPreferred(
            query: "σκύλος", groups: [["custom_gr"]], enabledSources: ["custom_gr"])
        XCTAssertEqual(preferred.first?.word, "σκύλος", "got \(preferred.map(\.word))")
    }
}

// MARK: - Issue #88: Greek UI localization
//
// DESIGN_DOC.md §10a. Every lookup names its lproj bundle explicitly, so the
// results do not depend on the simulator's device language or on an in-app
// language persisted by an earlier UI-test run.

extension DictAppTests {
    /// The decoded `SupportedLocales.json`, in picker order.
    static func shippedUILanguages() throws -> [UILanguage] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "SupportedLocales", withExtension: "json"),
                                "SupportedLocales.json must be bundled with the app")
        return try JSONDecoder().decode([UILanguage].self, from: Data(contentsOf: url))
    }

    /// Keys whose value is legitimately identical to English in an LTR
    /// language: pure format strings with no words (DESIGN_DOC.md §3a).
    private static let formatOnlyKeys: Set<String> = [
        "dictionaryPair.title %@ %@",
        "dictionaryInfo.direction.value %@ %@",
        "sourceBadge.accessibilityLabel.single %@ %@",
    ]

    /// The multiset of `%@` / `%lld` specifiers (with positional index) in a
    /// value, sorted so word order does not matter.
    private static func formatSpecifiers(_ value: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"%(\d+\$)?(lld|@)"#)
        let range = NSRange(value.startIndex..., in: value)
        return (regex?.matches(in: value, range: range) ?? [])
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }

    /// The compiled tables of one lproj: plain strings, and plural keys
    /// mapped to their category → format variants.
    private struct CompiledTables {
        let strings: [String: String]
        let plurals: [String: [String: String]]
    }

    /// Reads `<code>.lproj/Localizable.{strings,stringsdict}` straight from
    /// the app bundle. `NSDictionary(contentsOf:)` handles the binary plists
    /// the build writes.
    private static func compiledTables(code: String) throws -> CompiledTables {
        let path = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"),
                                 "'\(code).lproj' must be compiled into the app bundle")
        let lproj = URL(fileURLWithPath: path)
        let strings = try XCTUnwrap(
            NSDictionary(contentsOf: lproj.appendingPathComponent("Localizable.strings")) as? [String: String],
            "\(code).lproj/Localizable.strings must be a readable [String: String] plist")
        let rawPlurals = try XCTUnwrap(
            NSDictionary(contentsOf: lproj.appendingPathComponent("Localizable.stringsdict")) as? [String: Any],
            "\(code).lproj/Localizable.stringsdict must be a readable plist")
        var plurals: [String: [String: String]] = [:]
        for (key, entry) in rawPlurals {
            let entry = try XCTUnwrap(entry as? [String: Any], "\(code): '\(key)' is not a dictionary")
            var variants: [String: String] = [:]
            for case let rule as [String: Any] in entry.values
            where rule["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType" {
                for (category, format) in rule where !category.hasPrefix("NSString") {
                    variants[category] = format as? String
                }
            }
            plurals[key] = variants
        }
        return CompiledTables(strings: strings, plurals: plurals)
    }

    /// `el` in the manifest: `nativeName` "Ελληνικά" (precomposed NFC),
    /// `displayKey` "language.el.name", codes ⊇ {en, ru, es, ar, el}, `el`
    /// last, no duplicate codes.
    func testSupportedLocalesManifestIncludesGreek() throws {
        let languages = try Self.shippedUILanguages()
        let codes = languages.map(\.code)
        XCTAssertTrue(Set(codes).isSuperset(of: ["en", "ru", "es", "ar", "el"]),
                      "the five shipped UI languages must all be offered; got \(codes)")
        XCTAssertEqual(Set(codes).count, codes.count, "manifest codes must be unique; got \(codes)")
        XCTAssertEqual(codes.last, "el", "picker order = manifest order: Ελληνικά is appended after العربية")

        let el = try XCTUnwrap(languages.first { $0.code == "el" }, "Manifest must include Greek (code 'el')")
        XCTAssertEqual(el.nativeName, "Ελληνικά")
        XCTAssertEqual(el.nativeName.unicodeScalars.map(\.value),
                       [0x395, 0x3BB, 0x3BB, 0x3B7, 0x3BD, 0x3B9, 0x3BA, 0x3AC],
                       "nativeName must be NFC with a precomposed ά (U+03AC), not α + U+0301")
        XCTAssertEqual(el.displayKey, "language.el.name")

        // The display key resolves in its own and in the English table.
        let elBundle = try Self.lprojBundle(forLocale: "el")
        let enBundle = try Self.lprojBundle(forLocale: "en")
        XCTAssertEqual(elBundle.localizedString(forKey: el.displayKey, value: nil, table: nil), "Ελληνικά")
        XCTAssertEqual(enBundle.localizedString(forKey: el.displayKey, value: nil, table: nil), "Greek")
    }

    /// Shared manager lists `el`; a persisted "el" resolves to Greek with the
    /// `el.lproj` bundle; switching away and back persists each choice; a
    /// persisted "el" without a manifest entry falls back to English.
    @MainActor
    func testLocalizationManagerSupportsGreek() throws {
        XCTAssertTrue(LocalizationManager.shared.supportedLanguages.contains { $0.code == "el" },
                      "the shared manager must load Greek from SupportedLocales.json")
        let supported = LocalizationManager.shared.supportedLanguages
        XCTAssertEqual(LocalizationManager.resolveInitialLanguage(persistedCode: "el", supported: supported).code, "el")

        let settings = SettingsService(store: InMemoryKeyValueStore())
        settings.selectedUILanguageCode = "el"
        let manager = LocalizationManager(settingsService: settings, bundle: .main)
        XCTAssertEqual(manager.currentLanguage.code, "el")
        XCTAssertEqual(manager.currentLanguage.nativeName, "Ελληνικά")
        XCTAssertEqual(manager.currentLocale.identifier, "el")
        XCTAssertEqual(manager.localizedBundle.bundleURL.lastPathComponent, "el.lproj",
                       "plain-String lookups must read el.lproj, not fall back to .main")
        XCTAssertEqual(manager.localized("tab.settings"), "Ρυθμίσεις")
        XCTAssertEqual(Locale.Language(identifier: manager.currentLanguage.code).characterDirection, .leftToRight,
                       "Greek is LTR: DictApp derives layoutDirection from this, so no RTL mirroring")

        let english = try XCTUnwrap(manager.supportedLanguages.first { $0.code == "en" })
        let greek = try XCTUnwrap(manager.supportedLanguages.first { $0.code == "el" })
        manager.setLanguage(english)
        XCTAssertEqual(settings.selectedUILanguageCode, "en")
        XCTAssertEqual(manager.localized("tab.settings"), "Settings")
        manager.setLanguage(greek)
        XCTAssertEqual(settings.selectedUILanguageCode, "el")
        XCTAssertEqual(manager.localized("tab.settings"), "Ρυθμίσεις")
        XCTAssertEqual(LocalizationManager(settingsService: settings, bundle: .main).currentLanguage.code, "el",
                       "a relaunched manager picks the persisted Greek choice up")

        // An old manifest without Greek: a stale persisted "el" must not crash
        // or invent a language; it degrades to English.
        let englishOnly = [UILanguage(code: "en", displayKey: "language.en.name", nativeName: "English")]
        XCTAssertEqual(LocalizationManager.resolveInitialLanguage(persistedCode: "el", supported: englishOnly).code, "en")
    }

    /// Permanent completeness gate for every manifest language: an lproj
    /// exists; its strings / stringsdict key sets equal en's; no value is
    /// empty, padded, or the raw key; every value differs from English except
    /// the three format-only keys; the specifier multiset matches en (per
    /// plural variant); every plural has `other`, and `el` has exactly
    /// `one` / `other`. Greek values contain Greek letters and use "…", not "...".
    func testEveryCatalogKeyIsTranslatedInEveryShippedLanguage() throws {
        let codes = try Self.shippedUILanguages().map(\.code)
        XCTAssertTrue(codes.contains("en"), "English is the source language and must ship")
        let en = try Self.compiledTables(code: "en")
        XCTAssertGreaterThanOrEqual(en.strings.count + en.plurals.count, 90,
                                    "en tables look truncated (\(en.strings.count) + \(en.plurals.count)); the gate would be vacuous")
        XCTAssertTrue(Set(en.plurals.keys).isSuperset(of: ["dictionary.entries.count %lld",
                                                          "manageDictionaries.import.result.success %lld %@"]))

        for code in codes where code != "en" {
            let tables = try Self.compiledTables(code: code)

            XCTAssertEqual(Set(en.strings.keys).subtracting(tables.strings.keys).sorted(), [],
                           "\(code).lproj is missing keys (they would render as raw keys)")
            XCTAssertEqual(Set(tables.strings.keys).subtracting(en.strings.keys).sorted(), [],
                           "\(code).lproj has keys English does not")
            for (key, english) in en.strings {
                guard let value = tables.strings[key] else { continue }
                XCTAssertFalse(value.isEmpty, "\(code): '\(key)' is empty")
                XCTAssertNotEqual(value, key, "\(code): '\(key)' renders the raw key")
                XCTAssertEqual(value, value.trimmingCharacters(in: .whitespacesAndNewlines),
                               "\(code): '\(key)' has leading/trailing whitespace")
                if !Self.formatOnlyKeys.contains(key) {
                    XCTAssertNotEqual(value, english, "\(code): '\(key)' falls back to the English text")
                }
                XCTAssertEqual(Self.formatSpecifiers(value), Self.formatSpecifiers(english),
                               "\(code): '\(key)' specifiers differ from en ('\(value)' vs '\(english)')")
            }

            XCTAssertEqual(Set(tables.plurals.keys), Set(en.plurals.keys), "\(code): plural key set differs from en")
            for (key, englishVariants) in en.plurals {
                let variants = tables.plurals[key] ?? [:]
                let englishOther = try XCTUnwrap(englishVariants["other"], "en: '\(key)' has no 'other'")
                XCTAssertNotNil(variants["other"], "\(code): '\(key)' has no 'other' variant")
                for (category, value) in variants {
                    XCTAssertFalse(value.isEmpty, "\(code): '\(key)' [\(category)] is empty")
                    XCTAssertEqual(Self.formatSpecifiers(value), Self.formatSpecifiers(englishOther),
                                   "\(code): '\(key)' [\(category)] specifiers differ from en")
                    XCTAssertNotEqual(value, englishVariants[category], "\(code): '\(key)' [\(category)] is English")
                }
                if code == "el" {
                    XCTAssertEqual(Set(variants.keys), ["one", "other"],
                                   "el: CLDR plural categories are exactly one / other for '\(key)'")
                }
            }

            if code == "el" {
                let greekLetter = try NSRegularExpression(pattern: "[\u{0370}-\u{03FF}\u{1F00}-\u{1FFF}]")
                for (key, value) in tables.strings where !Self.formatOnlyKeys.contains(key) {
                    let range = NSRange(value.startIndex..., in: value)
                    XCTAssertNotNil(greekLetter.firstMatch(in: value, range: range),
                                    "el: '\(key)' has no Greek letter: '\(value)'")
                    XCTAssertFalse(value.contains("..."), "el: '\(key)' must use the ellipsis character …")
                }
            }
        }
    }

    /// The pinned §4b values, read from `el.lproj`; plus the format strings
    /// a user sees (not-found message, pair title, (i) label, directions).
    func testGreekStringsCompiledIntoLproj() throws {
        let elBundle = try Self.lprojBundle(forLocale: "el")
        let el = Locale(identifier: "el")

        let cases: [(key: String, greek: String)] = [
            ("tab.search", "Αναζήτηση"), ("tab.history", "Ιστορικό"),
            ("tab.bookmarks", "Σελιδοδείκτες"), ("tab.settings", "Ρυθμίσεις"),
            ("search.title", "Λεξικό"), ("search.prompt", "Αναζήτηση λέξεων…"),
            ("search.recent.title", "Πρόσφατα"), ("search.notFound.title", "Δεν βρέθηκε"),
            ("history.title", "Ιστορικό"), ("history.clear", "Εκκαθάριση"), ("history.empty.title", "Χωρίς ιστορικό"),
            ("bookmarks.title", "Σελιδοδείκτες"), ("bookmarks.empty.title", "Χωρίς σελιδοδείκτες"),
            ("settings.title", "Ρυθμίσεις"),
            ("settings.language.section", "Γλώσσα διεπαφής"), ("settings.language.picker", "Γλώσσα"),
            ("settings.sorting.section", "Ταξινόμηση αποτελεσμάτων"), ("settings.sorting.mode", "Ταξινόμηση κατά"),
            ("settings.sorting.relevance", "Συνάφεια"), ("settings.sorting.preferred", "Προτιμώμενο λεξικό πρώτα"),
            ("settings.dictionaries.section", "Λεξικά"), ("settings.dictionaryOrder.title", "Σειρά λεξικών"),
            ("settings.manageDictionaries", "Διαχείριση λεξικών"), ("manageDictionaries.title", "Διαχείριση λεξικών"),
            ("settings.support.section", "Υποστήριξη"), ("settings.support.reportBug", "Αναφορά σφάλματος"),
            ("settings.support.credits", "Συντελεστές"), ("credits.title", "Συντελεστές"),
            ("settings.writeReview", "Γράψτε μια κριτική"), ("settings.version", "Έκδοση"),
            ("settings.learningMode.section", "Λειτουργία εκμάθησης"), ("common.comingSoon", "Έρχεται σύντομα"),
            ("about.section", "Πληροφορίες"), ("about.tagline", "Λεξικό εκτός σύνδεσης"),
            ("app.loading", "Φόρτωση λεξικού…"), ("common.loading", "Φόρτωση…"),
            ("language.en.name", "Αγγλικά"), ("language.ru.name", "Ρωσικά"), ("language.es.name", "Ισπανικά"),
            ("language.ar.name", "Αραβικά"), ("language.el.name", "Ελληνικά"),
            ("dictionaryInfo.direction", "Κατεύθυνση"), ("dictionaryInfo.language", "Γλώσσα"),
            ("dictionaryInfo.sourceID", "Αναγνωριστικό πηγής"), ("dictionaryInfo.version", "Έκδοση"),
            ("dictionaryInfo.entries", "Λήμματα"), ("dictionaryInfo.license", "Άδεια χρήσης"),
            ("dictionaryInfo.noMetadata",
             "Εισαγόμενο λεξικό. Δεν υπάρχουν διαθέσιμες πληροφορίες έκδοσης ή άδειας χρήσης."),
            ("readingMode.a11y.enable", "Ενεργοποίηση λειτουργίας ανάγνωσης"),
            ("readingMode.a11y.disable", "Απενεργοποίηση λειτουργίας ανάγνωσης"),
            ("definition.a11y.speakWord", "Εκφώνηση λέξης"),
            ("definition.a11y.addBookmark", "Προσθήκη σελιδοδείκτη"),
            ("definition.a11y.removeBookmark", "Αφαίρεση σελιδοδείκτη"),
            ("error.database.title", "Σφάλμα βάσης δεδομένων"),
        ]
        for (key, greek) in cases {
            XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: elBundle, locale: el), greek,
                           "'\(key)' must render its pinned Greek value from el.lproj")
        }

        // Format strings, filled in.
        XCTAssertEqual(String(localized: "search.notFound.description \("σκύλος")", bundle: elBundle, locale: el),
                       "Η λέξη «σκύλος» δεν βρέθηκε σε κανένα λεξικό.")
        XCTAssertEqual(SettingsViewModel.infoButtonLabel(for: "Ελληνικά – Αγγλικά", locale: el),
                       "Λεπτομέρειες: Ελληνικά – Αγγλικά")

        // No-leak control: the same key differs between en and el.
        let enBundle = try Self.lprojBundle(forLocale: "en")
        XCTAssertEqual(String(localized: "tab.search", bundle: enBundle, locale: Locale(identifier: "en")), "Search")
        XCTAssertNotEqual(String(localized: "tab.search", bundle: elBundle, locale: el), "Search")
    }

    /// CLDR `el` has one / other; 0 is `other`. `%lld` is grouped by the `el`
    /// locale ("147.229"), both in the Dictionary order caption and in the
    /// import result; the (i) "Entries" value uses the same grouping.
    func testGreekPluralFormsForEntriesCount() throws {
        let elBundle = try Self.lprojBundle(forLocale: "el")
        let el = Locale(identifier: "el")
        func entries(_ n: Int) -> String {
            String(localized: "dictionary.entries.count \(n)", bundle: elBundle, locale: el)
        }
        XCTAssertEqual(entries(1), "1 λήμμα", "'one' (1) is singular")
        XCTAssertEqual(entries(0), "0 λήμματα", "0 is CLDR 'other' in Greek, not 'one'")
        XCTAssertEqual(entries(2), "2 λήμματα")
        XCTAssertEqual(entries(5), "5 λήμματα")
        XCTAssertEqual(entries(999), "999 λήμματα", "no separator below 1000")
        XCTAssertEqual(entries(1234), "1.234 λήμματα", "el groups from 4 digits with '.'")
        XCTAssertEqual(entries(147229), "147.229 λήμματα")

        func imported(_ n: Int, _ file: String) -> String {
            String(localized: "manageDictionaries.import.result.success \(n) \(file)", bundle: elBundle, locale: el)
        }
        XCTAssertEqual(imported(1, "my_dict"), "Εισήχθη 1 λήμμα από my_dict")
        XCTAssertEqual(imported(0, "my_dict"), "Εισήχθησαν 0 λήμματα από my_dict")
        XCTAssertEqual(imported(2, "my_dict"), "Εισήχθησαν 2 λήμματα από my_dict")
        XCTAssertEqual(imported(147229, "my_dict"), "Εισήχθησαν 147.229 λήμματα από my_dict")

        // (i) detail "Entries" value: `count.formatted(.number.locale(locale))`.
        XCTAssertEqual(147229.formatted(.number.locale(el)), "147.229")
        XCTAssertEqual(1234.formatted(.number.locale(el)), "1.234")

        // Control: the separator comes from the locale, not from the catalog.
        let enBundle = try Self.lprojBundle(forLocale: "en")
        XCTAssertEqual(String(localized: "dictionary.entries.count \(147229)", bundle: enBundle,
                              locale: Locale(identifier: "en")), "147,229 entries")
    }

    /// PM decision 2: the import result follows the in-app language (`el`
    /// picked in-app → Greek text, whatever the device language), for the
    /// one / other / zero success forms and the unsupported-type message; an
    /// in-app switch to English flips the next message to English.
    @MainActor
    func testImportResultMessageFollowsInAppLanguage() async throws {
        let settings = SettingsService(store: InMemoryKeyValueStore())
        settings.selectedUILanguageCode = "el"
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        XCTAssertEqual(localization.currentLanguage.code, "el", "precondition: in-app language is Greek")
        let vm = ManageDictionariesViewModel(settingsService: settings, localization: localization)

        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "test_import_fixture", withExtension: "json"))
        await vm.performImport(url: fixture)
        XCTAssertEqual(vm.importResult, "Εισήχθησαν 10 λήμματα από test_import_fixture")
        XCTAssertFalse(vm.isImporting)
        let imported = try await db.search(query: "qaflux")
        XCTAssertEqual(imported.first?.source, "test_import_fixture", "the rows really landed")

        let one = tempDir.appendingPathComponent("greek_one.json")
        try Data(#"[{"word": "καλημέρα", "definition": "good morning"}]"#.utf8).write(to: one)
        await vm.performImport(url: one)
        XCTAssertEqual(vm.importResult, "Εισήχθη 1 λήμμα από greek_one", "CLDR 'one'")

        let empty = tempDir.appendingPathComponent("empty.json")
        try Data("[]".utf8).write(to: empty)
        await vm.performImport(url: empty)
        XCTAssertEqual(vm.importResult, "Εισήχθησαν 0 λήμματα από empty", "0 is 'other' in Greek")

        let unsupported = tempDir.appendingPathComponent("notes.txt")
        try Data("not a dictionary".utf8).write(to: unsupported)
        await vm.performImport(url: unsupported)
        XCTAssertEqual(vm.importResult, "Μη υποστηριζόμενος τύπος αρχείου: .txt")

        // Switch the in-app language: the same view model now reports in English.
        let english = try XCTUnwrap(localization.supportedLanguages.first { $0.code == "en" })
        localization.setLanguage(english)
        await vm.performImport(url: one)
        XCTAssertEqual(vm.importResult, "Imported 1 entry from greek_one")
        await vm.performImport(url: unsupported)
        XCTAssertEqual(vm.importResult, "Unsupported file type: .txt")
    }
}

extension SettingsViewModelPairTests {
    /// Inserts `count` rows for `source` (the class's `seed(source:)` only
    /// knows the pre-Greek counts).
    private func seedRows(source: String, count: Int) async throws {
        let pool = try DatabasePool(path: dbPath)
        try await pool.writeWithoutTransaction { db in
            for i in 0..<count {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: ["\(source)-w\(i)", "\(source)-w\(i)", "def \(i)", "", "noun", source]
                )
            }
        }
    }

    /// First launch in `el` (nil stored order): the Greek pair is row 1
    /// ("Ελληνικά – Αγγλικά"), its sources in `DictionaryDefaults["el"]`
    /// order even though their counts are scattered, other titles Greek; the
    /// order is persisted and a second load is idempotent. The same seed in
    /// English keeps `eng` first, and a stored order survives a switch to Greek.
    @MainActor
    func testFirstLaunchGreekPutsGreekPairFirst() async throws {
        try await seedBundled()   // wordnet 7, openrussian 6, freedict-eng-spa 5, wordnet-spa-eng 4, wordnet-arb-eng 3
        // Distinct counts that scatter the Greek sources through the count-desc
        // base order, in an order unlike the mapping's.
        let greekCounts = ["wordnet-eng-ell": 9, "wordnet-ell-eng": 8, "freedict-ell-eng": 2, "freedict-eng-ell": 1]
        for (source, count) in greekCounts { try await seedRows(source: source, count: count) }
        let greekIDs = DictAppTests.greekSourceIDs
        XCTAssertEqual(DictionaryDefaults.preferredSources["el"], greekIDs)

        let (vm, settings, _) = makeViewModel(languageCode: "el")
        XCTAssertNil(settings.dictionaryOrder, "precondition: first launch")
        await vm.loadDictionaries()

        let expectedOrder = greekIDs + ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"]
        XCTAssertEqual(vm.dictionaries.map(\.id), ["ell-eng", "eng", "eng-rus", "eng-spa", "arb-eng"])
        XCTAssertEqual(vm.dictionaries.map(\.displayName),
                       ["Ελληνικά – Αγγλικά", "Αγγλικά", "Ρωσικά – Αγγλικά", "Ισπανικά – Αγγλικά", "Αραβικά – Αγγλικά"],
                       "titles follow the in-app Greek UI, not the process locale")
        let greekRow = try XCTUnwrap(vm.dictionaries.first)
        XCTAssertEqual(greekRow.pair.sourceIDs, greekIDs, "members in DictionaryDefaults[\"el\"] order")
        XCTAssertEqual(greekRow.count, 20, "row count is the sum of the four Greek sources")
        XCTAssertTrue(vm.dictionaries.allSatisfy(\.isEnabled))
        XCTAssertEqual(settings.dictionaryOrder, expectedOrder, "the derived default is persisted")
        XCTAssertEqual(DictionaryGrouping.groupedOrder(expectedOrder), expectedOrder, "and already grouped")

        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.map(\.id).first, "ell-eng", "second load idempotent")
        XCTAssertEqual(settings.dictionaryOrder, expectedOrder)

        // Same seed, English UI: no Greek promotion (counts pull it to row 2).
        let (english, _, _) = makeViewModel(languageCode: "en")
        await english.loadDictionaries()
        XCTAssertEqual(english.dictionaries.map(\.id), ["eng", "ell-eng", "eng-rus", "eng-spa", "arb-eng"])
        XCTAssertEqual(english.dictionaries.dropFirst().first?.displayName, "Greek – English")

        // #74 rule: an existing user switching to Greek keeps their order.
        let userOrder = ["wordnet-arb-eng", "wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng"] + greekIDs
        let (switched, switchedSettings, _) = makeViewModel(languageCode: "el", storedOrder: userOrder)
        await switched.loadDictionaries()
        XCTAssertEqual(switched.dictionaries.map(\.id), ["arb-eng", "eng", "eng-rus", "eng-spa", "ell-eng"])
        XCTAssertEqual(switched.dictionaries.last?.displayName, "Ελληνικά – Αγγλικά")
        XCTAssertEqual(switchedSettings.dictionaryOrder, userOrder, "a stored order is never overridden")
    }
}

extension DictionaryDefaultsTests {
    /// Bundled + Greek IDs in a count-desc order → the four Greek IDs first in
    /// mapping order, the rest in their incoming order; a permutation, already
    /// grouped, idempotent. Missing Greek sources are skipped; region / case /
    /// ISO-639-3 variants of the code are not mapped.
    func testGreekPromotesAllFourGreekSources() throws {
        let greek = DictAppTests.greekSourceIDs
        let seedOrder = ["wordnet", "wordnet-eng-ell", "openrussian", "freedict-eng-spa", "wordnet-ell-eng",
                         "wordnet-spa-eng", "freedict-eng-ell", "wordnet-arb-eng", "freedict-ell-eng"]
        let result = DictionaryDefaults.defaultOrder(for: language("el"), sources: seedOrder)
        XCTAssertEqual(Array(result.prefix(4)), greek, "all four Greek sources first, in mapping order")
        XCTAssertEqual(Array(result.dropFirst(4)),
                       ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"],
                       "the rest keep their incoming relative order")
        assertPermutation(result, of: seedOrder)
        XCTAssertEqual(DictionaryGrouping.groupedOrder(result), result, "no reshuffle by pair grouping")
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("el"), sources: result), result, "idempotent")

        // Only two Greek sources installed → those two, in mapping order.
        let partial = ["wordnet", "wordnet-eng-ell", "openrussian", "freedict-ell-eng"]
        let partialResult = DictionaryDefaults.defaultOrder(for: language("el"), sources: partial)
        XCTAssertEqual(partialResult, ["freedict-ell-eng", "wordnet-eng-ell", "wordnet", "openrussian"])
        assertPermutation(partialResult, of: partial)

        // No Greek source at all (a pre-#87 seed) → unchanged, nothing invented.
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("el"), sources: bundledSources), bundledSources)
        XCTAssertEqual(DictionaryDefaults.defaultOrder(for: language("el"), sources: []), [])

        // The lookup is by exact manifest code.
        for code in ["el-GR", "EL", "ell"] {
            XCTAssertEqual(DictionaryDefaults.defaultOrder(forLanguageCode: code, sources: seedOrder), seedOrder,
                           "'\(code)' is not a shipped code and must not promote Greek")
        }
    }
}

// MARK: - Issue #111: Instant start, background unpack of the bundled seed
//
// DESIGN_DOC_111 §7.5, plus PM decisions 3 (re-run on landing), 4 (a failure
// never blocks) and 7 (no writable connection on someone else's file). The app
// DB is the `setUp` DB or a seed clone. Fixture "bundles" are tiny SQLite
// files with the seed's shape (`inlineSchema`, one `dict_metadata` row per
// source in seed order, `word_count` = its rows); the real seed is used where
// its size or shipped content matters. Seams: `DatabaseService.
// unpackFailureAfterInsert` (a kill mid-source) and `unpackSourceDelay`, set in
// the argument domain where `-unpackSourceDelay` lands.

extension DictAppTests {

    // MARK: Fixtures

    /// The seed's sources in `dict_metadata` rowid order (= entry block order).
    static let seedOrder = ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng",
                            "wordnet-ell-eng", "wordnet-eng-ell", "freedict-ell-eng", "freedict-eng-ell"]

    /// Four fixture sources with distinct sizes (4 + 3 + 2 + 1 = 10 rows), in
    /// seed order. Headwords are unique tokens, so a search hits one row.
    static let fixtureSources: [(String, [String])] = [
        ("wordnet", ["qawnalpha", "qawnbeta", "qawngamma", "qawndelta"]),
        ("openrussian", ["qaorone", "qaortwo", "qaorthree"]),
        ("freedict-eng-spa", ["qaesuno", "qaesdos"]),
        ("wordnet-spa-eng", ["qawsone"]),
    ]

    /// One `dict_metadata` row of the real seed.
    struct BundleSource {
        let source: String
        let wordCount: Int
        let builtAt: String
        let displayName: String
        let license: String
        let version: String
    }

    /// The real seed's metadata rows in rowid order.
    private static func realSeedMetadata() throws -> [BundleSource] {
        try openBundledSeedReadOnly().read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT source, word_count, built_at, display_name, license, version
                FROM dict_metadata ORDER BY rowid
                """).map {
                BundleSource(source: $0["source"], wordCount: $0["word_count"], builtAt: $0["built_at"],
                             displayName: $0["display_name"], license: $0["license"], version: $0["version"])
            }
        }
    }

    /// A fixture bundle: `sources` (id, headwords) in seed order, each with a
    /// metadata row (`display_name` "<prefix> <id>", `word_count` = its rows,
    /// `built_at` = `builtAt`). Definitions are "<word> in <source>" plus
    /// `definitionSuffix`, so a rebuilt bundle can change content.
    private func makeUnpackBundle(_ sources: [(String, [String])], builtAt: String = "b1",
                                  name: String = "unpack-bundle.sqlite", displayPrefix: String = "Bundle",
                                  definitionSuffix: String = "") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { conn in
            try conn.execute(sql: DatabaseService.inlineSchema)
            for (source, words) in sources {
                for word in words {
                    try conn.execute(
                        sql: """
                            INSERT INTO entries(word, word_normalized, definition, phonetic, pos, source)
                            VALUES (?, ?, ?, '', 'noun', ?)
                            """,
                        arguments: [word, word.lowercased(), "\(word) in \(source)\(definitionSuffix)", source])
                }
                try conn.execute(
                    sql: """
                        INSERT INTO dict_metadata(source, display_name, version, license, url, word_count,
                                                  built_at, description)
                        VALUES (?, ?, 'v1', ?, 'https://example.org', ?, ?, ?)
                        """,
                    arguments: [source, "\(displayPrefix) \(source)", "License of \(source)", words.count,
                                builtAt, "About \(source)"])
            }
        }
        try queue.close()
        return url
    }

    /// `source → built_at` of an app DB (default: the `setUp` DB).
    private func appMarkers(path: String? = nil) async throws -> [String: String] {
        let pool = try DatabasePool(path: path ?? syncAppPath)
        return try await pool.read { conn in
            var markers: [String: String] = [:]
            for row in try Row.fetchAll(conn, sql: "SELECT source, built_at FROM dict_metadata") {
                markers[row["source"] as String] = (row["built_at"] as String?) ?? ""
            }
            return markers
        }
    }

    /// `source → row count` of an app DB's `entries`.
    private func appCounts(path: String? = nil) async throws -> [String: Int] {
        let pool = try DatabasePool(path: path ?? syncAppPath)
        return try await pool.read { conn in
            var counts: [String: Int] = [:]
            for row in try Row.fetchAll(conn, sql: "SELECT source, COUNT(*) AS n FROM entries GROUP BY source") {
                counts[row["source"] as String] = row["n"] as Int
            }
            return counts
        }
    }

    /// Sets (or with `nil` removes) `unpackSourceDelay` in the volatile
    /// argument domain, where `-unpackSourceDelay` lands: never persisted, so
    /// a crashed test cannot slow a later app launch. `startBundledUnpack`
    /// reads it once, when it starts.
    static func setUnpackSourceDelay(_ seconds: Double?) {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        if let seconds {
            arguments["unpackSourceDelay"] = seconds
        } else {
            arguments.removeValue(forKey: "unpackSourceDelay")
        }
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// The fraction of an `.unpacking` phase, `nil` for `.idle`.
    private static func fraction(_ phase: DictionaryUnpackStatus.Phase) -> Double? {
        if case .unpacking(let fraction) = phase { return fraction }
        return nil
    }

    /// Records every phase a `DictionaryUnpackStatus` publishes from now on;
    /// the first value is the phase at subscription.
    @MainActor
    final class PhaseRecorder {
        private(set) var phases: [DictionaryUnpackStatus.Phase] = []
        private var subscription: AnyCancellable?

        init(_ status: DictionaryUnpackStatus) {
            subscription = status.$phase.sink { [weak self] in self?.phases.append($0) }
        }
    }

    /// Polls `condition` every 20 ms until it holds or `timeout` passes.
    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    /// Runs `plan` the way the app does (status first, then the background
    /// task) and returns once the loop is done and `.idle` is published. The
    /// task frees its single-flight slot just before it publishes `.idle`, so
    /// `waitForBundledUnpack()` alone can return a moment before `.idle` lands.
    @MainActor
    private func runAppUnpack(_ plan: BundledUnpackPlan) async {
        DictionaryUnpackStatus.shared.begin(plan)
        await db.startBundledUnpack(plan)
        await waitForUnpackIdle()
    }

    /// `waitForBundledUnpack()`, then until `.idle` has been published.
    @MainActor
    private func waitForUnpackIdle() async {
        await db.waitForBundledUnpack()
        let idle = await waitUntil(timeout: 5) { DictionaryUnpackStatus.shared.phase == .idle }
        XCTAssertTrue(idle, "the unpack must end by publishing .idle")
    }

    // MARK: Plan

    /// 1. A fresh install: preparing registers the nine bundled sources
    /// (`built_at ''`, descriptive columns from the bundle), writes no entry,
    /// and plans all nine as new, `wordnet` first and then the UI language's
    /// dictionaries, for every shipped UI language. Re-preparing (a kill
    /// before the first commit) plans the same.
    func testUnpackPlanOnEmptyDatabase() async throws {
        let seedURL = try Self.greekSeedURL()
        let bundle = try Self.realSeedMetadata()
        XCTAssertEqual(bundle.map(\.source), Self.seedOrder, "precondition: the seed's metadata order")
        let wordCounts = Dictionary(uniqueKeysWithValues: bundle.map { ($0.source, $0.wordCount) })
        let seedRows = try await Self.openBundledSeedReadOnly().read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries") ?? 0
        }
        let expected: [String: [String]] = [
            "en": Self.seedOrder,
            "ru": ["wordnet", "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng",
                   "wordnet-ell-eng", "wordnet-eng-ell", "freedict-ell-eng", "freedict-eng-ell"],
            "es": ["wordnet", "wordnet-spa-eng", "freedict-eng-spa", "openrussian", "wordnet-arb-eng",
                   "wordnet-ell-eng", "wordnet-eng-ell", "freedict-ell-eng", "freedict-eng-ell"],
            "ar": ["wordnet", "wordnet-arb-eng", "openrussian", "freedict-eng-spa", "wordnet-spa-eng",
                   "wordnet-ell-eng", "wordnet-eng-ell", "freedict-ell-eng", "freedict-eng-ell"],
            "el": ["wordnet", "freedict-ell-eng", "wordnet-ell-eng", "freedict-eng-ell", "wordnet-eng-ell",
                   "openrussian", "freedict-eng-spa", "wordnet-spa-eng", "wordnet-arb-eng"],
        ]
        let shipped = try Self.shippedUILanguages().map(\.code)
        XCTAssertEqual(Set(shipped), Set(expected.keys), "one expected order per shipped UI language")

        for code in shipped {
            let plan = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: code)
            XCTAssertEqual(plan.items.map(\.source), expected[code], "\(code): unpack order")
            XCTAssertTrue(plan.items.allSatisfy(\.isNew), "\(code): nothing unpacked yet, so every source is new")
            XCTAssertEqual(plan.items.map(\.rowCount), plan.items.map { wordCounts[$0.source] ?? -1 },
                           "\(code): each source weighs its bundle word_count")
            XCTAssertEqual(plan.allRows, seedRows, "\(code): progress covers every seed row")
            XCTAssertEqual(plan.initialFraction, 0, "\(code): a fresh install starts at 0%")
            XCTAssertEqual(plan.seedURL, seedURL)
        }

        let metadata = try await db.fetchMetadata()
        XCTAssertEqual(metadata.map(\.source).sorted(), Self.seedOrder.sorted(), "nine rows, registered once")
        for row in metadata {
            let source = try XCTUnwrap(bundle.first { $0.source == row.source })
            XCTAssertEqual(row.builtAt, "", "\(row.source): registered, not unpacked")
            XCTAssertEqual(row.displayName, source.displayName, "\(row.source): display name")
            XCTAssertEqual(row.license, source.license, "\(row.source): license")
            XCTAssertEqual(row.version, source.version, "\(row.source): version")
            XCTAssertEqual(row.wordCount, source.wordCount, "\(row.source): word count")
        }
        let entries = try await db.entryCount()
        XCTAssertEqual(entries, 0, "preparing never writes entries: the UI must not wait for rows")
        let hits = try await db.search(query: "dog")
        XCTAssertTrue(hits.isEmpty)
    }

    /// 2. Every bundled source complete and current: an empty plan that
    /// starts nothing and keeps the bar hidden. Registration still refreshes
    /// the descriptive columns of current rows but never writes `built_at`,
    /// and with the gate closed rows are not re-synced even if they differ.
    @MainActor
    func testUnpackPlanOnSyncedDatabaseIsEmpty() async throws {
        let first = try makeUnpackBundle(Self.fixtureSources, name: "b1.sqlite")
        try await db.seedIfNeeded(bundledSeedURL: first)
        let markersBefore = try await appMarkers()
        XCTAssertEqual(markersBefore, Dictionary(uniqueKeysWithValues: Self.fixtureSources.map { ($0.0, "b1") }),
                       "precondition: synced")
        var rowsBefore: [String: [SyncedRow]] = [:]
        for (source, _) in Self.fixtureSources {
            rowsBefore[source] = try await syncRows(source: source)
        }

        // Same build stamp, renamed sources and different definitions.
        let renamed = try makeUnpackBundle(Self.fixtureSources, name: "b1-renamed.sqlite",
                                           displayPrefix: "Renamed", definitionSuffix: " (changed)")
        let plan = try await db.prepareBundledSeed(bundledSeedURL: renamed, languageCode: "en")

        XCTAssertTrue(plan.isEmpty, "nothing pending; got \(plan.items.map(\.source))")
        XCTAssertEqual(plan.initialFraction, 1, "a complete install is at 100% before any work")
        let markersAfter = try await appMarkers()
        XCTAssertEqual(markersAfter, markersBefore, "registration never writes built_at for a current source")
        for meta in try await db.fetchMetadata() {
            XCTAssertEqual(meta.displayName, "Renamed \(meta.source)", "descriptive columns follow the bundle")
        }
        for (source, before) in rowsBefore {
            let after = try await syncRows(source: source)
            XCTAssertEqual(after, before, "\(source): a current source is never re-synced")
        }

        let recorder = PhaseRecorder(DictionaryUnpackStatus.shared)
        await runAppUnpack(plan)
        XCTAssertTrue(recorder.phases.allSatisfy { $0 == .idle }, "a normal launch never shows the bar; got \(recorder.phases)")
        let markersFinal = try await appMarkers()
        XCTAssertEqual(markersFinal, markersBefore, "an empty plan writes nothing")
    }

    /// 3. A 1.3.0-shaped install (five sources from an older seed): the four
    /// Greek sources are new and come first, in the UI language's priority,
    /// then the five stale ones. Registration adds the Greek rows with
    /// `built_at ''` and leaves the stale rows (old stamp, old names) to
    /// their unpack, which replaces them in the same transaction as the data.
    func testUnpackPlanOnUpgradePutsNewSourcesFirst() async throws {
        let five = Array(Self.seedOrder.prefix(5))
        let greek = Array(Self.seedOrder.suffix(4))
        let all = Self.seedOrder.map { ($0, ["qa\($0.replacingOccurrences(of: "-", with: ""))word"]) }
        let bundle = try makeUnpackBundle(all, builtAt: "1.4.0")
        let old = try makeUnpackBundle(all.filter { five.contains($0.0) }, builtAt: "1.3.0", name: "old.sqlite",
                                       displayPrefix: "Old")
        try await db.seedIfNeeded(bundledSeedURL: old)

        let expected: [(String, [String])] = [
            ("en", greek + five),
            ("ru", greek + five),
            ("es", greek + ["wordnet", "wordnet-spa-eng", "freedict-eng-spa", "openrussian", "wordnet-arb-eng"]),
            ("ar", greek + ["wordnet", "wordnet-arb-eng", "openrussian", "freedict-eng-spa", "wordnet-spa-eng"]),
            ("el", ["freedict-ell-eng", "wordnet-ell-eng", "freedict-eng-ell", "wordnet-eng-ell"] + five),
        ]
        for (code, order) in expected {
            let plan = try await db.prepareBundledSeed(bundledSeedURL: bundle, languageCode: code)
            XCTAssertEqual(plan.items.map(\.source), order, "\(code): new sources first, each group by priority")
            XCTAssertEqual(plan.items.map(\.isNew), [true, true, true, true, false, false, false, false, false],
                           "\(code): the four Greek sources are new, the five old ones stale")
            XCTAssertEqual(plan.initialFraction, 0, "\(code): stale sources are pending too")
        }
        let markers = try await appMarkers()
        for source in five {
            XCTAssertEqual(markers[source], "1.3.0", "\(source): the stale gate stays open until its unpack")
        }
        for source in greek {
            XCTAssertEqual(markers[source], "", "\(source): registered, not unpacked")
        }
        for meta in try await db.fetchMetadata() {
            let prefix = five.contains(meta.source) ? "Old" : "Bundle"
            XCTAssertEqual(meta.displayName, "\(prefix) \(meta.source)",
                           "a stale row keeps its old metadata until its data is replaced")
        }
        let counts = try await appCounts()
        XCTAssertEqual(Set(counts.keys), Set(five), "preparing writes no entries")
    }

    // MARK: Unpack

    /// 4. Fresh install on the real seed through the app path: every source
    /// complete and byte-identical to the seed (`word_normalized` included,
    /// Arabic and Greek search depend on it), one contiguous id block per
    /// source in plan order, every marker closed, FTS consistent, WAL
    /// truncated. AC: total unpack time not worse than the 26.9 s import it
    /// replaces (simulator budget 20 s; the Mac does the same SQL in ~4.5 s).
    @MainActor
    func testUnpackOfRealSeedIsCompleteAndFast() async throws {
        let seedURL = try Self.greekSeedURL()
        let bundle = try Self.realSeedMetadata()
        let plan = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: "en")
        XCTAssertEqual(plan.items.count, 9)

        let start = CFAbsoluteTimeGetCurrent()
        await runAppUnpack(plan)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("⏱ fresh-install unpack of the real seed: \(String(format: "%.3f", elapsed))s")

        let walSize = (try? FileManager.default.attributesOfItem(atPath: syncAppPath + "-wal")[.size] as? Int) ?? 0
        XCTAssertEqual(walSize, 0, "the final TRUNCATE checkpoint shrinks the WAL left by the wordnet transaction")

        let counts = try await appCounts()
        let markers = try await appMarkers()
        for item in bundle {
            XCTAssertEqual(counts[item.source], item.wordCount, "\(item.source): every row")
            XCTAssertEqual(markers[item.source], item.builtAt, "\(item.source): completion marker")
        }
        try await checkFTSIntegrity()

        let pool = try DatabasePool(path: syncAppPath)
        let mismatches = try await pool.writeWithoutTransaction { conn -> Int in
            try conn.execute(sql: "ATTACH DATABASE ? AS seed", arguments: [seedURL.path])
            defer { try? conn.execute(sql: "DETACH DATABASE seed") }
            return try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM seed.entries s
                LEFT JOIN main.entries e ON e.source = s.source AND e.word = s.word COLLATE NOCASE
                WHERE e.id IS NULL OR e.word IS NOT s.word OR e.word_normalized IS NOT s.word_normalized
                   OR e.definition IS NOT s.definition OR e.phonetic IS NOT s.phonetic OR e.pos IS NOT s.pos
                """) ?? -1
        }
        XCTAssertEqual(mismatches, 0, "every seed row arrives byte-identical")

        let blocks = try await pool.read { conn in
            try Row.fetchAll(conn, sql: "SELECT source, MIN(id) AS lo, MAX(id) AS hi FROM entries GROUP BY source ORDER BY lo")
        }
        XCTAssertEqual(blocks.map { $0["source"] as String }, plan.items.map(\.source),
                       "sources commit one after another, in plan order")
        for (earlier, later) in zip(blocks, blocks.dropFirst()) {
            XCTAssertLessThan(earlier["hi"] as Int64, later["lo"] as Int64, "one contiguous id block per source")
        }

        let greek = try await db.search(query: "καλημερα")
        XCTAssertTrue(greek.contains { $0.word == "καλημέρα" && $0.source == "freedict-ell-eng" },
                      "the last source is searchable, accent-free")
        XCTAssertLessThan(elapsed, 20, "unpack must stay far below the 26.9 s import it replaces (got \(elapsed)s)")
    }

    /// Update path (1.3.0 → 1.4.0) on the real seed: the five old sources
    /// with an older stamp and an outdated eng-spa definition, two bookmarks,
    /// no Greek. The old sources are searchable before any work; the unpack
    /// adds the four Greek sources first, then syncs the five in place (#108):
    /// every old id survives, nothing is re-inserted, the bookmarks stay on
    /// their rows, the definition is updated and re-indexed, FTS is consistent.
    @MainActor
    func testUpdatePathAddsGreekInBackgroundAndKeepsBookmarks() async throws {
        let seedURL = try Self.greekSeedURL()
        let bundle = try Self.realSeedMetadata()
        let five = Array(Self.seedOrder.prefix(5))
        let greek = Array(Self.seedOrder.suffix(4))
        try await useSeedClone()
        let clonePath = tempDir.appendingPathComponent("seed-clone.sqlite").path
        let clone = try DatabasePool(path: clonePath)
        let greekList = greek.map { "'\($0)'" }.joined(separator: ", ")
        try await clone.write { conn in
            try conn.execute(sql: "DELETE FROM entries WHERE source IN (\(greekList))")
            try conn.execute(sql: "DELETE FROM dict_metadata WHERE source IN (\(greekList))")
            try conn.execute(sql: "UPDATE dict_metadata SET built_at = '1.3.0'")
            try conn.execute(sql: "UPDATE entries SET definition = ? WHERE word = 'quickly' AND source = ?",
                             arguments: [Self.oldQuickly, Self.syncEngSpa])
        }
        func rowID(_ word: String, _ source: String) async throws -> Int64 {
            let id = try await clone.read { conn in
                try Int64.fetchOne(conn, sql: "SELECT id FROM entries WHERE word = ? AND source = ?",
                                   arguments: [word, source])
            }
            return try XCTUnwrap(id, "\(word) / \(source)")
        }
        func fingerprint() async throws -> [String: [Int64]] {
            try await clone.read { conn in
                var result: [String: [Int64]] = [:]
                for row in try Row.fetchAll(conn, sql: "SELECT source, COUNT(*) AS n, SUM(id) AS s FROM entries GROUP BY source") {
                    result[row["source"] as String] = [row["n"] as Int64, row["s"] as Int64]
                }
                return result
            }
        }
        let dogID = try await rowID("dog", "wordnet")
        let quicklyID = try await rowID("quickly", Self.syncEngSpa)
        try await db.addBookmark(entryId: dogID)
        try await db.addBookmark(entryId: quicklyID)
        let before = try await fingerprint()
        XCTAssertEqual(Set(before.keys), Set(five), "precondition: a 1.3.0 install has no Greek rows")

        let plan = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: "en")
        XCTAssertEqual(plan.items.map(\.source), greek + five)
        XCTAssertEqual(plan.items.map(\.isNew), [true, true, true, true, false, false, false, false, false])
        let early = try await db.search(query: "dog")
        XCTAssertTrue(early.contains { $0.id == dogID }, "the old dictionaries are searchable before any work")
        XCTAssertFalse(early.contains { greek.contains($0.source) }, "Greek is not unpacked yet")

        let recorder = PhaseRecorder(DictionaryUnpackStatus.shared)
        let start = CFAbsoluteTimeGetCurrent()
        await runAppUnpack(plan)
        print("⏱ update-path unpack (4 new + 5 stale) on the real seed: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start))s")

        let after = try await fingerprint()
        for source in five {
            XCTAssertEqual(after[source], before[source], "\(source): every old id kept, nothing re-inserted")
        }
        let markers = try await appMarkers(path: clonePath)
        for item in bundle {
            XCTAssertEqual(markers[item.source], item.builtAt, "\(item.source): gate closed")
            if greek.contains(item.source) {
                XCTAssertEqual(after[item.source]?.first, Int64(item.wordCount), "\(item.source): imported completely")
            }
        }
        let bookmarks = try await db.fetchBookmarkedEntries()
        XCTAssertEqual(Set(bookmarks.compactMap(\.entry.id)), [dogID, quicklyID], "bookmarks stay on their rows")
        let quickly = try await db.search(query: "velozmente")
        XCTAssertTrue(quickly.contains { $0.id == quicklyID }, "the #108 update reached the same row and FTS")
        let kalimera = try await db.search(query: "καλημέρα")
        XCTAssertTrue(kalimera.contains { $0.source == "freedict-ell-eng" }, "Greek arrived")
        try await checkFTSIntegrity(path: clonePath)

        let fractions = recorder.phases.compactMap(Self.fraction)
        XCTAssertEqual(fractions.count, 1 + plan.items.count, "the start plus one step per source; got \(fractions)")
        XCTAssertEqual(fractions.first, 0, "every source is pending on the update path")
        XCTAssertEqual(fractions, fractions.sorted(), "progress never goes back")
        XCTAssertEqual(recorder.phases.last, .idle)
    }

    /// 5. A kill mid-source (the seam throws inside the source's transaction,
    /// after its INSERT): the sources before it stay complete, the killed one
    /// has no row and no marker, the rest are untouched, and the app stays
    /// usable (PM decision 4): the bar hides, committed sources are
    /// searchable, the writer and the bundle alias are free. The next launch
    /// resumes from the markers: only the remaining sources run, the
    /// committed ones keep their rows and ids, every count is exact.
    @MainActor
    func testUnpackKilledMidSourceResumesWithoutDuplicates() async throws {
        let bundleURL = try makeUnpackBundle(Self.fixtureSources)
        let plan = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        XCTAssertEqual(plan.items.map(\.source), Self.fixtureSources.map(\.0))

        DatabaseService.unpackFailureAfterInsert = "freedict-eng-spa"
        let recorder = PhaseRecorder(DictionaryUnpackStatus.shared)
        await runAppUnpack(plan)
        DatabaseService.unpackFailureAfterInsert = nil

        let counts = try await appCounts()
        XCTAssertEqual(counts, ["wordnet": 4, "openrussian": 3], "committed sources complete, the killed one rolled back")
        let markers = try await appMarkers()
        XCTAssertEqual(markers, ["wordnet": "b1", "openrussian": "b1", "freedict-eng-spa": "", "wordnet-spa-eng": ""])
        XCTAssertEqual(recorder.phases, [.idle, .unpacking(fraction: 0), .unpacking(fraction: 0.4),
                                         .unpacking(fraction: 0.7), .idle],
                       "no progress for the failed source, and the bar is not left stuck")

        let committed = try await db.search(query: "qawnbeta")
        XCTAssertEqual(committed.map(\.source), ["wordnet"], "committed sources stay searchable")
        let killed = try await db.search(query: "qaesuno")
        XCTAssertTrue(killed.isEmpty, "no partial source is ever visible")
        try await db.addToHistory(word: "qawnbeta", source: "wordnet")
        let history = try await db.historyCount()
        XCTAssertEqual(history, 1, "the writer is free after the failure")
        try await checkFTSIntegrity()
        let wordnetRows = try await syncRows(source: "wordnet")
        let russianRows = try await syncRows(source: "openrussian")

        let resumed = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        XCTAssertEqual(resumed.items.map(\.source), ["freedict-eng-spa", "wordnet-spa-eng"], "only what is left")
        XCTAssertTrue(resumed.items.allSatisfy(\.isNew))
        XCTAssertEqual(resumed.initialFraction, 0.7, accuracy: 1e-9, "the bar resumes at the share already done")
        await runAppUnpack(resumed)

        let countsAfter = try await appCounts()
        XCTAssertEqual(countsAfter, ["wordnet": 4, "openrussian": 3, "freedict-eng-spa": 2, "wordnet-spa-eng": 1])
        let markersAfter = try await appMarkers()
        XCTAssertEqual(Set(markersAfter.values), ["b1"])
        let wordnetAfter = try await syncRows(source: "wordnet")
        let russianAfter = try await syncRows(source: "openrussian")
        XCTAssertEqual(wordnetAfter, wordnetRows, "wordnet not re-imported: same rows, same ids")
        XCTAssertEqual(russianAfter, russianRows, "openrussian not re-imported: same rows, same ids")
        let spanish = try await db.search(query: "qaesuno")
        XCTAssertEqual(spanish.map(\.source), ["freedict-eng-spa"])
        try await checkFTSIntegrity()
    }

    /// 6. A source half-imported by 1.3.x or older (rows but no metadata row,
    /// one row outdated, one bookmarked): registered as new, then completed in
    /// place. Existing ids and the bookmark survive, the outdated row is
    /// updated and re-indexed, the missing rows arrive, FTS stays consistent.
    func testUnpackCompletesLegacyHalfImportedSource() async throws {
        let words = ["qahalfa", "qahalfb", "qahalfc", "qahalfd"]
        let bundleURL = try makeUnpackBundle([("wordnet", ["qawnonly"]), (Self.syncEngSpa, words)])
        try await seedSyncApp([("qahalfa", "qahalfa in \(Self.syncEngSpa)", Self.syncEngSpa),
                               ("qahalfb", "an outdated definition", Self.syncEngSpa)], builtAt: nil)
        let before = try await syncRows(source: Self.syncEngSpa)
        let bookmarked = try XCTUnwrap(before.first)
        try await db.addBookmark(entryId: bookmarked.id)

        let plan = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        XCTAssertEqual(plan.items.map(\.source), ["wordnet", Self.syncEngSpa])
        XCTAssertTrue(plan.items.allSatisfy(\.isNew), "no metadata row = never completed = new")
        await db.startBundledUnpack(plan)
        await db.waitForBundledUnpack()

        let after = try await syncRows(source: Self.syncEngSpa)
        XCTAssertEqual(after.map(\.word), words)
        XCTAssertEqual(after.prefix(2).map(\.id), before.map(\.id), "existing rows completed in place")
        XCTAssertEqual(after.map(\.definition), words.map { "\($0) in \(Self.syncEngSpa)" })
        XCTAssertEqual(Set(after.map(\.pos)), ["noun"], "every column follows the bundle")
        let isBookmarked = try await db.isBookmarked(entryId: bookmarked.id)
        XCTAssertTrue(isBookmarked, "the bookmark survives")
        let markers = try await appMarkers()
        XCTAssertEqual(markers, ["wordnet": "b1", Self.syncEngSpa: "b1"])
        let added = try await db.search(query: "qahalfd")
        XCTAssertEqual(added.map(\.word), ["qahalfd"])
        let stale = try await db.search(query: "outdated")
        XCTAssertTrue(stale.isEmpty, "the outdated text left the FTS index")
        try await checkFTSIntegrity()
    }

    /// 7. Searching while the real seed unpacks: never an error, and a reader
    /// sees a source completely or not at all. Phase A holds the unpack 3 s
    /// after `wordnet` commits: English search returns WordNet rows and the
    /// pending sources give nothing. Phase B resumes the other seven with no
    /// delay while searches and a per-source count check loop until idle.
    @MainActor
    func testSearchDuringUnpack() async throws {
        let seedURL = try Self.greekSeedURL()
        let bundle = try Self.realSeedMetadata()
        let wordCounts = Dictionary(uniqueKeysWithValues: bundle.map { ($0.source, $0.wordCount) })
        let full = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: "en")
        XCTAssertEqual(full.items.first?.source, "wordnet", "English search is served first")

        // Phase A: wordnet and openrussian, held `hold` s between them.
        let firstTwo = BundledUnpackPlan(
            seedURL: seedURL,
            bundled: bundle.filter { ["wordnet", "openrussian"].contains($0.source) }
                .map { BundledUnpackPlan.BundledSource(source: $0.source, rowCount: $0.wordCount, builtAt: $0.builtAt) },
            appBuiltAt: [:], languageCode: "en")
        let hold: TimeInterval = 3
        Self.setUnpackSourceDelay(hold)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "unpackSourceDelay"), hold, "precondition: the delay seam")
        DictionaryUnpackStatus.shared.begin(firstTwo)
        await db.startBundledUnpack(firstTwo)
        Self.setUnpackSourceDelay(nil)
        let wordnetCommitted = await waitUntil(timeout: 60) { (Self.fraction(DictionaryUnpackStatus.shared.phase) ?? 0) > 0 }
        let heldAt = Date()
        XCTAssertTrue(wordnetCommitted, "wordnet must commit")

        let dog = try await db.search(query: "dog")
        let russian = try await db.search(query: "яблоко")
        let counts = try await appCounts()
        if Date().timeIntervalSince(heldAt) < hold - 0.25 {
            XCTAssertEqual(counts, ["wordnet": wordCounts["wordnet"] ?? -1], "only the committed source is visible")
            XCTAssertEqual(Set(dog.map(\.source)), ["wordnet"], "results come from committed sources only")
            XCTAssertTrue(russian.allSatisfy { $0.source == "wordnet" }, "nothing from the pending openrussian")
        } else {
            print("note: phase A took longer than the hold; skipped the pending-source assertions")
        }
        XCTAssertTrue(dog.contains { $0.word == "dog" && $0.source == "wordnet" }, "WordNet answers mid-unpack")
        await db.waitForBundledUnpack()
        let russianAfter = try await db.search(query: "яблоко")
        XCTAssertTrue(russianAfter.contains { $0.word == "яблоко" && $0.source == "openrussian" },
                      "a source that lands is found on the next query")

        // Phase B: the seven others, searched while they are written.
        let rest = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: "en")
        XCTAssertEqual(rest.items.map(\.source), Array(Self.seedOrder.dropFirst(2)))
        let done = Double((wordCounts["wordnet"] ?? 0) + (wordCounts["openrussian"] ?? 0)) / Double(full.allRows)
        XCTAssertEqual(rest.initialFraction, done, accuracy: 1e-9)
        let watcher = try DatabasePool(path: syncAppPath)
        var rounds = 0
        var partial: [String] = []
        DictionaryUnpackStatus.shared.begin(rest)
        await db.startBundledUnpack(rest)
        while DictionaryUnpackStatus.shared.phase != .idle {
            for query in ["water", "σκυλος", "casa", "كتاب"] {
                _ = try await db.search(query: query)   // a lock or busy error fails the test
            }
            let seen = try await watcher.read { conn in
                try Row.fetchAll(conn, sql: "SELECT source, COUNT(*) AS n FROM entries GROUP BY source")
            }
            for row in seen where (row["n"] as Int) != wordCounts[row["source"] as String] {
                partial.append("\(row["source"] as String): \(row["n"] as Int)")
            }
            rounds += 1
        }
        await db.waitForBundledUnpack()
        XCTAssertGreaterThan(rounds, 0, "searches ran while the unpack was writing")
        XCTAssertEqual(partial, [], "a reader never sees a partly unpacked source")
        let finalCounts = try await appCounts()
        XCTAssertEqual(finalCounts, wordCounts)
    }

    /// 8. Dictionary order mid-unpack (after wordnet and openrussian):
    /// `fetchSourceStats` lists all nine with the bundle counts, count-desc,
    /// with full metadata; the first Settings load gives the five pairs and
    /// persists the #74 default; a toggle mid-unpack keeps every pending
    /// dictionary on (F3). After the unpack: the same list and the same order.
    @MainActor
    func testSourceStatsMidUnpackListAllBundledSources() async throws {
        let seedURL = try Self.greekSeedURL()
        let bundle = try Self.realSeedMetadata()
        let plan = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: "en")
        DatabaseService.unpackFailureAfterInsert = "freedict-eng-spa"
        await runAppUnpack(plan)
        DatabaseService.unpackFailureAfterInsert = nil
        let counts = try await appCounts()
        XCTAssertEqual(Set(counts.keys), ["wordnet", "openrussian"], "precondition: mid-unpack")

        let mid = try await db.fetchSourceStats()
        XCTAssertEqual(mid.map(\.source).sorted(), Self.seedOrder.sorted(), "all nine bundled sources are listed")
        XCTAssertEqual(mid.map(\.count), mid.map(\.count).sorted(by: >), "count-desc base order")
        for stat in mid {
            let meta = try XCTUnwrap(bundle.first { $0.source == stat.source })
            XCTAssertEqual(stat.count, meta.wordCount, "\(stat.source): the final count, unpacked or not")
            XCTAssertEqual(stat.displayName, meta.displayName, "\(stat.source)")
            XCTAssertEqual(stat.license, meta.license, "\(stat.source)")
            XCTAssertEqual(stat.version, meta.version, "\(stat.source)")
        }

        let (vmMid, settingsMid) = makeEnglishSettingsViewModel()
        let loadedMid = await waitUntil(timeout: 10) { !vmMid.dictionaries.isEmpty }
        XCTAssertTrue(loadedMid)
        XCTAssertEqual(vmMid.dictionaries.map(\.id), ["eng", "eng-spa", "eng-rus", "ell-eng", "arb-eng"])
        let orderMid = try XCTUnwrap(settingsMid.dictionaryOrder, "the first load persists the default order")
        XCTAssertEqual(orderMid.sorted(), Self.seedOrder.sorted(), "the persisted order holds every bundled source")
        vmMid.togglePair(id: "eng-rus")
        XCTAssertEqual(settingsMid.enabledSources, Set(Self.seedOrder).subtracting(["openrussian"]),
                       "switching Russian off mid-unpack keeps every pending dictionary on")

        let rest = try await db.prepareBundledSeed(bundledSeedURL: seedURL, languageCode: "en")
        await runAppUnpack(rest)
        let done = try await db.fetchSourceStats()
        XCTAssertEqual(done, mid, "Dictionary order does not change when the dictionaries land")
        let (vmDone, settingsDone) = makeEnglishSettingsViewModel()
        let loadedDone = await waitUntil(timeout: 10) { !vmDone.dictionaries.isEmpty }
        XCTAssertTrue(loadedDone)
        XCTAssertEqual(vmDone.dictionaries.map(\.id), vmMid.dictionaries.map(\.id))
        XCTAssertEqual(settingsDone.dictionaryOrder, orderMid, "the #74 default is the same during and after")
    }

    /// A `SettingsViewModel` on fresh in-memory prefs, in-app language English.
    @MainActor
    private func makeEnglishSettingsViewModel() -> (SettingsViewModel, SettingsService) {
        let settings = SettingsService(store: InMemoryKeyValueStore())
        settings.selectedUILanguageCode = "en"
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        return (SettingsViewModel(settingsService: settings, localization: localization), settings)
    }

    // MARK: Progress and Search screen

    /// 9. Progress on a resumed unpack (a first launch killed after wordnet,
    /// 4 of 10 rows): the bar starts at the share already done, rises with
    /// each committed source to 100%, and ends `.idle`; the killed launch
    /// itself ended `.idle` too. The `seedIfNeeded` facade never publishes.
    /// The bar shows whole percents, floored and clamped.
    @MainActor
    func testUnpackProgressIsMonotonicAndEndsIdle() async throws {
        let bundleURL = try makeUnpackBundle(Self.fixtureSources)
        let first = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        DatabaseService.unpackFailureAfterInsert = "openrussian"
        let killed = PhaseRecorder(DictionaryUnpackStatus.shared)
        await runAppUnpack(first)
        DatabaseService.unpackFailureAfterInsert = nil
        XCTAssertEqual(killed.phases, [.idle, .unpacking(fraction: 0), .unpacking(fraction: 0.4), .idle])

        let plan = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        XCTAssertEqual(plan.initialFraction, 0.4, accuracy: 1e-9)
        let recorder = PhaseRecorder(DictionaryUnpackStatus.shared)
        await runAppUnpack(plan)
        XCTAssertEqual(recorder.phases.first, .idle, "the phase at subscription")
        XCTAssertEqual(recorder.phases.last, .idle, "ends idle: the bar hides")
        XCTAssertEqual(recorder.phases.filter { $0 == .idle }.count, 2, "no idle in between")
        let fractions = recorder.phases.compactMap(Self.fraction)
        XCTAssertEqual(fractions.count, 4, "the start plus one step per remaining source; got \(fractions)")
        for (got, want) in zip(fractions, [0.4, 0.7, 0.9, 1.0]) {
            XCTAssertEqual(got, want, accuracy: 1e-9, "fractions \(fractions)")
        }
        XCTAssertTrue(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 }, "strictly rising: \(fractions)")

        let rebuilt = try makeUnpackBundle(Self.fixtureSources, builtAt: "b2", name: "b2.sqlite", definitionSuffix: " (b2)")
        let silent = PhaseRecorder(DictionaryUnpackStatus.shared)
        try await db.seedIfNeeded(bundledSeedURL: rebuilt)
        XCTAssertEqual(silent.phases, [.idle], "the seedIfNeeded facade never publishes")
        let markers = try await appMarkers()
        XCTAssertEqual(Set(markers.values), ["b2"], "the facade still synced every source")

        XCTAssertNil(SearchViewModel.displayFraction(for: .idle))
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: 0)), 0)
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: 0.29)), 0.29, "an exact percent stays")
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: 0.3549)), 0.35, "floored")
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: 0.999)), 0.99, "never 100% early")
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: 1)), 1)
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: -0.2)), 0, "clamped")
        XCTAssertEqual(SearchViewModel.displayFraction(for: .unpacking(fraction: 1.7)), 1, "clamped")
    }

    /// PM decision 3: when a dictionary lands, the current query re-runs
    /// (debounced) so its results fill in without retyping. Nothing polls:
    /// only a status change triggers it; `.idle` adds no data and triggers
    /// nothing; a burst costs one re-run; an empty query never searches.
    @MainActor
    func testSearchReRunsWhenADictionaryLands() async throws {
        let status = DictionaryUnpackStatus()
        let settings = SettingsService(store: InMemoryKeyValueStore())
        let vm = SearchViewModel(db: db, settings: settings, unpackStatus: status)
        var searches = 0
        let counter = vm.$isSearching.dropFirst().filter { $0 }.sink { _ in searches += 1 }
        defer { counter.cancel() }

        XCTAssertNil(vm.unpackFraction, "idle: no bar")
        status.update(.unpacking(fraction: 0.3549))
        XCTAssertEqual(vm.unpackFraction, 0.35, "the bar shows whole percents")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(searches, 0, "a landing dictionary starts no search on an empty query")

        vm.query = "qalanding"
        vm.onQueryChanged()
        let firstDone = await waitUntil(timeout: 5) { !vm.isSearching }
        XCTAssertTrue(firstDone)
        XCTAssertTrue(vm.results.isEmpty, "precondition: the word's dictionary has not landed")
        XCTAssertEqual(searches, 1)

        try await insertNormalizedEntry(word: "qalanding", normalized: "qalanding", definition: "arrived",
                                        source: "wordnet")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(vm.results.isEmpty, "no polling: the list changes only when the status does")
        XCTAssertEqual(searches, 1)

        status.update(.unpacking(fraction: 0.6))
        let filled = await waitUntil(timeout: 5) { vm.results.map(\.word) == ["qalanding"] && !vm.isSearching }
        XCTAssertTrue(filled, "results fill in without retyping; got \(vm.results.map(\.word))")
        XCTAssertEqual(searches, 2)
        XCTAssertNil(vm.errorMessage)

        status.update(.unpacking(fraction: 0.7))
        status.update(.unpacking(fraction: 0.8))
        status.update(.unpacking(fraction: 0.9))
        let burst = await waitUntil(timeout: 5) { searches == 3 && !vm.isSearching }
        XCTAssertTrue(burst, "the burst re-runs the query")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(searches, 3, "debounced: one re-run for three landings")

        try await insertNormalizedEntry(word: "qalandings", normalized: "qalandings", definition: "late",
                                        source: "wordnet")
        status.update(.idle)
        XCTAssertNil(vm.unpackFraction, "the bar goes away")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(searches, 3, "`.idle` triggers no re-run")
        XCTAssertEqual(vm.results.map(\.word), ["qalanding"])
    }

    // MARK: Priority, single flight, pool

    /// 10. `DictionaryDefaults.unpackPriority`: `wordnet` first, then the UI
    /// language's dictionaries in mapping order, then the rest in incoming
    /// order; IDs that are not in the input are skipped, never invented; the
    /// result is always a permutation.
    func testUnpackPriority() throws {
        let seed = Self.seedOrder
        func priority(_ code: String, _ sources: [String]) -> [String] {
            DictionaryDefaults.unpackPriority(forLanguageCode: code, sources: sources)
        }
        XCTAssertEqual(priority("en", seed), seed)
        XCTAssertEqual(priority("ru", seed), seed, "openrussian already follows wordnet")
        XCTAssertEqual(priority("es", seed), ["wordnet", "wordnet-spa-eng", "freedict-eng-spa", "openrussian",
                                              "wordnet-arb-eng", "wordnet-ell-eng", "wordnet-eng-ell",
                                              "freedict-ell-eng", "freedict-eng-ell"])
        XCTAssertEqual(priority("ar", seed), ["wordnet", "wordnet-arb-eng", "openrussian", "freedict-eng-spa",
                                              "wordnet-spa-eng", "wordnet-ell-eng", "wordnet-eng-ell",
                                              "freedict-ell-eng", "freedict-eng-ell"])
        XCTAssertEqual(priority("el", seed), ["wordnet", "freedict-ell-eng", "wordnet-ell-eng", "freedict-eng-ell",
                                              "wordnet-eng-ell", "openrussian", "freedict-eng-spa",
                                              "wordnet-spa-eng", "wordnet-arb-eng"])
        XCTAssertEqual(priority("fr", ["openrussian", "my_dict", "wordnet"]), ["wordnet", "openrussian", "my_dict"],
                       "unknown language: wordnet first, the rest untouched")
        XCTAssertEqual(priority("es", ["openrussian", "freedict-eng-spa", "my_dict"]),
                       ["freedict-eng-spa", "openrussian", "my_dict"],
                       "no wordnet and a missing preferred id: skipped, never invented")
        XCTAssertEqual(priority("ru", ["wordnet-arb-eng", "openrussian", "wordnet"]),
                       ["wordnet", "openrussian", "wordnet-arb-eng"])
        XCTAssertEqual(priority("el", []), [])
        for code in ["en", "ru", "es", "ar", "el", "fr", ""] {
            for k in seed.indices {
                let rotated = Array(seed[k...] + seed[..<k])
                let result = priority(code, rotated)
                XCTAssertEqual(result.sorted(), rotated.sorted(), "\(code)/\(k): a permutation")
                XCTAssertEqual(result.first, "wordnet", "\(code)/\(k): English is served first")
            }
        }
    }

    /// 11. Single flight: a second `startBundledUnpack` while one runs (the
    /// WindowGroup `.task` running again), or one with another plan, is a
    /// no-op: one loop, one progress step per source. `waitForBundledUnpack`
    /// returns only when the loop is done, and the slot is free afterwards.
    @MainActor
    func testStartBundledUnpackIsSingleFlight() async throws {
        let bundleURL = try makeUnpackBundle(Self.fixtureSources)
        let plan = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        let otherURL = try makeUnpackBundle([("wordnet-arb-eng", ["qaarb"])], name: "other.sqlite")
        let otherPlan = BundledUnpackPlan(
            seedURL: otherURL,
            bundled: [BundledUnpackPlan.BundledSource(source: "wordnet-arb-eng", rowCount: 1, builtAt: "b1")],
            appBuiltAt: [:], languageCode: "en")

        let recorder = PhaseRecorder(DictionaryUnpackStatus.shared)
        Self.setUnpackSourceDelay(0.3)
        DictionaryUnpackStatus.shared.begin(plan)
        await db.startBundledUnpack(plan)
        Self.setUnpackSourceDelay(nil)
        await db.startBundledUnpack(plan)
        await db.startBundledUnpack(otherPlan)
        await waitForUnpackIdle()

        let markers = try await appMarkers()
        XCTAssertEqual(markers.filter { $0.value == "b1" }.count, 4, "waitForBundledUnpack returns after the last source")
        let fractions = recorder.phases.compactMap(Self.fraction)
        XCTAssertEqual(fractions.count, 1 + plan.items.count, "one loop; got \(fractions)")
        XCTAssertEqual(recorder.phases.last, .idle)
        let counts = try await appCounts()
        XCTAssertEqual(counts, ["wordnet": 4, "openrussian": 3, "freedict-eng-spa": 2, "wordnet-spa-eng": 1],
                       "the other plan never ran alongside")

        await db.startBundledUnpack(otherPlan)
        await db.waitForBundledUnpack()
        let countsAfter = try await appCounts()
        XCTAssertEqual(countsAfter["wordnet-arb-eng"], 1, "the slot is free once the first unpack has finished")
    }

    /// §3.6 "capture the pool once" (F4): an unpack keeps writing into the
    /// database it started on after `setup(path:)` swaps the shared pool, so
    /// the host's unpack can never write into a test's database.
    @MainActor
    func testUnpackKeepsThePoolItStartedWith() async throws {
        let bundleURL = try makeUnpackBundle(Self.fixtureSources)
        let plan = try await db.prepareBundledSeed(bundledSeedURL: bundleURL, languageCode: "en")
        Self.setUnpackSourceDelay(0.3)
        await db.startBundledUnpack(plan)
        Self.setUnpackSourceDelay(nil)
        let swappedPath = tempDir.appendingPathComponent("swapped.sqlite").path
        try await db.setup(path: swappedPath)
        await db.waitForBundledUnpack()

        let started = try await appCounts()
        XCTAssertEqual(started, ["wordnet": 4, "openrussian": 3, "freedict-eng-spa": 2, "wordnet-spa-eng": 1])
        let swappedCounts = try await appCounts(path: swappedPath)
        XCTAssertEqual(swappedCounts, [:], "nothing leaked into the database swapped in mid-unpack")
        let swappedMarkers = try await appMarkers(path: swappedPath)
        XCTAssertEqual(swappedMarkers, [:])
    }

    // MARK: Seed and catalog

    /// 12. The plan is driven by the seed's metadata, so: the sources of its
    /// `entries` are exactly its `dict_metadata` sources; every `built_at` is
    /// non-empty ('' means "not unpacked" in the app); `word_count` is exact
    /// (the progress weights); the metadata order is the entry block order;
    /// the seed is not in WAL mode (it is ATTACHed from the read-only bundle).
    func testSeedEntrySourcesMatchMetadata() throws {
        let queue = try Self.openBundledSeedReadOnly()
        let blocks = try queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT source, COUNT(*) AS n, MIN(id) AS lo, MAX(id) AS hi FROM entries GROUP BY source ORDER BY lo
                """)
        }
        let metadata = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT source, word_count, built_at FROM dict_metadata ORDER BY rowid")
        }
        let journal = try queue.read { conn in try String.fetchOne(conn, sql: "PRAGMA journal_mode") }

        XCTAssertEqual(metadata.map { $0["source"] as String }, blocks.map { $0["source"] as String },
                       "metadata lists exactly the entry sources, in entry block order")
        XCTAssertEqual(metadata.count, 9)
        for (earlier, later) in zip(blocks, blocks.dropFirst()) {
            XCTAssertLessThan(earlier["hi"] as Int64, later["lo"] as Int64, "entry blocks do not interleave")
        }
        let rows = Dictionary(uniqueKeysWithValues: blocks.map { ($0["source"] as String, $0["n"] as Int) })
        for row in metadata {
            let source: String = row["source"]
            let builtAt: String = row["built_at"]
            XCTAssertFalse(builtAt.isEmpty, "\(source): '' is reserved for 'registered, not unpacked'")
            XCTAssertEqual(row["word_count"] as Int, rows[source], "\(source): word_count is the progress weight")
        }
        XCTAssertNotEqual(journal?.lowercased(), "wal", "a WAL seed could not be ATTACHed from the read-only bundle")
    }

    /// 13. `search.unpacking.title` is compiled for every shipped UI
    /// language with the agreed text and carries no number (the percent is
    /// formatted separately with the in-app locale).
    func testUnpackingTitleIsLocalized() throws {
        let expected = [
            "en": "Preparing dictionaries…",
            "ru": "Подготовка словарей…",
            "es": "Preparando diccionarios…",
            "ar": "جارٍ تجهيز القواميس…",
            "el": "Προετοιμασία λεξικών…",
        ]
        let shipped = try Self.shippedUILanguages().map(\.code)
        XCTAssertEqual(Set(shipped), Set(expected.keys), "an expected value for every shipped UI language")
        for code in shipped {
            let value = try XCTUnwrap(Self.compiledTables(code: code).strings["search.unpacking.title"],
                                      "\(code): compiled")
            XCTAssertEqual(value, expected[code], "\(code)")
            XCTAssertFalse(value.contains("%"), "\(code): no format specifier in the title")
            let resolved = try Self.lprojBundle(forLocale: code)
                .localizedString(forKey: "search.unpacking.title", value: "MISSING", table: nil)
            XCTAssertEqual(resolved, expected[code], "\(code): resolves at runtime")
        }
    }
}

// MARK: - Issue #111, PM decision 7: custom SQLite import opens the file read-only

extension DictAppTests {

    /// The user's file stays byte-identical and gets no journal, WAL or SHM
    /// sidecar, even when it and its folder are write-protected.
    func testImportSQLiteReadsWriteProtectedFileWithoutTouchingIt() async throws {
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "test_import_fixture", withExtension: "sqlite"))
        let folder = tempDir.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("user.sqlite")
        try FileManager.default.copyItem(at: fixture, to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        }

        let imported = try await db.importSQLite(at: file, source: "qa_readonly")
        XCTAssertEqual(imported, 10)
        let hits = try await db.search(query: "zarboom")
        XCTAssertEqual(hits.map(\.source), ["qa_readonly"])
        XCTAssertEqual(try Data(contentsOf: file), bytes, "the user's file is never written")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["user.sqlite"],
                       "no journal, WAL or SHM file next to it")
    }

    /// A missing file fails the import and leaves nothing at the user's path
    /// (a writable open created an empty database there).
    func testImportSQLiteMissingFileFailsWithoutCreatingIt() async throws {
        let missing = tempDir.appendingPathComponent("gone.sqlite")
        do {
            _ = try await db.importSQLite(at: missing, source: "qa_missing")
            XCTFail("importing a missing file must throw")
        } catch {
            // expected
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path), "no file created at the user's path")
        let count = try await db.entryCount(source: "qa_missing")
        XCTAssertEqual(count, 0)
    }

    /// A file that is not an SQLite database: the import throws, imports
    /// nothing and leaves the file as it was.
    func testImportSQLiteRejectsNonDatabaseFile() async throws {
        let file = tempDir.appendingPathComponent("notes.sqlite")
        let bytes = Data(String(repeating: "not an SQLite database\n", count: 200).utf8)
        try bytes.write(to: file)
        do {
            _ = try await db.importSQLite(at: file, source: "qa_garbage")
            XCTFail("a non-database file must be rejected")
        } catch {
            // expected
        }
        let count = try await db.entryCount(source: "qa_garbage")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try Data(contentsOf: file), bytes, "the file is left as it was")
    }
}
