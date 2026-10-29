// DictAppTests.swift
// Unit tests and performance tests for the dictionary app.

import XCTest
@testable import DictApp
import GRDB
import SQLite3
import MessageUI
import Combine
import CoreText
import UIKit

final class DictAppTests: XCTestCase {

    private var db: DatabaseService!
    private var tempDir: URL!
    /// Issue #138: the test's dictionary file (empty until a test adds rows)
    /// and its user database, both in `tempDir`.
    private var dictionary: TestDictionaryFixture!

    override func setUp() async throws {
        try await super.setUp()
        await Self.waitForHostAppLaunch()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        db = DatabaseService.shared
        dictionary = TestDictionaryFixture(directory: tempDir)
        try await dictionary.open()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Test host launch

    @MainActor private static var hostLaunchSettled = false

    /// The test host is the real app: its launch-time `initializeDatabase`
    /// (setup, the test hooks) runs on `DatabaseService.shared` while the
    /// first tests run, and its later steps re-read the `dbPool` that each
    /// `setUp` swaps in, so they can write into (and lock) a test's DB. Wait
    /// once per run, before the first swap, until the host shows its tab bar
    /// (set only after `isReady`). Every test class that swaps the shared
    /// database calls this first, so test order does not matter.
    @MainActor
    static func waitForHostAppLaunch(timeout: TimeInterval = 30) async {
        guard !hostLaunchSettled else { return }
        hostLaunchSettled = true
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hostShowsTabBar() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        print("DictAppTests: the host app was not ready within \(Int(timeout)) s; continuing")
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
    //
    // Issue #138: rows go into the test's dictionary file, which is rebuilt
    // and reattached (`TestDictionaryFixture`).

    private func seedEntries(count: Int) async throws {
        try await dictionary.add((0..<count).map { i in
            // FTS indexes `word_normalized` (Issue #10); for these Latin test
            // words it equals `word` (normalization is a no-op).
            TestDictionary.Row(word: "word\(i)",
                               definition: "Definition for word number \(i). This is a sample definition.",
                               phonetic: "/wɜːrd/", pos: "noun", source: "test")
        })
    }

    /// Seeds a fixed set of words for the given source, used by the per-source
    /// filter tests in issue #2. Word prefix is namespaced so concurrent
    /// sources don't collide on the (word, source) unique index.
    private func seedSourcedEntries(source: String, words: [String]) async throws {
        try await dictionary.add(words.map { word in
            // FTS indexes `word_normalized` (Issue #10); == word here.
            TestDictionary.Row(word: word, definition: "Definition of \(word) in \(source).",
                               pos: "noun", source: source)
        })
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

    /// Verifies exact lookup by entry key works (Issue #138: `entry(for:)`).
    func testExactLookup() async throws {
        try await seedEntries(count: 5)

        let entry = try await db.entry(for: EntryKey(source: "test", word: "word3"))
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

    /// Verifies the My words add / check / remove cycle (Issue #138: the
    /// interim bookmark).
    func testBookmarkCycle() async throws {
        try await seedEntries(count: 1)

        let entry = try await db.entry(for: EntryKey(source: "test", word: "word0"))
        let key = EntryKey(try XCTUnwrap(entry))

        // Add.
        try await db.addToMyWords(key)
        var isBookmarked = try await db.isInMyWords(key)
        XCTAssertTrue(isBookmarked)

        // Remove.
        try await db.removeFromMyWords(key)
        isBookmarked = try await db.isInMyWords(key)
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
    /// crash that occurred when the bundled database was shipped as a Git-LFS pointer
    /// stub instead of the real database. Fails loudly if the bundled resource is
    /// missing, too small, or isn't a real SQLite file (e.g. an LFS pointer header).
    func testBundledDictionaryFileIsRealSQLite() throws {
        let fileURL = try TestDictionary.bundledURL()

        let data = try Data(contentsOf: fileURL, options: .alwaysMapped)
        // SQLite files start with the 16-byte magic header "SQLite format 3\0".
        // Git-LFS pointer stubs start with "version https://git-lfs.github.com/".
        let header = data.prefix(16)
        let headerString = String(data: header, encoding: .utf8) ?? ""

        XCTAssertFalse(
            headerString.hasPrefix("version https://git-lfs"),
            "dictionaries.sqlite is a Git-LFS pointer stub. Run `git lfs install && git lfs pull` before building."
        )
        XCTAssertGreaterThan(
            data.count, 1024,
            "dictionaries.sqlite is suspiciously small (\(data.count) bytes) — likely not the real database."
        )
        XCTAssertEqual(
            headerString, "SQLite format 3\u{0000}",
            "dictionaries.sqlite does not have a valid SQLite header."
        )

        // And it must actually open and contain entries. Read-only: the
        // bundle never gets a writable connection (#111).
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: fileURL.path, configuration: config)
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") ?? 0
        }
        XCTAssertGreaterThan(count, 0, "Bundled dictionaries.sqlite must contain entries.")
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
    func testSettingsViewModelNoLongerOwnsImportState() async throws {
        // In-memory prefs, so the init-time load writes nothing to the host's
        // UserDefaults. Its first load stores the order; wait for it, so the
        // load never reads this test's database after tearDown deleted it.
        let settings = SettingsService(store: InMemoryKeyValueStore())
        let vm = SettingsViewModel(settingsService: settings,
                                   localization: LocalizationManager(settingsService: settings, bundle: .main))
        let deadline = Date().addingTimeInterval(10)
        while settings.dictionaryOrder == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(settings.dictionaryOrder, "the init-time load finished")
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

    /// Missing keys fall back visibly: `gitDescribe` empty → `displayString`
    /// uses `marketingVersion`; `CFBundleShortVersionString` falls back to
    /// `"unknown"` rather than crashing or returning empty.
    func testAppVersionFallsBackWhenInfoPlistMissing() throws {
        // Case 1: infoDictionary is nil (no Info.plist at all).
        let nilVersion = AppVersion(infoDictionary: nil)
        XCTAssertEqual(nilVersion.gitDescribe, "",
                       "Missing GIT_DESCRIBE must read as empty")
        XCTAssertEqual(nilVersion.marketingVersion, "unknown",
                       "Missing CFBundleShortVersionString must fall back to 'unknown'")
        XCTAssertEqual(nilVersion.displayString, "unknown",
                       "Empty gitDescribe must fall back to the marketing version")
        XCTAssertFalse(nilVersion.isCleanTag, "An empty describe is not a clean tag")

        // Case 2: infoDictionary exists but the keys we care about are absent.
        let emptyVersion = AppVersion(infoDictionary: [:])
        XCTAssertEqual(emptyVersion.marketingVersion, "unknown")
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
            "CFBundleShortVersionString": 1.0
        ]
        let wrongTypeVersion = AppVersion(infoDictionary: wrongType)
        XCTAssertEqual(wrongTypeVersion.gitDescribe, "",
                       "Non-string GIT_DESCRIBE must fall back to empty, not crash")
        XCTAssertEqual(wrongTypeVersion.marketingVersion, "unknown",
                       "Non-string CFBundleShortVersionString must fall back to 'unknown', not crash")
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

        XCTAssertNotNil(bundleVersion,
                        "Host bundle must expose CFBundleShortVersionString (guarded by GENERATE_INFOPLIST_FILE)")

        let current = AppVersion(bundle: hostBundle)
        XCTAssertEqual(current.marketingVersion, bundleVersion,
                       "AppVersion.marketingVersion must mirror the bundle's CFBundleShortVersionString")

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
    // The dictionary content itself lives in the bundled `dictionaries.sqlite`,
    // so coverage spans two surfaces:
    //   1. Cosmetic Swift (`sourceLabel`, Settings toggle wiring) —
    //      independent of the file's contents.
    //   2. Bundled data (metadata row + searchable headwords) — the
    //      tests query the host bundle's `dictionaries.sqlite` directly via
    //      GRDB, identical to the pattern in `testBundledDictionaryFileIsRealSQLite`.
    //      If the maintainer hasn't yet regenerated `dictionaries.sqlite` with
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

    /// The bundled `dictionaries.sqlite` must contain a `dict_metadata` row for
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
            "Bundled dictionaries.sqlite has no dict_metadata row for '\(Self.freeDictEngSpaSource)'. Regenerate via `python Scripts/build_dictionaries.py` before merging Issue #24."
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
            "Bundled dictionary file has no entries with source='\(Self.freeDictEngSpaSource)'. Regenerate via `python Scripts/build_dictionaries.py`."
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

    /// Opens the bundled `dictionaries.sqlite` read-only via GRDB so the
    /// FreeDict tests can probe it without touching the per-test database.
    private static func openBundledSeedReadOnly() throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: TestDictionary.bundledURL().path, configuration: config)
    }

    // MARK: - Issue #42: Spanish WordNet (Spanish–English) bundle
    //
    // Content lives in the bundled `dictionaries.sqlite` under source
    // `wordnet-spa-eng`, so coverage mirrors the #24 FreeDict tests:
    //   1. Cosmetic Swift (sourceLabel, Settings toggle) — independent of
    //      the seed contents.
    //   2. Bundled data (metadata row + searchable headwords) — queried
    //      directly via `openBundledSeedReadOnly()`. These fail loudly if
    //      the maintainer hasn't regenerated `dictionaries.sqlite` with the new
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
            "Bundled dictionaries.sqlite has no dict_metadata row for '\(Self.spanishWordNetSource)'. Regenerate via `python Scripts/build_dictionaries.py` before merging Issue #42."
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
            "Bundled dictionary file has no entries with source='\(Self.spanishWordNetSource)'. Regenerate via `python Scripts/build_dictionaries.py`."
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

    // MARK: - Issue #10: Arabic search symmetry (§1 / §2)

    /// Inserts one row with an explicit `word_normalized` (mimicking what the
    /// Python build does for Arabic), via a direct connection so the value
    /// isn't overwritten by the `= word` custom-import policy.
    /// `decomposeGreekDefinition` stores the definition through
    /// `decomposeGreek`, as the build does for the four Greek sources (#87).
    private func insertNormalizedEntry(word: String, normalized: String,
                                       definition: String, source: String,
                                       decomposeGreekDefinition: Bool = false) async throws {
        let stored = decomposeGreekDefinition ? Self.decomposeGreek(definition) : definition
        try await dictionary.add([TestDictionary.Row(word: word, normalized: normalized, definition: stored,
                                                     pos: "noun", source: source)])
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

    /// Gives a source a `dict_metadata` row the way `build_dictionaries.py` does for
    /// bundled sources (by default a test source shows its ID and no license).
    private func insertMetadata(source: String, displayName: String,
                                license: String, version: String) async throws {
        try await dictionary.setMetadata(TestDictionary.Metadata(source: source, displayName: displayName,
                                                                 license: license, version: version))
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
    /// imported source (no metadata row, Issue #138) → `""`.
    func testFetchSourceStatsCarriesLicenseAndVersion() async throws {
        // Distinct counts (3 > 2 > 1) so the count-desc order is deterministic.
        try await seedSourcedEntries(source: "wordnet", words: ["alpha", "beta", "delta"])
        try await seedSourcedEntries(source: "freedict-eng-spa", words: ["gato", "perro"])
        let importFile = tempDir.appendingPathComponent("test_import_fixture.json")
        try Data(#"[{"word": "gamma", "definition": "Definition of gamma."}]"#.utf8).write(to: importFile)
        _ = try await db.importJSON(at: importFile, source: "test_import_fixture")
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
    /// Issue #138: the test's dictionary file and user database.
    private var dictionary: TestDictionaryFixture!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await DictAppTests.waitForHostAppLaunch()
        dictionary = TestDictionaryFixture(directory: tempDir)
        try await dictionary.open()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func language(_ code: String) -> UILanguage {
        UILanguage(code: code, displayKey: "language.\(code)", nativeName: code)
    }

    /// Inserts `count` distinct rows for `source` so `fetchSourceStats()` ranks
    /// sources by descending row count. Words are namespaced per source so the
    /// (word, source) unique index never collides across sources.
    private func seed(source: String, count: Int) async throws {
        try await dictionary.add(TestDictionary.rows(source: source, count: count))
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
    /// Issue #138: the test's dictionary file and user database.
    private var dictionary: TestDictionaryFixture!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await DictAppTests.waitForHostAppLaunch()
        dictionary = TestDictionaryFixture(directory: tempDir)
        try await dictionary.open()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func seed(source: String) async throws {
        let count = try XCTUnwrap(counts[source], "no seed count for \(source)")
        try await dictionary.add(TestDictionary.rows(source: source, count: count))
    }

    private func seedBundled() async throws {
        try await dictionary.add(bundledSources.flatMap { TestDictionary.rows(source: $0, count: counts[$0] ?? 0) })
    }

    private func insertMetadata(source: String, displayName: String) async throws {
        try await dictionary.setMetadata(TestDictionary.Metadata(source: source, displayName: displayName))
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
        // (U+2068 FSI … U+2069 PDI) so the names never reorder across the dash;
        // the catalog's leading U+200F (RLM) makes the line right-to-left (#119).
        XCTAssertEqual(ar.dictionaries.first?.displayName,
                       "\u{200F}\u{2068}العربية\u{2069} – \u{2068}الإنجليزية\u{2069}")
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
                       "\u{200F}\u{2068}الإسبانية\u{2069} – \u{2068}الإنجليزية\u{2069}",
                       "Arabic: leading RLM (#119), catalog names, each bidi-isolated by Foundation's RTL formatting")
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
        XCTAssertEqual(stripIsolates(arabic), "\u{200F}العربية ← الإنجليزية",
                       "leading RLM (#119), from-language first in logical order, both names Arabic")

        let spanish = try XCTUnwrap(SettingsViewModel.languageSummary(for: stat("freedict-eng-spa"), locale: ar))
        XCTAssertEqual(stripIsolates(spanish), "\u{200F}الإنجليزية ← الإسبانية")

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

    /// Opens `DatabaseService.shared` on a fresh user database with the
    /// bundled dictionary file attached (Issue #138), so the real
    /// `fetchSourceStats()` SQL runs against the shipped metadata.
    private func seedSourceStats() async throws -> [SourceStat] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        await DictAppTests.waitForHostAppLaunch()
        try await DatabaseService.shared.setup(userPath: dir.appendingPathComponent("user.sqlite").path,
                                               dictionaryURL: try TestDictionary.bundledURL())
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

    /// The stored `definition` of one fixture row, read back raw from the
    /// test's dictionary file.
    private func storedDefinition(word: String, source: String) async throws -> String {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: try XCTUnwrap(dictionary.dictionaryURL).path, configuration: config)
        return try await queue.read { conn in
            try String.fetchOne(conn, sql: "SELECT definition FROM entries WHERE word = ? AND source = ?",
                                arguments: [word, source]) ?? ""
        }
    }

    /// Points `db` at the bundled dictionary file (Issue #138: attached, not
    /// copied), so the app's real `search` SQL runs on shipped rows.
    private func useSeedClone() async throws {
        try await db.setup(userPath: tempDir.appendingPathComponent("seed-user.sqlite").path,
                           dictionaryURL: try TestDictionary.bundledURL())
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
        var rows = (0..<89_999).map { i in
            TestDictionary.Row(word: "word\(i)", definition: "Definition for word number \(i). This is a sample definition.",
                               pos: "noun", source: "test")
        }
        for i in 0..<10_000 {
            let a = vocabulary[i % vocabulary.count]
            let b = vocabulary[(i / vocabulary.count) % vocabulary.count]
            let mention = i % 500 == 0 ? ", σκύλος" : ""
            let definition = Self.decomposeGreek("**noun**\n1. \(a), \(b)\(mention) — gloss number \(i)")
            rows.append(TestDictionary.Row(word: "gword\(i)", definition: definition, pos: "noun", source: "wordnet-eng-ell"))
        }
        rows.append(TestDictionary.Row(word: "σκύλος", normalized: "σκυλοσ", definition: "**noun**\n1. dog, hound",
                                       pos: "noun", source: "freedict-ell-eng"))
        try await dictionary.add(rows)
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
                                          (es, "Griego – Inglés"), (ar, "\u{200F}اليونانية – الإنجليزية"),
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
                       "\u{200F}اليونانية ← الإنجليزية")
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
        try await dictionary.add(TestDictionary.rows(source: source, count: count))
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

// MARK: - Bundled dictionary file shape

extension DictAppTests {
    /// The sources of the bundled file's `entries` are exactly its
    /// `dict_metadata` sources, in entry block order, with an exact
    /// `word_count` (Settings counts read it since #138); the file is not in
    /// WAL mode (it is attached read-only and immutable from the bundle).
    func testSeedEntrySourcesMatchMetadata() throws {
        let queue = try Self.openBundledSeedReadOnly()
        let blocks = try queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT source, COUNT(*) AS n, MIN(id) AS lo, MAX(id) AS hi FROM entries GROUP BY source ORDER BY lo
                """)
        }
        let metadata = try queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT source, word_count FROM dict_metadata ORDER BY rowid")
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
            XCTAssertEqual(row["word_count"] as Int, rows[source], "\(source): word_count is its row count")
        }
        XCTAssertNotEqual(journal?.lowercased(), "wal", "a WAL file could not be attached from the read-only bundle")
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

// MARK: - Issue #114: History timestamp caption

/// `HistoryTimestamp` is pure, so every case pins its locale and time zone.
/// en, el and ar output carries U+202F / RLM / U+060C, so those locales are
/// checked by fragment; ar digits are never asserted (iOS may use Arabic-Indic).
final class HistoryTimestampTests: XCTestCase {
    /// 20:41 UTC, so Tokyo (UTC+9, no DST) is already 16 Jan.
    private let stored = "2026-01-15 20:41:07"
    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let languages = ["en", "ru", "es", "ar", "el"]
    private let todayWords = ["en": "Today", "ru": "Сегодня", "es": "Hoy", "ar": "اليوم", "el": "Σήμερα"]
    private let yesterdayWords = ["en": "Yesterday", "ru": "Вчера", "es": "Ayer", "ar": "أمس", "el": "Χθες"]
    private let rawUTCPattern = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#

    /// `date` as `addToHistory` stores it: UTC `datetime('now')` text.
    private func storedString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func caption(_ raw: String, _ locale: Locale, in zone: TimeZone) throws -> String {
        try XCTUnwrap(HistoryTimestamp.text(raw, locale: locale, timeZone: zone),
                      "\(locale.identifier) in \(zone.identifier) must format '\(raw)'")
    }

    private func caption(_ raw: String, _ code: String, in zone: TimeZone) throws -> String {
        try caption(raw, Locale(identifier: code), in: zone)
    }

    func testParsesStoredStringAsUTC() {
        XCTAssertEqual(HistoryTimestamp.date(fromStored: stored), Date(timeIntervalSince1970: 1_768_509_667))
    }

    func testRejectsMissingOrMalformedInput() {
        let inputs: [String?] = [nil, "", "2026-01-15T20:41:07", "garbage"]
        for raw in inputs {
            XCTAssertNil(HistoryTimestamp.text(raw, locale: Locale(identifier: "en"), timeZone: utc),
                         "'\(raw ?? "nil")' must hide the caption, never show the raw text")
        }
    }

    func testFixedTimestampInTwoTimeZones() throws {
        XCTAssertEqual(try caption(stored, "ru", in: utc), "15.01.2026, 20:41")
        XCTAssertEqual(try caption(stored, "ru", in: tokyo), "16.01.2026, 05:41")

        let enUTC = try caption(stored, "en", in: utc)
        XCTAssertTrue(enUTC.contains("1/15/26") && enUTC.contains("8:41"), enUTC)
        let enTokyo = try caption(stored, "en", in: tokyo)
        XCTAssertTrue(enTokyo.contains("1/16/26") && enTokyo.contains("5:41"), enTokyo)
    }

    func testOlderDateIsShortDateInAllLocales() throws {
        for code in languages {
            for zone in [utc, tokyo] {
                let out = try caption(stored, code, in: zone)
                let context = "\(code) in \(zone.identifier): '\(out)'"
                XCTAssertFalse(out.isEmpty, context)
                XCTAssertFalse(out.contains(todayWords[code]!), context)
                XCTAssertFalse(out.contains(yesterdayWords[code]!), context)
                XCTAssertNil(out.range(of: rawUTCPattern, options: .regularExpression), context)
            }
        }
        for code in ["es", "el"] {
            let inUTC = try caption(stored, code, in: utc)
            XCTAssertTrue(inUTC.contains("15/1"), "\(code) UTC: '\(inUTC)'")
            let inTokyo = try caption(stored, code, in: tokyo)
            XCTAssertTrue(inTokyo.contains("16/1"), "\(code) Tokyo: '\(inTokyo)'")
        }
    }

    /// Capitalised words prove `.beginningOfSentence`. Never 2 days back: ru,
    /// es, el and ar have a "day before yesterday" word.
    func testTodayAndYesterdayAreRelativeInAllLocales() throws {
        let now = Date()
        let today = storedString(now)
        let yesterday = storedString(now.addingTimeInterval(-86_400))
        for code in languages {
            for zone in [utc, tokyo] {
                let todayOut = try caption(today, code, in: zone)
                XCTAssertTrue(todayOut.contains(todayWords[code]!), "\(code) in \(zone.identifier): '\(todayOut)'")
                let yesterdayOut = try caption(yesterday, code, in: zone)
                XCTAssertTrue(yesterdayOut.contains(yesterdayWords[code]!),
                              "\(code) in \(zone.identifier): '\(yesterdayOut)'")
            }
        }
    }

    func testInAppLocaleWinsOverDevice() throws {
        let out = try caption(storedString(Date()), "ru", in: utc)
        XCTAssertTrue(out.contains("Сегодня"), "the passed locale, not Locale.current, picks the words: '\(out)'")
    }

    /// PM decision 1: in-app language on the device's region and 24-hour setting.
    func testFormattingLocaleKeepsDeviceRegionAndHourCycle() throws {
        let english = Locale(identifier: "en")

        // English UI on a Russian device: day-first, 24-hour, English words.
        let enRU = HistoryTimestamp.formattingLocale(language: english, device: Locale(identifier: "ru_RU"))
        XCTAssertEqual(enRU.language.languageCode?.identifier, "en")
        XCTAssertEqual(enRU.region?.identifier, "RU")
        let ruRegion = try caption(stored, enRU, in: utc)
        XCTAssertTrue(ruRegion.contains("15.01.2026") && ruRegion.contains("20:41"), ruRegion)
        let ruRegionToday = try caption(storedString(Date()), enRU, in: utc)
        XCTAssertTrue(ruRegionToday.contains("Today"), ruRegionToday)

        // English UI on a Spanish-language US device: month-first, 12-hour.
        let enUS = HistoryTimestamp.formattingLocale(language: english, device: Locale(identifier: "es_US"))
        XCTAssertEqual(enUS.language.languageCode?.identifier, "en")
        XCTAssertEqual(enUS.region?.identifier, "US")
        let usRegion = try caption(stored, enUS, in: utc)
        XCTAssertTrue(usRegion.contains("1/15/26") && usRegion.contains("8:41") && usRegion.contains("PM"), usRegion)

        // The device's 24-hour switch carries over.
        let enUS24 = HistoryTimestamp.formattingLocale(language: english,
                                                       device: Locale(identifier: "en_US@hours=h23"))
        XCTAssertEqual(enUS24.hourCycle, .zeroToTwentyThree)
        let usRegion24 = try caption(stored, enUS24, in: utc)
        XCTAssertTrue(usRegion24.contains("20:41"), usRegion24)

        // The device's script belongs to its language and must not leak into the in-app one.
        let ruOnLatinSerbian = HistoryTimestamp.formattingLocale(language: Locale(identifier: "ru"),
                                                                 device: Locale(identifier: "sr-Latn_RS"))
        let latinSerbianToday = try caption(storedString(Date()), ruOnLatinSerbian, in: utc)
        XCTAssertTrue(latinSerbianToday.contains("Сегодня"), latinSerbianToday)
    }
}

// MARK: - Issue #119: Arabic composed strings read right to left

/// Foundation wraps every `%@` argument in FSI … PDI for an RTL locale, and the
/// bidi algorithm skips isolates when it looks for the first strong character.
/// Without the catalog's leading U+200F (RLM) an Arabic pair title or direction
/// line is laid out left to right, so its first name is drawn on the left and
/// read last. CoreText draws in the same order as SwiftUI `Text` on screen.
final class ArabicBidiOrderTests: XCTestCase {
    private let ar = Locale(identifier: "ar")
    private let ltrLocales = ["en", "ru", "es", "el"].map(Locale.init(identifier:))
    private let english = "الإنجليزية"
    /// Bilingual pairs and their non-English name in Arabic (title leads with it).
    private let pairs: [(id: String, languages: [String], source: String, name: String)] = [
        ("arb-eng", ["arb", "eng"], "wordnet-arb-eng", "العربية"),
        ("eng-spa", ["eng", "spa"], "freedict-eng-spa", "الإسبانية"),
        ("eng-rus", ["eng", "rus"], "openrussian", "الروسية"),
        ("ell-eng", ["ell", "eng"], "freedict-ell-eng", "اليونانية"),
    ]
    /// 20:41 UTC on 15 Jan 2026: never "Today" / "Yesterday".
    private let stored = "2026-01-15 20:41:07"
    private let utc = TimeZone(identifier: "UTC")!
    private let bidiControls: [Unicode.Scalar] = ["\u{200F}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]

    private func pair(_ entry: (id: String, languages: [String], source: String, name: String)) -> DictionaryPair {
        DictionaryPair(id: entry.id, languages: entry.languages, isCustom: false,
                       sources: [SourceStat(source: entry.source, displayName: "Raw \(entry.source)", count: 1)])
    }

    private func direction(_ source: String, _ locale: Locale) throws -> String {
        try XCTUnwrap(SettingsViewModel.languageSummary(
            for: SourceStat(source: source, displayName: "Raw \(source)", count: 1), locale: locale))
    }

    /// The text without RLM and isolates: what a reader sees, in logical order.
    private func visible(_ s: String) -> String {
        String(s.unicodeScalars.filter { !bidiControls.contains($0) })
    }

    /// CoreText x offset of the middle character of `part` inside `text`, laid
    /// out in a natural-direction line with the body font. The middle avoids the
    /// caret ambiguity at an isolate boundary. Larger x = drawn further right.
    private func drawnX(of part: String, in text: String) throws -> CGFloat {
        let found = try XCTUnwrap(text.range(of: part), "'\(part)' not found in '\(text)'")
        let range = NSRange(found, in: text)
        let attributed = NSAttributedString(string: text,
                                            attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
        let line = CTLineCreateWithAttributedString(attributed)
        return CTLineGetOffsetForStringIndex(line, range.location + range.length / 2, nil)
    }

    /// An import view model whose in-app language is `code` (the real path).
    @MainActor
    private func importViewModel(language code: String) -> ManageDictionariesViewModel {
        let settings = SettingsService(store: InMemoryKeyValueStore())
        settings.selectedUILanguageCode = code
        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        XCTAssertEqual(localization.currentLanguage.code, code, "precondition: in-app language is \(code)")
        return ManageDictionariesViewModel(settingsService: settings, localization: localization)
    }

    /// Every bilingual title in `ar` starts with U+200F (the first strong
    /// character outside the isolates, so the line is RTL) and puts the
    /// non-English language first. `arb-eng` is pinned scalar by scalar.
    func testArabicPairTitlesStartWithRLMAndLeadWithNonEnglishLanguage() {
        for entry in pairs {
            let title = SettingsViewModel.displayName(for: pair(entry), locale: ar)
            XCTAssertEqual(title.unicodeScalars.first, "\u{200F}", "\(entry.id): '\(title)'")
            XCTAssertEqual(visible(title), "\(entry.name) – \(english)", entry.id)
        }
        let arabic = SettingsViewModel.displayName(for: pair(pairs[0]), locale: ar)
        XCTAssertEqual(arabic.unicodeScalars.map(\.value),
                       [0x200F,
                        0x2068, 0x627, 0x644, 0x639, 0x631, 0x628, 0x64A, 0x629, 0x2069,
                        0x20, 0x2013, 0x20,
                        0x2068, 0x627, 0x644, 0x625, 0x646, 0x62C, 0x644, 0x64A, 0x632, 0x64A, 0x629, 0x2069],
                       "RLM, isolated العربية, ' – ', isolated الإنجليزية")
    }

    /// `ar` direction lines start with U+200F and keep ← (U+2190), never →.
    func testArabicDirectionLinesStartWithRLMAndKeepLeftArrow() throws {
        for (source, from, to) in [("wordnet-arb-eng", "العربية", english), ("freedict-eng-spa", english, "الإسبانية")] {
            let line = try direction(source, ar)
            XCTAssertEqual(line.unicodeScalars.first, "\u{200F}", "\(source): '\(line)'")
            XCTAssertTrue(line.contains("\u{2190}"), "\(source): '\(line)'")
            XCTAssertFalse(line.contains("\u{2192}"), "\(source): '\(line)'")
            XCTAssertEqual(visible(line), "\(from) ← \(to)", source)
        }
    }

    /// Real layout order: in `ar` the first name of a title or direction line
    /// is drawn to the right of the second. Control: the same line without the
    /// RLM lays out left to right (the #119 bug), so the check is not vacuous.
    func testArabicTitleAndDirectionDrawFirstNameOnTheRight() throws {
        for entry in pairs {
            let title = SettingsViewModel.displayName(for: pair(entry), locale: ar)
            let titleFirst = try drawnX(of: entry.name, in: title)
            let titleSecond = try drawnX(of: english, in: title)
            XCTAssertGreaterThan(titleFirst, titleSecond, "\(entry.id): '\(entry.name)' must be drawn right of '\(english)'")
        }
        for (source, from, to) in [("wordnet-arb-eng", "العربية", english), ("freedict-eng-spa", english, "الإسبانية")] {
            let line = try direction(source, ar)
            let fromX = try drawnX(of: from, in: line)
            let toX = try drawnX(of: to, in: line)
            XCTAssertGreaterThan(fromX, toX, "\(source): from-language '\(from)' must be drawn right of '\(to)'")
        }

        let title = SettingsViewModel.displayName(for: pair(pairs[0]), locale: ar)
        let withoutRLM = String(title.unicodeScalars.dropFirst())
        let bugFirst = try drawnX(of: "العربية", in: withoutRLM)
        let bugSecond = try drawnX(of: english, in: withoutRLM)
        XCTAssertLessThan(bugFirst, bugSecond, "control: without the RLM the line is LTR and the order flips")
    }

    /// Every RTL language in `SupportedLocales.json` (today `ar`) starts both
    /// composed values with U+200F in its compiled lproj. Catches a translator
    /// or an Xcode re-save dropping the invisible mark, and a new RTL language.
    func testEveryRTLLanguageStartsComposedLinesWithRLM() throws {
        let rtl = try DictAppTests.shippedUILanguages().map(\.code)
            .filter { Locale.Language(identifier: $0).characterDirection == .rightToLeft }
        XCTAssertTrue(rtl.contains("ar"), "Arabic is the shipped RTL language; the guard would be vacuous: \(rtl)")
        for code in rtl {
            let path = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"),
                                     "'\(code).lproj' must be compiled into the app bundle")
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["dictionaryPair.title %@ %@", "dictionaryInfo.direction.value %@ %@"] {
                let value = bundle.localizedString(forKey: key, value: "\u{0}MISSING", table: nil)
                XCTAssertNotEqual(value, "\u{0}MISSING", "'\(key)' missing in \(code).lproj")
                XCTAssertEqual(value.unicodeScalars.first, "\u{200F}",
                               "\(code): '\(key)' must start with U+200F (RLM), got '\(value)'")
            }
        }
    }

    /// PM decision Q1: Arabic UI on a 24-hour non-Arabic region (en_GB, de_DE
    /// devices) gets a leading RLM, so the date is drawn right of the time.
    func testArabicHistoryCaptionOn24HourRegionReadsRightToLeft() throws {
        for device in ["en_GB", "de_DE"] {
            let locale = HistoryTimestamp.formattingLocale(language: ar, device: Locale(identifier: device))
            XCTAssertEqual(locale.language.characterDirection, .rightToLeft, "\(device): \(locale.identifier)")
            let caption = try XCTUnwrap(HistoryTimestamp.text(stored, locale: locale, timeZone: utc))
            XCTAssertEqual(caption.unicodeScalars.first, "\u{200F}", "\(device): '\(caption)'")

            // 24-hour: "<date>، <time>"; digits are never asserted. Split after
            // the leading RLM only, so any ICU marks stay inside the tokens.
            let words = String(caption.unicodeScalars.dropFirst()).split(separator: " ").map(String.init)
            XCTAssertEqual(words.count, 2, "\(device): '\(caption)'")
            let date = try XCTUnwrap(words.first).trimmingCharacters(in: CharacterSet(charactersIn: "\u{060C},"))
            let time = try XCTUnwrap(words.last)
            let dateX = try drawnX(of: date, in: caption)
            let timeX = try drawnX(of: time, in: caption)
            XCTAssertGreaterThan(dateX, timeX, "\(device): the date is read first, so it is drawn right of the time")
        }
        let bare = try XCTUnwrap(HistoryTimestamp.text(stored, locale: ar, timeZone: utc))
        XCTAssertEqual(bare.unicodeScalars.first, "\u{200F}", "plain ar: '\(bare)'")
    }

    /// PM decision Q2: the unsupported-import message keeps ".pdf" in an LTR
    /// isolate (LRI … PDI), so the dot is drawn left of the extension.
    @MainActor
    func testArabicUnsupportedImportKeepsDotBeforeExtension() async throws {
        let vm = importViewModel(language: "ar")
        await vm.performImport(url: FileManager.default.temporaryDirectory.appendingPathComponent("notes.pdf"))
        let message = try XCTUnwrap(vm.importResult)
        let arabicText: [UInt32] = "نوع ملف غير مدعوم: ".unicodeScalars.map(\.value)
        let isolatedExtension: [UInt32] = [0x2066, 0x2E, 0x2068, 0x70, 0x64, 0x66, 0x2069, 0x2069]
        XCTAssertEqual(message.unicodeScalars.map(\.value), arabicText + isolatedExtension,
                       "LRI '.' FSI pdf PDI PDI after the Arabic text: '\(message)'")
        let dotX = try drawnX(of: ".", in: message)
        let extensionX = try drawnX(of: "pdf", in: message)
        XCTAssertLessThan(dotX, extensionX, "'.pdf', not 'pdf.': '\(message)'")
    }

    /// en, ru, es and el get no RLM or isolate: title, direction, History
    /// caption and the unsupported-import message stay as they were.
    @MainActor
    func testLTRLanguagesGetNoBidiMarks() async throws {
        for locale in ltrLocales {
            let code = locale.identifier
            let title = SettingsViewModel.displayName(for: pair(pairs[1]), locale: locale)
            let line = try direction("freedict-eng-spa", locale)
            let caption = try XCTUnwrap(HistoryTimestamp.text(stored, locale: locale, timeZone: utc))
            let vm = importViewModel(language: code)
            await vm.performImport(url: FileManager.default.temporaryDirectory.appendingPathComponent("notes.pdf"))
            let message = try XCTUnwrap(vm.importResult)
            for output in [title, line, caption, message] {
                XCTAssertFalse(output.unicodeScalars.contains { bidiControls.contains($0) },
                               "\(code): '\(output)' must carry no bidi control")
            }
        }
    }
}

// MARK: - Issue #202: Speak each word in its own language

@MainActor
final class SpeechLanguageTests: XCTestCase {
    private func entry(_ word: String, _ source: String) -> DictionaryEntry {
        DictionaryEntry(id: nil, word: word, definition: "", phonetic: "", pos: "", source: source, createdAt: nil)
    }

    /// Every bundled source speaks in its headword (source) language.
    func testBundledSourcesMapToHeadwordLanguage() {
        let expected = [
            "wordnet": "en-US", "openrussian": "ru-RU",
            "freedict-eng-spa": "en-US", "wordnet-spa-eng": "es-ES",
            "wordnet-arb-eng": "ar-SA",
            "freedict-ell-eng": "el-GR", "wordnet-ell-eng": "el-GR",
            "freedict-eng-ell": "en-US", "wordnet-eng-ell": "en-US",
        ]
        let bundled = Set(DictionaryGrouping.legacyBareIDs.keys).union(DictionaryGrouping.bundledSourceIDs)
        XCTAssertEqual(Set(expected.keys), bundled, "every bundled source is covered")
        for (source, language) in expected {
            XCTAssertEqual(SpeechService.language(forSource: source), language, source)
        }
    }

    /// Imports declare no language: `en-US`, unless the file name is a bundled ID.
    func testImportsUseEnglishUnlessNamedLikeABundledSource() {
        for source in ["test_import_fixture", "my dict", "freedict-spa-eng", "freedict-deu-eng", ""] {
            XCTAssertEqual(SpeechService.language(forSource: source), "en-US", source)
        }
        XCTAssertEqual(SpeechService.language(forSource: "wordnet-ell-eng"), "el-GR")
    }

    /// AC1: дом, casa, بيت, σπίτι and house each get their own voice.
    func testDefinitionSpeaksTheHeadwordLanguage() {
        let cases = [
            (entry("дом", "openrussian"), "ru-RU"), (entry("casa", "wordnet-spa-eng"), "es-ES"),
            (entry("بيت", "wordnet-arb-eng"), "ar-SA"), (entry("σπίτι", "freedict-ell-eng"), "el-GR"),
            (entry("house", "wordnet"), "en-US"),
        ]
        for (entry, language) in cases {
            var asked: [String] = []
            let vm = DefinitionViewModel(entry: entry, hasVoice: { asked.append($0); return true })
            XCTAssertEqual(vm.speechLanguage, language, entry.word)
            XCTAssertEqual(asked, [language], "\(entry.word): the voice check gets the headword language")
            XCTAssertTrue(vm.canSpeak, entry.word)
        }
    }

    /// Every voice code resolves on the OS under test (checked on iOS 17.5 and 26.4).
    func testEveryBundledLanguageHasAVoice() {
        for language in Set(SpeechService.voiceLanguages.values) {
            XCTAssertTrue(SpeechService.hasVoice(for: language), language)
        }
    }

    /// No voice for the headword language hides the speaker button.
    func testNoVoiceHidesSpeaker() {
        let englishOnly: (String) -> Bool = { $0 == "en-US" }
        XCTAssertFalse(DefinitionViewModel(entry: entry("σπίτι", "freedict-ell-eng"), hasVoice: englishOnly).canSpeak)
        XCTAssertTrue(DefinitionViewModel(entry: entry("house", "wordnet"), hasVoice: englishOnly).canSpeak)
    }
}

// MARK: - Issue #140: the dictionary file's format

/// The bundled `dictionaries.sqlite` as `Scripts/build_dictionaries.py`
/// writes it (0129-dictionary-file.md, "Dictionary file" and "Build").
final class DictionaryFileTests: XCTestCase {

    /// `user_version` is the app's `DictionaryFile.formatVersion`, the file
    /// is in rollback-journal mode, every dictionary's `word_count` is its row
    /// count and its languages are the ISO 639-3 codes of its source ID, and
    /// no column stamps the build time.
    func testDictionaryFileFormat() throws {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: TestDictionary.bundledURL().path, configuration: config)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), DictionaryFile.formatVersion,
                           "the bundled file and DictionaryFile.formatVersion (FORMAT_VERSION in the build) must match")
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased(), "delete")

            let counts = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: """
                SELECT source, COUNT(*) AS n FROM entries GROUP BY source
                """).map { ($0["source"] as String, $0["n"] as Int) })
            let metadata = try Row.fetchAll(db, sql: "SELECT source, word_count, from_lang, to_lang FROM dict_metadata")
            XCTAssertEqual(Set(metadata.map { $0["source"] as String }), Set(counts.keys),
                           "dict_metadata lists exactly the entry sources")
            for row in metadata {
                let source: String = row["source"]
                XCTAssertEqual(row["word_count"] as Int, counts[source], "\(source): word_count is its row count")
                let languages = DictionaryGrouping.parse(sourceID: source).languages
                XCTAssertEqual(row["from_lang"] as String, languages.first, "\(source): from_lang")
                XCTAssertEqual(row["to_lang"] as String, languages.last, "\(source): to_lang")
            }

            XCTAssertFalse(try db.columns(in: "entries").map(\.name).contains("created_at"))
            XCTAssertFalse(try db.columns(in: "dict_metadata").map(\.name).contains("built_at"))
            XCTAssertTrue(try db.tableExists("data_source"), "credits table for non-dictionary data sets")
        }
    }

    /// The rest of the file's shape (0129, "Dictionary file"): no triggers,
    /// because the file never changes; no `ANALYZE` statistics, so the query
    /// plans stay the measured ones; the unique `(word COLLATE NOCASE,
    /// source)` index that makes `EntryKey` unique; the FTS5 index over
    /// `entries` with the tokenizer the imported index shares; and every id
    /// below 2^40, where imported ids start.
    func testDictionaryFileStructure() throws {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: TestDictionary.bundledURL().path, configuration: config)
        try queue.read { db in
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'"), [],
                           "no triggers: the FTS index is rebuilt once by the build")
            XCTAssertFalse(try db.tableExists("sqlite_stat1"), "no ANALYZE")
            XCTAssertFalse(try db.tableExists("history") || db.tableExists("bookmarks"),
                           "the 1.x seed's empty user tables are gone")

            let uniqueIndexes = try Row.fetchAll(db, sql: "PRAGMA index_list(entries)")
                .filter { ($0["unique"] as Int) == 1 }
                .map { $0["name"] as String }
            let keys = try uniqueIndexes.map { name in
                try Row.fetchAll(db, sql: "PRAGMA index_xinfo(\(name.quotedDatabaseIdentifier))")
                    .filter { ($0["key"] as Int) == 1 }
                    .map { "\($0["name"] as String? ?? "?") \($0["coll"] as String)" }
            }
            XCTAssertTrue(keys.contains(["word NOCASE", "source BINARY"]),
                          "entries is unique on (word COLLATE NOCASE, source): \(keys)")

            let fts = try XCTUnwrap(String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'entries_fts'"))
            for clause in ["fts5", "word_normalized, definition", "content='entries'", "content_rowid='id'",
                           "tokenize='unicode61 remove_diacritics 2'"] {
                XCTAssertTrue(fts.contains(clause), "entries_fts has \(clause): \(fts)")
            }

            let maxID = try XCTUnwrap(Int64.fetchOne(db, sql: "SELECT MAX(id) FROM entries"))
            XCTAssertGreaterThan(maxID, 0)
            XCTAssertLessThan(maxID, Int64(1) << 40, "bundled ids stay below the first imported id")
        }
    }

    /// A dictionary file the app cannot read fails setup loudly instead of
    /// attaching an empty `dict`, so the app shows its database error rather
    /// than a Search that fails on every query:
    /// - missing: `mode=ro` never creates a file at the path (SQLITE_CANTOPEN);
    /// - a Git LFS pointer checked out instead of the file (the 1.x "SQLite
    ///   error 26" crash): SQLITE_NOTADB, and the pointer is left as it was.
    func testSetupFailsWithoutAReadableDictionaryFile() async throws {
        await DictAppTests.waitForHostAppLaunch()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let userPath = folder.appendingPathComponent("user.sqlite").path

        let missing = folder.appendingPathComponent("missing.sqlite")
        do {
            try await DatabaseService.shared.setup(userPath: userPath, dictionaryURL: missing)
            XCTFail("setup must fail on a missing dictionary file")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CANTOPEN, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path),
                       "a read-only attach creates no empty file at the dictionary path")

        let pointer = folder.appendingPathComponent("pointer.sqlite")
        let pointerText = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:14dcb3318077de8dc872412683e9d12a6ede8d6cb3a7ce43751b05f9c61c6ff5
            size 126050304

            """
        try pointerText.write(to: pointer, atomically: true, encoding: .utf8)
        do {
            try await DatabaseService.shared.setup(userPath: userPath, dictionaryURL: pointer)
            XCTFail("setup must fail on a Git LFS pointer")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_NOTADB, "\(error)")
        }
        XCTAssertEqual(try String(contentsOf: pointer, encoding: .utf8), pointerText, "the pointer file is untouched")
    }

    /// #129, #139, #140: the dictionaries are stored once, in the bundle.
    /// The host app launched through the real `setup()`, so `Application
    /// Support/DictApp` holds the user database alone (`user.sqlite` with its
    /// `-wal` and `-shm`), and all of Application Support and Documents stays
    /// under 5 MB with no copy of the dictionary file (1.4.0 unpacked ~138 MB
    /// there). A 1.x `dict.sqlite` left by an earlier install on this
    /// simulator is #139's to move and delete, so it is left out.
    func testDictionaryFileIsNeverCopied() async throws {
        await DictAppTests.waitForHostAppLaunch()
        let fileManager = FileManager.default
        let userDatabase = DatabaseService.userDatabaseURL().resolvingSymlinksInPath()
        let folder = userDatabase.deletingLastPathComponent()
        let legacy = DatabaseService.legacyDatabaseURL().resolvingSymlinksInPath()
        let legacyPaths = Set(["", "-wal", "-shm", "-journal"].map { legacy.path + $0 })
        let userNames = Set(["", "-wal", "-shm"].map { userDatabase.lastPathComponent + $0 })

        let names = try fileManager.contentsOfDirectory(atPath: folder.path)
            .filter { !legacyPaths.contains(folder.appendingPathComponent($0).path) }
        XCTAssertTrue(names.contains(userDatabase.lastPathComponent), "the launch created the user database: \(names)")
        XCTAssertTrue(Set(names).isSubset(of: userNames), "only the user database lives in \(folder.path): \(names.sorted())")

        let files = try [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory]
            .compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
            .flatMap(Self.regularFiles(under:))
            .filter { !legacyPaths.contains($0.url.resolvingSymlinksInPath().path) }
        let total = files.reduce(0) { $0 + $1.size }
        let listing = files.map { "\($0.url.lastPathComponent) \($0.size) B" }
        XCTAssertLessThan(total, 5_000_000, "Application Support and Documents hold \(total) bytes: \(listing)")
        let bundledName = DictionaryFile.resourceName + "." + DictionaryFile.resourceExtension
        XCTAssertFalse(files.contains { $0.url.lastPathComponent == bundledName },
                       "the dictionary file is never copied: \(listing)")
    }

    /// Every regular file below `root`, with its size.
    private static func regularFiles(under root: URL) throws -> [(url: URL, size: Int)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var files: [(url: URL, size: Int)] = []
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true { files.append((url, values.fileSize ?? 0)) }
        }
        return files
    }
}

// MARK: - Issue #138: test dictionary files

/// Dictionary files for unit tests: the bundled dictionary file's schema
/// (copied from its `sqlite_master`) holding only the given rows, so a test
/// controls exactly what Search sees. Rollback journal, like the bundled
/// file, and no triggers: the FTS index is rebuilt once after the inserts.
/// `DatabaseService.setup(userPath:dictionaryURL:)` attaches the result.
enum TestDictionary {
    struct Row {
        var word: String
        var wordNormalized: String
        var definition: String
        var phonetic: String
        var pos: String
        var source: String

        /// `normalized` defaults to `word`, as for every en, ru and es source.
        init(word: String, normalized: String? = nil, definition: String,
             phonetic: String = "", pos: String = "", source: String) {
            self.word = word
            self.wordNormalized = normalized ?? word
            self.definition = definition
            self.phonetic = phonetic
            self.pos = pos
            self.source = source
        }
    }

    /// One `dict_metadata` row. A source without one gets its ID as the
    /// display name, an empty license and version, and `eng` → `eng`.
    struct Metadata {
        var source: String
        var displayName: String
        var license = ""
        var version = ""
        var fromLang = "eng"
        var toLang = "eng"
    }

    /// `count` distinct rows for `source` (`<source>-w<i>`, "def <i>").
    static func rows(source: String, count: Int) -> [Row] {
        (0..<count).map { Row(word: "\(source)-w\($0)", definition: "def \($0)", pos: "noun", source: source) }
    }

    /// The bundled dictionary file of the host app.
    static func bundledURL() throws -> URL {
        let hostBundle: Bundle = {
            if let url = Bundle.main.url(forResource: "DictApp", withExtension: "app") {
                return Bundle(url: url) ?? .main
            }
            return .main
        }()
        let name = DictionaryFile.resourceName, ext = DictionaryFile.resourceExtension
        return try XCTUnwrap(
            hostBundle.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext),
            "Bundled \(name).\(ext) is missing from the app bundle")
    }

    /// Writes a dictionary file with `rows` (in this order, `INSERT OR
    /// IGNORE` as the build does) and one `dict_metadata` row per source:
    /// `metadata` where given, else the default, with `word_count` = its
    /// rows. Returns its URL: `url`, or a new temp file.
    @discardableResult
    static func make(rows: [Row], metadata: [Metadata] = [], at url: URL? = nil) throws -> URL {
        let url = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("dictionary-\(UUID().uuidString).sqlite")
        var readonly = Configuration()
        readonly.readonly = true
        let schema = try DatabaseQueue(path: bundledURL().path, configuration: readonly).read { db in
            try GRDB.Row.fetchAll(db, sql: """
                SELECT type, name, sql FROM sqlite_master
                WHERE sql IS NOT NULL AND type IN ('table', 'index') AND name NOT LIKE 'sqlite%'
                ORDER BY rowid
                """)
        }
        // A virtual table creates its own shadow tables (`entries_fts_data`, …).
        let virtualTables = schema.filter { ($0["sql"] as String).hasPrefix("CREATE VIRTUAL TABLE") }
            .map { $0["name"] as String }
        let statements = schema.filter { row in
            let name: String = row["name"]
            let sql: String = row["sql"]
            return sql.hasPrefix("CREATE VIRTUAL TABLE") || !virtualTables.contains { name.hasPrefix($0 + "_") }
        }.map { $0["sql"] as String }

        try? FileManager.default.removeItem(at: url)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            for sql in statements { try db.execute(sql: sql) }
            let insert = try db.makeStatement(sql: """
                INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            for row in rows {
                try insert.execute(arguments: [row.word, row.wordNormalized, row.definition,
                                               row.phonetic, row.pos, row.source])
            }
            try db.execute(sql: "INSERT INTO entries_fts(entries_fts) VALUES('rebuild')")

            let counts = try GRDB.Row.fetchAll(db, sql: """
                SELECT source, COUNT(*) AS n FROM entries GROUP BY source ORDER BY MIN(id)
                """).map { ($0["source"] as String, $0["n"] as Int) }
            var sources = counts.map(\.0)
            sources += metadata.map(\.source).filter { !sources.contains($0) }
            for source in sources {
                let entry = metadata.first { $0.source == source } ?? Metadata(source: source, displayName: source)
                try db.execute(
                    sql: """
                        INSERT INTO dict_metadata(source, display_name, license, version, word_count, from_lang, to_lang)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [source, entry.displayName, entry.license, entry.version,
                                counts.first { $0.0 == source }?.1 ?? 0, entry.fromLang, entry.toLang])
            }
        }
        return url
    }
}

/// The dictionary a unit test searches, on `DatabaseService.shared`. An
/// attached dictionary file is immutable, so every change writes a new file
/// with all rows so far and reopens the service on it. The user database
/// (`user.sqlite` in `directory`) carries over: History, My words and
/// imports survive a change.
final class TestDictionaryFixture {
    let directory: URL
    private(set) var rows: [TestDictionary.Row] = []
    private var metadata: [TestDictionary.Metadata] = []
    /// The file the service has attached, once `open()` ran.
    private(set) var dictionaryURL: URL?
    private var generation = 0

    var userPath: String { directory.appendingPathComponent("user.sqlite").path }

    init(directory: URL) {
        self.directory = directory
    }

    /// Writes the current rows into a new file and reopens the service on it.
    func open() async throws {
        generation += 1
        let url = try TestDictionary.make(
            rows: rows, metadata: metadata,
            at: directory.appendingPathComponent("dictionary-\(generation).sqlite"))
        dictionaryURL = url
        try await DatabaseService.shared.setup(userPath: userPath, dictionaryURL: url)
    }

    func add(_ newRows: [TestDictionary.Row]) async throws {
        rows += newRows
        try await open()
    }

    func setMetadata(_ entry: TestDictionary.Metadata) async throws {
        metadata.removeAll { $0.source == entry.source }
        metadata.append(entry)
        try await open()
    }
}

// MARK: - Issue #138: user database and the attached dictionary file
//
// The spec's #138 tests (0129-dictionary-file.md, Test plan), plus the
// import, preferred-mode and My words cases around them.

/// The user database with a `TestDictionary` file attached as `dict`, on
/// `DatabaseService.shared`. Each test opens a fresh user database in its own
/// folder. A test that swaps the dictionary file reopens the service on the
/// same user database, as an app update does.
final class UserDatabaseTests: XCTestCase {
    private var tempDir: URL!
    private var db: DatabaseService { .shared }
    /// The source ID an import of the bundled fixtures gets (their file name).
    private let fixtureSource = "test_import_fixture"
    /// Imported ids start here; dictionary file ids stay below.
    private static let firstImportedID: Int64 = 1 << 40

    /// "dog" in two bundled sources. `wordnet` has the lower id, so 1.4.0's
    /// lookup in any source opened every "dog" History row from WordNet.
    private static let dogRows = [
        TestDictionary.Row(word: "dog", definition: "**noun**\n1. a member of the genus Canis", pos: "noun",
                           source: "wordnet"),
        TestDictionary.Row(word: "dog", definition: "**noun**\n1. perro, can", pos: "noun",
                           source: "freedict-eng-spa"),
        TestDictionary.Row(word: "cat", definition: "**noun**\n1. a feline mammal", pos: "noun", source: "wordnet"),
    ]

    override func setUp() async throws {
        try await super.setUp()
        await DictAppTests.waitForHostAppLaunch()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private var userPath: String { tempDir.appendingPathComponent("user.sqlite").path }

    /// Writes `rows` into the dictionary file `name` and opens the service on
    /// it. The user database carries over.
    @discardableResult
    private func open(_ rows: [TestDictionary.Row], name: String = "dictionary-a.sqlite") async throws -> URL {
        let url = try TestDictionary.make(rows: rows, at: tempDir.appendingPathComponent(name))
        try await db.setup(userPath: userPath, dictionaryURL: url)
        return url
    }

    private func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: "test_import_fixture", withExtension: ext),
                      "the bundled import fixture .\(ext)")
    }

    /// Writes `rows` as an import file named `name` (its source ID).
    private func importFile(_ name: String, _ rows: [[String: String]]) throws -> URL {
        let url = tempDir.appendingPathComponent(name + ".json")
        try JSONSerialization.data(withJSONObject: rows).write(to: url)
        return url
    }

    /// A read-only connection of the test's own, outside the service.
    private func inspect(_ path: String) throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: path, configuration: config)
    }

    /// The files SQLite would create next to a database it writes.
    private func sidecars(of url: URL) -> [String] {
        ["-journal", "-wal", "-shm"].map { url.path + $0 }.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private func historyItem(_ word: String, file: StaticString = #filePath,
                             line: UInt = #line) async throws -> HistoryItem {
        let items = try await db.fetchHistory()
        return try XCTUnwrap(items.first { $0.word == word }, "History row '\(word)'", file: file, line: line)
    }

    private static func keys(_ entries: [DictionaryEntry]) -> [EntryKey] {
        entries.map { EntryKey($0) }
    }

    // MARK: Dictionary file and user database

    /// Every kind of write to `dict.*` fails with SQLITE_READONLY on the
    /// writer, the one connection that writes. `dict` is the test's file
    /// itself, so iOS SQLite honours the URI (`mode=ro&immutable=1`). The
    /// file stays byte-identical with no journal next to it, and the writer
    /// keeps serving the user database.
    func testDictionaryFileIsReadOnly() async throws {
        let url = try await open(Self.dogRows)
        let bytes = try Data(contentsOf: url)

        let (files, readOnly) = try await db.writeForTesting { conn in
            let files = try Row.fetchAll(conn, sql: "PRAGMA database_list")
                .map { ($0["name"] as String, $0["file"] as String) }
            return (Dictionary(uniqueKeysWithValues: files), sqlite3_db_readonly(conn.sqliteConnection, "dict"))
        }
        let attached = try XCTUnwrap(files["dict"], "dict is attached on the writer: \(files)")
        XCTAssertEqual(URL(fileURLWithPath: attached).resolvingSymlinksInPath().path,
                       url.resolvingSymlinksInPath().path,
                       "dict is the dictionary file, not a new file named after the URI")
        XCTAssertEqual(readOnly, 1, "SQLite opened dict read-only")

        let writes = [
            "INSERT INTO dict.entries(word, word_normalized, definition, source) VALUES ('wolf', 'wolf', 'x', 'wordnet')",
            "UPDATE dict.entries SET definition = 'changed' WHERE word = 'dog'",
            "DELETE FROM dict.entries",
            "UPDATE dict.dict_metadata SET word_count = 0",
            "INSERT INTO dict.entries_fts(entries_fts) VALUES('rebuild')",
            "CREATE TABLE dict.scratch(x)",
            "DROP TABLE dict.dict_metadata",
        ]
        for sql in writes {
            do {
                try await db.writeForTesting { conn in try conn.execute(sql: sql) }
                XCTFail("'\(sql)' must fail: the dictionary file is read-only")
            } catch let error as DatabaseError {
                XCTAssertEqual(error.resultCode, .SQLITE_READONLY, "'\(sql)': \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), bytes, "the dictionary file is byte-identical")
        XCTAssertEqual(sidecars(of: url), [], "no journal, WAL or SHM next to the dictionary file")
        let dog = try await db.entry(for: EntryKey(source: "freedict-eng-spa", word: "dog"))
        XCTAssertEqual(dog?.definition, "**noun**\n1. perro, can", "readers see the original rows")
        let rows = try await db.entryCount()
        XCTAssertEqual(rows, 3)
        let found = try await db.search(query: "dog")
        XCTAssertEqual(found.count, 2)

        // The failed writes rolled back; the writer still serves the user database.
        try await db.addToHistory(word: "dog", source: "wordnet")
        let history = try await db.historyCount()
        XCTAssertEqual(history, 1)
    }

    /// History, My words and an import are written to `user.sqlite` only.
    /// The dictionary file stays byte-identical (its leftover 1.x `history`
    /// and `bookmarks` tables stay empty), and a connection of the test's
    /// own finds every row in the user tables. Removing them touches only the
    /// user database too.
    func testUserWritesLandInUserDatabase() async throws {
        let url = try await open(Self.dogRows)
        let bytes = try Data(contentsOf: url)

        try await db.addToHistory(word: "dog", source: "freedict-eng-spa")
        try await db.addToMyWords(EntryKey(source: "wordnet", word: "dog"))
        let read = try await db.importJSON(at: fixture("json"), source: fixtureSource)
        XCTAssertEqual(read, 10)

        XCTAssertEqual(try Data(contentsOf: url), bytes, "the dictionary file is never written")
        XCTAssertEqual(sidecars(of: url), [])
        let dictionaryCounts = try await inspect(url.path).read { conn -> [String: Int] in
            var counts: [String: Int] = [:]
            for table in ["entries", "history", "bookmarks"] {
                if try conn.tableExists(table) {
                    counts[table] = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM \(table)")
                }
            }
            return counts
        }
        XCTAssertEqual(dictionaryCounts["entries"], 3)
        XCTAssertEqual(dictionaryCounts["history", default: 0], 0, "History is not written to the dictionary file")
        XCTAssertEqual(dictionaryCounts["bookmarks", default: 0], 0, "My words are not written to the dictionary file")

        let user = try await inspect(userPath).read { conn in
            (hasEntries: try conn.tableExists("entries"),
             history: try Row.fetchAll(conn, sql: "SELECT source, word FROM history")
                .map { "\($0["source"] as String)/\($0["word"] as String)" },
             myWords: try Row.fetchAll(conn, sql: "SELECT source, word FROM my_words")
                .map { "\($0["source"] as String)/\($0["word"] as String)" },
             importedSources: try String.fetchAll(conn, sql: "SELECT DISTINCT source FROM imported_entries"),
             importedCount: try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM imported_entries") ?? 0,
             lowestImportedID: try Int64.fetchOne(conn, sql: "SELECT MIN(id) FROM imported_entries") ?? 0,
             registered: try String.fetchAll(conn, sql: "SELECT source FROM imported_sources"),
             indexed: try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM imported_fts WHERE imported_fts MATCH 'qaflux'") ?? 0)
        }
        XCTAssertFalse(user.hasEntries, "the user database has no table named like a dictionary table")
        XCTAssertEqual(user.history, ["freedict-eng-spa/dog"])
        XCTAssertEqual(user.myWords, ["wordnet/dog"])
        XCTAssertEqual(user.importedSources, [fixtureSource])
        XCTAssertEqual(user.importedCount, 10)
        XCTAssertGreaterThanOrEqual(user.lowestImportedID, Self.firstImportedID, "imported ids start at 2^40")
        XCTAssertEqual(user.registered, [fixtureSource])
        XCTAssertEqual(user.indexed, 1, "the trigger indexed the import")

        try await db.clearHistory()
        try await db.removeFromMyWords(EntryKey(source: "wordnet", word: "dog"))
        try await db.clearEntries(fromSource: fixtureSource)
        let left = try await inspect(userPath).read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT (SELECT COUNT(*) FROM history) + (SELECT COUNT(*) FROM my_words)
                     + (SELECT COUNT(*) FROM imported_entries) + (SELECT COUNT(*) FROM imported_sources)
                """) ?? -1
        }
        XCTAssertEqual(left, 0)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let bundledLeft = try await db.entryCount()
        XCTAssertEqual(bundledLeft, 3)
    }

    /// An app update brings a new dictionary file with reshuffled ids (a new
    /// source first, rows reversed, one headword dropped). Both imports stay
    /// searchable in both modes with their ids, Settings still counts them,
    /// My words keys resolve to the new rows, and the key of the dropped
    /// headword stays stored but is skipped (#137 rule).
    func testImportSurvivesDictionaryFileReplacement() async throws {
        let alpha = (0..<6).map {
            TestDictionary.Row(word: "alpha\($0)", definition: "alpha word \($0)", source: "alpha")
        }
        try await open(alpha + Self.dogRows, name: "dictionary-a.sqlite")
        let json = try await db.importJSON(at: fixture("json"), source: fixtureSource)
        let sqlite = try await db.importSQLite(at: fixture("sqlite"), source: "sqlite_fixture")
        XCTAssertEqual([json, sqlite], [10, 10])

        let kept = EntryKey(source: "alpha", word: "alpha3")
        let dropped = EntryKey(source: "alpha", word: "alpha5")
        let imported = EntryKey(source: fixtureSource, word: "qaflux")
        for key in [kept, dropped, imported] {
            try await db.addToMyWords(key)
        }
        try await db.addToHistory(word: "alpha3", source: "alpha")
        let idInA = try await db.entry(for: kept)?.id
        let importedIDs = try await db.search(query: "qaflux").map(\.id)

        let fileB = [TestDictionary.Row(word: "zeta", definition: "a new source", source: "zeta")]
            + (alpha + Self.dogRows).reversed().filter { $0.word != dropped.word }
        try await open(fileB, name: "dictionary-b.sqlite")

        let keptInB = try await db.entry(for: kept)
        XCTAssertEqual(keptInB?.definition, "alpha word 3")
        XCTAssertNotNil(keptInB?.id)
        XCTAssertNotEqual(keptInB?.id, idInA, "precondition: the new file reshuffled the ids")

        let qaflux = try await db.search(query: "qaflux")
        XCTAssertEqual(Self.keys(qaflux), [imported])
        XCTAssertEqual(qaflux.map(\.id), importedIDs, "an imported row keeps its id")
        let zarboom = try await db.search(query: "zarboom")
        XCTAssertEqual(Self.keys(zarboom), [EntryKey(source: "sqlite_fixture", word: "zarboom")])
        let groups = [["alpha"], ["zeta"], ["wordnet"], ["freedict-eng-spa"], [fixtureSource], ["sqlite_fixture"]]
        let preferred = try await db.searchPreferred(query: "qaflux", groups: groups,
                                                     enabledSources: Set(groups.joined()))
        XCTAssertEqual(Self.keys(preferred), [imported], "preferred mode finds the import too")
        let jsonRows = try await db.entryCount(source: fixtureSource)
        XCTAssertEqual(jsonRows, 10)

        let stats = Dictionary(uniqueKeysWithValues: try await db.fetchSourceStats().map { ($0.source, $0.count) })
        XCTAssertEqual(stats[fixtureSource], 10)
        XCTAssertEqual(stats["sqlite_fixture"], 10)
        XCTAssertEqual(stats["alpha"], 5, "the bundled count comes from the new file")
        XCTAssertEqual(stats["zeta"], 1)

        let myWords = try await db.fetchMyWords()
        XCTAssertEqual(Set(Self.keys(myWords)), [kept, imported])
        XCTAssertEqual(myWords.first { EntryKey($0) == kept }?.id, keptInB?.id, "the key resolves to the new row")
        let droppedStored = try await db.isInMyWords(dropped)
        XCTAssertTrue(droppedStored, "a key that no longer resolves stays stored")

        let opened = await HistoryDestination.entry(for: try await historyItem("alpha3"))
        XCTAssertEqual(opened?.id, keptInB?.id, "History reopens the row of the new file")
    }

    /// A file named like a bundled source (`freedict-eng-spa.json`) adds only
    /// the words that source lacks, case-insensitively, as 1.4.0 did. They
    /// are searched, opened and counted under the bundled ID. A file whose
    /// words are all bundled stores nothing and registers no dictionary.
    func testImportNamedLikeBundledSourceAddsOnlyMissingWords() async throws {
        try await open(Self.dogRows)
        let file = try importFile("freedict-eng-spa", [
            ["word": "DOG", "definition": "imported perro"],
            ["word": "kennel", "definition": "perrera"],
            ["word": "puppy", "definition": "cachorro"],
        ])
        let read = try await db.importJSON(at: file, source: "freedict-eng-spa")
        XCTAssertEqual(read, 3, "the message counts the rows read, as in 1.4.0")

        let dog = try await db.entry(for: EntryKey(source: "freedict-eng-spa", word: "dog"))
        XCTAssertEqual(dog?.definition, "**noun**\n1. perro, can", "the bundled row wins over 'DOG'")
        let dogs = try await db.search(query: "dog")
        XCTAssertEqual(Set(Self.keys(dogs)), [EntryKey(source: "wordnet", word: "dog"),
                                               EntryKey(source: "freedict-eng-spa", word: "dog")])
        let kennel = try await db.search(query: "kennel")
        XCTAssertEqual(Self.keys(kennel), [EntryKey(source: "freedict-eng-spa", word: "kennel")])
        XCTAssertGreaterThanOrEqual(kennel.first?.id ?? 0, Self.firstImportedID)
        let puppy = try await db.entry(for: EntryKey(source: "freedict-eng-spa", word: "Puppy"))
        XCTAssertEqual(puppy?.definition, "cachorro", "an imported key resolves, case-insensitively")
        let disabled = try await db.search(query: "kennel", enabledSources: ["wordnet"])
        XCTAssertEqual(disabled, [], "the import follows its pair's enabled state")

        let stats = try await db.fetchSourceStats().filter { $0.source == "freedict-eng-spa" }
        XCTAssertEqual(stats.map(\.count), [3], "one Settings row: 1 bundled + 2 imported")

        let allBundled = try importFile("wordnet", [["word": "Cat", "definition": "another cat"]])
        _ = try await db.importJSON(at: allBundled, source: "wordnet")
        let cats = try await db.entryCount(source: "wordnet")
        XCTAssertEqual(cats, 2, "nothing stored")
        let registered = try await inspect(userPath).read { conn in
            try String.fetchAll(conn, sql: "SELECT source FROM imported_sources ORDER BY source")
        }
        XCTAssertEqual(registered, ["freedict-eng-spa"], "a file that stored nothing registers no dictionary")
    }

    /// Preferred mode with imports enabled: an import named like a bundled
    /// source ranks inside its pair's bucket (exact matches before prefix
    /// matches across both stores, one top 4), a custom import is its own
    /// bucket in Dictionary Order, and the relevance tail takes the rest.
    func testPreferredModeRanksImportsInTheirBuckets() async throws {
        try await open([
            TestDictionary.Row(word: "dog", definition: "a canine", source: "wordnet"),
            TestDictionary.Row(word: "dog", definition: "perro", source: "freedict-eng-spa"),
            TestDictionary.Row(word: "dogma", definition: "dogma", source: "freedict-eng-spa"),
            TestDictionary.Row(word: "dogo", definition: "mastiff", source: "wordnet-spa-eng"),
        ])
        _ = try await db.importJSON(at: try importFile("wordnet-spa-eng", [
            ["word": "dog", "definition": "imported perro"],
            ["word": "doggerel", "definition": "ripio"],
        ]), source: "wordnet-spa-eng")
        _ = try await db.importJSON(at: try importFile("my_dogs", [
            ["word": "dogcart", "definition": "a cart"],
            ["word": "dog", "definition": "my dog"],
        ]), source: "my_dogs")

        let groups = [["wordnet"], ["freedict-eng-spa", "wordnet-spa-eng"], ["my_dogs"]]
        let rows = Self.keys(try await db.searchPreferred(query: "dog", groups: groups,
                                                          enabledSources: Set(groups.joined())))
        let prefixRows: Set = [EntryKey(source: "freedict-eng-spa", word: "dogma"),
                               EntryKey(source: "wordnet-spa-eng", word: "dogo"),
                               EntryKey(source: "wordnet-spa-eng", word: "doggerel")]
        XCTAssertEqual(rows.count, 8, "every match once: \(rows)")
        XCTAssertEqual(Set(rows).count, 8)
        guard rows.count == 8 else { return }
        XCTAssertEqual(rows[0], EntryKey(source: "wordnet", word: "dog"))
        XCTAssertEqual(Set(rows[1...2]), [EntryKey(source: "freedict-eng-spa", word: "dog"),
                                          EntryKey(source: "wordnet-spa-eng", word: "dog")],
                       "the pair's exact matches lead its bucket, the imported one included")
        XCTAssertTrue(Set(rows[3...4]).isSubset(of: prefixRows), "then two prefix matches (top 4): \(rows)")
        XCTAssertEqual(Array(rows[5...6]), [EntryKey(source: "my_dogs", word: "dog"),
                                            EntryKey(source: "my_dogs", word: "dogcart")],
                       "the custom import's own bucket, in Dictionary Order")
        XCTAssertTrue(prefixRows.contains(rows[7]), "the tail takes the pair's fifth match")

        let relevance = Self.keys(try await db.search(query: "dog"))
        XCTAssertEqual(Set(relevance.prefix(4)), [EntryKey(source: "wordnet", word: "dog"),
                                                  EntryKey(source: "freedict-eng-spa", word: "dog"),
                                                  EntryKey(source: "wordnet-spa-eng", word: "dog"),
                                                  EntryKey(source: "my_dogs", word: "dog")],
                       "relevance mode: exact matches from both stores first")
    }

    /// The interim Bookmarks tab and star (until #158) read and write My
    /// words by `(source, word)`: the same headword in another source keeps
    /// its own star, the tab skips a key whose entry is gone, and removing a
    /// word on the tab clears its star.
    @MainActor
    func testStarAndBookmarksTabUseMyWords() async throws {
        try await open(Self.dogRows)
        let freeDictEntry = try await db.entry(for: EntryKey(source: "freedict-eng-spa", word: "dog"))
        let wordNetEntry = try await db.entry(for: EntryKey(source: "wordnet", word: "dog"))
        let freeDictDog = try XCTUnwrap(freeDictEntry)
        let wordNetDog = try XCTUnwrap(wordNetEntry)

        let star = DefinitionViewModel(entry: freeDictDog, hasVoice: { _ in false })
        await star.onAppear()
        XCTAssertFalse(star.isBookmarked)
        await star.toggleBookmark()
        XCTAssertTrue(star.isBookmarked)
        XCTAssertNil(star.errorMessage)
        let stored = try await db.isInMyWords(EntryKey(source: "freedict-eng-spa", word: "dog"))
        XCTAssertTrue(stored)

        let otherStar = DefinitionViewModel(entry: wordNetDog, hasVoice: { _ in false })
        await otherStar.onAppear()
        XCTAssertFalse(otherStar.isBookmarked, "the key is (source, word), not the word")
        let viewed = try await historyItem("dog")
        XCTAssertEqual(viewed.source, "wordnet", "opening a definition records its source")

        try await db.addToMyWords(EntryKey(source: "freedict-eng-spa", word: "wolf"))
        let tab = BookmarksViewModel()
        await tab.load()
        XCTAssertEqual(Self.keys(tab.entries), [EntryKey(freeDictDog)], "a key that does not resolve is skipped")
        XCTAssertNil(tab.errorMessage)
        let wolfStored = try await db.isInMyWords(EntryKey(source: "freedict-eng-spa", word: "wolf"))
        XCTAssertTrue(wolfStored, "and stays stored")

        await tab.remove(freeDictDog)
        XCTAssertEqual(tab.entries, [])
        let reopened = DefinitionViewModel(entry: freeDictDog, hasVoice: { _ in false })
        await reopened.onAppear()
        XCTAssertFalse(reopened.isBookmarked, "removing on the tab clears the star")
    }

    /// No user table shares a name with a table of the bundled dictionary
    /// file, so an unqualified name can never reach the wrong store. #140's
    /// `dictionaries.sqlite` no longer carries the 1.x seed's empty
    /// `history` and `bookmarks` tables.
    func testUserSchemaSharesNoTableNameWithTheDictionaryFile() async throws {
        try await db.setup(userPath: userPath, dictionaryURL: try TestDictionary.bundledURL())
        let (user, dictionary) = try await db.writeForTesting { conn in
            let tables = "type IN ('table', 'view') AND name NOT LIKE 'sqlite%'"
            return (try String.fetchAll(conn, sql: "SELECT name FROM main.sqlite_master WHERE \(tables)"),
                    try String.fetchAll(conn, sql: "SELECT name FROM dict.sqlite_master WHERE \(tables)"))
        }
        XCTAssertTrue(user.contains("imported_entries") && dictionary.contains("entries"), "\(user) / \(dictionary)")
        XCTAssertEqual(Set(user).intersection(dictionary), [])
    }

    // MARK: History rows (Kirill, 2026-10-27)

    /// A History row opens the entry of its stored source, not the first
    /// source that has the word (1.4.0 opened WordNet). The last viewed
    /// source wins, the key matches case-insensitively, an imported row
    /// opens from the user database, and a Recent word on Search carries the
    /// same source.
    @MainActor
    func testHistoryOpensStoredSource() async throws {
        try await open(Self.dogRows)
        try await db.addToHistory(word: "dog", source: "freedict-eng-spa")

        let item = try await historyItem("dog")
        XCTAssertEqual(item.source, "freedict-eng-spa")
        let opened = await HistoryDestination.entry(for: item)
        XCTAssertEqual(opened.map { EntryKey($0) }, EntryKey(source: "freedict-eng-spa", word: "dog"))
        XCTAssertEqual(opened?.definition, "**noun**\n1. perro, can")

        let search = SearchViewModel(settings: SettingsService(store: InMemoryKeyValueStore()))
        await search.loadRecent()
        let recent = try XCTUnwrap(search.recentWords.first)
        XCTAssertEqual(recent, item, "a Recent word carries the History row")
        let fromRecent = await HistoryDestination.entry(for: recent)
        XCTAssertEqual(fromRecent?.source, "freedict-eng-spa")

        try await db.addToHistory(word: "dog", source: "wordnet")
        let reread = await HistoryDestination.entry(for: try await historyItem("dog"))
        XCTAssertEqual(reread?.definition, "**noun**\n1. a member of the genus Canis", "the last viewed source wins")

        let upper = await HistoryDestination.entry(for: HistoryItem(word: "DOG", source: "freedict-eng-spa"))
        XCTAssertEqual(upper?.word, "dog", "the word matches case-insensitively")

        _ = try await db.importJSON(at: fixture("json"), source: fixtureSource)
        try await db.addToHistory(word: "qaflux", source: fixtureSource)
        let importedEntry = await HistoryDestination.entry(for: try await historyItem("qaflux"))
        XCTAssertEqual(importedEntry?.source, fixtureSource)
        XCTAssertGreaterThanOrEqual(importedEntry?.id ?? 0, Self.firstImportedID)
        XCTAssertTrue(importedEntry?.definition.hasPrefix("JSON-FIXTURE") ?? false)
    }

    /// The enabled sources only filter Search: a History row of a disabled
    /// source (or with every source off) still opens that source's entry.
    func testHistoryOpensDisabledSource() async throws {
        try await open(Self.dogRows)
        try await db.addToHistory(word: "dog", source: "freedict-eng-spa")
        let settings = SettingsService.shared
        let saved = settings.enabledSources
        defer { settings.enabledSources = saved }

        for enabled: Set<String> in [["wordnet"], []] {
            settings.enabledSources = enabled
            let visible = try await db.search(query: "dog", enabledSources: settings.enabledSources)
            XCTAssertFalse(visible.contains { $0.source == "freedict-eng-spa" },
                           "precondition: Search hides the disabled source (\(enabled))")
            let opened = await HistoryDestination.entry(for: try await historyItem("dog"))
            XCTAssertEqual(opened.map { EntryKey($0) }, EntryKey(source: "freedict-eng-spa", word: "dog"),
                           "enabled \(enabled)")
        }
    }

    /// A History row whose entry is gone shows "not found" (`nil`), with no
    /// lookup in other sources, and stays in History: a headword a
    /// dictionary update dropped (another source still has it), an imported
    /// dictionary that was removed, a source the app never had.
    func testHistoryShowsNotFoundWhenEntryMissing() async throws {
        let kennels = [TestDictionary.Row(word: "kennel", definition: "perrera", source: "freedict-eng-spa"),
                       TestDictionary.Row(word: "kennel", definition: "a dog house", source: "wordnet")]
        try await open(Self.dogRows + kennels, name: "dictionary-a.sqlite")
        try await db.addToHistory(word: "kennel", source: "freedict-eng-spa")
        _ = try await db.importJSON(at: fixture("json"), source: fixtureSource)
        try await db.addToHistory(word: "qaflux", source: fixtureSource)

        try await open(Self.dogRows + [kennels[1]], name: "dictionary-b.sqlite")
        try await db.clearEntries(fromSource: fixtureSource)

        let wordNetKennel = try await db.entry(for: EntryKey(source: "wordnet", word: "kennel"))
        XCTAssertNotNil(wordNetKennel, "precondition: another source still has the word")
        let dropped = await HistoryDestination.entry(for: try await historyItem("kennel"))
        XCTAssertNil(dropped, "a dropped headword is not found, not opened from WordNet")
        let removedImport = await HistoryDestination.entry(for: try await historyItem("qaflux"))
        XCTAssertNil(removedImport, "a removed import is not found")
        let unknown = await HistoryDestination.entry(for: HistoryItem(word: "dog", source: "freedict-deu-eng"))
        XCTAssertNil(unknown, "a source the app never had is not found")

        let words = try await db.fetchHistory().map(\.word)
        XCTAssertEqual(Set(words), ["kennel", "qaflux"], "the rows stay in History")
    }

    /// A row from before 1.3.0 has no source (`''`): it shows "not found"
    /// even though two sources have the word, and it stays in History.
    func testHistoryShowsNotFoundForEmptySource() async throws {
        try await open(Self.dogRows)
        try await db.addToHistory(word: "dog", source: "")

        let item = try await historyItem("dog")
        XCTAssertEqual(item.source, "")
        let found = try await db.search(query: "dog")
        XCTAssertEqual(found.count, 2, "precondition: both sources have the word")
        let opened = await HistoryDestination.entry(for: item)
        XCTAssertNil(opened, "no lookup in other sources")
        let words = try await db.fetchHistory().map(\.word)
        XCTAssertEqual(words, ["dog"], "the row stays in History")
    }
}

// MARK: - Issue #138: search probe against 1.4.0

/// Search on the bundled dictionary file against 1.4.0 (0129 Test plan).
/// `search-probe-1.4.0.json`, next to this file, holds the top 50
/// `(source, word)` of each probe query as 1.4.0 ranked them; it is written
/// by `Scripts/make_search_probe.py`. The test reads it from the source tree
/// (the simulator shares the Mac's file system), so it needs no target
/// membership. A PR that changes the bundled entries regenerates it.
final class SearchProbeTests: XCTestCase {
    private struct Probe: Decodable {
        struct Query: Decodable {
            let query: String
            let groups: [[String]]?
            let results: [[String]]
        }
        let tag: String
        let limit: Int
        let topN: Int
        let relevance: [Query]
        let preferred: [Query]
    }

    private var tempDir: URL!
    private var db: DatabaseService { .shared }
    private let jsonSource = "test_import_fixture"
    private let sqliteSource = "test_import_fixture_sqlite"

    override func setUp() async throws {
        try await super.setUp()
        await DictAppTests.waitForHostAppLaunch()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try await db.setup(userPath: tempDir.appendingPathComponent("user.sqlite").path,
                           dictionaryURL: try TestDictionary.bundledURL())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private static func loadProbe() throws -> Probe {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("search-probe-1.4.0.json")
        let data = try XCTUnwrap(try? Data(contentsOf: url),
                                 "golden file missing at \(url.path); run Scripts/make_search_probe.py")
        let probe = try JSONDecoder().decode(Probe.self, from: data)
        XCTAssertEqual(probe.tag, "v1.4.0")
        XCTAssertEqual(probe.limit, 50)
        XCTAssertEqual(probe.topN, Search.preferredDictionaryTopN)
        XCTAssertGreaterThanOrEqual(probe.relevance.count, 20)
        XCTAssertEqual(probe.preferred.count, 3)
        let sources = Set((probe.relevance + probe.preferred).flatMap { $0.results.map { $0[0] } })
        XCTAssertEqual(sources.count, 9, "the probe reaches every bundled dictionary: \(sources.sorted())")
        return probe
    }

    private static func keys(_ entries: [DictionaryEntry]) -> [[String]] {
        entries.map { [$0.source, $0.word] }
    }

    /// Fails with the first position where `got` leaves the 1.4.0 list.
    private func assertSameList(_ got: [[String]], _ expected: [[String]], _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard got != expected else { return }
        let index = zip(got, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(got.count, expected.count)
        let gotRow = index < got.count ? got[index].joined(separator: "/") : "end"
        let expectedRow = index < expected.count ? expected[index].joined(separator: "/") : "end"
        XCTFail("\(label): row \(index + 1) is \(gotRow), 1.4.0 has \(expectedRow) "
                + "(\(got.count) rows against \(expected.count))", file: file, line: line)
    }

    private func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: "test_import_fixture", withExtension: ext))
    }

    /// Every probe list, relevance and preferred mode, equals 1.4.0's.
    func testBundledProbeMatches140() async throws {
        let probe = try Self.loadProbe()
        for item in probe.relevance {
            let got = try await db.search(query: item.query, limit: probe.limit)
            assertSameList(Self.keys(got), item.results, "relevance '\(item.query)'")
        }
        for item in probe.preferred {
            let groups = try XCTUnwrap(item.groups)
            let got = try await db.searchPreferred(query: item.query, groups: groups,
                                                   enabledSources: Set(groups.joined()),
                                                   topN: probe.topN, limit: probe.limit)
            assertSameList(Self.keys(got), item.results, "preferred '\(item.query)'")
        }
    }

    /// With both fixtures imported: the bundled rows of every list keep
    /// 1.4.0's order (imported rows only interleave), each list holds every
    /// imported match up to the limit, `qaflux` and `zarboom` come first and
    /// `json` returns exactly the 10 JSON fixture rows.
    func testProbeWithFixtureImports() async throws {
        let probe = try Self.loadProbe()
        let read = [try await db.importJSON(at: fixture("json"), source: jsonSource),
                    try await db.importSQLite(at: fixture("sqlite"), source: sqliteSource)]
        XCTAssertEqual(read, [10, 10])
        let imported: Set = [jsonSource, sqliteSource]

        for item in probe.relevance {
            let got = try await db.search(query: item.query, limit: probe.limit)
            let bundled = got.filter { !imported.contains($0.source) }
            assertSameList(Self.keys(bundled), Array(item.results.prefix(bundled.count)),
                           "relevance '\(item.query)', bundled rows")
            let importedMatches = try await db.search(query: item.query, limit: 1_000, enabledSources: imported).count
            XCTAssertEqual(got.count, min(probe.limit, item.results.count + importedMatches),
                           "relevance '\(item.query)': imports add rows, never hide one below the limit")
        }
        for item in probe.preferred {
            let groups = try XCTUnwrap(item.groups) + [[jsonSource], [sqliteSource]]
            let got = try await db.searchPreferred(query: item.query, groups: groups,
                                                   enabledSources: Set(groups.joined()),
                                                   topN: probe.topN, limit: probe.limit)
            let bundled = got.filter { !imported.contains($0.source) }
            assertSameList(Self.keys(bundled), Array(item.results.prefix(bundled.count)),
                           "preferred '\(item.query)', bundled rows")
            XCTAssertEqual(got.count, probe.limit, "preferred '\(item.query)'")
        }

        let qaflux = try await db.search(query: "qaflux")
        XCTAssertEqual(Self.keys(qaflux).first, [jsonSource, "qaflux"])
        let zarboom = try await db.search(query: "zarboom")
        XCTAssertEqual(Self.keys(zarboom).first, [sqliteSource, "zarboom"])

        let fixtureWords = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: fixture("json")))
            .compactMap { $0["word"] }
        let json = try await db.search(query: "json")
        XCTAssertEqual(json.count, 10)
        XCTAssertEqual(Set(Self.keys(json)), Set(fixtureWords.map { [jsonSource, $0] }))
        XCTAssertTrue(json.allSatisfy { ($0.id ?? 0) >= 1 << 40 }, "imported ids start at 2^40")
    }
}

// MARK: - Issue #139: 1.x migration

/// The move of a 1.x database into the user database (0129, "1.x
/// migration"). The fixtures next to this file (`legacy-1.2.0.sqlite`,
/// `legacy-1.3.0.sqlite`, `legacy-1.4.0.sqlite`) are 1.x databases written by
/// `Scripts/make_legacy_fixtures.py`: a subset of each release's bundled rows,
/// two imports, bookmarks and History. The tests read them from the source
/// tree through `#filePath`, like the search probe, so the target needs no
/// resource. Each test copies one into a simulated `Application
/// Support/DictApp` folder and attaches the bundled dictionary file, so the
/// 1.x copy of the bundled rows is recognised and dropped.
final class LegacyMigrationTests: XCTestCase {
    /// What a fixture holds, as the script writes it.
    private struct Fixture {
        let name: String
        /// The import named like a bundled source.
        let named: String
        /// Bookmark keys in bookmark order, dated `bookmarkedAt(i)`.
        let bookmarks: [EntryKey]
        let historyCount: Int
    }

    private static let glossary = "my_glossary"
    private static let glossaryWords = ["house", "housesitter", "zorblat", "quindle", "flumox", "brantoor", "wexley"]
    /// The named import also had "dog", which 1.x skipped: the bundle has it.
    private static let namedWords = ["doomscroll", "photobomb", "dogsitter"]

    private static let v140 = Fixture(
        name: "legacy-1.4.0.sqlite", named: "freedict-eng-spa",
        bookmarks: [EntryKey(source: "wordnet", word: "dog"), EntryKey(source: "freedict-eng-spa", word: "house"),
                    EntryKey(source: "openrussian", word: "дом"), EntryKey(source: "wordnet-arb-eng", word: "كِتاب"),
                    EntryKey(source: "freedict-ell-eng", word: "σπίτι"), EntryKey(source: glossary, word: "zorblat"),
                    EntryKey(source: "freedict-eng-spa", word: "dogsitter")],
        historyCount: 8)
    private static let v130 = Fixture(
        name: "legacy-1.3.0.sqlite", named: "freedict-eng-spa",
        bookmarks: v140.bookmarks.filter { $0.source != "freedict-ell-eng" },
        historyCount: 7)
    /// The 1.1/1.2 shape: no `history.source`, WordNet and OpenRussian only.
    private static let v120 = Fixture(
        name: "legacy-1.2.0.sqlite", named: "wordnet",
        bookmarks: [EntryKey(source: "wordnet", word: "dog"), EntryKey(source: "openrussian", word: "дом"),
                    EntryKey(source: glossary, word: "zorblat"), EntryKey(source: "wordnet", word: "dogsitter")],
        historyCount: 5)

    private static func bookmarkedAt(_ index: Int) -> String {
        String(format: "2026-06-01 %02d:00:00", 9 + index)
    }

    private var tempDir: URL!
    private var db: DatabaseService { .shared }
    /// The simulated `Application Support/DictApp` folder.
    private var appSupport: URL { tempDir.appendingPathComponent("DictApp") }
    private var legacyURL: URL { appSupport.appendingPathComponent("dict.sqlite") }
    private var userPath: String { appSupport.appendingPathComponent("user.sqlite").path }
    private static let userFiles: Set = ["user.sqlite", "user.sqlite-wal", "user.sqlite-shm"]

    override func setUp() async throws {
        try await super.setUp()
        await DictAppTests.waitForHostAppLaunch()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try await db.setup(userPath: userPath, dictionaryURL: try TestDictionary.bundledURL())
    }

    override func tearDown() async throws {
        LegacyMigration.failBeforeCommit = false
        LegacyMigration.failBeforeDelete = false
        LegacyMigration.beforeCopy = nil
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyURL.path)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: Helpers

    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Copies the fixture `name` into the app folder as the 1.x `dict.sqlite`.
    private func install(_ name: String) throws {
        let source = Self.fixtureURL(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "fixture missing at \(source.path); run Scripts/make_legacy_fixtures.py")
        try? FileManager.default.removeItem(at: legacyURL)
        try FileManager.default.copyItem(at: source, to: legacyURL)
    }

    /// Copies the fixture `name` into the app folder and edits it with
    /// `edit`, in one transaction, for rows the fixtures do not hold.
    /// Foreign keys are off, so a test can leave a bookmark without its entry.
    private func install(_ name: String, editedBy edit: (Database) throws -> Void) throws {
        try install(name)
        var config = Configuration()
        config.foreignKeysEnabled = false
        let queue = try DatabaseQueue(path: legacyURL.path, configuration: config)
        try queue.write(edit)
        try queue.close()
    }

    /// Holds the move on the writer, inside its transaction, until `release`
    /// is signalled (30 s at most).
    private final class MoveGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isEntered = false
        let release = DispatchSemaphore(value: 0)
        var entered: Bool { lock.withLock { isEntered } }
        func enter() { lock.withLock { isEntered = true } }
    }

    /// Starts moving the installed 1.x file and returns once the move waits
    /// inside its transaction (the `beforeCopy` seam), before the copy.
    private func startHeldMove(file: StaticString = #filePath,
                               line: UInt = #line) async throws -> (move: Task<Void, Never>, gate: MoveGate) {
        let gate = MoveGate()
        LegacyMigration.beforeCopy = {
            gate.enter()
            _ = gate.release.wait(timeout: .now() + 30)
        }
        let task = await db.startLegacyMigration(legacyURL: legacyURL)
        let move = try XCTUnwrap(task, file: file, line: line)
        let deadline = Date().addingTimeInterval(10)
        while !gate.entered, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(gate.entered, "the move is inside its transaction", file: file, line: line)
        return (move, gate)
    }

    /// `datetime('now')` as SQLite writes it (UTC), for comparing dates the
    /// move stamps.
    private static func sqliteNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    /// Runs the move to its end and returns how long it took.
    @discardableResult
    private func move(file: StaticString = #filePath, line: UInt = #line) async throws -> TimeInterval {
        let started = Date()
        let task = await db.startLegacyMigration(legacyURL: legacyURL)
        let move = try XCTUnwrap(task, "a 1.x file is there, so a move starts", file: file, line: line)
        await move.value
        return Date().timeIntervalSince(started)
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// The 1.x file and its sidecars that are still on disk.
    private func legacyFiles() -> [String] {
        ["", "-wal", "-shm", "-journal"].map { legacyURL.path + $0 }.filter(exists)
    }

    /// A connection of the test's own on a copy of `url`: 1.x files are in
    /// WAL mode, which a read-only connection cannot open without its `-shm`.
    /// The `-wal` comes along, so rows not yet checkpointed are counted.
    private func inspectCopy(of url: URL) throws -> DatabaseQueue {
        let copy = tempDir.appendingPathComponent("inspect-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: url, to: copy)
        if exists(url.path + "-wal") {
            try FileManager.default.copyItem(atPath: url.path + "-wal", toPath: copy.path + "-wal")
        }
        return try DatabaseQueue(path: copy.path)
    }

    /// History rows as `word|source|looked_at`, in id order. `source` is
    /// `''` where the table has no such column (1.1, 1.2); a NULL date reads
    /// `NULL`.
    private static func historyRows(_ conn: Database) throws -> [String] {
        let hasSource = try Row.fetchAll(conn, sql: "PRAGMA table_info(history)")
            .contains { ($0["name"] as String?) == "source" }
        return try Row.fetchAll(conn, sql: """
            SELECT word, \(hasSource ? "source" : "''") AS source, looked_at FROM history ORDER BY id
            """).map { "\($0["word"] as String)|\($0["source"] as String)|\(($0["looked_at"] as String?) ?? "NULL")" }
    }

    /// The user database as a connection of the test's own reads it.
    private struct UserState {
        var history: [String] = []
        /// `source/word|added_at`, in insertion order.
        var myWords: [String] = []
        /// `source/word`, in id order.
        var imported: [String] = []
        var lowestImportedID: Int64 = 0
        /// `source|imported_at`.
        var importedSources: [String] = []
        var marker: String?
    }

    private func userState() throws -> UserState {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: userPath, configuration: config).read { conn in
            UserState(
                history: try Self.historyRows(conn),
                myWords: try Row.fetchAll(conn, sql: "SELECT source, word, added_at FROM my_words ORDER BY added_at")
                    .map { "\($0["source"] as String)/\($0["word"] as String)|\($0["added_at"] as String)" },
                imported: try Row.fetchAll(conn, sql: "SELECT source, word FROM imported_entries ORDER BY id")
                    .map { "\($0["source"] as String)/\($0["word"] as String)" },
                lowestImportedID: try Int64.fetchOne(conn, sql: "SELECT MIN(id) FROM imported_entries") ?? 0,
                importedSources: try Row.fetchAll(conn, sql: "SELECT source, imported_at FROM imported_sources ORDER BY source")
                    .map { "\($0["source"] as String)|\($0["imported_at"] as String)" },
                marker: try String.fetchOne(conn, sql: "SELECT value FROM user_meta WHERE key = ?",
                                            arguments: [LegacyMigration.markerKey]))
        }
    }

    /// `imported_fts` matches `imported_entries` exactly (FTS5 integrity-check
    /// on the writer), so a rolled-back move left no stray index rows.
    private func assertImportIndexIntact(file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await db.writeForTesting { conn in
                try conn.execute(sql: "INSERT INTO imported_fts(imported_fts) VALUES('integrity-check')")
            }
        } catch {
            XCTFail("imported_fts integrity-check: \(error)", file: file, line: line)
        }
    }

    private static func keys(_ entries: [DictionaryEntry]) -> [EntryKey] {
        entries.map { EntryKey($0) }
    }

    /// The imports of `fixture` after a move, in 1.x row order.
    private static func expectedImports(_ fixture: Fixture) -> [String] {
        glossaryWords.map { "\(glossary)/\($0)" } + namedWords.map { "\(fixture.named)/\($0)" }
    }

    /// Moves `fixture` and checks every kind of user data: each bookmark is
    /// a My words key that resolves, dated by the bookmark; History is equal
    /// row for row; exactly the two imports moved (none of the 1.x copy of
    /// the bundled rows), above 2^40, indexed, registered with their earliest
    /// date and searchable; the marker is set; the 1.x file is gone.
    private func assertMigrates(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        try install(fixture.name)
        let legacyHistory = try await inspectCopy(of: legacyURL).read { try Self.historyRows($0) }
        XCTAssertEqual(legacyHistory.count, fixture.historyCount, "precondition", file: file, line: line)

        let seconds = try await move(file: file, line: line)
        print("LegacyMigrationTests: \(fixture.name) moved in \(Int(seconds * 1000)) ms")

        let state = try userState()
        XCTAssertEqual(state.history, legacyHistory, "History is equal row for row", file: file, line: line)
        XCTAssertEqual(state.myWords, fixture.bookmarks.enumerated().map {
            "\($0.element.source)/\($0.element.word)|\(Self.bookmarkedAt($0.offset))"
        }, "each bookmark is a My words key, dated by the bookmark", file: file, line: line)
        let myWords = try await db.fetchMyWords()
        XCTAssertEqual(Self.keys(myWords), fixture.bookmarks.reversed(), "every key resolves, newest first",
                       file: file, line: line)

        XCTAssertEqual(state.imported, Self.expectedImports(fixture),
                       "exactly the two imports moved; the 1.x copy of the bundled rows did not", file: file, line: line)
        XCTAssertGreaterThanOrEqual(state.lowestImportedID, 1 << 40, file: file, line: line)
        XCTAssertEqual(state.importedSources, [
            "\(Self.glossary)|2026-05-10 12:00:00", "\(fixture.named)|2026-05-20 19:30:00",
        ].sorted(), "one row per import, dated by its earliest row", file: file, line: line)
        await assertImportIndexIntact(file: file, line: line)
        let zorblat = try await db.search(query: "zorblat")
        XCTAssertEqual(Self.keys(zorblat), [EntryKey(source: Self.glossary, word: "zorblat")], file: file, line: line)
        let dogsitter = try await db.search(query: "dogsitter")
        XCTAssertEqual(Self.keys(dogsitter), [EntryKey(source: fixture.named, word: "dogsitter")],
                       "the import named like a bundled source is searchable under its ID", file: file, line: line)
        let dog = try await db.entry(for: EntryKey(source: fixture.named, word: "dog"))
        XCTAssertNil(dog?.createdAt, "\"dog\" stays the bundled row", file: file, line: line)

        XCTAssertNotNil(state.marker, "the marker is set", file: file, line: line)
        XCTAssertEqual(legacyFiles(), [], "the 1.x file is gone", file: file, line: line)
    }

    /// `enabled_sources` and `dictionary_order`, as a 1.x install stored
    /// them, still apply after the move: the launch normalisation leaves
    /// them alone, Search filters and orders by them, and Dictionary Order
    /// lists the moved import where it stood, with the pair counts.
    @MainActor
    private func assertPreferencesStillApply(_ fixture: Fixture, file: StaticString = #filePath,
                                             line: UInt = #line) async throws {
        let bundled = try await db.fetchMetadata().map(\.source)
        let store = InMemoryKeyValueStore()
        let settings = SettingsService(store: store)
        settings.selectedUILanguageCode = "en"
        let order = DictionaryGrouping.groupedOrder([Self.glossary] + bundled)
        let enabled = Set(bundled + [Self.glossary]).subtracting(["wordnet-arb-eng"])
        settings.dictionaryOrder = order
        settings.enabledSources = enabled
        let writes = store.writeLog.count

        settings.normalizeDictionaryPreferences(knownSources: bundled)
        XCTAssertEqual(store.writeLog.count, writes, "the launch normalisation changes nothing", file: file, line: line)

        let house = Self.keys(try await db.search(query: "house", enabledSources: settings.enabledSources))
        XCTAssertTrue(house.contains(EntryKey(source: Self.glossary, word: "house")), "\(house)", file: file, line: line)
        XCTAssertTrue(house.contains(EntryKey(source: "wordnet", word: "house")), file: file, line: line)
        let arabic = try await db.search(query: "كتاب", enabledSources: settings.enabledSources)
        XCTAssertFalse(arabic.contains { $0.source == "wordnet-arb-eng" }, "a disabled pair stays off",
                       file: file, line: line)
        let preferred = try await db.searchPreferred(
            query: "house", groups: DictionaryGrouping.sourceGroups(order: try XCTUnwrap(settings.dictionaryOrder)),
            enabledSources: try XCTUnwrap(settings.enabledSources))
        XCTAssertEqual(Self.keys(Array(preferred.prefix(2))), [EntryKey(source: Self.glossary, word: "house"),
                                                               EntryKey(source: Self.glossary, word: "housesitter")],
                       "the import's bucket leads, as in the stored order", file: file, line: line)

        let localization = LocalizationManager(settingsService: settings, bundle: .main)
        let vm = SettingsViewModel(settingsService: settings, localization: localization)
        await vm.loadDictionaries()
        XCTAssertEqual(vm.dictionaries.first?.id, "custom:\(Self.glossary)", file: file, line: line)
        XCTAssertEqual(vm.dictionaries.first?.count, Self.glossaryWords.count, file: file, line: line)
        XCTAssertEqual(vm.dictionaries.first { $0.id == "arb-eng" }?.isEnabled, false, file: file, line: line)
        let metadata = try await db.fetchMetadata()
        let bundledSpanish = metadata.filter { ["freedict-eng-spa", "wordnet-spa-eng"].contains($0.source) }
            .reduce(0) { $0 + $1.wordCount }
        XCTAssertEqual(vm.dictionaries.first { $0.id == "eng-spa" }?.count, bundledSpanish + Self.namedWords.count,
                       "the pair counts the import named like its source", file: file, line: line)
        XCTAssertFalse(vm.dictionaries.contains { $0.id == "custom:\(fixture.named)" },
                       "the import named like a bundled source joins its pair, with no row of its own",
                       file: file, line: line)
        XCTAssertEqual(settings.dictionaryOrder, order, file: file, line: line)
        XCTAssertEqual(settings.enabledSources, enabled, file: file, line: line)
    }

    // MARK: Upgrades

    /// Upgrade from 1.4.0 keeps bookmarks (as My words), History, both
    /// imports and the preferences.
    @MainActor
    func testMigrates140Fixture() async throws {
        try await assertMigrates(Self.v140)
        try await assertPreferencesStillApply(Self.v140)
    }

    /// Upgrade from 1.3.0, before Greek: the same.
    @MainActor
    func testMigrates130Fixture() async throws {
        try await assertMigrates(Self.v130)
        try await assertPreferencesStillApply(Self.v130)
    }

    /// A 1.1 or 1.2 database has no `history.source` (and no
    /// `word_normalized`): History moves with `source = ''`, and such a row
    /// shows "not found" (#138). Bookmarks and imports move as from 1.4.0.
    func testMigratesDatabaseWithoutHistorySource() async throws {
        try install(Self.v120.name)
        let columns = try await inspectCopy(of: legacyURL).read { conn in
            (history: try Row.fetchAll(conn, sql: "PRAGMA table_info(history)").map { $0["name"] as String },
             entries: try Row.fetchAll(conn, sql: "PRAGMA table_info(entries)").map { $0["name"] as String })
        }
        XCTAssertFalse(columns.history.contains("source"), "precondition: \(columns.history)")
        XCTAssertFalse(columns.entries.contains("word_normalized"), "precondition: \(columns.entries)")

        try await assertMigrates(Self.v120)
        let history = try await db.fetchHistory()
        XCTAssertEqual(history.count, Self.v120.historyCount)
        XCTAssertTrue(history.allSatisfy { $0.source.isEmpty }, "\(history)")
        let dog = try XCTUnwrap(history.first { $0.word == "dog" })
        let opened = await HistoryDestination.entry(for: dog)
        XCTAssertNil(opened, "a row without a source shows \"not found\"")
    }

    // MARK: Crash safety

    /// Killed before the commit (the seam throws inside the transaction):
    /// the user database is unchanged, with no marker and no stray index
    /// rows, the 1.x file is intact, and the waiting calls go on. The next
    /// launch moves everything once, with exact counts.
    func testKilledBeforeCommitRetriesWithoutDuplicates() async throws {
        try install(Self.v140.name)
        let legacyCounts = try await inspectCopy(of: legacyURL).read { conn in
            try Int.fetchAll(conn, sql: """
                SELECT COUNT(*) FROM entries UNION ALL SELECT COUNT(*) FROM history
                UNION ALL SELECT COUNT(*) FROM bookmarks
                """)
        }

        LegacyMigration.failBeforeCommit = true
        try await move()
        let rolledBack = try userState()
        XCTAssertEqual(rolledBack.history + rolledBack.myWords + rolledBack.imported + rolledBack.importedSources, [])
        XCTAssertNil(rolledBack.marker)
        await assertImportIndexIntact()
        // SQLite may leave the 1.x `-wal` and `-shm` after the DETACH; the delete takes them too.
        XCTAssertTrue(exists(legacyURL.path), "the 1.x file stays")
        let stillThere = try await inspectCopy(of: legacyURL).read { conn in
            try Int.fetchAll(conn, sql: """
                SELECT COUNT(*) FROM entries UNION ALL SELECT COUNT(*) FROM history
                UNION ALL SELECT COUNT(*) FROM bookmarks
                """)
        }
        XCTAssertEqual(stillThere, legacyCounts, "the 1.x data is intact")
        let waiting = try await db.fetchHistory()
        XCTAssertEqual(waiting, [], "a call waiting for the failed move goes on with the user database")

        LegacyMigration.failBeforeCommit = false
        try await move()
        let state = try userState()
        XCTAssertEqual(state.history.count, Self.v140.historyCount)
        XCTAssertEqual(state.myWords.count, Self.v140.bookmarks.count)
        XCTAssertEqual(state.imported, Self.expectedImports(Self.v140))
        XCTAssertEqual(state.importedSources.count, 2)
        XCTAssertNotNil(state.marker)
        await assertImportIndexIntact()
        let zorblat = try await db.search(query: "zorblat")
        XCTAssertEqual(zorblat.count, 1, "indexed once")
        XCTAssertEqual(legacyFiles(), [])
    }

    /// Killed after the commit (the seam stops before the delete): the data
    /// is in and the marker set, and the 1.x file is still there. The next
    /// launch only deletes it: what the user changed in between stays
    /// changed, nothing is copied twice, and Search does not re-run.
    func testKilledAfterCommitOnlyDeletes() async throws {
        try install(Self.v140.name)
        let committed = expectation(forNotification: LegacyMigration.didCommit, object: nil)
        LegacyMigration.failBeforeDelete = true
        try await move()
        await fulfillment(of: [committed], timeout: 5)
        let first = try userState()
        let marker = try XCTUnwrap(first.marker)
        XCTAssertEqual(first.imported.count, 10)
        XCTAssertEqual(first.myWords.count, Self.v140.bookmarks.count)
        XCTAssertTrue(exists(legacyURL.path), "killed before the delete")

        try await db.removeFromMyWords(EntryKey(source: "wordnet", word: "dog"))
        try await db.clearEntries(fromSource: Self.glossary)
        try await db.addToHistory(word: "dog", source: "freedict-eng-spa")

        LegacyMigration.failBeforeDelete = false
        let noRerun = expectation(forNotification: LegacyMigration.didCommit, object: nil)
        noRerun.isInverted = true
        try await move()
        await fulfillment(of: [noRerun], timeout: 0.5)
        XCTAssertEqual(legacyFiles(), [], "the next launch deletes the file")
        let state = try userState()
        XCTAssertEqual(state.marker, marker, "the marker is not rewritten")
        XCTAssertEqual(state.myWords.count, Self.v140.bookmarks.count - 1, "a removed My word does not come back")
        XCTAssertEqual(state.imported, Self.namedWords.map { "\(Self.v140.named)/\($0)" },
                       "a removed import does not come back")
        XCTAssertEqual(state.history.count, Self.v140.historyCount)
        XCTAssertTrue(state.history.contains { $0.hasPrefix("dog|freedict-eng-spa|") },
                      "a later History view is kept: \(state.history)")
    }

    // MARK: Files

    /// A 1.x database the app was killed with, a History row still only in
    /// its WAL: the move replays the WAL (the file is attached read-write),
    /// so the row moves too. Then `dict.sqlite`, `-wal` and `-shm` are gone
    /// and only the user database is left in the folder.
    func testLegacyFilesDeletedAfterCommit() async throws {
        let original = tempDir.appendingPathComponent("1x/dict.sqlite")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixtureURL(Self.v140.name), to: original)
        var writer: DatabaseQueue? = try DatabaseQueue(path: original.path)
        try await writer?.write { conn in
            try conn.execute(sql: """
                INSERT INTO history(word, source, looked_at) VALUES ('walonly', 'wordnet', '2026-06-03 08:00:00')
                """)
        }
        let walSize = (try? FileManager.default.attributesOfItem(atPath: original.path + "-wal")[.size] as? Int) ?? 0
        XCTAssertGreaterThan(walSize, 0, "precondition: the row is only in the WAL")
        // Copied while the writer is open, as a killed app leaves them.
        try FileManager.default.copyItem(atPath: original.path, toPath: legacyURL.path)
        try FileManager.default.copyItem(atPath: original.path + "-wal", toPath: legacyURL.path + "-wal")
        writer = nil
        XCTAssertEqual(legacyFiles(), [legacyURL.path, legacyURL.path + "-wal"])

        try await move()
        XCTAssertEqual(legacyFiles(), [], "dict.sqlite, -wal and -shm are deleted")
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: appSupport.path))
        XCTAssertTrue(names.isSubset(of: Self.userFiles) && names.contains("user.sqlite"), "\(names)")
        let state = try userState()
        XCTAssertTrue(state.history.contains("walonly|wordnet|2026-06-03 08:00:00"), "the WAL was replayed")
        XCTAssertEqual(state.history.count, Self.v140.historyCount + 1)
    }

    /// An unreadable 1.x file is logged and kept as it is, and every launch
    /// tries again; the calls waiting for the move go on. Not a database at
    /// all: kept byte for byte, twice. A database the app cannot open
    /// (no permission): kept, then moved once it opens.
    func testUnreadableLegacyDatabaseIsKeptAndRetried() async throws {
        let garbage = Data(repeating: 0x5A, count: 8192)
        try garbage.write(to: legacyURL)
        for attempt in 1...2 {
            try await move()
            XCTAssertEqual(try Data(contentsOf: legacyURL), garbage, "attempt \(attempt): kept as it was")
            XCTAssertEqual(legacyFiles(), [legacyURL.path], "attempt \(attempt): no sidecars")
            XCTAssertNil(try userState().marker)
            let history = try await db.fetchHistory()
            XCTAssertEqual(history, [], "attempt \(attempt): waiting calls go on")
        }

        try install(Self.v140.name)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: legacyURL.path)
        try await move()
        XCTAssertTrue(exists(legacyURL.path), "an unopenable file is kept")
        XCTAssertNil(try userState().marker)
        // History used in between: a new word, a word the 1.x History has
        // older, and one it has newer.
        try await db.addToHistory(word: "cat", source: "wordnet")
        try await db.addToHistory(word: "house", source: "wordnet")
        try await db.writeForTesting { conn in
            try conn.execute(sql: """
                INSERT INTO history(word, source, looked_at) VALUES ('dog', 'wordnet-spa-eng', '2020-01-01 00:00:00')
                """)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyURL.path)
        try await move()
        XCTAssertEqual(legacyFiles(), [], "moved and deleted once it opens")
        let state = try userState()
        XCTAssertNotNil(state.marker)
        XCTAssertEqual(state.imported, Self.expectedImports(Self.v140))
        XCTAssertEqual(state.history.count, Self.v140.historyCount + 1, "one row per word")
        XCTAssertTrue(state.history.contains { $0.hasPrefix("cat|wordnet|") })
        XCTAssertTrue(state.history.contains { $0.hasPrefix("house|wordnet|") }, "the newer row wins: \(state.history)")
        XCTAssertTrue(state.history.contains("dog|wordnet|2026-06-02 08:00:00"), "the newer 1.x row wins")
    }

    /// Search answers from the dictionary file while the move runs (held
    /// inside its transaction by the delay seam), while History waits for the
    /// move rather than show a half-moved state. When the move commits, the
    /// current query re-runs and the moved import appears.
    @MainActor
    func testSearchDuringMigration() async throws {
        try install(Self.v140.name)
        let (move, gate) = try await startHeldMove()

        let historyDuringMove = Task { try await DatabaseService.shared.fetchHistory() }
        let vm = SearchViewModel(settings: SettingsService(store: InMemoryKeyValueStore()))
        vm.query = "house"
        let started = Date()
        vm.onQueryChanged()
        let during = try await results(of: vm) { !$0.isEmpty }
        print("LegacyMigrationTests: Search answered in \(Int(Date().timeIntervalSince(started) * 1000)) ms during the move")
        XCTAssertTrue(during.contains { EntryKey($0) == EntryKey(source: "wordnet", word: "house") },
                      "bundled results while the move runs")
        XCTAssertFalse(during.contains { $0.source == Self.glossary }, "the import is not in yet")

        gate.release.signal()
        await move.value
        let after = try await results(of: vm) { $0.contains { $0.source == Self.glossary } }
        XCTAssertTrue(Self.keys(after).contains(EntryKey(source: Self.glossary, word: "house")),
                      "the query re-ran when the move committed")
        let history = try await historyDuringMove.value
        XCTAssertEqual(history.count, Self.v140.historyCount, "History waited for the move")
    }

    /// Polls `vm.results` until `done` holds (5 s at most).
    @MainActor
    private func results(of vm: SearchViewModel, until done: ([DictionaryEntry]) -> Bool,
                         file: StaticString = #filePath, line: UInt = #line) async throws -> [DictionaryEntry] {
        let deadline = Date().addingTimeInterval(5)
        while !done(vm.results) || vm.isSearching {
            guard Date() < deadline else {
                XCTFail("Search results never matched: \(Self.keys(vm.results))", file: file, line: line)
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return vm.results
    }

    /// Installed size ≈ app bundle + user data (#129, #139): after the move
    /// the app folder holds only `user.sqlite` with its `-wal` and `-shm`,
    /// under 5 MB. The host app's own folder holds no more than that either
    /// (a 1.x file found there at launch has been moved).
    func testApplicationSupportHoldsOnlyTheUserDatabase() async throws {
        try install(Self.v140.name)
        try await move()
        let names = try FileManager.default.contentsOfDirectory(atPath: appSupport.path)
        XCTAssertTrue(Set(names).isSubset(of: Self.userFiles) && names.contains("user.sqlite"), "\(names)")
        let bytes = try names.reduce(0) { total, name in
            total + ((try FileManager.default.attributesOfItem(
                atPath: appSupport.appendingPathComponent(name).path)[.size] as? Int) ?? 0)
        }
        XCTAssertLessThan(bytes, 5_000_000)

        let host = DatabaseService.userDatabaseURL().deletingLastPathComponent()
        let deadline = Date().addingTimeInterval(10)
        while exists(host.appendingPathComponent("dict.sqlite").path), Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let hostNames = Set(try FileManager.default.contentsOfDirectory(atPath: host.path))
        XCTAssertTrue(hostNames.isSubset(of: Self.userFiles), "host app folder: \(hostNames.sorted())")
    }

    // MARK: Edge cases

    /// An import named like a bundled source whose words the bundle has, in
    /// another case (1.x kept such rows where the import landed before the
    /// bundled rows, as during the 1.4.0 background unpack): nothing moves
    /// and the source registers no import, so Dictionary Order counts only
    /// the bundled rows. A bookmark and a History row on such a word open
    /// today's bundled entry.
    func testImportWithOnlyBundledWordsRegistersNothing() async throws {
        try install(Self.v140.name) { conn in
            for word in ["CASA", "Perro", "MESA"] {
                try conn.execute(sql: """
                    INSERT INTO entries(word, word_normalized, definition, source, created_at)
                    VALUES (?, ?, '1.x import', 'wordnet-spa-eng', '2026-05-25 10:00:00')
                    """, arguments: [word, word])
            }
            try conn.execute(sql: """
                INSERT INTO bookmarks(entry_id, created_at)
                SELECT id, '2026-06-05 10:00:00' FROM entries WHERE word = 'CASA'
                """)
            try conn.execute(sql: """
                INSERT INTO history(word, source, looked_at) VALUES ('Perro', 'wordnet-spa-eng', '2026-06-05 11:00:00')
                """)
        }
        try await move()

        let state = try userState()
        XCTAssertEqual(state.imported, Self.expectedImports(Self.v140), "no row of the bundled words moved")
        XCTAssertFalse(state.importedSources.contains { $0.hasPrefix("wordnet-spa-eng|") }, "\(state.importedSources)")
        let stats = try await db.fetchSourceStats()
        let metadata = try await db.fetchMetadata()
        let bundledCount = try XCTUnwrap(metadata.first { $0.source == "wordnet-spa-eng" }?.wordCount)
        XCTAssertEqual(stats.first { $0.source == "wordnet-spa-eng" }?.count, bundledCount,
                       "only the bundled rows count")

        let myWords = try await db.fetchMyWords()
        let casa = try XCTUnwrap(myWords.first, "the bookmark resolves, newest first")
        XCTAssertEqual(EntryKey(casa), EntryKey(source: "wordnet-spa-eng", word: "casa"))
        XCTAssertNil(casa.createdAt, "the bookmark opens the bundled row")
        XCTAssertTrue(state.myWords.contains("wordnet-spa-eng/CASA|2026-06-05 10:00:00"), "\(state.myWords)")
        let history = try await db.fetchHistory()
        let perro = try XCTUnwrap(history.first { $0.word == "Perro" })
        let opened = await HistoryDestination.entry(for: perro)
        XCTAssertEqual(opened.map { EntryKey($0) }, EntryKey(source: "wordnet-spa-eng", word: "perro"))
        XCTAssertNil(opened?.createdAt, "the History row opens the bundled row")
    }

    /// A 1.x row of a bundled source that today's data lacks (a dictionary
    /// update dropped the headword; none today, measured) moves like a row
    /// of an import named like that source: the bookmark on it stays a My
    /// words key that resolves, its History row opens it, Search finds it
    /// and Dictionary Order counts it with its source.
    func testBookmarkOfARowTodaysDataLacksKeepsItsEntry() async throws {
        let dropped = EntryKey(source: "wordnet", word: "qadroppedheadword")
        let definition = "A headword a later dictionary update dropped."
        try install(Self.v140.name) { conn in
            try conn.execute(sql: """
                INSERT INTO entries(word, word_normalized, definition, phonetic, pos, source, created_at)
                VALUES (?, ?, ?, '', 'noun', ?, '2026-04-01 00:00:00')
                """, arguments: [dropped.word, dropped.word, definition, dropped.source])
            try conn.execute(sql: """
                INSERT INTO bookmarks(entry_id, created_at)
                SELECT id, '2026-06-05 10:00:00' FROM entries WHERE word = ?
                """, arguments: [dropped.word])
            try conn.execute(sql: """
                INSERT INTO history(word, source, looked_at) VALUES (?, ?, '2026-06-05 11:00:00')
                """, arguments: [dropped.word, dropped.source])
        }
        let metadata = try await db.fetchMetadata()
        let wordCount = try XCTUnwrap(metadata.first { $0.source == dropped.source }?.wordCount)
        try await move()

        let state = try userState()
        XCTAssertEqual(state.imported, Self.expectedImports(Self.v140) + ["wordnet/\(dropped.word)"])
        XCTAssertTrue(state.importedSources.contains("wordnet|2026-04-01 00:00:00"), "\(state.importedSources)")
        let myWords = try await db.fetchMyWords()
        XCTAssertEqual(myWords.first.map { EntryKey($0) }, dropped, "the bookmark resolves, newest first")
        XCTAssertEqual(myWords.count, Self.v140.bookmarks.count + 1)
        let history = try await db.fetchHistory()
        let row = try XCTUnwrap(history.first { $0.word == dropped.word })
        let opened = await HistoryDestination.entry(for: row)
        XCTAssertEqual(opened.map { EntryKey($0) }, dropped)
        XCTAssertEqual(opened?.definition, definition)
        let found = try await db.search(query: dropped.word)
        XCTAssertEqual(Self.keys(found), [dropped])
        let stats = try await db.fetchSourceStats()
        XCTAssertEqual(stats.first { $0.source == dropped.source }?.count, wordCount + 1)
    }

    /// Rows a 1.x database can hold that the fixtures do not: an import row
    /// with NULL phonetic, part of speech and date, a bookmark whose entry
    /// is gone, a bookmark and a History row without a date. None of them
    /// fails the move: NULL text becomes '', a missing date becomes the
    /// move's time (a History date stays NULL and sorts last), and the
    /// orphan bookmark is skipped.
    func testLegacyRowsWithNullsAndAnOrphanBookmarkMove() async throws {
        try install(Self.v140.name) { conn in
            try conn.execute(sql: """
                INSERT INTO entries(word, word_normalized, definition, phonetic, pos, source, created_at)
                VALUES ('nullish', 'nullish', 'A row with NULL columns.', NULL, NULL, 'null_import', NULL)
                """)
            try conn.execute(sql: "INSERT INTO bookmarks(entry_id, created_at) VALUES (999999, '2026-06-05 10:00:00')")
            try conn.execute(sql: """
                INSERT INTO bookmarks(entry_id, created_at) SELECT id, NULL FROM entries WHERE word = 'nullish'
                """)
            try conn.execute(sql: "INSERT INTO history(word, source, looked_at) VALUES ('undated', 'wordnet', NULL)")
        }
        let before = Self.sqliteNow()
        try await move()
        let after = Self.sqliteNow()

        let state = try userState()
        XCTAssertNotNil(state.marker)
        XCTAssertEqual(legacyFiles(), [])
        XCTAssertEqual(state.imported, Self.expectedImports(Self.v140) + ["null_import/nullish"])
        let importedAt = try XCTUnwrap(state.importedSources.first { $0.hasPrefix("null_import|") })
            .replacingOccurrences(of: "null_import|", with: "")
        XCTAssertTrue((before...after).contains(importedAt), "dated by the move: \(importedAt)")
        let entry = try await db.entry(for: EntryKey(source: "null_import", word: "nullish"))
        XCTAssertEqual(entry?.phonetic, "")
        XCTAssertEqual(entry?.pos, "")

        XCTAssertEqual(state.myWords.count, Self.v140.bookmarks.count + 1, "the orphan bookmark is skipped")
        let addedAt = try XCTUnwrap(state.myWords.first { $0.hasPrefix("null_import/nullish|") })
            .replacingOccurrences(of: "null_import/nullish|", with: "")
        XCTAssertTrue((before...after).contains(addedAt), "dated by the move: \(addedAt)")

        XCTAssertTrue(state.history.contains("undated|wordnet|NULL"), "\(state.history)")
        let history = try await db.fetchHistory()
        XCTAssertEqual(history.count, Self.v140.historyCount + 1)
        XCTAssertEqual(history.last?.word, "undated")
        XCTAssertNil(history.last?.lookedAt)
    }

    /// History word conflicts on a retried move (the user database has
    /// History from launches whose move failed): the newer `looked_at` wins
    /// and brings its source; on a tie the row already there stays.
    func testHistoryConflictsKeepTheNewerRow() async throws {
        try install(Self.v140.name)
        // The fixture has dog|wordnet at 08:00, house|freedict-eng-spa at
        // 09:00 and дом|openrussian at 10:00 on 2026-06-02.
        try await db.writeForTesting { conn in
            try conn.execute(sql: """
                INSERT INTO history(word, source, looked_at) VALUES
                    ('dog', 'freedict-eng-spa', '2026-06-02 08:00:00'),
                    ('house', 'wordnet', '2026-06-02 09:00:01'),
                    ('дом', '', '2026-06-02 09:59:59')
                """)
        }
        try await move()

        let history = try userState().history
        XCTAssertEqual(history.count, Self.v140.historyCount, "one row per word: \(history)")
        XCTAssertTrue(history.contains("dog|freedict-eng-spa|2026-06-02 08:00:00"), "a tie keeps the row: \(history)")
        XCTAssertTrue(history.contains("house|wordnet|2026-06-02 09:00:01"), "a newer row stays: \(history)")
        XCTAssertTrue(history.contains("дом|openrussian|2026-06-02 10:00:00"),
                      "the newer 1.x row wins with its source: \(history)")
    }

    /// User-data writes that come while the move runs (History, My words, an
    /// import) wait for it and land after it: none is lost or undone by the
    /// move, the user's later action wins, and nothing is stored twice.
    func testWritesDuringTheMoveLandAfterIt() async throws {
        try install(Self.v140.name)
        let json = tempDir.appendingPathComponent("my_glossary.json")
        try Data("""
            [{"word": "zorblat", "definition": "a second zorblat"},
             {"word": "midmove", "definition": "imported while the move ran"}]
            """.utf8).write(to: json)
        let (move, gate) = try await startHeldMove()

        let writes = Task {
            async let history: Void = DatabaseService.shared.addToHistory(word: "house", source: "wordnet")
            async let removed: Void = DatabaseService.shared.removeFromMyWords(
                EntryKey(source: Self.glossary, word: "zorblat"))
            async let added: Void = DatabaseService.shared.addToMyWords(EntryKey(source: "wordnet", word: "dog"))
            async let imported = DatabaseService.shared.importJSON(at: json, source: Self.glossary)
            _ = try await (history, removed, added, imported)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let held = try userState()
        XCTAssertEqual(held.history + held.myWords + held.imported, [], "nothing lands before the move commits")

        gate.release.signal()
        await move.value
        try await writes.value

        let state = try userState()
        XCTAssertNotNil(state.marker)
        XCTAssertEqual(state.history.count, Self.v140.historyCount)
        XCTAssertTrue(state.history.contains { $0.hasPrefix("house|wordnet|") },
                      "the later view wins: \(state.history)")
        XCTAssertEqual(state.myWords.count, Self.v140.bookmarks.count - 1, "\(state.myWords)")
        XCTAssertFalse(state.myWords.contains { $0.hasPrefix("\(Self.glossary)/zorblat|") }, "the removal applies")
        XCTAssertTrue(state.myWords.contains("wordnet/dog|2026-06-01 09:00:00"), "kept once, with its bookmark date")
        XCTAssertEqual(state.imported, Self.expectedImports(Self.v140) + ["\(Self.glossary)/midmove"],
                       "the moved row wins over the import's copy")
        XCTAssertEqual(state.importedSources.first { $0.hasPrefix("\(Self.glossary)|") },
                       "\(Self.glossary)|2026-05-10 12:00:00", "the import keeps its 1.x date")
        let zorblat = try await db.search(query: "zorblat")
        XCTAssertEqual(zorblat.map(\.definition), ["A made-up word of the legacy fixture."])
    }

    /// No 1.x file (a fresh install, or the move is done): no move starts,
    /// nothing is posted, and user data works at once.
    func testNoLegacyDatabaseStartsNoMove() async throws {
        let posted = expectation(forNotification: LegacyMigration.didCommit, object: nil)
        posted.isInverted = true
        let task = await db.startLegacyMigration(legacyURL: legacyURL)
        XCTAssertNil(task)
        try await db.addToHistory(word: "dog", source: "wordnet")
        let history = try await db.fetchHistory()
        XCTAssertEqual(history.map(\.word), ["dog"])
        await fulfillment(of: [posted], timeout: 0.5)
        XCTAssertNil(try userState().marker)
        XCTAssertEqual(legacyFiles(), [])
    }

    /// A 1.x database with no user data (no import, History or bookmark;
    /// here not even the bundled copy) moves nothing, sets the marker,
    /// posts the commit and is deleted.
    func testLegacyDatabaseWithoutUserDataIsDeleted() async throws {
        try install(Self.v140.name) { conn in
            try conn.execute(sql: "DELETE FROM bookmarks; DELETE FROM history; DELETE FROM entries")
        }
        let committed = expectation(forNotification: LegacyMigration.didCommit, object: nil)
        try await move()
        await fulfillment(of: [committed], timeout: 5)

        let state = try userState()
        XCTAssertEqual(state.history + state.myWords + state.imported + state.importedSources, [])
        XCTAssertNotNil(state.marker)
        XCTAssertEqual(legacyFiles(), [])
    }

    /// A zero-byte `dict.sqlite` (1.x killed before it wrote its schema) has
    /// no 1.x tables: it is kept like an unreadable file, nothing is created
    /// next to it, and user data works.
    func testZeroByteLegacyFileIsKept() async throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: legacyURL.path, contents: Data()))
        try await move()
        XCTAssertEqual(legacyFiles(), [legacyURL.path], "kept, with no sidecar")
        XCTAssertEqual(try Data(contentsOf: legacyURL), Data())
        XCTAssertNil(try userState().marker)
        try await db.addToMyWords(EntryKey(source: "wordnet", word: "dog"))
        let myWords = try await db.fetchMyWords()
        XCTAssertEqual(Self.keys(myWords), [EntryKey(source: "wordnet", word: "dog")])
    }

    /// A real 1.x database, local only: never committed. Run with
    /// `TEST_RUNNER_LIBREDICT_LEGACY_DB=/path/to/dict.sqlite xcodebuild test …`
    /// (xcodebuild hands `TEST_RUNNER_` variables to the tests without the
    /// prefix). The file, and its `-wal` if there is one, is copied, never
    /// changed. Skipped when the variable is absent.
    func testMigratesLocalLegacyDatabase() async throws {
        guard let path = ProcessInfo.processInfo.environment["LIBREDICT_LEGACY_DB"], !path.isEmpty else {
            throw XCTSkip("LIBREDICT_LEGACY_DB is not set")
        }
        try FileManager.default.copyItem(atPath: path, toPath: legacyURL.path)
        if exists(path + "-wal") {
            try FileManager.default.copyItem(atPath: path + "-wal", toPath: legacyURL.path + "-wal")
        }
        let bundledPath = try TestDictionary.bundledURL().path
        let expected = try await inspectCopy(of: legacyURL).writeWithoutTransaction { conn in
            try conn.execute(sql: "ATTACH DATABASE ? AS dict", arguments: ["file:\(bundledPath)?mode=ro&immutable=1"])
            return (history: try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM history") ?? 0,
                    bookmarks: Set(try Row.fetchAll(conn, sql: """
                        SELECT e.source, e.word FROM bookmarks b JOIN entries e ON e.id = b.entry_id
                        """).map { EntryKey(source: $0["source"], word: $0["word"]) }),
                    rows: try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM entries") ?? 0,
                    imported: try Int.fetchOne(conn, sql: """
                        SELECT COUNT(*) FROM entries l WHERE NOT EXISTS (
                            SELECT 1 FROM dict.entries d WHERE d.word = l.word COLLATE NOCASE AND d.source = l.source)
                        """) ?? 0)
        }

        let seconds = try await move()
        print("LegacyMigrationTests: \(path) (\(expected.rows) rows) moved in \(Int(seconds * 1000)) ms")
        XCTAssertEqual(legacyFiles(), [], "moved and deleted")
        let state = try userState()
        XCTAssertEqual(state.history.count, expected.history)
        XCTAssertEqual(state.imported.count, expected.imported)
        let myWords = try await db.fetchMyWords()
        XCTAssertEqual(Set(Self.keys(myWords)), expected.bookmarks, "every bookmark is a My words key that resolves")
    }
}
