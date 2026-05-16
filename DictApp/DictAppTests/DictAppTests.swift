// DictAppTests.swift
// Unit tests and performance tests for the dictionary app.

import XCTest
@testable import DictApp
import GRDB

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

