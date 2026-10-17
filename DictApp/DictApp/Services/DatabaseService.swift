// DatabaseService.swift
// Manages SQLite connections, schema migration, FTS5 search, and data seeding.

import Foundation
import GRDB

/// Search constants + the pure result-assembly used by "Preferred dictionary
/// first" (Issue #6). Kept out of the `actor` so `assemble` is testable without
/// a database.
enum Search {
    /// Top-N rows surfaced per dictionary in preferred-dictionary mode (v1.3.0).
    /// A future per-dictionary-N Settings control replaces this read with a
    /// settings read — one line.
    static let preferredDictionaryTopN = 4

    /// Flattens per-dictionary `buckets` in `order`, then appends the relevance
    /// `tail`. Deduplicates by entry `id` defensively (buckets are disjoint by
    /// source and the tail SQL already excludes bucketed IDs, so this is a
    /// belt-and-braces guarantee that the result never repeats a row). Order is
    /// preserved: each ordered bucket, then the tail.
    static func assemble(
        buckets: [String: [DictionaryEntry]],
        tail: [DictionaryEntry],
        order: [String]
    ) -> [DictionaryEntry] {
        var seen = Set<Int64>()
        var result: [DictionaryEntry] = []
        func append(_ entries: [DictionaryEntry]) {
            for entry in entries {
                guard let id = entry.id else { result.append(entry); continue }
                if seen.insert(id).inserted { result.append(entry) }
            }
        }
        for source in order { append(buckets[source] ?? []) }
        append(tail)
        return result
    }

    // MARK: Greek folding (Issue #87)
    //
    // The bundled Greek sources store a folded `word_normalized` and their
    // definitions' Greek decomposed (NFD), which the `unicode61
    // remove_diacritics 2` tokenizer indexes accent-free. The query side only
    // has to fold Greek the same way. Every step touches Greek code points
    // only, so Russian й, Spanish ñ and Arabic harakat are never folded.

    /// Greek and Coptic (U+0370–U+03FF) or Greek Extended (U+1F00–U+1FFF).
    static func isGreek(_ scalar: Unicode.Scalar) -> Bool {
        (0x0370...0x03FF).contains(scalar.value) || (0x1F00...0x1FFF).contains(scalar.value)
    }

    /// The accent-, case- and final-sigma-free search key of `s`. Must match
    /// `normalize_greek` in `Scripts/build_greek.py` scalar for scalar:
    /// 1. a string without a Greek code point is returned unchanged;
    /// 2. otherwise NFC it, and for each Greek scalar NFD-decompose it, drop
    ///    every nonspacing mark (Mn) and lowercase the rest;
    /// 3. map final sigma ς (U+03C2) to σ (U+03C3).
    /// Non-Greek scalars pass through unchanged.
    static func foldGreek(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: isGreek) else { return s }
        var out = String.UnicodeScalarView()
        for scalar in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            guard isGreek(scalar) else {
                out.append(scalar)
                continue
            }
            let base = String(String.UnicodeScalarView(
                String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
                    .filter { $0.properties.generalCategory != .nonspacingMark }
            ))
            // Step 3 inline: ς only ever comes from a Greek scalar.
            for folded in base.lowercased().unicodeScalars {
                out.append(folded == "\u{03C2}" ? "\u{03C3}" : folded)
            }
        }
        return String(out)
    }

    /// The FTS `MATCH` string and the `word_normalized` ranking key for a
    /// sanitized query. A query that folding leaves unchanged (every
    /// non-Greek query) keeps today's exact strings: `q*` and `q`. Otherwise
    /// the raw branch still finds accented custom imports (stored NFC, not
    /// folded) and the folded branch finds the bundled Greek sources.
    static func ftsQuery(sanitized: String) -> (match: String, rankKey: String, rawKey: String) {
        let folded = foldGreek(sanitized)
        // Scalar comparison: `==` on String is canonical equivalence.
        if folded.unicodeScalars.elementsEqual(sanitized.unicodeScalars) {
            return (sanitized + "*", sanitized, sanitized)
        }
        // Rank on both keys: bundled Greek rows store the folded key, custom
        // imports store the raw (NFC) headword (PR #113 review).
        return ("(" + sanitized + "*) OR (" + folded + "*)", folded, sanitized)
    }
}

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

            // Issue #6: history gains `source` (the dictionary of the last-viewed
            // entry for the word) so the History row can show the per-source
            // stripe. Pre-existing rows migrate with source='' (neutral stripe
            // until re-viewed). Same shape as the dict_metadata.description
            // migration above.
            let historyColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(history)")
            let historyColumnNames = Set(historyColumns.map { $0["name"] as String })
            if !historyColumnNames.contains("source") {
                try db.execute(sql: "ALTER TABLE history ADD COLUMN source TEXT NOT NULL DEFAULT ''")
            }

            try Self.migrate(db)
        }
    }

    /// Versioned schema migrations, gated on `PRAGMA user_version`.
    ///
    /// `CREATE TABLE/VIRTUAL TABLE IF NOT EXISTS` in `Schema.sql` does not
    /// alter tables that already exist, so installs created on an older
    /// schema need an explicit migration. This is the project's first true
    /// `user_version`-gated migration — extend the `if version < N` ladder
    /// for future schema changes and bump the final `PRAGMA user_version`.
    private static func migrate(_ db: Database) throws {
        let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0

        // v1 — normalized search column (Issue #10). Adds `word_normalized`
        // and repoints `entries_fts` (+ triggers) at it. On a fresh install
        // the updated Schema.sql already created the v1 shape, so the guards
        // below are no-ops and this just stamps user_version = 1.
        if version < 1 {
            let entryColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(entries)")
            let entryColumnNames = Set(entryColumns.map { $0["name"] as String })
            if !entryColumnNames.contains("word_normalized") {
                try db.execute(sql: "ALTER TABLE entries ADD COLUMN word_normalized TEXT NOT NULL DEFAULT ''")
                // No Arabic exists pre-#10, so every existing row's normalized
                // form is exactly its word.
                try db.execute(sql: "UPDATE entries SET word_normalized = word")
            }

            // Rebuild the FTS table + triggers if they still index `word`.
            let ftsSQL = try String.fetchOne(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'entries_fts'"
            ) ?? ""
            if !ftsSQL.contains("word_normalized") {
                try db.execute(sql: """
                    DROP TRIGGER IF EXISTS entries_ai;
                    DROP TRIGGER IF EXISTS entries_ad;
                    DROP TRIGGER IF EXISTS entries_au;
                    DROP TABLE IF EXISTS entries_fts;
                    CREATE VIRTUAL TABLE entries_fts USING fts5(
                        word_normalized, definition,
                        content='entries', content_rowid='id',
                        tokenize='unicode61 remove_diacritics 2'
                    );
                    CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
                        INSERT INTO entries_fts(rowid, word_normalized, definition)
                            VALUES (new.id, new.word_normalized, new.definition);
                    END;
                    CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
                        INSERT INTO entries_fts(entries_fts, rowid, word_normalized, definition)
                            VALUES ('delete', old.id, old.word_normalized, old.definition);
                    END;
                    CREATE TRIGGER entries_au AFTER UPDATE ON entries BEGIN
                        INSERT INTO entries_fts(entries_fts, rowid, word_normalized, definition)
                            VALUES ('delete', old.id, old.word_normalized, old.definition);
                        INSERT INTO entries_fts(rowid, word_normalized, definition)
                            VALUES (new.id, new.word_normalized, new.definition);
                    END;
                    INSERT INTO entries_fts(entries_fts) VALUES('rebuild');
                    """)
            }

            try db.execute(sql: "PRAGMA user_version = 1")
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
        // Issue #87: Greek queries also match their folded form.
        let fts = Search.ftsQuery(sanitized: sanitized)
        return try await pool.read { db in
            var sql = """
                SELECT e.*
                FROM entries_fts fts
                JOIN entries e ON e.id = fts.rowid
                WHERE entries_fts MATCH ?
                """
            var arguments: [DatabaseValueConvertible] = [fts.match]

            if let sources = enabledSources, !sources.isEmpty {
                let placeholders = sources.map { _ in "?" }.joined(separator: ", ")
                sql += " AND e.source IN (\(placeholders))"
                arguments += sources.map { $0 as DatabaseValueConvertible }
            }

            sql += """

                ORDER BY
                    (e.word_normalized = ? COLLATE NOCASE OR e.word_normalized = ? COLLATE NOCASE) DESC,
                    (e.word_normalized LIKE ? COLLATE NOCASE OR e.word_normalized LIKE ? COLLATE NOCASE) DESC,
                    rank
                LIMIT ?
                """
            arguments += [fts.rankKey, fts.rawKey, fts.rankKey + "%", fts.rawKey + "%", limit]

            var statArgs = StatementArguments()
            for arg in arguments { statArgs += [arg] }
            return try DictionaryEntry.fetchAll(db, sql: sql, arguments: statArgs)
        }
    }

    /// "Preferred dictionary first" search (Issue #6, `ResultSortMode.preferredDictionary`).
    ///
    /// Runs one capped `MATCH` query per **pair group** in user order (Issue
    /// #92: `groups` are the language-pair groups from
    /// `DictionaryGrouping.sourceGroups(order:)`; a pair's directions share one
    /// bucket and one `LIMIT topN`, merged by the shared ORDER BY), then one
    /// relevance "tail" query over all enabled sources excluding the rows
    /// already bucketed. Per-bucket `LIMIT` is the correct primitive (FTS5 has
    /// no window functions): a single global query capped at `limit` could push
    /// a low-ranking dictionary's top rows past the cutoff, so its top-N would
    /// be missing. Assembly is the pure `Search.assemble` for testability.
    func searchPreferred(
        query: String,
        groups: [[String]],
        enabledSources: Set<String>,
        topN: Int = Search.preferredDictionaryTopN,
        limit: Int = 50
    ) async throws -> [DictionaryEntry] {
        if enabledSources.isEmpty { return [] }
        guard let pool = dbPool else { throw DBError.notConnected }
        let sanitized = sanitizeFTS(query)
        guard !sanitized.isEmpty else { return [] }

        // Bucket only enabled members, group by group in user order. Enabled
        // sources absent from `groups` (e.g. a freshly-imported dict before
        // reconciliation) get no bucket but still appear via the relevance tail.
        let enabledGroups = groups
            .map { $0.filter { enabledSources.contains($0) } }
            .filter { !$0.isEmpty }
        // Issue #87: Greek queries also match their folded form.
        let fts = Search.ftsQuery(sanitized: sanitized)
        let match = fts.match
        let rankKey = fts.rankKey
        let rawKey = fts.rawKey

        return try await pool.read { db in
            var buckets: [String: [DictionaryEntry]] = [:]
            var bucketOrder: [String] = []
            var takenIds: [Int64] = []

            for (index, members) in enabledGroups.enumerated() {
                // Index, not joined IDs: a custom ID may contain any separator.
                let key = String(index)
                let placeholders = members.map { _ in "?" }.joined(separator: ", ")
                var args = StatementArguments()
                args += [match]
                for member in members { args += [member] }
                args += [rankKey, rawKey, rankKey + "%", rawKey + "%", topN]
                let rows = try DictionaryEntry.fetchAll(db, sql: """
                    SELECT e.*
                    FROM entries_fts fts JOIN entries e ON e.id = fts.rowid
                    WHERE entries_fts MATCH ? AND e.source IN (\(placeholders))
                    ORDER BY (e.word_normalized = ? COLLATE NOCASE OR e.word_normalized = ? COLLATE NOCASE) DESC,
                             (e.word_normalized LIKE ? COLLATE NOCASE OR e.word_normalized LIKE ? COLLATE NOCASE) DESC,
                             rank
                    LIMIT ?
                    """, arguments: args)
                buckets[key] = rows
                bucketOrder.append(key)
                takenIds += rows.compactMap(\.id)
            }

            // Relevance tail over all enabled sources, excluding bucketed IDs.
            var tail: [DictionaryEntry] = []
            let remaining = limit - takenIds.count
            if remaining > 0 {
                let enabledArr = Array(enabledSources)
                let srcPlaceholders = enabledArr.map { _ in "?" }.joined(separator: ", ")
                let notIn = takenIds.isEmpty
                    ? ""
                    : " AND e.id NOT IN (\(takenIds.map { _ in "?" }.joined(separator: ", ")))"
                var args = StatementArguments()
                args += [match]
                for s in enabledArr { args += [s] }
                for tid in takenIds { args += [tid] }
                args += [remaining]
                tail = try DictionaryEntry.fetchAll(db, sql: """
                    SELECT e.*
                    FROM entries_fts fts JOIN entries e ON e.id = fts.rowid
                    WHERE entries_fts MATCH ? AND e.source IN (\(srcPlaceholders))\(notIn)
                    ORDER BY rank
                    LIMIT ?
                    """, arguments: args)
            }

            return Search.assemble(buckets: buckets, tail: tail, order: bucketOrder)
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

    /// Records a viewed word with the `source` of the entry that was viewed
    /// (Issue #6). On a repeat view the last-viewed source wins (`excluded.source`).
    func addToHistory(word: String, source: String) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO history(word, source, looked_at) VALUES (?, ?, datetime('now'))
                    ON CONFLICT(word) DO UPDATE SET source = excluded.source, looked_at = datetime('now')
                    """,
                arguments: [word, source]
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

    /// Per-source entry counts, with display name / license / version from
    /// metadata where available (empty strings for custom imports, which have
    /// no `dict_metadata` row). License and version feed the #91 detail via
    /// `DictionaryPair.sources` (Issue #92).
    func fetchSourceStats() async throws -> [SourceStat] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            // Count first, then join the metadata once per source. Joined
            // inside the aggregate, the metadata columns were read for every
            // entry row; with the full Apache 2.0 text of the Greek WordNet
            // sources (Issue #87, ~9.8 KB on overflow pages) that left the
            // Dictionary Order screen empty for 25+ s after launch.
            let sql = """
                SELECT c.source,
                       COALESCE(m.display_name, c.source) AS display_name,
                       COALESCE(m.license, '') AS license,
                       COALESCE(m.version, '') AS version,
                       c.cnt
                FROM (SELECT source, COUNT(*) AS cnt FROM entries GROUP BY source) c
                LEFT JOIN dict_metadata m ON m.source = c.source
                ORDER BY c.cnt DESC
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { row in
                SourceStat(
                    source: row["source"],
                    displayName: row["display_name"],
                    count: row["cnt"],
                    license: row["license"],
                    version: row["version"]
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
                // Custom imports are not run through the Arabic normalizer
                // (single source of truth stays in the Python build), so the
                // search key is the word verbatim. Consequence: imported
                // Arabic is searched diacritic-sensitively — a documented
                // v1.3.0 limitation, not a regression.
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        word,
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
                // word_normalized = word for custom imports (see importJSON).
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [entry.word, entry.word, entry.definition, entry.phonetic, entry.pos, entry.source]
                )
                n += 1
            }
            return n
        }
        return count
    }

    /// Seed the database from the bundled seed.sqlite / seed.json.
    /// Re-seeds any sources present in the bundle but missing from the app
    /// database, and updates bundled sources whose seed was rebuilt since this
    /// install last synced (Issue #108). `bundledSeedURL` is a test seam: `nil`
    /// means the app bundle's `seed.sqlite`.
    func seedIfNeeded(bundledSeedURL: URL? = nil) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }

        // Priority 1: bundled SQLite file.
        if let sqliteURL = bundledSeedURL ?? Bundle.main.url(forResource: "seed", withExtension: "sqlite") {
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

            // Issue #108: a bundled source the app already has is stale when its
            // `built_at` differs from the bundle's (a missing app row counts).
            // `refreshMetadata` below copies `built_at`, so it closes this gate
            // only after a successful sync.
            let bundleBuiltAt = try await bundledQueue.read { db in try Self.builtAtBySource(db) }
            let appBuiltAt = try await pool.read { db in try Self.builtAtBySource(db) }
            let staleSources = bundledSources.intersection(existingSources).filter {
                appBuiltAt[$0] != bundleBuiltAt[$0]
            }

            let missingSources = bundledSources.subtracting(existingSources)
            if !missingSources.isEmpty {
                _ = try await importBundledSQLite(at: sqliteURL, sources: missingSources)
            }

            if !staleSources.isEmpty {
                do {
                    try await syncBundledSources(from: sqliteURL, sources: staleSources)
                } catch {
                    // Non-fatal: start on the old (still usable) data. Skipping
                    // `refreshMetadata` keeps the old `built_at`, so the next
                    // launch retries.
                    print("DatabaseService: bundled source sync failed, retrying next launch: \(error)")
                    return
                }
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

    /// Issue #108: brings existing `sources` up to date with the bundled seed at
    /// `url`, in one transaction. Rows are matched on (source, word NOCASE) and
    /// updated in place only when their content differs, so ids (and the
    /// bookmarks that cascade from them) survive and `entries_au` re-indexes
    /// just the changed rows. Bundle headwords the app lacks are inserted; app
    /// rows the bundle lacks are kept. Pass bundled source names only, never
    /// custom imports. Never use DELETE or REPLACE here: both change the id.
    @discardableResult
    func syncBundledSources(from url: URL, sources: Set<String>) async throws -> (updated: Int, inserted: Int) {
        guard let pool = dbPool else { throw DBError.notConnected }
        guard !sources.isEmpty else { return (0, 0) }
        let sourceList = Array(sources)
        let placeholders = sourceList.map { _ in "?" }.joined(separator: ", ")
        let path = url.path
        return try await pool.writeWithoutTransaction { db in
            // ATTACH and DETACH stay outside the transaction: DETACH inside one
            // fails with "database bundled is locked".
            try db.execute(sql: "ATTACH DATABASE ? AS bundled", arguments: [path])
            defer { try? db.execute(sql: "DETACH DATABASE bundled") }
            var updated = 0
            var inserted = 0
            try db.inTransaction {
                try db.execute(
                    sql: """
                        UPDATE main.entries AS e
                        SET word = x.word, word_normalized = x.word_normalized,
                            definition = x.definition, phonetic = x.phonetic, pos = x.pos
                        FROM bundled.entries AS x
                        WHERE x.source IN (\(placeholders))
                          AND e.source = x.source
                          AND e.word = x.word COLLATE NOCASE
                          AND (e.word IS NOT x.word OR e.word_normalized IS NOT x.word_normalized
                               OR e.definition IS NOT x.definition OR e.phonetic IS NOT x.phonetic
                               OR e.pos IS NOT x.pos)
                        """,
                    arguments: StatementArguments(sourceList)
                )
                updated = db.changesCount
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO main.entries(word, word_normalized, definition, phonetic, pos, source)
                        SELECT word, word_normalized, definition, phonetic, pos, source
                        FROM bundled.entries WHERE source IN (\(placeholders))
                        """,
                    arguments: StatementArguments(sourceList)
                )
                inserted = db.changesCount
                return .commit
            }
            return (updated, inserted)
        }
    }

    /// `source → built_at` from a database's `dict_metadata` (empty if the table
    /// is missing). The per-source gate for `syncBundledSources` (Issue #108).
    private static func builtAtBySource(_ db: Database) throws -> [String: String] {
        guard try db.tableExists("dict_metadata") else { return [:] }
        var result: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT source, built_at FROM dict_metadata") {
            if let source: String = row["source"] {
                result[source] = (row["built_at"] as String?) ?? ""
            }
        }
        return result
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

        // Read entries. `word_normalized` MUST be carried across: the client
        // re-imports rows and rebuilds its own FTS from triggers (it does not
        // copy the seed's FTS index), so if this column were left at its empty
        // default the FTS would index empty and Arabic search would silently
        // break on-device even though the seed is correct.
        let rows: [(String, String, String, String, String, String)] = try await bundledQueue.read { db in
            let sql = "SELECT word, word_normalized, definition, phonetic, pos, source FROM entries \(sourceFilter)"
            var args = StatementArguments()
            for s in sourceArgs { args += [s] }
            let cursor = try Row.fetchCursor(db, sql: sql, arguments: args)
            var result: [(String, String, String, String, String, String)] = []
            while let row = try cursor.next() {
                let word = row["word"] as String? ?? ""
                result.append((
                    word,
                    // Fall back to `word` if an older seed lacks the column.
                    row["word_normalized"] as String? ?? word,
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
                for (word, wordNormalized, definition, phonetic, pos, source) in batch {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO entries(word, word_normalized, definition, phonetic, pos, source)
                            VALUES (?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [word, wordNormalized, definition, phonetic, pos, source]
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
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            word            TEXT    NOT NULL,
            word_normalized TEXT    NOT NULL DEFAULT '',
            definition      TEXT    NOT NULL,
            phonetic        TEXT    DEFAULT '',
            pos             TEXT    DEFAULT '',
            source          TEXT    DEFAULT 'default',
            created_at      TEXT    DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_word_source
            ON entries(word COLLATE NOCASE, source);
        CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
            word_normalized, definition,
            content='entries', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
            INSERT INTO entries_fts(rowid, word_normalized, definition)
                VALUES (new.id, new.word_normalized, new.definition);
        END;
        CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, word_normalized, definition)
                VALUES ('delete', old.id, old.word_normalized, old.definition);
        END;
        CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
            INSERT INTO entries_fts(entries_fts, rowid, word_normalized, definition)
                VALUES ('delete', old.id, old.word_normalized, old.definition);
            INSERT INTO entries_fts(rowid, word_normalized, definition)
                VALUES (new.id, new.word_normalized, new.definition);
        END;
        CREATE TABLE IF NOT EXISTS history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            word        TEXT    NOT NULL UNIQUE,
            source      TEXT    NOT NULL DEFAULT '',
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
