// DatabaseService.swift
// The user database with the bundled dictionary file attached (Issue #138):
// connections, the user schema, FTS5 search, History, My words and imports.
// Also the move of a 1.x database into the user database (Issue #139), and
// the reopen of the dictionary file after the system invalidates it (#213).

import Foundation
import GRDB
import os

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
    /// preserved: each ordered bucket, then the tail. Rows are entries or,
    /// since #142, `SearchResult`s.
    static func assemble<Row: Identifiable>(
        buckets: [String: [Row]],
        tail: [Row],
        order: [String]
    ) -> [Row] where Row.ID == Int64? {
        var seen = Set<Int64>()
        var result: [Row] = []
        func append(_ entries: [Row]) {
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

    // MARK: Search by any form (Issue #142)
    //
    // 0136-word-forms.md, "Search path": a one-word query is also looked up
    // as an inflected form, and its lemmas' headword rows come right after
    // the exact matches, each with a `FormMatch`. The SQL is in
    // `DatabaseService`; the decisions below are pure.

    /// Which form step a sanitized query gets.
    enum FormStep: Equatable {
        /// Every letter Greek: look up `key`, the folded query, in
        /// `dict.form_lookup`.
        case greek(key: String)
        // #143 adds `english` for a query of a–z letters, through Morphy.
    }

    /// A query needs at least this many letters for the form step.
    static let formStepMinimumLetters = 2
    /// At most this many lemmas and lemma rows join one search.
    static let maximumFormLemmas = 5
    static let maximumLemmaRows = 10

    /// The form step for a sanitized query: one word of 2+ letters, every
    /// letter Greek (accents, case and final sigma are folded away). Several
    /// words, other or mixed scripts and digits get none.
    static func formStep(for sanitized: String) -> FormStep? {
        var letters = 0
        for scalar in sanitized.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                guard isGreek(scalar), scalar.properties.isAlphabetic else { return nil }
                letters += 1
            }
        }
        return letters >= formStepMinimumLetters ? .greek(key: foldGreek(sanitized)) : nil
    }

    /// A lemma the query is a form of, as the candidate query returns it.
    struct LemmaCandidate: Equatable, Sendable {
        /// The lemma's headword (NFC) and its folded search key.
        let word: String
        let wordNormalized: String
        let match: FormMatch
    }

    /// One row of a base search query: the entry, and whether it matched the
    /// query's key exactly (the first ranking term).
    struct RankedEntry: Equatable, Sendable {
        let entry: DictionaryEntry
        let isExact: Bool
    }

    /// Merges one bucket: the exact rows (the leading run of `ranked`, which
    /// is in rank order), then the lemma rows not already among them, then
    /// the remaining rows of `ranked` without the lemma rows, cut to `limit`.
    /// A lemma row that `ranked` has further down moves up and keeps its
    /// caption. Without lemma rows the result is `ranked` as it is.
    static func mergeLemmaBucket(ranked: [RankedEntry], lemmaRows: [SearchResult], limit: Int) -> [SearchResult] {
        let exact = ranked.prefix { $0.isExact }
        var seen = Set<Int64>()
        var result: [SearchResult] = []
        func append(_ row: SearchResult) {
            guard let id = row.id else { result.append(row); return }
            if seen.insert(id).inserted { result.append(row) }
        }
        exact.forEach { append(SearchResult(entry: $0.entry)) }
        lemmaRows.forEach(append)
        ranked.dropFirst(exact.count).forEach { append(SearchResult(entry: $0.entry)) }
        return Array(result.prefix(limit))
    }

    /// The lemma rows of the first `maximumLemmas` lemmas present in `rows`,
    /// which come ordered by candidate.
    static func capLemmas(_ rows: [SearchResult], maximumLemmas: Int = maximumFormLemmas) -> [SearchResult] {
        var lemmas: [String] = []
        return rows.filter { row in
            guard let lemma = row.formMatch?.lemma else { return false }
            if lemmas.contains(lemma) { return true }
            guard lemmas.count < maximumLemmas else { return false }
            lemmas.append(lemma)
            return true
        }
    }

    /// An FTS5 string literal: `"…"` with inner quotes doubled.
    static func ftsString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}


actor DatabaseService {
    static let shared = DatabaseService()

    /// The user database, with the dictionary file attached as `dict` on
    /// every connection (Issue #138).
    private var dbPool: DatabasePool?

    /// The move of a 1.x database, once started (Issue #139). Every method
    /// that touches user data awaits it first; Search does not.
    private var legacyMove: Task<Void, Never>?

    /// The `ATTACH` URI of the dictionary file, as `setup` built it. A
    /// reopen attaches it again on the writer (Issue #213).
    private var dictionaryURI = ""

    /// Bumped by every reopen of the dictionary file, never reset (Issue
    /// #213). A call that fails with an I/O error reopens only if no reopen
    /// happened since it started.
    private var reopenGeneration = 0

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
        let uri = Self.dictionaryURI(dictionaryURL)
        var config = Configuration()
        // Wait instead of failing with SQLITE_BUSY if another pool on the same
        // file is mid-write (a test reopening the shared service).
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in try Self.attachDictionary(db, uri: uri) }
        let pool = try DatabasePool(path: userPath, configuration: config)
        try Self.migrator.migrate(pool)
        dbPool = pool
        dictionaryURI = uri
        // A move belongs to the pool it writes; a new pool starts without one.
        legacyMove = nil
    }

    /// The read-only, immutable `ATTACH` URI of the dictionary file at
    /// `url`, its path percent-encoded.
    static func dictionaryURI(_ url: URL) -> String {
        let path = url.path
        return "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
            + "?mode=ro&immutable=1"
    }

    /// Attaches the dictionary file as `dict`: on every new connection, and
    /// on the writer again after a reopen (Issue #213).
    private static func attachDictionary(_ db: Database, uri: String) throws {
        try db.execute(sql: "ATTACH DATABASE ? AS dict", arguments: [uri])
    }

    // MARK: - Invalidated dictionary file (Issue #213)
    //
    // After an install over the app, the old bundle's hard link of the
    // dictionary file can go while the app has the file open. iOS SQLite then
    // invalidates the open descriptors, and every `dict.*` read that misses a
    // connection's page cache fails with a disk I/O error, while a new
    // connection reads the file. Every public read runs through `read` below,
    // and the import's write, the one write that reads `dict`, through
    // `dictionaryWrite`: on SQLITE_IOERR they reopen the file and run the call
    // once more. A second failure throws as before. History and My words
    // writes touch only `user.sqlite`, so they call `pool.write` directly and
    // throw as before. Not wrapped either: `setup`, the 1.x move and
    // `writeForTesting`. The file is never copied.

    private static let logger = Logger(subsystem: "com.kyukhin.DictApp", category: "database")

    #if DEBUG
    /// Unit-test seam: how many times the dictionary file was reopened. It
    /// only grows.
    var dictionaryReopenCount: Int { reopenGeneration }
    #endif

    /// Whether `error` may come from the invalidated dictionary file, so the
    /// call is reopened and run once more: SQLITE_IOERR from any statement but
    /// `COMMIT`. A failed `COMMIT`, which GRDB reports with the `sql` "COMMIT
    /// TRANSACTION", wrote only `user.sqlite` and may have taken effect, so it
    /// is never retried.
    private static func isDictionaryIOError(_ error: DatabaseError) -> Bool {
        error.resultCode == .SQLITE_IOERR && !(error.sql?.uppercased().hasPrefix("COMMIT") ?? false)
    }

    /// `pool.read`, run once more after a reopen if it fails with SQLITE_IOERR.
    private func read<T>(_ pool: DatabasePool, _ value: @escaping @Sendable (Database) throws -> T) async throws -> T {
        let generation = reopenGeneration
        do {
            return try await pool.read(value)
        } catch let error as DatabaseError where Self.isDictionaryIOError(error) {
            reopenDictionary(pool, after: error, generation: generation)
            return try await pool.read(value)
        }
    }

    /// `pool.write` for the import, the one write that reads `dict` (its key
    /// check): run once more after a reopen if a statement fails with
    /// SQLITE_IOERR. The failed transaction has rolled back. A failed
    /// `COMMIT` throws.
    private func dictionaryWrite<T>(_ pool: DatabasePool,
                                    _ updates: @escaping @Sendable (Database) throws -> T) async throws -> T {
        let generation = reopenGeneration
        do {
            return try await pool.write(updates)
        } catch let error as DatabaseError where Self.isDictionaryIOError(error) {
            reopenDictionary(pool, after: error, generation: generation)
            return try await pool.write(updates)
        }
    }

    /// Opens new connections to the dictionary file, unless a call that
    /// failed too already did since `generation`:
    /// 1. readers: idle ones close now, busy ones when their read ends; each
    ///    new reader attaches the file in `prepareDatabase`;
    /// 2. the writer: `DETACH` and `ATTACH` again, queued on the writer
    ///    between two writes, never inside a transaction.
    /// It never suspends, so no other call runs between the generation bump
    /// and both steps: a call that sees the new generation reads from new
    /// readers, and an import it retries runs after the re-attach. If the
    /// re-attach fails, the writer stays without `dict` until a restart.
    private func reopenDictionary(_ pool: DatabasePool, after error: DatabaseError, generation: Int) {
        guard generation == reopenGeneration else { return }
        reopenGeneration += 1
        let started = Date()
        let code = error.extendedResultCode.rawValue
        let uri = dictionaryURI
        pool.invalidateReadOnlyConnections()
        pool.asyncWriteWithoutTransaction { db in
            do {
                try db.execute(sql: "DETACH DATABASE dict")
                try Self.attachDictionary(db, uri: uri)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Self.logger.notice("Reopened the dictionary file after SQLite error \(code) in \(ms) ms")
            } catch {
                // The result code only: never the SQL or its arguments.
                let failure = (error as? DatabaseError)?.extendedResultCode.rawValue ?? -1
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Self.logger.error(
                    "Reopening the dictionary file after SQLite error \(code) failed in \(ms) ms with SQLite error \(failure)")
            }
        }
    }

    // MARK: - 1.x migration (Issue #139)

    /// Starts moving the 1.x database at `legacyURL` into the user database
    /// as a detached utility task, if the file exists, and returns at once.
    /// Launch calls it before showing the UI, so every user-data call finds
    /// the move. Returns the move, which tests await.
    @discardableResult
    func startLegacyMigration(legacyURL: URL = DatabaseService.legacyDatabaseURL()) -> Task<Void, Never>? {
        guard let pool = dbPool, FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        let previous = legacyMove
        let move = Task.detached(priority: .utility) {
            await previous?.value
            await LegacyMigration.run(legacyURL: legacyURL, pool: pool)
        }
        legacyMove = move
        return move
    }

    /// The pool, once a running 1.x move has ended: committed, or failed and
    /// left for the next launch. Every method that touches user data starts
    /// here, so History, My words, imports and their counts never show a
    /// half-moved state.
    private func userPool() async throws -> DatabasePool {
        await legacyMove?.value
        guard let pool = dbPool else { throw DBError.notConnected }
        return pool
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
    /// raw key (the `is_exact` column, #142), then a prefix match, then FTS
    /// `rank`. Takes `relevanceArguments(_:)`.
    private static let relevanceOrder = """
        is_exact DESC,
            (word_normalized LIKE ? COLLATE NOCASE OR word_normalized LIKE ? COLLATE NOCASE) DESC,
            rank
        """

    private static func relevanceArguments(_ fts: (match: String, rankKey: String, rawKey: String)) -> StatementArguments {
        [fts.rankKey + "%", fts.rawKey + "%"]
    }

    /// The sources of the imported dictionaries.
    private static func importedSources(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT source FROM imported_sources"))
    }

    /// The `UNION ALL` of the search branches, one per store, each with the
    /// entry columns plus `rank`: rows matching `match` and `filter` (SQL on
    /// the entry `e`, with its arguments). `sources`: the sources to keep
    /// (`nil`: every source). `ids`: rows to leave out. `withImports` adds
    /// the imported branch.
    private static func searchBranches(
        match: String, filter: (sql: String, arguments: StatementArguments)? = nil,
        sources: [String]?, excluding ids: [Int64] = [], withImports: Bool
    ) -> (sql: String, arguments: StatementArguments) {
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
            if let filter {
                branch += " AND " + filter.sql
                arguments += filter.arguments
            }
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
        return (branches.joined(separator: "\nUNION ALL\n"), arguments)
    }

    /// Rows matching the query, ranked by `order` and cut to `limit`, each
    /// with `is_exact`: whether its `word_normalized` is the folded or the
    /// raw key (#142). `order` names columns of the union and `is_exact`.
    private static func rankedEntries(
        _ db: Database, fts: (match: String, rankKey: String, rawKey: String), sources: [String]?,
        excluding ids: [Int64] = [], withImports: Bool, order: String, orderArguments: StatementArguments,
        limit: Int
    ) throws -> [Search.RankedEntry] {
        let union = searchBranches(match: fts.match, sources: sources, excluding: ids, withImports: withImports)
        var arguments: StatementArguments = [fts.rankKey, fts.rawKey]
        arguments += union.arguments
        arguments += orderArguments
        arguments += [limit]
        return try Row.fetchAll(db, sql: """
            SELECT *, (word_normalized = ? COLLATE NOCASE OR word_normalized = ? COLLATE NOCASE) AS is_exact FROM (
            \(union.sql)
            )
            ORDER BY \(order)
            LIMIT ?
            """, arguments: arguments)
            .map { row in Search.RankedEntry(entry: try DictionaryEntry(row: row), isExact: row["is_exact"]) }
    }

    /// Prefix search using FTS5 with relevance ranking:
    ///   Priority 1: exact match (word == query)
    ///   Priority 2: starts-with (word LIKE 'query%')
    ///   Priority 3: FTS relevance (rank)
    /// The unicode61 tokenizer handles both Latin and Cyrillic input. The
    /// entries of `searchResults`, lemma rows included (#142).
    func search(query: String, limit: Int = 50, enabledSources: Set<String>? = nil) async throws -> [DictionaryEntry] {
        try await searchResults(query: query, limit: limit, enabledSources: enabledSources).map(\.entry)
    }

    /// Relevance search, as `search`, with the form step (#142): when the
    /// query is an inflected form, its lemmas' rows follow the exact matches,
    /// each with its `FormMatch`.
    func searchResults(query: String, limit: Int = 50, enabledSources: Set<String>? = nil) async throws -> [SearchResult] {
        // If an explicit (non-nil) empty set is passed, no sources are enabled — return immediately.
        if let sources = enabledSources, sources.isEmpty { return [] }

        guard let pool = dbPool else { throw DBError.notConnected }
        let sanitized = sanitizeFTS(query)
        guard !sanitized.isEmpty else { return [] }
        // Issue #87: Greek queries also match their folded form.
        let fts = Search.ftsQuery(sanitized: sanitized)
        let formStep = Self.formStep(for: sanitized)
        return try await read(pool) { db in
            let imported = try Self.importedSources(db)
            let sources = enabledSources.map { Array($0) }
            let withImports = enabledSources.map { !imported.isDisjoint(with: $0) } ?? !imported.isEmpty
            let ranked = try Self.rankedEntries(
                db, fts: fts, sources: sources, withImports: withImports,
                order: Self.relevanceOrder, orderArguments: Self.relevanceArguments(fts), limit: limit
            )
            let lemmaRows = try Self.lemmaRows(db, step: formStep, sources: sources, withImports: withImports)
            return Search.mergeLemmaBucket(ranked: ranked, lemmaRows: lemmaRows, limit: limit)
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
    /// The entries of `searchPreferredResults`, lemma rows included (#142).
    func searchPreferred(
        query: String,
        groups: [[String]],
        enabledSources: Set<String>,
        topN: Int = Search.preferredDictionaryTopN,
        limit: Int = 50
    ) async throws -> [DictionaryEntry] {
        try await searchPreferredResults(query: query, groups: groups, enabledSources: enabledSources,
                                         topN: topN, limit: limit).map(\.entry)
    }

    /// "Preferred dictionary first", as `searchPreferred`, with the form step
    /// (#142): each pair bucket merges its lemma rows after its exact rows,
    /// then takes its top N, before the tail query, so the tail excludes
    /// them. Lemma rows of sources outside every pair group join the tail.
    func searchPreferredResults(
        query: String,
        groups: [[String]],
        enabledSources: Set<String>,
        topN: Int = Search.preferredDictionaryTopN,
        limit: Int = 50
    ) async throws -> [SearchResult] {
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
        let formStep = Self.formStep(for: sanitized)

        return try await read(pool) { db in
            let imported = try Self.importedSources(db)
            let lemmaRows = try Self.lemmaRows(db, step: formStep, sources: Array(enabledSources),
                                               withImports: !imported.isDisjoint(with: enabledSources))
            var buckets: [String: [SearchResult]] = [:]
            var bucketOrder: [String] = []
            var takenIds: [Int64] = []

            for (index, members) in enabledGroups.enumerated() {
                // Index, not joined IDs: a custom ID may contain any separator.
                let key = String(index)
                let ranked = try Self.rankedEntries(
                    db, fts: fts, sources: members, withImports: !imported.isDisjoint(with: members),
                    order: Self.relevanceOrder, orderArguments: Self.relevanceArguments(fts), limit: topN
                )
                let rows = Search.mergeLemmaBucket(
                    ranked: ranked, lemmaRows: lemmaRows.filter { members.contains($0.entry.source) }, limit: topN
                )
                buckets[key] = rows
                bucketOrder.append(key)
                takenIds += rows.compactMap(\.id)
            }

            // Relevance tail over all enabled sources, excluding bucketed IDs,
            // with the lemma rows of sources outside every group (#142).
            var tail: [SearchResult] = []
            let remaining = limit - takenIds.count
            if remaining > 0 {
                let ranked = try Self.rankedEntries(
                    db, fts: fts, sources: Array(enabledSources), excluding: takenIds,
                    withImports: !imported.isDisjoint(with: enabledSources),
                    order: "rank", orderArguments: [], limit: remaining
                )
                let grouped = Set(enabledGroups.joined())
                tail = Search.mergeLemmaBucket(
                    ranked: ranked, lemmaRows: lemmaRows.filter { !grouped.contains($0.entry.source) }, limit: remaining
                )
            }

            return Search.assemble(buckets: buckets, tail: tail, order: bucketOrder)
        }
    }

    // MARK: - Search by any form (Issue #142)
    //
    // 0136-word-forms.md, "Search path". Inside the search's read: the
    // query's lemmas from the forms tables (`dict.form_lookup`, through its
    // primary-key prefix), then their headword rows in the enabled
    // dictionaries. The merge is the pure `Search.mergeLemmaBucket`.

    #if DEBUG
    /// Unit-test seam: turns the form step off, so a test compares search
    /// with and without it. The app never sets it.
    static var lemmaStepEnabled = true
    #endif

    /// The Greek lemma candidates of a folded query (both arguments): a probe
    /// of the `form_lookup` primary-key prefix, then the lemma and tag set
    /// by id. A lookup that missed the key's first column would scan the
    /// table (6× slower in the prototype); a unit test checks the plan.
    static let greekLemmaCandidatesSQL = """
        SELECT l.word, l.word_normalized, t.tags
        FROM dict.form_lookup f
        JOIN dict.lemma l ON l.id = f.lemma_id
        JOIN dict.tagset t ON t.id = f.tagset_id
        WHERE f.form_norm = ? AND l.word_normalized <> ?
        ORDER BY CASE l.pos WHEN 'verb' THEN 0 WHEN 'noun' THEN 1 WHEN 'adj' THEN 2 ELSE 3 END,
                 l.word, l.pos
        """

    /// The form step for a sanitized query, or `nil`.
    private static func formStep(for sanitized: String) -> Search.FormStep? {
        #if DEBUG
        guard lemmaStepEnabled else { return nil }
        #endif
        return Search.formStep(for: sanitized)
    }

    /// The lemmas the query is a form of, ordered verb, noun, adj, others,
    /// then by word, without the lemmas whose key is the query's own (a base
    /// form adds nothing). One per headword: the first of its parts of speech
    /// (κύριε: κύριος, noun). Lemmas that fold alike but are spelt apart
    /// (γέρου: γέρος and γερός) each stay, so a row is captioned with its
    /// own lemma (`lemmaRows`). Unlimited: the lemma-row query's limit
    /// applies after the enabled filter.
    private static func lemmaCandidates(_ db: Database, step: Search.FormStep) throws -> [Search.LemmaCandidate] {
        switch step {
        case .greek(let key):
            let rows = try Row.fetchAll(db, sql: greekLemmaCandidatesSQL, arguments: [key, key])
            var words = Set<String>()
            return rows.compactMap { row in
                let word: String = row["word"], wordNormalized: String = row["word_normalized"]
                guard words.insert(word).inserted else { return nil }
                let tags = Set((row["tags"] as String).split(separator: " ").map(String.init))
                return Search.LemmaCandidate(word: word, wordNormalized: wordNormalized,
                                             match: FormMatch(lemma: word, analysis: .greek(tags: tags)))
            }
        }
    }

    /// The headword rows of the query's lemmas in the enabled dictionaries,
    /// each with its `FormMatch`: ordered by candidate, then rank, at most
    /// `Search.maximumLemmaRows` rows of `Search.maximumFormLemmas` lemmas.
    /// One query of the base query's shape: an FTS filter on the
    /// `word_normalized` column, which uses the index, plus the exact key.
    /// Bundled Greek rows store the folded key and imported rows the word as
    /// it is, so each lemma matches both.
    private static func lemmaRows(_ db: Database, step: Search.FormStep?, sources: [String]?,
                                  withImports: Bool) throws -> [SearchResult] {
        guard let step else { return [] }
        let candidates = try lemmaCandidates(db, step: step)
        guard !candidates.isEmpty else { return [] }

        let keysPerCandidate = candidates.map { Array(Set([$0.wordNormalized, $0.word])).sorted() }
        let keys = keysPerCandidate.flatMap { $0 }
        let match = "word_normalized : (" + keys.map(Search.ftsString).joined(separator: " OR ") + ")"
        let union = searchBranches(
            match: match,
            filter: ("e.word_normalized COLLATE NOCASE IN (\(keys.map { _ in "?" }.joined(separator: ", ")))",
                     StatementArguments(keys)),
            sources: sources, withImports: withImports
        )
        var whens: [String] = []
        var arguments = StatementArguments()
        for (index, candidateKeys) in keysPerCandidate.enumerated() {
            whens.append("WHEN " + candidateKeys.map { _ in "word_normalized = ? COLLATE NOCASE" }
                .joined(separator: " OR ") + " THEN \(index)")
            arguments += StatementArguments(candidateKeys)
        }
        arguments += union.arguments
        arguments += [Search.maximumLemmaRows]
        let rows = try Row.fetchAll(db, sql: """
            SELECT *, CASE \(whens.joined(separator: " ")) END AS candidate FROM (
            \(union.sql)
            )
            ORDER BY candidate, rank
            LIMIT ?
            """, arguments: arguments)
        return Search.capLemmas(try rows.compactMap { row in
            guard let index: Int = row["candidate"], candidates.indices.contains(index) else { return nil }
            let entry = try DictionaryEntry(row: row)
            // Lemmas that fold alike share a key, which orders the rows; the
            // caption names the lemma the row spells (γερός, not γέρος), else
            // the key's first lemma.
            let candidate = candidates.first { $0.word == entry.word } ?? candidates[index]
            return SearchResult(entry: entry, formMatch: candidate.match)
        })
    }

    // MARK: - Entries by key (Issue #138)

    /// The entry `key` names: the dictionary file first, then the imported
    /// dictionaries; `nil` when neither has it. A disabled source resolves
    /// too: the enabled set only filters Search.
    func entry(for key: EntryKey) async throws -> DictionaryEntry? {
        let pool = try await userPool()
        return try await read(pool) { db in try Self.entry(for: key, in: db) }
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
        let pool = try await userPool()
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
        let pool = try await userPool()
        return try await read(pool) { db in
            try HistoryItem
                .order(Column("looked_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func clearHistory() async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM history")
        }
    }

    // MARK: - My words (Issue #138)
    //
    // Until #158 replaces the Bookmarks tab, the Definition star and the tab
    // read and write My words, by stable entry key.

    func addToMyWords(_ key: EntryKey) async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO my_words(source, word) VALUES (?, ?)",
                arguments: [key.source, key.word]
            )
        }
    }

    func removeFromMyWords(_ key: EntryKey) async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(
                sql: "DELETE FROM my_words WHERE source = ? AND word = ?",
                arguments: [key.source, key.word]
            )
        }
    }

    func isInMyWords(_ key: EntryKey) async throws -> Bool {
        let pool = try await userPool()
        return try await read(pool) { db in
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
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: "SELECT source, word FROM my_words ORDER BY added_at DESC")
                .compactMap { row in
                    try Self.entry(for: EntryKey(source: row["source"], word: row["word"]), in: db)
                }
        }
    }

    func clearMyWords() async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM my_words")
        }
    }

    // MARK: - Metadata & Statistics

    /// Metadata of every bundled dictionary, in dictionary file order.
    func fetchMetadata() async throws -> [DictMetadata] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await read(pool) { db in
            try DictMetadata.fetchAll(db, sql: """
                SELECT source, display_name, version, license, url, word_count, description
                FROM dict.dict_metadata ORDER BY rowid
                """)
        }
    }

    /// Fetch metadata for a single dictionary source.
    func fetchMetadata(source: String) async throws -> DictMetadata? {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await read(pool) { db in
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
        let pool = try await userPool()
        return try await read(pool) { db in
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
        let pool = try await userPool()
        let raw = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: url))
        let rows = raw.compactMap { item -> ImportedRow? in
            guard let word = item["word"], let definition = item["definition"] else { return nil }
            return ImportedRow(word: word, definition: definition,
                               phonetic: item["phonetic"] ?? "", pos: item["pos"] ?? "")
        }
        return try await insertImported(rows, source: source, into: pool)
    }

    /// Import entries from an external SQLite file that has the same `entries` schema.
    func importSQLite(at url: URL, source: String) async throws -> Int {
        let pool = try await userPool()
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
        return try await insertImported(rows, source: source, into: pool)
    }

    private struct ImportedRow: Sendable {
        let word: String
        let definition: String
        let phonetic: String
        let pos: String
    }

    /// Inserts `rows` under `source` in one transaction and registers the
    /// source once it has rows. Returns the number of rows read, as 1.4.0 did.
    private func insertImported(_ rows: [ImportedRow], source: String,
                                into pool: DatabasePool) async throws -> Int {
        try await dictionaryWrite(pool) { db in
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
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM imported_entries WHERE source = ?", arguments: [source])
            try db.execute(sql: "DELETE FROM imported_sources WHERE source = ?", arguments: [source])
        }
    }

    // MARK: - Entry count (for testing / UI)

    /// Rows of `source` in both stores.
    func entryCount(source: String) async throws -> Int {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM dict.entries WHERE source = ?)
                     + (SELECT COUNT(*) FROM imported_entries WHERE source = ?)
                """, arguments: [source, source]) ?? 0
        }
    }

    func entryCount() async throws -> Int {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM dict.entries) + (SELECT COUNT(*) FROM imported_entries)
                """) ?? 0
        }
    }

    func historyCount() async throws -> Int {
        let pool = try await userPool()
        return try await read(pool) { db in
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

    /// The 1.x database. Launch moves its user data into the user database
    /// and deletes it (Issue #139).
    static func legacyDatabaseURL() -> URL {
        appSupportDirectory().appendingPathComponent("dict.sqlite")
    }

    private static func appSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DictApp")
    }

    /// The bundled dictionary file, `dictionaries.sqlite`.
    static func bundledDictionaryURL() -> URL? {
        Bundle.main.url(forResource: DictionaryFile.resourceName, withExtension: DictionaryFile.resourceExtension)
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

// MARK: - 1.x migration (Issue #139)

/// Moves the user data of a 1.x database (`Application Support/DictApp/
/// dict.sqlite`) into the user database, then deletes the 1.x file. That
/// file holds a copy of every bundled dictionary next to the user's imports,
/// History and bookmarks; only the user data moves.
///
/// One write on the user database writer: the 1.x file is attached as
/// `legacy` outside the transaction, and one transaction copies the rows and
/// sets the `user_meta` marker. Crash safety:
/// - killed before the commit: nothing changed, the next launch moves again;
/// - killed after the commit: the marker is set, the next launch only deletes;
/// - an unreadable file is logged and kept for the next launch. It is never
///   deleted without a committed copy.
/// Reads only columns that every 1.x schema (1.1.0+) has.
enum LegacyMigration {
    /// The `user_meta` key; its value is the time the move committed.
    static let markerKey = "legacy_migration"

    /// Posted when the move has committed, so Search re-runs its query once.
    static let didCommit = Notification.Name("LegacyMigrationDidCommit")

    #if DEBUG
    /// Test seams. `failBeforeCommit` throws inside the transaction, like a
    /// kill before the commit. `failBeforeDelete` stops after the commit,
    /// like a kill before the delete. `beforeCopy` is the delay seam: it runs
    /// on the writer inside the transaction, before the copy, so a test can
    /// hold the move there.
    static var failBeforeCommit = false
    static var failBeforeDelete = false
    static var beforeCopy: (@Sendable () -> Void)?

    struct InjectedFailure: Error {}
    #endif

    /// What one move copied, for the log.
    struct Moved: Sendable {
        var imported = 0
        var history = 0
        var myWords = 0
    }

    /// Moves `legacyURL` into the user database of `pool`, then deletes it.
    /// Never throws: a failure is logged and the file stays for the next
    /// launch, so the calls waiting for the move go on with the user
    /// database alone.
    static func run(legacyURL: URL, pool: DatabasePool) async {
        let started = Date()
        do {
            let moved = try await pool.writeWithoutTransaction { db in try move(legacyURL, in: db) }
            if moved != nil {
                NotificationCenter.default.post(name: didCommit, object: nil)
            }
            #if DEBUG
            if failBeforeDelete { return }
            #endif
            try deleteFiles(legacyURL)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if let moved {
                print("LegacyMigration: moved \(moved.imported) imported rows, \(moved.history) History rows "
                      + "and \(moved.myWords) bookmarks, then deleted the 1.x database, in \(ms) ms")
            } else {
                print("LegacyMigration: deleted the 1.x database an earlier launch had moved")
            }
        } catch {
            print("LegacyMigration: \(legacyURL.lastPathComponent) stays for the next launch: \(error)")
        }
    }

    /// The move, on the writer outside a transaction. `nil` when the marker
    /// is already set: an earlier launch committed and was killed before the
    /// delete.
    private static func move(_ legacyURL: URL, in db: Database) throws -> Moved? {
        if try String.fetchOne(db, sql: "SELECT value FROM user_meta WHERE key = ?", arguments: [markerKey]) != nil {
            return nil
        }
        // ATTACH and DETACH cannot run inside a transaction. Not read-only:
        // SQLite may have to replay the 1.x WAL.
        try db.execute(sql: "ATTACH DATABASE ? AS legacy", arguments: [legacyURL.path])
        var moved = Moved()
        do {
            try db.inTransaction {
                moved = try copy(db)
                #if DEBUG
                if failBeforeCommit { throw InjectedFailure() }
                #endif
                return .commit
            }
        } catch {
            try? db.execute(sql: "DETACH DATABASE legacy")
            throw error
        }
        try db.execute(sql: "DETACH DATABASE legacy")
        return moved
    }

    /// The copy, inside the transaction, with the 1.x file attached as `legacy`.
    private static func copy(_ db: Database) throws -> Moved {
        #if DEBUG
        beforeCopy?()
        #endif
        var moved = Moved()
        // Imported dictionaries: every 1.x row whose key the dictionary file
        // lacks. This carries custom imports and imports named like a bundled
        // source, and drops the 1.x copy of the bundled rows. The search key
        // is the word, as on import; the triggers fill `imported_fts`.
        try db.execute(sql: """
            INSERT OR IGNORE INTO imported_entries(word, word_normalized, definition, phonetic, pos, source, created_at)
            SELECT l.word, l.word, l.definition, COALESCE(l.phonetic, ''), COALESCE(l.pos, ''), l.source, l.created_at
            FROM legacy.entries l
            WHERE NOT EXISTS (SELECT 1 FROM dict.entries d WHERE d.word = l.word COLLATE NOCASE AND d.source = l.source)
            ORDER BY l.id
            """)
        moved.imported = db.changesCount
        // One row per imported dictionary, dated by its earliest row. A source
        // that an import after a failed move registered keeps its row.
        try db.execute(sql: """
            INSERT OR IGNORE INTO imported_sources(source, imported_at)
            SELECT source, COALESCE(MIN(created_at), datetime('now')) FROM imported_entries GROUP BY source
            """)
        // History: `source` exists from 1.3.0 on (#6); older rows get ''. On
        // a word already in History, the newer `looked_at` wins.
        let hasSource = try Row.fetchAll(db, sql: "PRAGMA legacy.table_info(history)")
            .contains { ($0["name"] as String?) == "source" }
        try db.execute(sql: """
            INSERT INTO history(word, source, looked_at)
            SELECT word, \(hasSource ? "source" : "''"), looked_at FROM legacy.history WHERE true ORDER BY id
            ON CONFLICT(word) DO UPDATE SET source = excluded.source, looked_at = excluded.looked_at
            WHERE excluded.looked_at > COALESCE(history.looked_at, '')
            """)
        moved.history = db.changesCount
        // My words: each bookmark's entry key, dated by the bookmark.
        try db.execute(sql: """
            INSERT OR IGNORE INTO my_words(source, word, added_at)
            SELECT e.source, e.word, COALESCE(b.created_at, datetime('now'))
            FROM legacy.bookmarks b JOIN legacy.entries e ON e.id = b.entry_id
            ORDER BY b.id
            """)
        moved.myWords = db.changesCount
        try db.execute(sql: "INSERT OR REPLACE INTO user_meta(key, value) VALUES (?, datetime('now'))",
                       arguments: [markerKey])
        return moved
    }

    /// Deletes the 1.x file with its `-wal` and `-shm`. The sidecars go
    /// first, so a kill in between leaves the file, and with it the next
    /// launch's delete, rather than an orphan sidecar.
    private static func deleteFiles(_ legacyURL: URL) throws {
        for suffix in ["-wal", "-shm", ""] {
            let path = legacyURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }
}
