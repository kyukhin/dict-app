// DatabaseService.swift
// Manages SQLite connections, schema migration, FTS5 search, and data seeding.

import Foundation
import Combine
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

    /// The background unpack of the bundled seed, while it runs (Issue #111).
    private var unpackTask: Task<Void, Never>?
    /// The latest unpack, kept after its single-flight slot is freed so a
    /// waiter also sees its final `.idle` (PR #116 review). ponytail: a second
    /// unpack in one process only happens in tests, so no generation counter.
    private var lastUnpackTask: Task<Void, Never>?

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
        // Wait instead of failing with SQLITE_BUSY if another pool on the same
        // file is mid-write (e.g. the background unpack, PR #116 review).
        config.busyMode = .timeout(5)
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
    ///
    /// Issue #111: a bundled source that is registered but not unpacked yet
    /// is listed too, with the bundle's `word_count` (its final count). So the
    /// first Settings load persists the same default order during the unpack
    /// as after it, and a toggle mid-unpack never switches a pending source off.
    func fetchSourceStats() async throws -> [SourceStat] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            // Count first, then join the metadata once per source. Joined
            // inside the aggregate, the metadata columns were read for every
            // entry row; with the full Apache 2.0 text of the Greek WordNet
            // sources (Issue #87, ~9.8 KB on overflow pages) that left the
            // Dictionary Order screen empty for 25+ s after launch. The counts
            // are computed once and reused for the metadata-only sources.
            let sql = """
                WITH c AS MATERIALIZED (SELECT source, COUNT(*) AS cnt FROM entries GROUP BY source)
                SELECT c.source AS source,
                       COALESCE(m.display_name, c.source) AS display_name,
                       COALESCE(m.license, '') AS license,
                       COALESCE(m.version, '') AS version,
                       c.cnt AS cnt
                FROM c
                LEFT JOIN dict_metadata m ON m.source = c.source
                UNION ALL
                SELECT m.source, m.display_name, m.license, m.version, m.word_count
                FROM dict_metadata m
                WHERE m.source NOT IN (SELECT source FROM c)
                ORDER BY cnt DESC
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
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await Self.importJSON(at: url, source: source, into: pool)
    }

    /// `importJSON(at:source:)` on an explicit pool, so the `seed.json`
    /// fallback of the background unpack keeps its own pool (Issue #111).
    private static func importJSON(at url: URL, source: String, into pool: DatabasePool) async throws -> Int {
        let raw = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url))
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
        // Read-only (Issue #111, PM decision 7): the user's file is never
        // written or created (a missing path fails instead of leaving an empty
        // database behind), and a read-only connection never toggles
        // `PRAGMA query_only`, the GRDB `endReadOnly()` crash site.
        var config = Configuration()
        config.readonly = true
        let externalQueue = try DatabaseQueue(path: url.path, configuration: config)
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

    // MARK: - Bundled seed (Issue #111)
    //
    // Launch only registers the bundled sources (metadata, a few ms) and gets
    // a plan; the rows are unpacked afterwards in the background, one
    // transaction per source, each searchable as soon as it commits.
    // `dict_metadata.built_at` is the per-source completion marker: equal to
    // the bundle's = complete and current, '' = registered but not unpacked
    // yet, any other value = unpacked from an older seed, stale (Issue #108).
    // The seed is only ever ATTACHed to the writer, never opened as a
    // connection of its own (PM decision 7: the cold-seed GRDB crash was in a
    // `DatabaseQueue` read of the bundle).

    /// Pre-UI half of the seed: in one transaction, registers every bundled
    /// source's metadata, then returns the ordered unpack plan. Reads the two
    /// `dict_metadata` tables only (no `entries` scan). `bundledSeedURL` is a
    /// test seam: `nil` means the app bundle's `seed.sqlite`. With no seed
    /// bundled the plan is empty and the unpack runs the JSON fallback.
    /// Throws for an unreadable bundle (the launch shows `setupError`).
    func prepareBundledSeed(bundledSeedURL: URL? = nil, languageCode: String) async throws -> BundledUnpackPlan {
        guard let pool = dbPool else { throw DBError.notConnected }
        guard let seedURL = bundledSeedURL ?? Bundle.main.url(forResource: "seed", withExtension: "sqlite") else {
            return BundledUnpackPlan(seedURL: nil, bundled: [], appBuiltAt: [:], languageCode: languageCode)
        }
        let path = seedURL.path
        let (bundled, appBuiltAt) = try await pool.writeWithoutTransaction { db in
            // ATTACH and DETACH stay outside the transaction: DETACH inside one
            // fails with "database bundled is locked".
            try db.execute(sql: "ATTACH DATABASE ? AS bundled", arguments: [path])
            defer { try? db.execute(sql: "DETACH DATABASE bundled") }
            var registered: ([BundledUnpackPlan.BundledSource], [String: String]) = ([], [:])
            try db.inTransaction {
                registered = try Self.registerBundledSources(db)
                return .commit
            }
            return registered
        }
        return BundledUnpackPlan(seedURL: seedURL, bundled: bundled, appBuiltAt: appBuiltAt,
                                 languageCode: languageCode)
    }

    /// Registration (§3.3), on a writer with the seed attached as `bundled`.
    /// A source the app lacks gets its bundle row with `built_at = ''`. Rows
    /// that are current or not unpacked yet get the bundle's descriptive
    /// columns (display name, version, license, url, word count, description).
    /// A stale row keeps its old metadata: its unpack copies the new row in
    /// the same transaction as the new data, so a failed sync leaves the
    /// install exactly as it was (#108). Returns the bundle's sources in seed
    /// order and the app's markers as they were before this call.
    private static func registerBundledSources(
        _ db: Database
    ) throws -> ([BundledUnpackPlan.BundledSource], [String: String]) {
        // The plan is driven by metadata, but a bundle without `entries` is
        // unreadable: fail before any write. Preparing the statement is enough.
        _ = try db.makeStatement(sql: "SELECT 1 FROM bundled.entries")
        let bundleRows = try Row.fetchAll(db, sql: """
            SELECT source, display_name, version, license, url, word_count, built_at,
                   COALESCE(description, '') AS description
            FROM bundled.dict_metadata
            ORDER BY rowid
            """)
        var appBuiltAt: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT source, built_at FROM main.dict_metadata") {
            if let source: String = row["source"] {
                appBuiltAt[source] = (row["built_at"] as String?) ?? ""
            }
        }

        var bundled: [BundledUnpackPlan.BundledSource] = []
        for row in bundleRows {
            guard let source: String = row["source"], !source.isEmpty else { continue }
            let builtAt = (row["built_at"] as String?) ?? ""
            let wordCount = (row["word_count"] as Int?) ?? 0
            bundled.append(.init(source: source, rowCount: wordCount, builtAt: builtAt))

            let details: [(any DatabaseValueConvertible)?] = [
                (row["display_name"] as String?) ?? source,
                (row["version"] as String?) ?? "",
                (row["license"] as String?) ?? "",
                (row["url"] as String?) ?? "",
                wordCount,
                (row["description"] as String?) ?? "",
            ]
            switch appBuiltAt[source] {
            case nil:
                try db.execute(
                    sql: """
                        INSERT INTO main.dict_metadata(display_name, version, license, url, word_count,
                                                       description, source, built_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, '')
                        """,
                    arguments: StatementArguments(details + [source]))
            case let marker? where marker.isEmpty || marker == builtAt:
                try db.execute(
                    sql: """
                        UPDATE main.dict_metadata
                        SET display_name = ?, version = ?, license = ?, url = ?, word_count = ?, description = ?
                        WHERE source = ?
                        """,
                    arguments: StatementArguments(details + [source]))
            default:
                break   // stale: refreshed by its unpack (see above)
            }
        }
        return (bundled, appBuiltAt)
    }

    /// Starts the background unpack of `plan` (§3.2) and returns at once.
    /// Single flight: a call while an unpack runs is a no-op (the WindowGroup
    /// `.task` may run again). The task keeps the pool it started with and
    /// never re-reads `dbPool`, so a later `setup(path:)` (unit tests) never
    /// receives its writes. Publishes progress to `DictionaryUnpackStatus`
    /// after each committed source and `.idle` at the end, also after a failure.
    func startBundledUnpack(_ plan: BundledUnpackPlan) {
        guard unpackTask == nil, let pool = dbPool else { return }
        // Nothing to do: every bundled source is complete and current.
        guard !plan.isEmpty || plan.seedURL == nil else { return }
        #if DEBUG
        // UI-test hook `-unpackSourceDelay <seconds>`: holds the unpack between
        // sources so mid-unpack states last long enough to assert on.
        let sourceDelay = UserDefaults.standard.double(forKey: "unpackSourceDelay")
        #else
        let sourceDelay = 0.0
        #endif
        unpackTask = Task.detached(priority: .utility) {
            await Self.runUnpack(plan, pool: pool, sourceDelay: sourceDelay) { fraction in
                await DictionaryUnpackStatus.shared.update(.unpacking(fraction: fraction))
            }
            // Free the single-flight slot before announcing `.idle`, so a
            // caller that waits for `.idle` can start the next unpack.
            await self.unpackDidFinish()
            await DictionaryUnpackStatus.shared.update(.idle)
        }
        lastUnpackTask = unpackTask
    }

    private func unpackDidFinish() {
        unpackTask = nil
    }

    /// Returns once the background unpack (if any) has finished. Test seam.
    func waitForBundledUnpack() async {
        await (unpackTask ?? lastUnpackTask)?.value
    }

    /// Synchronous facade over the plan and the unpack, for unit tests (§3.6):
    /// prepares the plan (English order) and unpacks every pending source on
    /// the current pool before returning. Never publishes to
    /// `DictionaryUnpackStatus`. A failed source is logged and ends the run
    /// without throwing (#108: the app must still start, the next launch
    /// retries); an unreadable bundle throws from the preparation.
    func seedIfNeeded(bundledSeedURL: URL? = nil) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        let plan = try await prepareBundledSeed(bundledSeedURL: bundledSeedURL, languageCode: "en")
        await Self.runUnpack(plan, pool: pool)
    }

    /// Issue #108: brings existing `sources` up to date with the bundled seed
    /// at `url`, one source (and one transaction) at a time, through the same
    /// per-source unit as the unpack. Returns the summed counts. Pass bundled
    /// source names only, never custom imports.
    @discardableResult
    func syncBundledSources(from url: URL, sources: Set<String>) async throws -> (updated: Int, inserted: Int) {
        guard let pool = dbPool else { throw DBError.notConnected }
        var total = (updated: 0, inserted: 0)
        for source in sources.sorted() {
            let counts = try await Self.unpackSource(source, seedPath: url.path, pool: pool)
            total.updated += counts.updated
            total.inserted += counts.inserted
        }
        return total
    }

    #if DEBUG
    /// Unit-test seam: the source whose unpack throws inside its transaction
    /// right after the INSERT step, as if the app were killed mid-source.
    nonisolated(unsafe) static var unpackFailureAfterInsert: String?
    #endif

    /// Runs `plan` on `pool` until done or until the first failure, one write
    /// per source; `progress` gets the plan's fraction after each commit. A
    /// failure is logged and stops the loop: committed sources stay, and the
    /// next launch's plan retries the rest from their markers (PM decision 4).
    private static func runUnpack(
        _ plan: BundledUnpackPlan,
        pool: DatabasePool,
        sourceDelay: Double = 0,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async {
        guard let seedURL = plan.seedURL else {
            await importJSONFallbackIfNeeded(into: pool)
            return
        }
        for (index, item) in plan.items.enumerated() {
            do {
                _ = try await unpackSource(item.source, seedPath: seedURL.path, pool: pool)
            } catch {
                print("DatabaseService: unpacking \(item.source) failed, retrying next launch: \(error)")
                break
            }
            await progress?(plan.fraction(afterCompleting: index + 1))
            if sourceDelay > 0, index < plan.items.count - 1 {
                try? await Task.sleep(for: .seconds(sourceDelay))
            }
        }
        guard !plan.isEmpty else { return }
        // Shrink the WAL (about 60 MB after the wordnet transaction). A busy
        // reader only turns this into a no-op.
        _ = try? await pool.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
    }

    /// The per-source unit (§2.1). One write that ATTACHes the seed and, in
    /// one transaction: updates the source's changed rows in place (#108:
    /// rows matched on word NOCASE, so ids and the bookmarks on them survive
    /// and `entries_au` re-indexes just those rows), inserts the rows the app
    /// lacks (`entries_ai` indexes them), and copies the bundle's metadata
    /// row, whose `built_at` is the completion marker. It imports a missing
    /// source, completes a half-imported one and updates a stale one alike.
    /// An error or a kill rolls the whole source back, marker included.
    /// Bundle headwords the app lacks are inserted; app rows the bundle lacks
    /// are kept. Never use DELETE or REPLACE here: both change the id.
    private static func unpackSource(_ source: String, seedPath: String,
                                     pool: DatabasePool) async throws -> (updated: Int, inserted: Int) {
        try await pool.writeWithoutTransaction { db in
            // ATTACH and DETACH stay outside the transaction: DETACH inside one
            // fails with "database bundled is locked".
            try db.execute(sql: "ATTACH DATABASE ? AS bundled", arguments: [seedPath])
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
                        WHERE x.source = ?
                          AND e.source = x.source
                          AND e.word = x.word COLLATE NOCASE
                          AND (e.word IS NOT x.word OR e.word_normalized IS NOT x.word_normalized
                               OR e.definition IS NOT x.definition OR e.phonetic IS NOT x.phonetic
                               OR e.pos IS NOT x.pos)
                        """,
                    arguments: [source]
                )
                updated = db.changesCount
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO main.entries(word, word_normalized, definition, phonetic, pos, source)
                        SELECT word, word_normalized, definition, phonetic, pos, source
                        FROM bundled.entries WHERE source = ? ORDER BY id
                        """,
                    arguments: [source]
                )
                inserted = db.changesCount
                #if DEBUG
                if Self.unpackFailureAfterInsert == source {
                    throw DatabaseError(resultCode: .SQLITE_ABORT,
                                        message: "unpackFailureAfterInsert: \(source)")
                }
                #endif
                try db.execute(
                    sql: """
                        INSERT INTO main.dict_metadata(source, display_name, version, license, url,
                                                       word_count, built_at, description)
                        SELECT source, display_name, version, license, url, word_count, built_at,
                               COALESCE(description, '')
                        FROM bundled.dict_metadata WHERE source = ?
                        ON CONFLICT(source) DO UPDATE SET
                            display_name = excluded.display_name, version = excluded.version,
                            license = excluded.license, url = excluded.url,
                            word_count = excluded.word_count, built_at = excluded.built_at,
                            description = excluded.description
                        """,
                    arguments: [source]
                )
                return .commit
            }
            return (updated, inserted)
        }
    }

    /// No `seed.sqlite` bundled: imports `seed.json`, only into an empty
    /// database (the pre-#111 fallback, unchanged).
    private static func importJSONFallbackIfNeeded(into pool: DatabasePool) async {
        do {
            let isEmpty = try await pool.read { db in try DictionaryEntry.fetchCount(db) == 0 }
            if isEmpty, let jsonURL = Bundle.main.url(forResource: "seed", withExtension: "json") {
                _ = try await importJSON(at: jsonURL, source: "bundled", into: pool)
            }
        } catch {
            print("DatabaseService: seed.json import failed: \(error)")
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

    #if DEBUG
    /// UI-test hook `-resetDatabase` (Issue #111): deletes the app database
    /// before `setup()`, for a deterministic fresh install without
    /// uninstalling (the simulator keeps its language and keyboard settings).
    static func removeDefaultDatabaseFiles() {
        let path = defaultDatabaseURL().path
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }
    #endif

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

// MARK: - Bundled unpack plan and status (Issue #111)

/// What the background unpack has to do (DESIGN_DOC_111 §3.3). Pure, so the
/// order and the progress rule are unit-testable without a database.
struct BundledUnpackPlan: Equatable, Sendable {
    /// One bundled source as the seed's `dict_metadata` lists it.
    struct BundledSource: Equatable, Sendable {
        let source: String
        /// The bundle's `word_count`.
        let rowCount: Int
        let builtAt: String
    }

    /// One source to unpack. `isNew`: never unpacked (no marker yet), else
    /// stale (unpacked from an older seed, synced in place).
    struct Item: Equatable, Sendable {
        let source: String
        /// The bundle's `word_count`.
        let rowCount: Int
        let isNew: Bool
    }

    /// The seed to unpack from; `nil` when none is bundled (JSON fallback).
    let seedURL: URL?
    /// Pending sources in unpack order: new ones first (new content before
    /// updates of content that is already searchable), each group in
    /// `DictionaryDefaults.unpackPriority` order.
    let items: [Item]
    /// Progress weight of every bundled source, pending or not: the sum of
    /// their `word_count`s (at least 1 each, so a fixture without counts
    /// still advances).
    let allRows: Int

    var isEmpty: Bool { items.isEmpty }

    /// The share already present when the unpack starts (a resumed unpack
    /// starts where the last one stopped).
    var initialFraction: Double { fraction(afterCompleting: 0) }

    /// - Parameters:
    ///   - bundled: the bundle's sources in seed order.
    ///   - appBuiltAt: the app's `source → built_at` markers before
    ///     registration. A source is pending when its marker is missing,
    ///     empty, or differs from the bundle's `built_at`.
    ///   - languageCode: the UI language, for `unpackPriority`.
    init(seedURL: URL?, bundled: [BundledSource], appBuiltAt: [String: String], languageCode: String) {
        self.seedURL = seedURL
        allRows = bundled.reduce(0) { $0 + Self.weight($1.rowCount) }
        let priority = DictionaryDefaults.unpackPriority(forLanguageCode: languageCode,
                                                         sources: bundled.map(\.source))
        let rank = Dictionary(priority.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        items = bundled
            .compactMap { source -> Item? in
                let marker = appBuiltAt[source.source] ?? ""
                guard marker.isEmpty || marker != source.builtAt else { return nil }
                return Item(source: source.source, rowCount: source.rowCount, isNew: marker.isEmpty)
            }
            .sorted { lhs, rhs in
                if lhs.isNew != rhs.isNew { return lhs.isNew }
                return rank[lhs.source, default: .max] < rank[rhs.source, default: .max]
            }
    }

    /// Share of all bundled rows present once the first `count` items have
    /// committed: `(allRows − rows still pending) / allRows`. Never decreases.
    func fraction(afterCompleting count: Int) -> Double {
        guard allRows > 0 else { return 1 }
        let pending = items.dropFirst(count).reduce(0) { $0 + Self.weight($1.rowCount) }
        return Double(allRows - pending) / Double(allRows)
    }

    private static func weight(_ rowCount: Int) -> Int { max(rowCount, 1) }
}

/// Observable progress of the background unpack, for the Search screen's
/// progress bar (Issue #111). A plain value holder: written only by
/// `DatabaseService` and `DictApp.initializeDatabase`; `SearchViewModel`
/// maps it for the view.
@MainActor
final class DictionaryUnpackStatus: ObservableObject {
    static let shared = DictionaryUnpackStatus()

    enum Phase: Equatable, Sendable {
        case idle
        /// `fraction`: share of all bundled rows present, 0...1.
        case unpacking(fraction: Double)
    }

    @Published private(set) var phase: Phase = .idle

    /// Sets the state for `plan` before the first frame (so the bar never
    /// flashes on a normal launch, and is already up on a fresh one).
    func begin(_ plan: BundledUnpackPlan) {
        phase = plan.isEmpty ? .idle : .unpacking(fraction: plan.initialFraction)
    }

    func update(_ phase: Phase) {
        self.phase = phase
    }
}
