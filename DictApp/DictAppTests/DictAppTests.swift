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
        try pool.write { dbConn in
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
