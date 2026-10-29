// DatabaseService.swift
// The user database with the bundled dictionary file attached (Issue #138):
// connections, the user schema, FTS5 search, History, My words and imports.

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

    /// The user database, with the dictionary file attached as `dict` on
    /// every connection (Issue #138).
    private var dbPool: DatabasePool?

    private init() {}

    // MARK: - Setup (Issue #138)
    //
    // One pool on the user database (`user.sqlite`). Every connection, the
    // writer and each reader, attaches the bundled dictionary file as `dict`,
    // read-only and immutable: writes to `dict.*` fail with SQLITE_READONLY,
    // and no GRDB connection is ever opened on the bundle (the #111 crash
    // site). SQL always qualifies `dict.`; no user table shares a name with a
    // dictionary table.

    /// Opens the user database at its default path with the bundled
    /// dictionary file attached, and migrates it. Nothing is copied or
    /// unpacked, so this takes milliseconds.
    func setup() async throws {
        guard let dictionaryURL = Self.bundledDictionaryURL() else { throw DBError.dictionaryMissing }
        let userURL = Self.userDatabaseURL()
        try FileManager.default.createDirectory(
            at: userURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await setup(userPath: userURL.path, dictionaryURL: dictionaryURL)
    }

    /// Opens the user database at `userPath` with the dictionary file at
    /// `dictionaryURL` attached as `dict`, and migrates it. Test seam: unit
    /// tests pass a temp user database and a `TestDictionary` file.
    func setup(userPath: String, dictionaryURL: URL) async throws {
        let path = dictionaryURL.path
        let uri = "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
            + "?mode=ro&immutable=1"
        var config = Configuration()
        // Wait instead of failing with SQLITE_BUSY if another pool on the same
        // file is mid-write (a test reopening the shared service).
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            try db.execute(sql: "ATTACH DATABASE ? AS dict", arguments: [uri])
        }
        let pool = try DatabasePool(path: userPath, configuration: config)
        try Self.migrator.migrate(pool)
        dbPool = pool
    }

    /// The user database schema. Migrations are append-only once merged to
    /// master; each epic registers its own, named `<epic>-<n>-<what>`.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("129-1-core") { db in
            try db.execute(sql: """
                CREATE TABLE history (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    word        TEXT    NOT NULL UNIQUE,
                    source      TEXT    NOT NULL DEFAULT '',
                    looked_at   TEXT    DEFAULT (datetime('now'))
                );

                -- My words (former bookmarks), by stable entry key.
                CREATE TABLE my_words (
                    source      TEXT    NOT NULL,
                    word        TEXT    NOT NULL COLLATE NOCASE,
                    added_at    TEXT    NOT NULL DEFAULT (datetime('now')),
                    PRIMARY KEY (source, word)
                ) WITHOUT ROWID;

                -- Imported dictionaries: the dictionary file's `entries`
                -- columns plus `created_at`.
                CREATE TABLE imported_entries (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    word            TEXT    NOT NULL,
                    word_normalized TEXT    NOT NULL DEFAULT '',
                    definition      TEXT    NOT NULL,
                    phonetic        TEXT    DEFAULT '',
                    pos             TEXT    DEFAULT '',
                    source          TEXT    NOT NULL,
                    created_at      TEXT    DEFAULT (datetime('now'))
                );
                CREATE UNIQUE INDEX imported_entries_word_source
                    ON imported_entries(word COLLATE NOCASE, source);
                CREATE INDEX imported_entries_source ON imported_entries(source);
                -- Imported ids start at 2^40, above every dictionary file id,
                -- so one Int64 identifies a row across both stores.
                INSERT INTO main.sqlite_sequence(name, seq) VALUES ('imported_entries', 1099511627775);

                CREATE VIRTUAL TABLE imported_fts USING fts5(
                    word_normalized, definition,
                    content='imported_entries', content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                );
                CREATE TRIGGER imported_ai AFTER INSERT ON imported_entries BEGIN
                    INSERT INTO imported_fts(rowid, word_normalized, definition)
                        VALUES (new.id, new.word_normalized, new.definition);
                END;
                CREATE TRIGGER imported_ad AFTER DELETE ON imported_entries BEGIN
                    INSERT INTO imported_fts(imported_fts, rowid, word_normalized, definition)
                        VALUES ('delete', old.id, old.word_normalized, old.definition);
                END;
                CREATE TRIGGER imported_au AFTER UPDATE ON imported_entries BEGIN
                    INSERT INTO imported_fts(imported_fts, rowid, word_normalized, definition)
                        VALUES ('delete', old.id, old.word_normalized, old.definition);
                    INSERT INTO imported_fts(rowid, word_normalized, definition)
                        VALUES (new.id, new.word_normalized, new.definition);
                END;

                -- One row per imported dictionary. The languages stay NULL
                -- until #208 fills them.
                CREATE TABLE imported_sources (
                    source      TEXT    PRIMARY KEY,
                    imported_at TEXT    NOT NULL DEFAULT (datetime('now')),
                    from_lang   TEXT,
                    to_lang     TEXT
                );

                CREATE TABLE user_meta (
                    key         TEXT    PRIMARY KEY,
                    value       TEXT    NOT NULL
                );
                """)
        }
        return migrator
    }

    // MARK: - Search
    //
    // Issue #138: bundled rows come from the dictionary file (`dict.entries`,
    // `dict.entries_fts`), imported rows from the user database
    // (`imported_entries`, `imported_fts`). Each store is one branch matching
    // its own FTS index; one ORDER BY and one LIMIT rank the union with the
    // 1.4.0 ranking. The imported branch is added only when an enabled source
    // is imported, so the bundled-only query keeps the 1.4.0 plan.

    /// Where entries live, as one search branch reads them.
    private enum Store: CaseIterable {
        case dictionary, imported

        /// The FTS table, its hidden MATCH column, the entries table and the
        /// `created_at` expression (bundled rows have none).
        var tables: (fts: String, match: String, entries: String, createdAt: String) {
            switch self {
            case .dictionary: return ("dict.entries_fts", "entries_fts", "dict.entries", "NULL")
            case .imported: return ("imported_fts", "imported_fts", "imported_entries", "e.created_at")
            }
        }
    }

    /// The 1.4.0 ranking: an exact `word_normalized` match on the folded or
    /// raw key, then a prefix match, then FTS `rank`. Takes
    /// `relevanceArguments(_:)`.
    private static let relevanceOrder = """
        (word_normalized = ? COLLATE NOCASE OR word_normalized = ? COLLATE NOCASE) DESC,
            (word_normalized LIKE ? COLLATE NOCASE OR word_normalized LIKE ? COLLATE NOCASE) DESC,
            rank
        """

    private static func relevanceArguments(_ fts: (match: String, rankKey: String, rawKey: String)) -> StatementArguments {
        [fts.rankKey, fts.rawKey, fts.rankKey + "%", fts.rawKey + "%"]
    }

    /// The sources of the imported dictionaries.
    private static func importedSources(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT source FROM imported_sources"))
    }

    /// Rows matching `match`, as `DictionaryEntry`s ranked by `order` and cut
    /// to `limit`. `sources`: the sources to keep (`nil`: every source).
    /// `ids`: rows to leave out. `withImports` adds the imported branch. Each
    /// branch has the entry columns plus `rank`, so `order` names columns of
    /// the union.
    private static func rankedEntries(
        _ db: Database, match: String, sources: [String]?, excluding ids: [Int64] = [],
        withImports: Bool, order: String, orderArguments: StatementArguments, limit: Int
    ) throws -> [DictionaryEntry] {
        var branches: [String] = []
        var arguments = StatementArguments()
        for store in withImports ? Store.allCases : [.dictionary] {
            let t = store.tables
            var branch = """
                SELECT e.id, e.word, e.word_normalized, e.definition, e.phonetic, e.pos, e.source,
                       \(t.createdAt) AS created_at, fts.rank AS rank
                FROM \(t.fts) fts JOIN \(t.entries) e ON e.id = fts.rowid
                WHERE \(t.match) MATCH ?
                """
            arguments += [match]
            if let sources {
                branch += " AND e.source IN (\(sources.map { _ in "?" }.joined(separator: ", ")))"
                arguments += StatementArguments(sources)
            }
            if !ids.isEmpty {
                branch += " AND e.id NOT IN (\(ids.map { _ in "?" }.joined(separator: ", ")))"
                arguments += StatementArguments(ids)
            }
            branches.append(branch)
        }
        arguments += orderArguments
        arguments += [limit]
        return try DictionaryEntry.fetchAll(db, sql: """
            SELECT * FROM (
            \(branches.joined(separator: "\nUNION ALL\n"))
            )
            ORDER BY \(order)
            LIMIT ?
            """, arguments: arguments)
    }

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
            let imported = try Self.importedSources(db)
            let withImports = enabledSources.map { !imported.isDisjoint(with: $0) } ?? !imported.isEmpty
            return try Self.rankedEntries(
                db, match: fts.match, sources: enabledSources.map { Array($0) }, withImports: withImports,
                order: Self.relevanceOrder, orderArguments: Self.relevanceArguments(fts), limit: limit
            )
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

        return try await pool.read { db in
            let imported = try Self.importedSources(db)
            var buckets: [String: [DictionaryEntry]] = [:]
            var bucketOrder: [String] = []
            var takenIds: [Int64] = []

            for (index, members) in enabledGroups.enumerated() {
                // Index, not joined IDs: a custom ID may contain any separator.
                let key = String(index)
                let rows = try Self.rankedEntries(
                    db, match: fts.match, sources: members, withImports: !imported.isDisjoint(with: members),
                    order: Self.relevanceOrder, orderArguments: Self.relevanceArguments(fts), limit: topN
                )
                buckets[key] = rows
                bucketOrder.append(key)
                takenIds += rows.compactMap(\.id)
            }

            // Relevance tail over all enabled sources, excluding bucketed IDs.
            var tail: [DictionaryEntry] = []
            let remaining = limit - takenIds.count
            if remaining > 0 {
                tail = try Self.rankedEntries(
                    db, match: fts.match, sources: Array(enabledSources), excluding: takenIds,
                    withImports: !imported.isDisjoint(with: enabledSources),
                    order: "rank", orderArguments: [], limit: remaining
                )
            }

            return Search.assemble(buckets: buckets, tail: tail, order: bucketOrder)
        }
    }

    // MARK: - Entries by key (Issue #138)

    /// The entry `key` names: the dictionary file first, then the imported
    /// dictionaries; `nil` when neither has it. A disabled source resolves
    /// too: the enabled set only filters Search.
    func entry(for key: EntryKey) async throws -> DictionaryEntry? {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in try Self.entry(for: key, in: db) }
    }

    private static func entry(for key: EntryKey, in db: Database) throws -> DictionaryEntry? {
        let arguments: StatementArguments = [key.word, key.source]
        return try DictionaryEntry.fetchOne(db, sql: """
                SELECT id, word, definition, phonetic, pos, source, NULL AS created_at
                FROM dict.entries WHERE word = ? COLLATE NOCASE AND source = ?
                """, arguments: arguments)
            ?? DictionaryEntry.fetchOne(db, sql: """
                SELECT id, word, definition, phonetic, pos, source, created_at
                FROM imported_entries WHERE word = ? COLLATE NOCASE AND source = ?
                """, arguments: arguments)
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

    // MARK: - My words (Issue #138)
    //
    // Until #158 replaces the Bookmarks tab, the Definition star and the tab
    // read and write My words, by stable entry key.

    func addToMyWords(_ key: EntryKey) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO my_words(source, word) VALUES (?, ?)",
                arguments: [key.source, key.word]
            )
        }
    }

    func removeFromMyWords(_ key: EntryKey) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(
                sql: "DELETE FROM my_words WHERE source = ? AND word = ?",
                arguments: [key.source, key.word]
            )
        }
    }

    func isInMyWords(_ key: EntryKey) async throws -> Bool {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS (SELECT 1 FROM my_words WHERE source = ? AND word = ?)",
                arguments: [key.source, key.word]
            ) ?? false
        }
    }

    /// My words whose entry resolves, newest first. A key that no longer
    /// resolves stays stored and is skipped here.
    func fetchMyWords() async throws -> [DictionaryEntry] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try Row.fetchAll(db, sql: "SELECT source, word FROM my_words ORDER BY added_at DESC")
                .compactMap { row in
                    try Self.entry(for: EntryKey(source: row["source"], word: row["word"]), in: db)
                }
        }
    }

    func clearMyWords() async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM my_words")
        }
    }

    // MARK: - Metadata & Statistics

    /// Metadata of every bundled dictionary, in dictionary file order.
    func fetchMetadata() async throws -> [DictMetadata] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictMetadata.fetchAll(db, sql: """
                SELECT source, display_name, version, license, url, word_count, description
                FROM dict.dict_metadata ORDER BY rowid
                """)
        }
    }

    /// Fetch metadata for a single dictionary source.
    func fetchMetadata(source: String) async throws -> DictMetadata? {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try DictMetadata.fetchOne(db, sql: """
                SELECT source, display_name, version, license, url, word_count, description
                FROM dict.dict_metadata WHERE source = ?
                """, arguments: [source])
        }
    }

    /// Per-source entry counts, count-desc, with display name / license /
    /// version from the metadata (Issue #92, for the #91 detail). Issue #138:
    /// a bundled source counts its `word_count` plus any rows imported under
    /// its ID; an imported source counts its rows (indexed) and shows its ID
    /// with an empty license and version. No scan of the bundled rows.
    func fetchSourceStats() async throws -> [SourceStat] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            let sql = """
                WITH i AS MATERIALIZED (SELECT source, COUNT(*) AS cnt FROM imported_entries GROUP BY source)
                SELECT m.source AS source, m.display_name AS display_name, m.license AS license,
                       m.version AS version, m.word_count + COALESCE(i.cnt, 0) AS cnt
                FROM dict.dict_metadata m
                LEFT JOIN i ON i.source = m.source
                UNION ALL
                SELECT i.source, i.source, '', '', i.cnt
                FROM i
                WHERE i.source NOT IN (SELECT source FROM dict.dict_metadata)
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
    //
    // Issue #138: imports go into `imported_entries` (the `imported_ai`
    // trigger indexes them) and `imported_sources`. A row whose key the
    // dictionary file already has is skipped, as `INSERT OR IGNORE` did in
    // 1.4.0 for a file named like a bundled source.

    /// Bulk-insert entries from a JSON array. Expects `[{word, definition, phonetic?, pos?}]`.
    func importJSON(at url: URL, source: String) async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        let raw = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url))
        let rows = raw.compactMap { item -> ImportedRow? in
            guard let word = item["word"], let definition = item["definition"] else { return nil }
            return ImportedRow(word: word, definition: definition,
                               phonetic: item["phonetic"] ?? "", pos: item["pos"] ?? "")
        }
        return try await Self.insertImported(rows, source: source, into: pool)
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
        let rows = entries.map {
            ImportedRow(word: $0.word, definition: $0.definition, phonetic: $0.phonetic, pos: $0.pos)
        }
        return try await Self.insertImported(rows, source: source, into: pool)
    }

    private struct ImportedRow: Sendable {
        let word: String
        let definition: String
        let phonetic: String
        let pos: String
    }

    /// Inserts `rows` under `source` in one transaction and registers the
    /// source once it has rows. Returns the number of rows read, as 1.4.0 did.
    private static func insertImported(_ rows: [ImportedRow], source: String,
                                       into pool: DatabasePool) async throws -> Int {
        try await pool.write { db in
            // Custom imports are not run through the Arabic or Greek
            // normalizers (single source of truth stays in the Python build),
            // so the search key is the word verbatim. Consequence: imported
            // Arabic is searched diacritic-sensitively — a documented v1.3.0
            // limitation, not a regression.
            let insert = try db.makeStatement(sql: """
                INSERT OR IGNORE INTO imported_entries(word, word_normalized, definition, phonetic, pos, source)
                SELECT ?1, ?1, ?2, ?3, ?4, ?5
                WHERE NOT EXISTS (SELECT 1 FROM dict.entries WHERE word = ?1 COLLATE NOCASE AND source = ?5)
                """)
            for row in rows {
                try insert.execute(arguments: [row.word, row.definition, row.phonetic, row.pos, source])
            }
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO imported_sources(source)
                    SELECT ?1 WHERE EXISTS (SELECT 1 FROM imported_entries WHERE source = ?1)
                    """,
                arguments: [source]
            )
            return rows.count
        }
    }

    /// Deletes an imported dictionary: its rows and its `imported_sources`
    /// row. Used by UI tests (`-clearFixtureImports`) to scrub previously
    /// imported fixture data before re-running.
    func clearEntries(fromSource source: String) async throws {
        guard let pool = dbPool else { throw DBError.notConnected }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM imported_entries WHERE source = ?", arguments: [source])
            try db.execute(sql: "DELETE FROM imported_sources WHERE source = ?", arguments: [source])
        }
    }

    // MARK: - Entry count (for testing / UI)

    /// Rows of `source` in both stores.
    func entryCount(source: String) async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM dict.entries WHERE source = ?)
                     + (SELECT COUNT(*) FROM imported_entries WHERE source = ?)
                """, arguments: [source, source]) ?? 0
        }
    }

    func entryCount() async throws -> Int {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM dict.entries) + (SELECT COUNT(*) FROM imported_entries)
                """) ?? 0
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

    /// `Application Support/DictApp/user.sqlite`: everything the user creates.
    static func userDatabaseURL() -> URL {
        appSupportDirectory().appendingPathComponent("user.sqlite")
    }

    /// The 1.x database. Nothing reads it until #139 moves its data.
    static func legacyDatabaseURL() -> URL {
        appSupportDirectory().appendingPathComponent("dict.sqlite")
    }

    private static func appSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DictApp")
    }

    /// The bundled dictionary file. Still `seed.sqlite` until #140 renames it
    /// to `dictionaries.sqlite`.
    static func bundledDictionaryURL() -> URL? {
        Bundle.main.url(forResource: "seed", withExtension: "sqlite")
    }

    #if DEBUG
    /// UI-test hook `-resetDatabase`: deletes the user database and any 1.x
    /// database, each with its `-wal` and `-shm`, before `setup()`, for a
    /// deterministic fresh install without uninstalling (the simulator keeps
    /// its language and keyboard settings).
    static func removeDatabaseFiles() {
        for url in [userDatabaseURL(), legacyDatabaseURL()] {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
    }

    /// Unit-test seam: runs `body` on the writer, the connection a write to
    /// `dict.*` would use, so a test can prove the attached dictionary file
    /// is read-only. The app never calls it.
    func writeForTesting<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await pool.write(body)
    }
    #endif

    enum DBError: Error, LocalizedError {
        case notConnected
        case dictionaryMissing
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Database is not connected. Call setup() first."
            case .dictionaryMissing: return "The bundled dictionary file is missing."
            }
        }
    }
}
