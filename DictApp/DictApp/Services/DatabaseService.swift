// DatabaseService.swift
// Manages SQLite connections, schema migration, FTS5 search, and data seeding.

import Foundation
import GRDB

actor DatabaseService {
    static let shared = DatabaseService()

    private var dbPool: DatabasePool?

    private init() {}

    // MARK: - Setup

    /// Opens (or creates) the database at the default app path and applies the schema.
    func setup() async throws {
        let url = Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        self.dbPool = pool
        try await applySchema(pool)
    }

    /// Opens a database from an arbitrary path (useful for testing / imports).
    func setup(path: String) async throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let pool = try DatabasePool(path: path, configuration: config)
        self.dbPool = pool
        try await applySchema(pool)
    }

    private func applySchema(_ pool: DatabasePool) async throws {
        let sql: String
        if let schemaURL = Bundle.main.url(forResource: "Schema", withExtension: "sql"),
           let contents = try? String(contentsOf: schemaURL, encoding: .utf8) {
            sql = contents
        } else {
            sql = Self.inlineSchema
        }
        try await pool.write { db in
            try db.execute(sql: sql)
            // Migrations: add columns that may be missing from older schemas.
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(dict_metadata)")
            let columnNames = Set(columns.map { $0["name"] as String })
            if !columnNames.contains("description") {
                try db.execute(sql: "ALTER TABLE dict_metadata ADD COLUMN description TEXT NOT NULL DEFAULT ''")
            }
        }
    }

    // MARK: - Search

    /// Prefix search using FTS5 with relevance ranking:
    ///   Priority 1: exact match (word == query)
    ///   Priority 2: starts-with (word LIKE 'query%')
    ///   Priority 3: FTS relevance (rank)
    /// The unicode61 tokenizer handles both Latin and Cyrillic input.
    func search(query: String, limit: Int = 50, enabledSources: Set<String>? = nil) async throws -> [DictionaryEntry] {
        // If an explicit (non-nil) empty set is passed, no sources are enabled — return immediately.
        if let sources = enabledSources, sources.isEmpty { return [] }

        guard let pool = dbPool else { throw DBError.notConnected }
        let sanitized = sanitizeFTS(query)
        guard !sanitized.isEmpty else { return [] }
        return try await pool.read { db in
            var sql = """
                SELECT e.*
                FROM entries_fts fts
                JOIN entries e ON e.id = fts.rowid
                WHERE entries_fts MATCH ?
                """
            var arguments: [DatabaseValueConvertible] = [sanitized + "*"]

            if let sources = enabledSources, !sources.isEmpty {
                let placeholders = sources.map { _ in "?" }.joined(separator: ", ")
                sql += " AND e.source IN (\(placeholders))"
                arguments += sources.map { $0 as DatabaseValueConvertible }
            }

            sql += """

                ORDER BY
                    (e.word = ? COLLATE NOCASE) DESC,
                    (e.word LIKE ? COLLATE NOCASE) DESC,
                    rank
                LIMIT ?
                """
            arguments += [sanitized, sanitized + "%", limit]

            var statArgs = StatementArguments()
            for arg in arguments { statArgs += [arg] }
            return try DictionaryEntry.fetchAll(db, sql: sql, arguments: statArgs)
        }
    }

    /// Exact lookup (case-insensitive).
    func lookup(word: String) async throws -> DictionaryEntry? {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictionaryEntry
                .filter(DictionaryEntry.Columns.word.collating(.nocase) == word)
                .fetchOne(db)
        }
    }

    // MARK: - History

    func addToHistory(word: String) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO history(word, looked_at) VALUES (?, datetime('now'))
                    ON CONFLICT(word) DO UPDATE SET looked_at = datetime('now')
                    """,
                arguments: [word]
            )
        }
    }

    func fetchHistory(limit: Int = 100) async throws -> [HistoryItem] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try HistoryItem
                .order(Column("looked_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func clearHistory() async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM history")
        }
    }

    func clearAllBookmarks() async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM bookmarks")
        }
    }

    /// Deletes every entry whose `source` equals the given value. Used by
    /// UI tests to scrub previously-imported fixture data before re-running.
    func clearEntries(fromSource source: String) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM entries WHERE source = ?", arguments: [source])
        }
    }

    // MARK: - Bookmarks

    func addBookmark(entryId: Int64) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO bookmarks(entry_id) VALUES (?)",
                arguments: [entryId]
            )
        }
    }

    func removeBookmark(entryId: Int64) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(
                sql: "DELETE FROM bookmarks WHERE entry_id = ?",
                arguments: [entryId]
            )
        }
    }

    func isBookmarked(entryId: Int64) async throws -> Bool {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try Bookmark.filter(Column("entry_id") == entryId).fetchOne(db) != nil
        }
    }

    func fetchBookmarkedEntries() async throws -> [BookmarkedEntry] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            let sql = """
                SELECT e.*, b.id AS b_id, b.entry_id, b.created_at AS b_created_at
                FROM bookmarks b
                JOIN entries e ON e.id = b.entry_id
                ORDER BY b.created_at DESC
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { row in
                let entry = DictionaryEntry(
                    id: row["id"],
                    word: row["word"],
                    definition: row["definition"],
                    phonetic: row["phonetic"] ?? "",
                    pos: row["pos"] ?? "",
                    source: row["source"] ?? "default",
                    createdAt: row["created_at"]
                )
                let bookmark = Bookmark(
                    id: row["b_id"],
                    entryId: row["entry_id"],
                    createdAt: row["b_created_at"]
                )
                return BookmarkedEntry(entry: entry, bookmark: bookmark)
            }
        }
    }

    // MARK: - Metadata & Statistics

    /// Fetch metadata for all loaded dictionaries.
    func fetchMetadata() async throws -> [DictMetadata] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictMetadata.fetchAll(db)
        }
    }

    /// Fetch metadata for a single dictionary source.
    func fetchMetadata(source: String) async throws -> DictMetadata? {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictMetadata.filter(Column("source") == source).fetchOne(db)
        }
    }

    /// Per-source entry counts, with display names from metadata where available.
    func fetchSourceStats() async throws -> [SourceStat] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            let sql = """
                SELECT e.source,
                       COALESCE(m.display_name, e.source) AS display_name,
                       COUNT(*) AS cnt
                FROM entries e
                LEFT JOIN dict_metadata m ON m.source = e.source
                GROUP BY e.source
                ORDER BY cnt DESC
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { row in
                SourceStat(
                    source: row["source"],
                    displayName: row["display_name"],
                    count: row["cnt"]
                )
            }
        }
    }

    // MARK: - Import

    /// Bulk-insert entries from a JSON array. Expects `[{word, definition, phonetic?, pos?}]`.
    func importJSON(at url: URL, source: String) async throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let raw = try decoder.decode([[String: String]].self, from: data)
        guard let pool = dbPool else { throw DBError.notConnected }
        let count = try await pool.write { db -> Int in
            var n = 0
            for item in raw {
                guard let word = item["word"], let definition = item["definition"] else { continue }
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        word,
                        definition,
                        item["phonetic"] ?? "",
                        item["pos"] ?? "",
                        source
                    ]
                )
                n += 1
            }
            return n
        }
        return count
    }

    /// Import entries from an external SQLite file that has the same `entries` schema.
    func importSQLite(at url: URL, source: String) async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        // Use DatabaseQueue — works with any journal mode (the file may not be in WAL mode).
        let externalQueue = try DatabaseQueue(path: url.path)
        let entries: [DictionaryEntry] = try await externalQueue.read { db in
            try DictionaryEntry.fetchAll(db)
        }
        let count = try await pool.write { db -> Int in
            var n = 0
            for var entry in entries {
                entry.source = source
                entry.id = nil
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [entry.word, entry.definition, entry.phonetic, entry.pos, entry.source]
                )
                n += 1
            }
            return n
        }
        return count
    }

    /// Seed the database from the bundled seed.sqlite / seed.json.
    /// Re-seeds any sources present in the bundle but missing from the app database.
    func seedIfNeeded() async throws {
        guard let pool = dbPool else { throw DBError.notConnected }

        // Priority 1: bundled SQLite file.
        if let sqliteURL = Bundle.main.url(forResource: "seed", withExtension: "sqlite") {
            // Find which sources exist in the bundled file.
            let bundledQueue = try DatabaseQueue(path: sqliteURL.path)
            let bundledSources: Set<String> = try await bundledQueue.read { db in
                let rows = try String.fetchAll(db, sql: "SELECT DISTINCT source FROM entries")
                return Set(rows)
            }

            // Find which sources are already in the app database.
            let existingSources: Set<String> = try await pool.read { db in
                let rows = try String.fetchAll(db, sql: "SELECT DISTINCT source FROM entries")
                return Set(rows)
            }

            let missingSources = bundledSources.subtracting(existingSources)
            if !missingSources.isEmpty {
                _ = try await importBundledSQLite(at: sqliteURL, sources: missingSources)
            }
            // Always refresh metadata from the bundle (picks up new columns / richer content).
            try await refreshMetadata(from: bundledQueue)
            return
        }

        // Priority 2: bundled JSON file (only if entries table is completely empty).
        let isEmpty = try await pool.read { db in
            try DictionaryEntry.fetchCount(db) == 0
        }
        if isEmpty, let jsonURL = Bundle.main.url(forResource: "seed", withExtension: "json") {
            _ = try await importJSON(at: jsonURL, source: "bundled")
        }
    }

    /// Imports entries (optionally filtered by source) and metadata from a bundled SQLite file.
    /// Uses DatabaseQueue (not DatabasePool) because the bundled file is read-only and
    /// may not be in WAL journal mode.
    private func importBundledSQLite(at url: URL, sources: Set<String>? = nil) async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }

        let bundledQueue = try DatabaseQueue(path: url.path)

        // Build WHERE clause for source filtering.
        let sourceFilter: String
        let sourceArgs: [String]
        if let sources, !sources.isEmpty {
            let placeholders = sources.map { _ in "?" }.joined(separator: ", ")
            sourceFilter = "WHERE source IN (\(placeholders))"
            sourceArgs = Array(sources)
        } else {
            sourceFilter = ""
            sourceArgs = []
        }

        // Read entries.
        let rows: [(String, String, String, String, String)] = try await bundledQueue.read { db in
            let sql = "SELECT word, definition, phonetic, pos, source FROM entries \(sourceFilter)"
            var args = StatementArguments()
            for s in sourceArgs { args += [s] }
            let cursor = try Row.fetchCursor(db, sql: sql, arguments: args)
            var result: [(String, String, String, String, String)] = []
            while let row = try cursor.next() {
                result.append((
                    row["word"] as String? ?? "",
                    row["definition"] as String? ?? "",
                    row["phonetic"] as String? ?? "",
                    row["pos"] as String? ?? "",
                    row["source"] as String? ?? "default"
                ))
            }
            return result
        }

        // Read metadata.
        let metadataRows: [(String, String, String, String, String, Int, String, String)] =
            try await bundledQueue.read { db in
                let hasTable = try db.tableExists("dict_metadata")
                guard hasTable else { return [] }
                let sql = "SELECT source, display_name, version, license, url, word_count, built_at, COALESCE(description, '') AS description FROM dict_metadata \(sourceFilter)"
                var args = StatementArguments()
                for s in sourceArgs { args += [s] }
                let cursor = try Row.fetchCursor(db, sql: sql, arguments: args)
                var result: [(String, String, String, String, String, Int, String, String)] = []
                while let row = try cursor.next() {
                    result.append((
                        row["source"] as String? ?? "",
                        row["display_name"] as String? ?? "",
                        row["version"] as String? ?? "",
                        row["license"] as String? ?? "",
                        row["url"] as String? ?? "",
                        row["word_count"] as Int? ?? 0,
                        row["built_at"] as String? ?? "",
                        row["description"] as String? ?? ""
                    ))
                }
                return result
            }

        // Bulk-insert entries in batches.
        var count = 0
        let batchSize = 1000
        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            let batch = rows[batchStart..<batchEnd]
            try await pool.write { db in
                for (word, definition, phonetic, pos, source) in batch {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO entries(word, definition, phonetic, pos, source)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                        arguments: [word, definition, phonetic, pos, source]
                    )
                }
            }
            count += batch.count
        }

        // Insert metadata.
        if !metadataRows.isEmpty {
            try await pool.write { db in
                for (source, name, version, license, url, wordCount, builtAt, description) in metadataRows {
                    try db.execute(
                        sql: """
                            INSERT OR REPLACE INTO dict_metadata(source, display_name, version, license, url, word_count, built_at, description)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [source, name, version, license, url, wordCount, builtAt, description]
                    )
                }
            }
        }

        return count
    }

    /// Re-imports all metadata rows from a bundled DatabaseQueue, overwriting existing rows.
    private func refreshMetadata(from bundledQueue: DatabaseQueue) async throws {
        guard let pool = dbPool else { return }
        let rows: [(String, String, String, String, String, Int, String, String)] =
            try await bundledQueue.read { db in
                let hasTable = try db.tableExists("dict_metadata")
                guard hasTable else { return [] }
                let sql = "SELECT source, display_name, version, license, url, word_count, built_at, COALESCE(description, '') AS description FROM dict_metadata"
                let cursor = try Row.fetchCursor(db, sql: sql)
                var result: [(String, String, String, String, String, Int, String, String)] = []
                while let row = try cursor.next() {
                    result.append((
                        row["source"] as String? ?? "",
                        row["display_name"] as String? ?? "",
                        row["version"] as String? ?? "",
                        row["license"] as String? ?? "",
                        row["url"] as String? ?? "",
                        row["word_count"] as Int? ?? 0,
                        row["built_at"] as String? ?? "",
                        row["description"] as String? ?? ""
                    ))
                }
                return result
            }
        guard !rows.isEmpty else { return }
        try await pool.write { db in
            for (source, name, version, license, url, wordCount, builtAt, description) in rows {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO dict_metadata(source, display_name, version, license, url, word_count, built_at, description)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [source, name, version, license, url, wordCount, builtAt, description]
                )
            }
        }
    }

    // MARK: - Entry count (for testing / UI)

    func entryCount(source: String) async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictionaryEntry.filter(Column("source") == source).fetchCount(db)
        }
    }

    func entryCount() async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictionaryEntry.fetchCount(db)
        }
    }

    func historyCount() async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try HistoryItem.fetchCount(db)
        }
    }

    // MARK: - Helpers

    private func sanitizeFTS(_ input: String) -> String {
        // Allow alphanumerics (Latin + Cyrillic via Unicode) and whitespace.
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        return String(input.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }

    static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DictApp/dict.sqlite")
    }

    // Inline schema used when Schema.sql is unavailable in the bundle.
    static let inlineSchema = """
        CREATE TABLE IF NOT EXISTS entries (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            word        TEXT    NOT NULL,
            definition  TEXT    NOT NULL,
            phonetic    TEXT    DEFAULT '',
            pos         TEXT    DEFAULT '',
            source      TEXT    DEFAULT 'default',
            created_at  TEXT    DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_word_source
            ON entries(word COLLATE NOCASE, source);
        CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
            word, definition,
            content='entries', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts(rowid, word, definition)
                VALUES (new.id, new.word, new.definition);
        END;
        CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, word, definition)
                VALUES ('delete', old.id, old.word, old.definition);
        END;
        CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, word, definition)
                VALUES ('delete', old.id, old.word, old.definition);
            INSERT INTO entries_fts(rowid, word, definition)
                VALUES (new.id, new.word, new.definition);
        END;
        CREATE TABLE IF NOT EXISTS history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            word        TEXT    NOT NULL UNIQUE,
            looked_at   TEXT    DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS bookmarks (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id    INTEGER NOT NULL UNIQUE REFERENCES entries(id) ON DELETE CASCADE,
            created_at  TEXT    DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS dict_metadata (
            source       TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            version      TEXT NOT NULL DEFAULT '',
            license      TEXT NOT NULL DEFAULT '',
            url          TEXT NOT NULL DEFAULT '',
            word_count   INTEGER NOT NULL DEFAULT 0,
            built_at     TEXT NOT NULL DEFAULT (datetime('now')),
            description  TEXT NOT NULL DEFAULT ''
        );
        """

    enum DBError: Error, LocalizedError {
        case notConnected
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Database is not connected. Call setup() first."
            }
        }
    }
}
