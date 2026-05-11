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
