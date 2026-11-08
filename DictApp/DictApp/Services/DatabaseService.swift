// DatabaseService.swift
// The user database with the bundled dictionary file attached (Issue #138):
// connections, the user schema, FTS5 search, History, My words and imports.
// Also the move of a 1.x database into the user database (Issue #139), the
// reopen of the dictionary file after the system invalidates it (#213), and
// the language packs attached next to it, read across files (#237).

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
        /// `ell.form_lookup`.
        case greek(key: String)
        /// Every letter a–z, any case (Issue #143): look up `word`,
        /// lowercased (Morphy's step 0), through `Morphy`.
        case english(word: String)
    }

    /// A query needs at least this many letters for the form step.
    static let formStepMinimumLetters = 2
    /// At most this many lemmas and lemma rows join one search.
    static let maximumFormLemmas = 5
    static let maximumLemmaRows = 10

    /// The form step for a sanitized query: one word of 2+ letters, every
    /// letter a–z in any case (English, #143) or every letter Greek
    /// (accents, case and final sigma are folded away). Several words,
    /// other or mixed scripts and digits get none.
    static func formStep(for sanitized: String) -> FormStep? {
        // Issue #143: English, a–z only, so `lowercased()` ignores the locale.
        if sanitized.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("A"..."Z").contains($0) }) {
            return sanitized.unicodeScalars.count >= formStepMinimumLetters ? .english(word: sanitized.lowercased()) : nil
        }
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

    /// The sources an English form step reads lemma rows from (Kirill,
    /// 2026-11-02, #143): the enabled ones (`nil`: every one) whose headwords
    /// are English, so Spanish WordNet's do never reads as a form of doing.
    static func englishLemmaSources(enabled: [String]?, english: Set<String>) -> [String] {
        (enabled.map { $0.filter(english.contains) } ?? Array(english)).sorted()
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


// MARK: - Dictionary files (Issue #237)

/// The file attached under each schema name of `DictionarySchemas.all`: the
/// bundle as `dict`, and every pack as its installed file or the stub
/// (0237, "Connection layout"). `prepareDatabase` runs on GRDB's queues, so
/// it reads this lock-protected snapshot, never the actor. An install or a
/// removal changes it, then `DatabaseService.attachPacks` re-attaches.
final class DictionaryFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var uris: [String: String]
    private var installedSchemas: Set<String>
    private let stubURI: String

    /// `packs`: the installed file of each pack; every other pack gets the
    /// stub. A file whose header is not `DictionaryFile.formatVersion` gets
    /// the stub too.
    init(bundle: URL, packs: [PackID: URL], stub: URL) {
        stubURI = DatabaseService.dictionaryURI(stub)
        var uris = [DictionarySchemas.bundle: DatabaseService.dictionaryURI(bundle)]
        var installed: Set<String> = [DictionarySchemas.bundle]
        for pack in PackID.all {
            if let file = packs[pack], DictionaryFile.headerFormat(of: file) == DictionaryFile.formatVersion {
                uris[pack.schema] = DatabaseService.dictionaryURI(file)
                installed.insert(pack.schema)
            } else {
                uris[pack.schema] = stubURI
            }
        }
        self.uris = uris
        installedSchemas = installed
    }

    /// The schemas attached to a file rather than the stub; always `dict`.
    var installed: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return installedSchemas
    }

    /// The `ATTACH` URI of `schema`.
    func uri(of schema: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return uris[schema] ?? stubURI
    }

    /// Points `pack` at `file`, or at the stub for `nil`. Returns whether the
    /// snapshot changed.
    @discardableResult
    func set(_ pack: PackID, file: URL?) -> Bool {
        let uri = file.map(DatabaseService.dictionaryURI) ?? stubURI
        lock.lock()
        defer { lock.unlock() }
        guard uris[pack.schema] != uri else { return false }
        uris[pack.schema] = uri
        if file == nil { installedSchemas.remove(pack.schema) } else { installedSchemas.insert(pack.schema) }
        return true
    }

    /// Attaches every schema, the bundle first: on every new connection.
    func attachAll(_ db: Database) throws {
        for schema in DictionarySchemas.all {
            try attach(schema, in: db)
        }
    }

    /// Attaches `schema` to its current file.
    func attach(_ schema: String, in db: Database) throws {
        try db.execute(sql: "ATTACH DATABASE ? AS \(schema)", arguments: [uri(of: schema)])
    }
}

actor DatabaseService {
    static let shared = DatabaseService()

    /// The user database, with the dictionary file attached as `dict` on
    /// every connection (Issue #138), and every language pack under its
    /// schema name (#237).
    private var dbPool: DatabasePool?

    /// The move of a 1.x database, once started (Issue #139). Every method
    /// that touches user data awaits it first; Search does not.
    private var legacyMove: Task<Void, Never>?

    /// The file of each schema name, as `setup` and the pack installs set
    /// it. A reopen attaches them again on the writer (Issues #213, #237).
    private var files: DictionaryFiles?

    /// Which file holds which dictionary (#237). Read after `setup` and
    /// after every change of an installed pack.
    private var schemas = DictionarySchemas.bundleOnly

    /// Bumped by every reopen of the dictionary file, never reset (Issue
    /// #213). A call that fails with an I/O error reopens only if no reopen
    /// happened since it started.
    private var reopenGeneration = 0

    /// `nextNewWords`' arrangements before enrolled words drop out (0130),
    /// per language, set of lists and order, until a list changes or the
    /// service reopens. `listGeneration` counts those changes, so an
    /// arrangement read across one is not cached.
    private var arrangements: [ArrangementKey: [WordListItem]] = [:]
    private var listGeneration = 0

    private struct ArrangementKey: Hashable {
        let lang: String
        let lists: Set<WordListID>
        let order: NewWordOrder
    }

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
    /// dictionary file attached and every pack name on the stub (#237: the
    /// launch scan attaches the installed packs next, `PackService.prepare`),
    /// and migrates it. Nothing is copied or unpacked, so this takes
    /// milliseconds.
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
    /// `dictionaryURL` attached as `dict`, each pack of `packFiles` under its
    /// schema name and the bundled stub for every other pack (#237), and
    /// migrates it. Test seam: unit tests pass a temp user database, a
    /// `TestDictionary` file or the bundled one, and `PackFixtures` files.
    func setup(userPath: String, dictionaryURL: URL, packFiles: [PackID: URL] = [:]) async throws {
        guard let stubURL = Self.bundledStubURL() else { throw DBError.dictionaryMissing }
        let files = DictionaryFiles(bundle: dictionaryURL, packs: packFiles, stub: stubURL)
        var config = Configuration()
        // Wait instead of failing with SQLITE_BUSY if another pool on the same
        // file is mid-write (a test reopening the shared service).
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in try files.attachAll(db) }
        let pool = try DatabasePool(path: userPath, configuration: config)
        try Self.migrator.migrate(pool)
        let installed = files.installed
        let schemas = try await pool.read { db in try Self.dictionarySchemas(db, installed: installed) }
        dbPool = pool
        self.files = files
        self.schemas = schemas
        // A move belongs to the pool it writes; a new pool starts without one.
        legacyMove = nil
        wordListsDidChange()
    }

    /// The read-only, immutable `ATTACH` URI of the dictionary file at
    /// `url`, its path percent-encoded.
    static func dictionaryURI(_ url: URL) -> String {
        let path = url.path
        return "file:" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
            + "?mode=ro&immutable=1"
    }

    /// Which file holds which dictionary: the rows of
    /// `DictionarySchemas.sourcesSQL`.
    private static func dictionarySchemas(_ db: Database, installed: Set<String>) throws -> DictionarySchemas {
        let rows = try Row.fetchAll(db, sql: DictionarySchemas.sourcesSQL)
        return DictionarySchemas(sources: rows.map { (schema: $0["schema"], source: $0["source"]) },
                                 installed: installed)
    }

    // MARK: - Language packs (Issue #237)

    /// The pack catalog of the attached bundle (`dict.catalog_*`), read
    /// through the pool after `setup` (0237, "Launch", step 3): no
    /// connection is opened on the bundle (#111).
    func packCatalog() async throws -> PackCatalog {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await read(pool) { db in try PackCatalog.read(db) }
    }
    //
    // 0237, "Connection layout": an install, a removal or an update changes
    // the snapshot, then re-attaches, as #213's reopen does: idle readers
    // close now and busy ones when their read ends, so every new reader
    // attaches the new file in `prepareDatabase`; the writer detaches and
    // attaches each changed name between two writes. The generation bump
    // lets a read that fails meanwhile retry once on a new reader.

    /// Points each pack of `changes` at its new file (`nil`: the stub) on
    /// every connection, then reads which file holds which dictionary again.
    /// Returns once the writer has re-attached too (#242), so the caller may
    /// delete a file no name points at any more: a reader still busy on it
    /// finishes on its open descriptor.
    func attachPacks(_ changes: [PackID: URL?]) async throws {
        guard let pool = dbPool, let files else { throw DBError.notConnected }
        let changed = changes.filter { files.set($0.key, file: $0.value) }.map(\.key.schema)
        guard !changed.isEmpty else { return }
        reattach(pool, files: files, schemas: DictionarySchemas.all.filter(changed.contains),
                 generation: reopenGeneration, log: nil)
        let installed = files.installed
        schemas = try await read(pool) { db in try Self.dictionarySchemas(db, installed: installed) }
        // A pack brings or takes its built-in lists (0130).
        wordListsDidChange()
        // Queued on the writer behind the re-attach.
        try await pool.writeWithoutTransaction { _ in }
    }

    /// 0237, "Download and install", step 7: the imported rows of `sources`
    /// that their newly installed pack has (same word, case-insensitive, and
    /// source) are deleted, and so is an `imported_sources` row left with no
    /// rows. Covers a file named like a pack source imported before the pack
    /// (`freedict-eng-spa.json`) and 1.x rows moved before it (#244). On the
    /// writer, after its re-attach, with #213's retry, as the import.
    func removeImportsCovered(by sources: [String]) async throws {
        let pool = try await userPool()
        let covered = sources.compactMap { source in schemas.schema(ofSource: source).map { (source, $0) } }
        guard !covered.isEmpty else { return }
        try await dictionaryWrite(pool) { db in
            for (source, schema) in covered {
                try db.execute(sql: """
                    DELETE FROM imported_entries
                    WHERE source = ?1 AND EXISTS (
                        SELECT 1 FROM \(schema).entries e
                        WHERE e.word = imported_entries.word COLLATE NOCASE AND e.source = ?1)
                    """, arguments: [source])
                try db.execute(sql: """
                    DELETE FROM imported_sources
                    WHERE source = ?1 AND NOT EXISTS (SELECT 1 FROM imported_entries WHERE source = ?1)
                    """, arguments: [source])
            }
        }
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
    /// Since #237 every file is attached again, from the current snapshot:
    /// the error does not say which file failed.
    private func reopenDictionary(_ pool: DatabasePool, after error: DatabaseError, generation: Int) {
        guard let files else { return }
        reattach(pool, files: files, schemas: DictionarySchemas.all, generation: generation,
                 log: error.extendedResultCode.rawValue)
    }

    /// The reopen and the pack re-attach (#213, #237): bumps the generation
    /// unless a call that failed too already did since `generation`, closes
    /// idle readers, and queues `DETACH` and `ATTACH` of `schemas` on the
    /// writer. `log`: the SQLite error a reopen logs; a pack change logs
    /// nothing.
    private func reattach(_ pool: DatabasePool, files: DictionaryFiles, schemas: [String], generation: Int,
                          log code: Int32?) {
        guard generation == reopenGeneration else { return }
        reopenGeneration += 1
        let started = Date()
        pool.invalidateReadOnlyConnections()
        pool.asyncWriteWithoutTransaction { db in
            do {
                for schema in schemas {
                    try db.execute(sql: "DETACH DATABASE \(schema)")
                    try files.attach(schema, in: db)
                }
                if let code {
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    Self.logger.notice("Reopened the dictionary file after SQLite error \(code) in \(ms) ms")
                }
            } catch {
                // The result code only: never the SQL or its arguments.
                let failure = (error as? DatabaseError)?.extendedResultCode.rawValue ?? -1
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if let code {
                    Self.logger.error(
                        "Reopening the dictionary file after SQLite error \(code) failed in \(ms) ms with SQLite error \(failure)")
                } else {
                    Self.logger.error("Attaching a language pack failed in \(ms) ms with SQLite error \(failure)")
                }
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

    /// Signs of an earlier install in the user database, for the
    /// first-launch offer (#244, 0237 "Launch"): the marker of a committed
    /// 1.x move, and any History, My words or imported row (the 2.0 alpha).
    /// Launch reads them before it starts a move, so nothing waits.
    func earlierInstallSigns() async throws -> (legacyMarker: Bool, userRows: Bool) {
        let pool = try await userPool()
        return try await read(pool) { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM user_meta WHERE key = ?) AS marker,
                       EXISTS (SELECT 1 FROM history) OR EXISTS (SELECT 1 FROM my_words)
                           OR EXISTS (SELECT 1 FROM imported_entries) AS user_rows
                """, arguments: [LegacyMigration.markerKey])
            return (legacyMarker: row?["marker"] ?? false, userRows: row?["user_rows"] ?? false)
        }
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
    /// Internal so a unit test can migrate step by step.
    static var migrator: DatabaseMigrator {
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
        // Imported word lists (0130-word-lists.md, "User database"). My
        // words stays in `my_words`. Deleting a list deletes its words: GRDB
        // turns foreign keys on.
        migrator.registerMigration("130-1-word-lists") { db in
            try db.execute(sql: """
                CREATE TABLE user_list (
                    id          TEXT PRIMARY KEY,       -- 'user-' + lowercase UUID
                    title       TEXT NOT NULL,
                    lang        TEXT NOT NULL,          -- ISO 639-3; 'und' for Other
                    origin      TEXT NOT NULL,          -- 'file', 'anki' or 'paste'
                    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
                );
                CREATE TABLE user_list_item (
                    list_id     TEXT NOT NULL REFERENCES user_list(id) ON DELETE CASCADE,
                    term        TEXT NOT NULL COLLATE NOCASE,
                    headword    TEXT,
                    translation TEXT NOT NULL DEFAULT '',
                    endings     TEXT NOT NULL DEFAULT '',
                    pos         TEXT NOT NULL DEFAULT '',
                    tags        TEXT NOT NULL DEFAULT '',
                    level       TEXT NOT NULL DEFAULT '',
                    level_ord   INTEGER NOT NULL DEFAULT 0,  -- 1 … 6 = A1 … C2; other level names 7, 8, … in order of first appearance; 0 = none
                    rank        INTEGER,
                    seq         INTEGER NOT NULL,
                    sort_key    TEXT NOT NULL,
                    PRIMARY KEY (list_id, term)
                ) WITHOUT ROWID;
                """)
        }
        // Learning (0131, #157). Enrols nothing: a language's My words are
        // enrolled when the language is chosen (`enrolMyWords`).
        migrator.registerMigration("131-1-learning") { db in
            try db.execute(sql: """
                -- A word in learning: one row per WordKey (0130).
                CREATE TABLE learn_word (
                    lang            TEXT NOT NULL,
                    word            TEXT NOT NULL,
                    term            TEXT NOT NULL,
                    endings         TEXT NOT NULL DEFAULT '',
                    pos             TEXT NOT NULL DEFAULT '',
                    translation     TEXT NOT NULL DEFAULT '',
                    -- its language ('eng' for Kirill's lists); '' = an
                    -- import's, shown in every pair
                    translation_lang TEXT NOT NULL DEFAULT '',
                    source          TEXT,
                    headword        TEXT,
                    list_id         TEXT,
                    added_at        TEXT NOT NULL DEFAULT (datetime('now')),
                    introduced_day  TEXT,
                    PRIMARY KEY (lang, word)
                ) WITHOUT ROWID;

                -- A card: two per word; E5 adds conjugation cards.
                CREATE TABLE learn_card (
                    lang       TEXT NOT NULL,
                    word       TEXT NOT NULL,
                    kind       TEXT NOT NULL,
                    facet      TEXT NOT NULL DEFAULT '',
                    step       INTEGER NOT NULL DEFAULT 0,
                    due_day    TEXT NOT NULL,
                    last_day   TEXT,
                    suspended  INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (lang, word, kind, facet)
                ) WITHOUT ROWID;
                CREATE INDEX learn_card_due ON learn_card(lang, due_day) WHERE suspended = 0;

                -- The answer log: one row per exercise item, append-only.
                CREATE TABLE learn_review (
                    id           INTEGER PRIMARY KEY,
                    answered_at  TEXT NOT NULL DEFAULT (datetime('now')),
                    day          TEXT NOT NULL,
                    lang         TEXT NOT NULL,
                    word         TEXT NOT NULL,
                    kind         TEXT NOT NULL,
                    facet        TEXT NOT NULL DEFAULT '',
                    exercise     TEXT NOT NULL,
                    mode         TEXT NOT NULL,
                    run_id       TEXT NOT NULL,
                    outcome      TEXT NOT NULL,
                    step_before  INTEGER NOT NULL,
                    step_after   INTEGER NOT NULL,
                    introduced   INTEGER NOT NULL DEFAULT 0,
                    duration_ms  INTEGER NOT NULL DEFAULT 0,
                    detail       TEXT
                );
                CREATE INDEX learn_review_day ON learn_review(day);
                CREATE INDEX learn_review_word ON learn_review(lang, word);
                -- A run's rows, for its summary (E10's reviewRows(run:)).
                CREATE INDEX learn_review_run ON learn_review(run_id);
                """)
        }
        // The daily goal (0166, #163): the goal in force when each day ended,
        // so a later change of the setting leaves past days alone. No
        // backfill: a day with answers and no row uses the current goal.
        migrator.registerMigration("166-1-daily-goal") { db in
            try db.execute(sql: """
                CREATE TABLE learn_day (
                    day   TEXT PRIMARY KEY,
                    goal  INTEGER NOT NULL
                ) WITHOUT ROWID;
                """)
        }
        return migrator
    }

    // MARK: - Search
    //
    // Issue #138: bundled rows come from the dictionary files, imported rows
    // from the user database (`imported_entries`, `imported_fts`). Since #237
    // (0237, "Reading across files") each file that holds an enabled source
    // is one branch matching its own FTS index (`nil`: the bundle and every
    // installed pack), plus the imported branch when an enabled source is
    // imported. Each branch sorts and keeps its own top `limit`, and one
    // ORDER BY and one LIMIT rank the union with the 1.4.0 ranking.
    // `Scripts/make_search_probe.py --packs` runs the same SQL.

    /// How the branches and their union are ordered and cut.
    private struct Ranking {
        /// The ORDER BY of the union (its column names).
        let order: String
        /// The same order inside a branch, on the entry `e`.
        let branchOrder: String
        /// The arguments of one ORDER BY; both take the same.
        let arguments: StatementArguments
        let limit: Int

        /// The 1.4.0 ranking: an exact `word_normalized` match on the folded
        /// or raw key (the `is_exact` column, #142), then a prefix match,
        /// then FTS `rank`.
        static func relevance(_ fts: (match: String, rankKey: String, rawKey: String), limit: Int) -> Ranking {
            Ranking(
                order: "is_exact DESC, (word_normalized LIKE ? COLLATE NOCASE OR word_normalized LIKE ? COLLATE NOCASE) DESC, rank",
                branchOrder: "is_exact DESC, (e.word_normalized LIKE ? COLLATE NOCASE OR e.word_normalized LIKE ? COLLATE NOCASE) DESC, rank",
                arguments: [fts.rankKey + "%", fts.rawKey + "%"], limit: limit)
        }

        /// FTS `rank` alone: the preferred mode's tail.
        static func rank(limit: Int) -> Ranking {
            Ranking(order: "rank", branchOrder: "rank", arguments: [], limit: limit)
        }
    }

    /// The sources of the imported dictionaries.
    private static func importedSources(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT source FROM imported_sources"))
    }

    /// The `UNION ALL` of the search branches, one per file of
    /// `schemas.files(holding: sources)` plus the imported branch when
    /// `withImports`, each with the entry columns, `rank` and `is_exact`
    /// (whether `word_normalized` is one of `exactKeys`; 0 without them):
    /// rows matching `match` and `filter` (SQL on the entry `e`, with its
    /// arguments). `sources`: the sources to keep (`nil`: every source).
    /// `ids`: rows to leave out. `ranking`: each branch keeps its own top
    /// `ranking.limit`. Empty when no file and no import holds a source.
    private static func searchBranches(
        _ schemas: DictionarySchemas, match: String, exactKeys: (String, String)? = nil,
        filter: (sql: String, arguments: StatementArguments)? = nil,
        sources: [String]?, excluding ids: [Int64] = [], withImports: Bool, ranking: Ranking? = nil
    ) -> (sql: String, arguments: StatementArguments) {
        var stores = schemas.files(holding: sources).map { schema in
            (fts: "\(schema).entries_fts", match: "entries_fts", entries: "\(schema).entries", createdAt: "NULL")
        }
        if withImports {
            stores.append((fts: "imported_fts", match: "imported_fts", entries: "imported_entries",
                           createdAt: "e.created_at"))
        }
        var branches: [String] = []
        var arguments = StatementArguments()
        for t in stores {
            let exact = exactKeys == nil
                ? "0"
                : "(e.word_normalized = ? COLLATE NOCASE OR e.word_normalized = ? COLLATE NOCASE)"
            var branch = """
                SELECT e.id, e.word, e.word_normalized, e.definition, e.phonetic, e.pos, e.source,
                       \(t.createdAt) AS created_at, fts.rank AS rank, \(exact) AS is_exact
                FROM \(t.fts) fts JOIN \(t.entries) e ON e.id = fts.rowid
                WHERE \(t.match) MATCH ?
                """
            if let exactKeys {
                arguments += [exactKeys.0, exactKeys.1]
            }
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
            if let ranking, branchLimitEnabled {
                branch = "SELECT * FROM (\n\(branch)\nORDER BY \(ranking.branchOrder)\nLIMIT ?\n)"
                arguments += ranking.arguments
                arguments += [ranking.limit]
            }
            branches.append(branch)
        }
        return (branches.joined(separator: "\nUNION ALL\n"), arguments)
    }

    #if DEBUG
    /// Unit-test seam (#241): turns the per-branch `ORDER BY … LIMIT` off, so
    /// a test compares the lists with and without it. The app never sets it.
    static var branchLimitEnabled = true
    #else
    private static let branchLimitEnabled = true
    #endif

    /// The ranked query of `rankedEntries`: its SQL and arguments, or nil
    /// when no file and no import holds one of `sources`.
    private static func rankedQuery(
        schemas: DictionarySchemas, fts: (match: String, rankKey: String, rawKey: String),
        sources: [String]?, excluding ids: [Int64] = [], withImports: Bool, ranking: Ranking
    ) -> (sql: String, arguments: StatementArguments)? {
        let union = searchBranches(schemas, match: fts.match, exactKeys: (fts.rankKey, fts.rawKey),
                                   sources: sources, excluding: ids, withImports: withImports, ranking: ranking)
        guard !union.sql.isEmpty else { return nil }
        var arguments = union.arguments
        arguments += ranking.arguments
        arguments += [ranking.limit]
        return ("""
            SELECT * FROM (
            \(union.sql)
            )
            ORDER BY \(ranking.order)
            LIMIT ?
            """, arguments)
    }

    /// Rows matching the query, ranked by `ranking` and cut to its limit,
    /// each with `is_exact`: whether its `word_normalized` is the folded or
    /// the raw key (#142).
    private static func rankedEntries(
        _ db: Database, schemas: DictionarySchemas, fts: (match: String, rankKey: String, rawKey: String),
        sources: [String]?, excluding ids: [Int64] = [], withImports: Bool, ranking: Ranking
    ) throws -> [Search.RankedEntry] {
        guard let query = rankedQuery(schemas: schemas, fts: fts, sources: sources, excluding: ids,
                                      withImports: withImports, ranking: ranking) else { return [] }
        return try Row.fetchAll(db, sql: query.sql, arguments: query.arguments)
            .map { row in Search.RankedEntry(entry: try DictionaryEntry(row: row), isExact: row["is_exact"]) }
    }

    #if DEBUG
    /// Unit-test seam (#241, 0237 "Reading across files"): the files the
    /// ranked query of `search(query:enabledSources:)` reads, from its
    /// bytecode (`EXPLAIN`: the schema of every `OpenRead`), and its
    /// `EXPLAIN QUERY PLAN` lines. `main` is the imported branch. The app
    /// never calls it.
    func searchFilesForTesting(query: String, enabledSources: Set<String>? = nil,
                               limit: Int = 50) async throws -> (files: Set<String>, plan: [String]) {
        guard let pool = dbPool else { throw DBError.notConnected }
        let fts = Search.ftsQuery(sanitized: sanitizeFTS(query))
        let schemas = schemas
        return try await read(pool) { db in
            let imported = try Self.importedSources(db)
            let withImports = enabledSources.map { !imported.isDisjoint(with: $0) } ?? !imported.isEmpty
            guard let query = Self.rankedQuery(schemas: schemas, fts: fts, sources: enabledSources.map { Array($0) },
                                               withImports: withImports, ranking: .relevance(fts, limit: limit))
            else { return ([], []) }
            let names = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "PRAGMA database_list")
                .map { ($0["seq"] as Int, $0["name"] as String) })
            let files = try Row.fetchAll(db, sql: "EXPLAIN " + query.sql, arguments: query.arguments)
                .filter { ($0["opcode"] as String) == "OpenRead" }
                .compactMap { names[$0["p3"] as Int] }
            let plan = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query.sql, arguments: query.arguments)
                .map { $0["detail"] as String }
            return (Set(files), plan)
        }
    }
    #endif

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
        let schemas = schemas
        return try await read(pool) { db in
            let imported = try Self.importedSources(db)
            let sources = enabledSources.map { Array($0) }
            let withImports = enabledSources.map { !imported.isDisjoint(with: $0) } ?? !imported.isEmpty
            let ranked = try Self.rankedEntries(
                db, schemas: schemas, fts: fts, sources: sources, withImports: withImports,
                ranking: .relevance(fts, limit: limit)
            )
            let lemmaRows = try Self.lemmaRows(db, schemas: schemas, step: formStep, sources: sources,
                                               withImports: withImports)
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
        let schemas = schemas

        return try await read(pool) { db in
            let imported = try Self.importedSources(db)
            let lemmaRows = try Self.lemmaRows(db, schemas: schemas, step: formStep, sources: Array(enabledSources),
                                               withImports: !imported.isDisjoint(with: enabledSources))
            var buckets: [String: [SearchResult]] = [:]
            var bucketOrder: [String] = []
            var takenIds: [Int64] = []

            for (index, members) in enabledGroups.enumerated() {
                // Index, not joined IDs: a custom ID may contain any separator.
                let key = String(index)
                let ranked = try Self.rankedEntries(
                    db, schemas: schemas, fts: fts, sources: members, withImports: !imported.isDisjoint(with: members),
                    ranking: .relevance(fts, limit: topN)
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
                    db, schemas: schemas, fts: fts, sources: Array(enabledSources), excluding: takenIds,
                    withImports: !imported.isDisjoint(with: enabledSources),
                    ranking: .rank(limit: remaining)
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
    // query's lemmas from the forms tables (`ell.form_lookup`, through its
    // primary-key prefix; the Greek pack since #237, the stub's empty table
    // without it), then their headword rows in the enabled dictionaries. The
    // merge is the pure `Search.mergeLemmaBucket`.

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
        FROM ell.form_lookup f
        JOIN ell.lemma l ON l.id = f.lemma_id
        JOIN ell.tagset t ON t.id = f.tagset_id
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
    /// applies after the enabled filter. English: `Morphy`'s lemmas (#143).
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
        case .english(let word):
            return try englishLemmaCandidates(db, word: word)
        }
    }

    /// The headword rows of the query's lemmas in the enabled dictionaries,
    /// each with its `FormMatch`: ordered by candidate, then rank, at most
    /// `Search.maximumLemmaRows` rows of `Search.maximumFormLemmas` lemmas.
    /// One query of the base query's shape: an FTS filter on the
    /// `word_normalized` column, which uses the index, plus the exact key.
    /// Bundled Greek rows store the folded key and imported rows the word as
    /// it is, so each lemma matches both.
    private static func lemmaRows(_ db: Database, schemas: DictionarySchemas, step: Search.FormStep?,
                                  sources: [String]?, withImports: Bool) throws -> [SearchResult] {
        guard let step else { return [] }
        var sources = sources
        if case .english = step {
            let english = Search.englishLemmaSources(enabled: sources, english: try englishHeadwordSources(db))
            guard !english.isEmpty else { return [] }
            sources = english
        }
        let candidates = try lemmaCandidates(db, step: step)
        guard !candidates.isEmpty else { return [] }

        let keysPerCandidate = candidates.map { Array(Set([$0.wordNormalized, $0.word])).sorted() }
        let keys = keysPerCandidate.flatMap { $0 }
        let match = "word_normalized : (" + keys.map(Search.ftsString).joined(separator: " OR ") + ")"
        let union = searchBranches(
            schemas, match: match,
            filter: ("e.word_normalized COLLATE NOCASE IN (\(keys.map { _ in "?" }.joined(separator: ", ")))",
                     StatementArguments(keys)),
            sources: sources, withImports: withImports
        )
        guard !union.sql.isEmpty else { return [] }
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

    // MARK: Search by an English form (Issue #143)
    //
    // 0136-word-forms.md, "Morphy (#143)" and "Search path" step 2: one
    // primary-key query on `dict.morphy_exception`, one on `dict.morphy_lemma`
    // for the rule bases, then the pure `Morphy`. English rows store the word
    // as their key, so a base is both the lemma's word and its key. The
    // lemma rows come only from dictionaries whose headwords are English.

    /// The word's lines of WordNet's exception lists: the primary-key prefix
    /// `form = ?`. A unit test checks the plan.
    static let morphyExceptionSQL = "SELECT pos, base FROM dict.morphy_exception WHERE form = ? ORDER BY pos, base"

    /// The parts of speech (`pos_mask`) of `count` rule bases, one
    /// primary-key search each.
    static func morphyLemmaSQL(count: Int) -> String {
        "SELECT word, pos_mask FROM dict.morphy_lemma WHERE word IN (\(Array(repeating: "?", count: count).joined(separator: ", ")))"
    }

    /// The dictionaries whose headwords are English (Kirill, 2026-11-02):
    /// those of the bundle and the installed packs by `dict_metadata.
    /// from_lang` (#237), imports by `imported_sources.from_lang` once an
    /// import records its language (#208). Until then an import counts only
    /// under a bundled English source ID, whose `dict_metadata` row it shares.
    static let englishHeadwordSourcesSQL = DictionarySchemas.union(
        "dict_metadata", columns: "source", where: "from_lang = 'eng'")
        + " UNION SELECT source FROM imported_sources WHERE from_lang = 'eng'"

    private static func englishHeadwordSources(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: englishHeadwordSourcesSQL))
    }

    /// The lemmas the lowercased `word` is a form of, in `Morphy`'s order,
    /// without the word itself.
    private static func englishLemmaCandidates(_ db: Database, word: String) throws -> [Search.LemmaCandidate] {
        let exceptions = try Row.fetchAll(db, sql: morphyExceptionSQL, arguments: [word]).compactMap { row in
            Morphy.PartOfSpeech(rawValue: row["pos"]).map { Morphy.Exception(pos: $0, base: row["base"]) }
        }
        let bases = Morphy.ruleBases(of: word)
        var lemmas: [String: Int] = [:]
        if !bases.isEmpty {
            for row in try Row.fetchAll(db, sql: morphyLemmaSQL(count: bases.count), arguments: StatementArguments(bases)) {
                let word: String = row["word"], mask: Int = row["pos_mask"]
                lemmas[word] = mask
            }
        }
        return Morphy.analyses(of: word, exceptions: exceptions, lemmas: lemmas).map { analysis in
            Search.LemmaCandidate(word: analysis.base, wordNormalized: analysis.base, match: FormMatch(
                lemma: analysis.base,
                analysis: .english(pos: analysis.pos, rule: analysis.rule, suffix: analysis.suffix)))
        }
    }

    // MARK: - Entries by key (Issue #138)

    /// The entry `key` names: the dictionary file of its source first (the
    /// bundle or its pack, #237), then the imported dictionaries; `nil` when
    /// neither has it, also while the source's pack is not installed. A
    /// disabled source resolves too: the enabled set only filters Search.
    func entry(for key: EntryKey) async throws -> DictionaryEntry? {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in try Self.entry(for: key, in: db, schemas: schemas) }
    }

    private static func entry(for key: EntryKey, in db: Database, schemas: DictionarySchemas) throws -> DictionaryEntry? {
        let arguments: StatementArguments = [key.word, key.source]
        if let schema = schemas.schema(ofSource: key.source),
           let entry = try DictionaryEntry.fetchOne(db, sql: """
                SELECT id, word, definition, phonetic, pos, source, NULL AS created_at
                FROM \(schema).entries WHERE word = ? COLLATE NOCASE AND source = ?
                """, arguments: arguments) {
            return entry
        }
        return try DictionaryEntry.fetchOne(db, sql: """
                SELECT id, word, definition, phonetic, pos, source, created_at
                FROM imported_entries WHERE word = ? COLLATE NOCASE AND source = ?
                """, arguments: arguments)
    }

    // MARK: - Inflection tables (Issue #144)
    //
    // The Greek forms tables (#141), in the Greek pack since #237: without
    // it the stub's empty tables give no table. Each read goes through an
    // index or a primary-key prefix: `lemma.word_normalized`, `paradigm
    // (lemma_id, ord)`, `form_lookup (form_norm, lemma_id)`.

    /// The lemmas whose folded word is the key.
    static let lemmaCandidatesSQL = """
        SELECT id, word, pos FROM ell.lemma WHERE word_normalized = ? AND lang = 'ell'
        """

    /// A lemma's cells in table order.
    static let paradigmSQL = """
        SELECT p.form, t.tags FROM ell.paradigm p JOIN ell.tagset t ON t.id = p.tagset_id
        WHERE p.lemma_id = ? ORDER BY p.ord
        """

    /// The lemmas of one part of speech with a table that a folded word is a
    /// form or an alternative of, other than the given lemma; and whether the
    /// table holds the word itself. Issue #143: only the lemmas whose table
    /// holds the word, or whose link page is spelled as the word
    /// (`form_link`), so a word that only folds like a link page (στύλος like
    /// στυλός, βολέ like βόλε) links nowhere. Arguments: the word, the word,
    /// its folded key, the lemma to leave out, the part of speech.
    static let linkedLemmasSQL = """
        SELECT id, word, pos, holds_headword FROM (
            SELECT l.id, l.word, l.pos,
                   EXISTS (SELECT 1 FROM ell.paradigm h WHERE h.lemma_id = l.id AND h.form = ?) AS holds_headword,
                   EXISTS (SELECT 1 FROM ell.form_link k WHERE k.form = ? AND k.lemma_id = l.id) AS spells_link
            FROM ell.form_lookup f JOIN ell.lemma l ON l.id = f.lemma_id
            WHERE f.form_norm = ? AND f.lemma_id <> ? AND l.pos = ?
              AND EXISTS (SELECT 1 FROM ell.paradigm p WHERE p.lemma_id = l.id)
        )
        WHERE holds_headword OR spells_link
        ORDER BY word
        """

    /// The table a Greek entry shows (`InflectionLookup.choose`): of the
    /// lemma it names, or, when that lemma has none, of the lemma it is a form
    /// or an alternative of (πάω → πηγαίνω). A word with no lemma of its part
    /// of speech follows its single link (μέρα → ημέρα), and a noun with no
    /// noun lemma takes its proper noun (WordNet's Αθήνα). `nil` for entries
    /// of other sources and for words without a table.
    func inflection(for entry: DictionaryEntry) async throws -> LemmaParadigm? {
        guard InflectionLookup.sources.contains(entry.source) else { return nil }
        guard let pool = dbPool else { throw DBError.notConnected }
        let word = entry.word.precomposedStringWithCanonicalMapping
        let pos = entry.pos
        let key = Search.foldGreek(word)
        return try await read(pool) { db in
            let candidates = try Row.fetchAll(db, sql: Self.lemmaCandidatesSQL, arguments: [key]).map {
                InflectionLookup.Lemma(id: $0["id"], word: $0["word"], pos: $0["pos"])
            }
            return try InflectionLookup.choose(
                entryWord: word, entryPOS: pos, candidates: candidates,
                table: { lemma in try Self.table(of: lemma, in: db) },
                link: { pos in try Self.linkedTable(of: word, pos: pos, excluding: nil, in: db) })
        }
    }

    /// `lemma`'s own table, else that of the lemma it is a form or an
    /// alternative of (πάω → πηγαίνω); nil when neither has a cell that fits
    /// a slot.
    private static func table(of lemma: InflectionLookup.Lemma, in db: Database) throws -> LemmaParadigm? {
        let cells = try paradigmCells(db, lemmaID: lemma.id)
        guard !cells.isEmpty else {
            return try linkedTable(of: lemma.word, pos: lemma.pos, excluding: lemma.id, in: db)
        }
        let paradigm = LemmaParadigm(word: lemma.word, pos: lemma.pos, cells: cells, isLinked: false)
        return ParadigmLayout.hasTable(paradigm) ? paradigm : nil
    }

    /// The table of the one lemma of part of speech `pos` with a table that
    /// `word` is a form or an alternative of (`InflectionLookup.chooseLink`),
    /// other than the lemma `excluding`; nil for none or several, for a table
    /// that only holds another word folded alike, and for a noun, adjective
    /// or proper noun the word is no nominative of (`InflectionLookup.linkFits`).
    /// A link needs the word itself: a cell of the table or the link page's
    /// own spelling (`linkedLemmasSQL`, #143).
    private static func linkedTable(of word: String, pos: String, excluding: Int64?,
                                    in db: Database) throws -> LemmaParadigm? {
        let links = try Row.fetchAll(db, sql: linkedLemmasSQL,
                                     arguments: [word, word, Search.foldGreek(word), excluding ?? -1, pos])
            .map { row in
                InflectionLookup.Link(lemma: InflectionLookup.Lemma(id: row["id"], word: row["word"], pos: row["pos"]),
                                      holdsHeadword: row["holds_headword"])
            }
        guard let linked = InflectionLookup.chooseLink(links) else { return nil }
        let cells = try paradigmCells(db, lemmaID: linked.id)
        guard InflectionLookup.linkFits(word: word, pos: linked.pos, cells: cells) else { return nil }
        let paradigm = LemmaParadigm(word: linked.word, pos: linked.pos, cells: cells, isLinked: true)
        return ParadigmLayout.hasTable(paradigm) ? paradigm : nil
    }

    private static func paradigmCells(_ db: Database, lemmaID: Int64) throws -> [ParadigmCell] {
        try Row.fetchAll(db, sql: paradigmSQL, arguments: [lemmaID]).map {
            ParadigmCell(form: $0["form"], tags: $0["tags"] as String)
        }
    }

    // MARK: - Example sentences (0134, #178)
    //
    // A word's examples are one primary-key prefix read of `example_word`
    // in its language's pack, with their sentences, then their translations
    // by `(sentence_id, lang)`. A pack that is not installed reads its
    // stub's empty tables: no examples, with no special code.

    #if DEBUG
    /// Unit-test seam: how many times `examples(for:limit:)` read a file. It
    /// only grows.
    private(set) var exampleReadCount = 0
    #endif

    /// The examples of `key` in the build's order, at most `limit`, each with
    /// its translations. Languages without examples (`DictionarySchemas.
    /// examplesSchema`) read nothing. The word is looked up in NFC, as the
    /// build stores it.
    func examples(for key: WordKey, limit: Int = 5) async throws -> [ExampleSentence] {
        guard let schema = DictionarySchemas.examplesSchema(for: key.lang), limit > 0 else { return [] }
        guard let pool = dbPool else { throw DBError.notConnected }
        #if DEBUG
        exampleReadCount += 1
        #endif
        let word = key.word.precomposedStringWithCanonicalMapping
        return try await read(pool) { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.lang, s.text, s.author, w.form_start, w.form_length
                FROM \(schema).example_word w JOIN \(schema).example_sentence s ON s.id = w.sentence_id
                WHERE w.lang = ? AND w.word = ? ORDER BY w.ord LIMIT ?
                """, arguments: [key.lang, word, limit])
            guard !rows.isEmpty else { return [] }
            let ids: [Int64] = rows.map { $0["id"] }
            var translations: [Int64: [ExampleTranslation]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT sentence_id, lang, text, author FROM \(schema).example_translation
                WHERE sentence_id IN (\(Self.placeholders(ids.count))) ORDER BY sentence_id, lang
                """, arguments: StatementArguments(ids)) {
                translations[row["sentence_id"], default: []].append(
                    ExampleTranslation(lang: row["lang"], text: row["text"], author: row["author"]))
            }
            return rows.map { row in
                let id: Int64 = row["id"]
                let start: Int = row["form_start"], length: Int = row["form_length"]
                return ExampleSentence(id: id, lang: row["lang"], text: row["text"], author: row["author"],
                                       form: start..<(start + max(length, 0)), translations: translations[id] ?? [])
            }
        }
    }

    // MARK: - Conjugation drill (0132, #167)
    //
    // The drill's verbs: the verbs of the checked Greek lists that have a
    // conjugation table, read in one read from the Greek pack (0237): the
    // lists through `DictionarySchemas.listsSchema(for: "ell")`, the forms
    // under `PackID.ell.schema`, as `inflection(for:)` reads them. Without
    // the pack, `ell` is the empty stub and the pool is empty. Every query
    // goes through a primary key or the `lemma (lang, word, pos)` index.

    /// The checked lists of the series in the lists schema `schema`, for
    /// their `level_ord` and `translation_lang`: `wordlist` by primary key.
    static func drillListLevelsSQL(schema: String, count: Int) -> String {
        "SELECT level_ord, translation_lang FROM \(schema).wordlist WHERE id IN (\(placeholders(count))) AND series = ?"
    }

    /// The items of `levelCount` levels of a series in the lists schema
    /// `lists`, each with the Greek verb lemma of its word (the linked
    /// headword, else the term) in the forms schema `forms`, if any, and
    /// whether that lemma has cells of its own: the `wordlist_item`
    /// primary-key prefix, then the `lemma` unique index. A word with no
    /// verb lemma stays for the link rule (αγαπώ → αγαπάω). Arguments: the
    /// series, the levels.
    static func drillItemsSQL(lists: String, forms: String, levelCount: Int) -> String {
        """
        SELECT COALESCE(i.headword, i.term) AS word, i.translation, i.level_ord, i.rank, i.seq,
               l.id AS lemma_id, l.word AS lemma_word,
               EXISTS (SELECT 1 FROM \(forms).paradigm p WHERE p.lemma_id = l.id) AS has_cells
        FROM \(lists).wordlist_item i
        LEFT JOIN \(forms).lemma l ON l.lang = 'ell' AND l.word = COALESCE(i.headword, i.term) AND l.pos = 'verb'
        WHERE i.series = ? AND i.level_ord IN (\(placeholders(levelCount)))
        """
    }

    /// The cells of `count` lemmas of the forms schema `schema` in table
    /// order, by the `paradigm` primary key.
    static func drillCellsSQL(schema: String, count: Int) -> String {
        """
        SELECT p.lemma_id, p.form, t.tags FROM \(schema).paradigm p
        JOIN \(schema).tagset t ON t.id = p.tagset_id
        WHERE p.lemma_id IN (\(placeholders(count))) ORDER BY p.lemma_id, p.ord
        """
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    /// The drill's verbs from `lists`, the checked built-in Greek lists
    /// (`DrillScope.greekLists`), in list level, frequency (unranked last)
    /// and list order. Each list word takes its table by the Definition rule
    /// for a verb: its verb lemma's own cells, else its single link
    /// (`linkedLemmasSQL`, `chooseLink`, `linkFits`), as `inflection(for:)`
    /// does, also for a word with no verb lemma; then `DrillVerb.make`. Two
    /// words with one verb are one: the lowest level, then the best rank,
    /// wins. An active verb whose passive is a list word of its own drops
    /// that passive (`DrillVerb.droppingSharedPassives`, #169). No list: no
    /// verb, and nothing is read.
    ///
    /// `meaningsLang` is the meanings language of Greek's pair
    /// (`LearningPair.meaningsLang`, 0131: English for Greek via English and
    /// the limited Greek via Russian). A list's translation is kept when the
    /// list's `translation_lang` is that language, or '' (0131's meaning
    /// rule 1); otherwise the verb's translation is empty, until
    /// 0131's `meanings` (#159) gives the pair's dictionary sense. Never the
    /// case in 2.0.
    func drillVerbs(lists: [WordListID], meaningsLang: String) async throws -> [DrillVerb] {
        guard !lists.isEmpty, let listsSchema = DictionarySchemas.listsSchema(for: "ell") else { return [] }
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await read(pool) { db in
            try Self.drillVerbs(lists: lists, meaningsLang: meaningsLang, listsSchema: listsSchema,
                                formsSchema: PackID.ell.schema, in: db)
        }
    }

    private static func drillVerbs(lists: [WordListID], meaningsLang: String, listsSchema: String,
                                   formsSchema: String, in db: Database) throws -> [DrillVerb] {
        // Each checked level, and whether its translations are in the
        // meanings language.
        var keepsTranslation: [Int: Bool] = [:]
        for row in try Row.fetchAll(db, sql: drillListLevelsSQL(schema: listsSchema, count: lists.count),
                                    arguments: StatementArguments(lists.map(\.rawValue) + [DrillScope.series])) {
            let translationLang: String = row["translation_lang"]
            keepsTranslation[row["level_ord"]] = translationLang.isEmpty || translationLang == meaningsLang
        }
        let levels = keepsTranslation.keys.sorted()
        guard !levels.isEmpty else { return [] }

        // 1. The list items, each with its verb lemma, if any.
        struct Item {
            let word: String
            let lemma: InflectionLookup.Lemma?
            let hasCells: Bool
            let translation: String
            let level: Int
            let rank: Int?
            let seq: Int
        }
        let items = try Row.fetchAll(db, sql: drillItemsSQL(lists: listsSchema, forms: formsSchema,
                                                            levelCount: levels.count),
                                     arguments: StatementArguments([DrillScope.series]) + StatementArguments(levels))
            .map { (row: Row) -> Item in
                let level: Int = row["level_ord"]
                let translation: String = keepsTranslation[level] == true ? row["translation"] : ""
                let lemmaID: Int64? = row["lemma_id"]
                return Item(word: row["word"],
                            lemma: lemmaID.map { InflectionLookup.Lemma(id: $0, word: row["lemma_word"], pos: "verb") },
                            hasCells: row["has_cells"], translation: translation, level: level,
                            rank: row["rank"], seq: row["seq"])
            }
            .sorted { a, b in (a.level, a.rank ?? .max, a.seq) < (b.level, b.rank ?? .max, b.seq) }

        // 2. Each word's table: its verb lemma's own, else its single link.
        var tables: [String: (lemma: InflectionLookup.Lemma, isLinked: Bool)] = [:]
        var looked = Set<String>()
        // Every list word without a verb table is looked up (about 4,000 with
        // the three lists): one prepared statement for all of them.
        let linkStatement = try db.cachedStatement(sql: linkedLemmasSQL)
        for item in items where looked.insert(item.word).inserted {
            if let lemma = item.lemma, item.hasCells {
                tables[item.word] = (lemma, false)
                continue
            }
            let word = item.word
            let links = try Row.fetchAll(linkStatement,
                                         arguments: [word, word, Search.foldGreek(word), item.lemma?.id ?? -1, "verb"])
                .map { row in
                    InflectionLookup.Link(lemma: InflectionLookup.Lemma(id: row["id"], word: row["word"], pos: row["pos"]),
                                          holdsHeadword: row["holds_headword"])
                }
            if let linked = InflectionLookup.chooseLink(links) { tables[item.word] = (linked, true) }
        }

        // 3. The cells of every table.
        var cells: [Int64: [ParadigmCell]] = [:]
        let ids = Array(Set(tables.values.map(\.lemma.id))).sorted()
        for start in stride(from: 0, to: ids.count, by: 500) {
            let chunk = Array(ids[start..<min(start + 500, ids.count)])
            for row in try Row.fetchAll(db, sql: drillCellsSQL(schema: formsSchema, count: chunk.count),
                                        arguments: StatementArguments(chunk)) {
                cells[row["lemma_id"], default: []].append(ParadigmCell(form: row["form"], tags: row["tags"] as String))
            }
        }

        // 4. The verbs, each word once: the items are in level, rank and
        // list order, so the first item of a word wins.
        var verbs: [DrillVerb] = []
        var words = Set<String>()
        for item in items {
            guard let table = tables[item.word], let tableCells = cells[table.lemma.id] else { continue }
            if table.isLinked,
               !InflectionLookup.linkFits(word: item.word, pos: table.lemma.pos, cells: tableCells) { continue }
            let paradigm = LemmaParadigm(word: table.lemma.word, pos: table.lemma.pos, cells: tableCells,
                                         isLinked: table.isLinked)
            guard let verb = DrillVerb.make(word: item.word, paradigm: paradigm, translation: item.translation,
                                            listLevel: item.level, rank: item.rank, seq: item.seq),
                  words.insert(verb.word).inserted else { continue }
            verbs.append(verb)
        }
        return DrillVerb.droppingSharedPassives(verbs)
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
    // My words by stable entry key. The Learn button and the My words swipe
    // go through `learnWord` and `stopLearning` (#158); "No" to "Learn %@?"
    // adds the entry here without cards. E3's lists read these too.

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

    /// Whether My words holds the word `key`, from any dictionary: the Learn
    /// button's "Remove from My words" (#158).
    func isInMyWords(_ key: WordKey) async throws -> Bool {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM (\(LearningSQL.myWordsKeys)) WHERE lang = ? AND word = ?)
                """, arguments: [key.lang, key.word]) ?? false
        }
    }

    /// My words whose entry resolves, newest first. A key that no longer
    /// resolves stays stored and is skipped here.
    func fetchMyWords() async throws -> [DictionaryEntry] {
        try await fetchMyWordRows().compactMap(\.entry)
    }

    /// My words, newest first (#245): each key with its entry, or with none
    /// while its dictionary's pack is not installed, so the row can open
    /// the "not downloaded" view. A key that resolves neither way (a
    /// headword a dictionary dropped, an import that is gone) is skipped.
    func fetchMyWordRows() async throws -> [(key: EntryKey, entry: DictionaryEntry?)] {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: "SELECT source, word FROM my_words ORDER BY added_at DESC")
                .compactMap { row in
                    let key = EntryKey(source: row["source"], word: row["word"])
                    if let entry = try Self.entry(for: key, in: db, schemas: schemas) {
                        return (key, entry)
                    }
                    return schemas.schema(ofSource: key.source) == nil ? (key, nil) : nil
                }
        }
    }

    /// Whether `source` is a dictionary of a pack that is not installed
    /// (#245): its entries resolve only once the pack is downloaded.
    func needsPack(source: String) -> Bool {
        schemas.schema(ofSource: source) == nil
    }

    func clearMyWords() async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM my_words")
        }
    }

    // MARK: - Word lists (0130, #151)
    //
    // 0130-word-lists.md, "Swift". Built-in lists are the `wordlist` tables
    // of the dictionary files, read through `DictionarySchemas` (0237, "For
    // E3 and E4"): each language's pack fills its own, every other file has
    // them empty, and a pack that is not installed reads as the stub's empty
    // tables. Imported lists are `user_list` and `user_list_item`; My words
    // is `my_words`. The order of new words and the linking rules are the
    // pure `LearningOrder` and `ListLinking`.

    /// The `user_meta` key of the install's shuffle seed: a random `UInt64`,
    /// written on first use and kept by `-resetData`.
    static let wordListSeedKey = "wordlists.seed"

    /// The columns `wordlist_item` and `user_list_item` share.
    private static let listItemColumns =
        "term, headword, translation, endings, pos, tags, level, level_ord, rank, seq, sort_key"

    /// A built-in list's words in `order` (SQL on the item columns): the
    /// primary-key prefix `series`, then the list's level. Arguments: the
    /// series and the level's `level_ord`.
    static func wordListItemsSQL(schema: String, order: String) -> String {
        "SELECT \(listItemColumns) FROM \(schema).wordlist_item WHERE series = ? AND level_ord = ? ORDER BY \(order)"
    }

    /// A word's frequency rank, as #155's import reads it: the primary key.
    /// Arguments: the language and the key (folded Greek, lowercase English).
    static func wordRankSQL(schema: String) -> String {
        "SELECT rank FROM \(schema).word_rank WHERE lang = ? AND key = ?"
    }

    /// The Greek lemmas whose table holds a word's exact spelling: a probe of
    /// the `form_lookup` primary-key prefix, then each lemma's cells by the
    /// `paradigm` primary-key prefix. Arguments: the folded word, the word.
    /// No `lemma.lang` filter: every lemma is Greek, and the filter makes
    /// SQLite walk all of them by the `(lang, word, pos)` index.
    static func greekFormLemmasSQL(schema: String) -> String {
        """
        SELECT DISTINCT l.word FROM \(schema).form_lookup f JOIN \(schema).lemma l ON l.id = f.lemma_id
        WHERE f.form_norm = ?
          AND EXISTS (SELECT 1 FROM \(schema).paradigm p WHERE p.lemma_id = l.id AND p.form = ?)
        ORDER BY l.word
        """
    }

    /// Every list: the built-in lists of the installed packs (every file's
    /// `wordlist`) by language and level, My words (its count counts keys),
    /// then the imported lists, newest first. The view models keep the
    /// learned languages' lists.
    func wordLists() async throws -> [WordList] {
        let pool = try await userPool()
        return try await read(pool) { db in
            var builtIn = try Row.fetchAll(db, sql: Self.builtInListsSQL).map { row in
                (list: WordList(id: WordListID(rawValue: row["id"]), kind: .builtIn, lang: row["lang"],
                                level: row["level"], title: "", count: row["word_count"]),
                 level: row["level_ord"] as Int)
            }
            builtIn.sort { ($0.list.lang, $0.level, $0.list.id.rawValue) < ($1.list.lang, $1.level, $1.list.id.rawValue) }
            let myWords = WordList(id: .myWords, kind: .myWords, lang: WordList.myWordsLanguage, level: "", title: "",
                                   count: try Self.myWordsItems(db).count)
            let imported = try Row.fetchAll(db, sql: """
                SELECT l.id, l.title, l.lang, (SELECT COUNT(*) FROM user_list_item i WHERE i.list_id = l.id) AS n
                FROM user_list l ORDER BY l.created_at DESC, l.id
                """).map { row in
                    WordList(id: WordListID(rawValue: row["id"]), kind: .user, lang: row["lang"], level: "",
                             title: row["title"], count: row["n"])
                }
            return builtIn.map(\.list) + [myWords] + imported
        }
    }

    /// A list's words, alphabetical (`sort_key`, then `term`); My words
    /// newest first, one item per `WordKey`. An unknown id has none.
    func wordListItems(_ id: WordListID) async throws -> [WordListItem] {
        let pool = try await userPool()
        return try await read(pool) { db in try Self.listItems(id, order: "sort_key, term", in: db) }
    }

    /// The next `count` new words of language `lang` (0130, "Order of new
    /// words"): the lists of `lists` in that language, in Lists screen order,
    /// arranged by `LearningOrder` with the install's seed; then the words
    /// whose key is in `enrolled` drop out, and in frequency order the
    /// neighbour pass runs again on the rest, so a word that drops out never
    /// leaves two alphabetical neighbours side by side. My words and ids of
    /// lists that no longer exist are skipped; no list of `lang` gives no
    /// words. The arrangement is cached per language, set and order until a
    /// list changes.
    func nextNewWords(in lang: String, from lists: Set<WordListID>, count: Int,
                      excluding enrolled: Set<WordKey>, order: NewWordOrder) async throws -> [WordListItem] {
        let pool = try await userPool()
        let key = ArrangementKey(lang: lang, lists: lists, order: order)
        let arranged: [WordListItem]
        if let cached = arrangements[key] {
            arranged = cached
        } else {
            let generation = listGeneration
            let installSeed = try await wordListSeed(pool)
            arranged = try await read(pool) { db in
                let ids = try Self.listsInScreenOrder(lists, lang: lang, in: db)
                let items = try ids.flatMap { try Self.listItems($0, order: "seq", in: db) }
                return LearningOrder.arrange(
                    items, order: order, seed: LearningOrder.seed(installSeed: installSeed, lists: ids, order: order))
            }
            if generation == listGeneration { arrangements[key] = arranged }
        }
        var rest = arranged.filter { !enrolled.contains($0.key) }
        if order == .frequency && rest.count < arranged.count {
            rest = LearningOrder.separateNeighbours(rest)
        }
        return Array(rest.prefix(max(0, count)))
    }

    /// The entry a list word opens: its headword in the first source of
    /// `sourceOrder` whose language is the word's and that has it (the
    /// source's file, then the imports, as `entry(for:)`), then in the other
    /// sources of that language. A source of no known language counts as
    /// `und`, as in the My words key, so a My words row of such an import
    /// opens through `sourceOrder`. nil for a standalone word. The caller
    /// passes Dictionary Order's sources, enabled first.
    func entry(for item: WordListItem, sourceOrder: [String]) async throws -> DictionaryEntry? {
        guard item.headword != nil else { return nil }
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in try Self.entry(for: item, sourceOrder: sourceOrder, in: db, schemas: schemas) }
    }

    /// `entry(for:sourceOrder:)` on `db`, inside a read or a write.
    private static func entry(for item: WordListItem, sourceOrder: [String], in db: Database,
                              schemas: DictionarySchemas) throws -> DictionaryEntry? {
        guard let headword = item.headword else { return nil }
        return try entry(headword: headword, lang: item.key.lang, sourceOrder: sourceOrder, in: db, schemas: schemas)
    }

    /// The entry of `headword`, a word of language `lang`: in the first
    /// source of `sourceOrder` of that language that has it, then in the
    /// other sources of that language, as a list word opens (0133, #172:
    /// a grammar topic's Words). A source of no known language counts as
    /// `und`.
    func entry(headword: String, lang: String, sourceOrder: [String]) async throws -> DictionaryEntry? {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            try Self.entry(headword: headword, lang: lang, sourceOrder: sourceOrder, in: db, schemas: schemas)
        }
    }

    /// `entry(headword:lang:sourceOrder:)` on `db`, inside a read or a write.
    private static func entry(headword: String, lang: String, sourceOrder: [String], in db: Database,
                              schemas: DictionarySchemas) throws -> DictionaryEntry? {
        let languages = try sourceLanguages(db)
        let given = Set(sourceOrder)
        let sources = sourceOrder + languages.keys.filter { !given.contains($0) }.sorted()
        for source in sources where (languages[source] ?? "und") == lang {
            if let entry = try entry(for: EntryKey(source: source, word: headword), in: db, schemas: schemas) { return entry }
        }
        return nil
    }

    /// The link of each of `terms`, words of a list in `lang`, to a headword
    /// of that language's dictionaries (`ListLinking`); nil for a standalone
    /// word. One read, for #155's import.
    func links(for terms: [String], lang: String) async throws -> [ListLinking.Link?] {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            let lookup = try Self.linkLookup(lang: lang, schemas: schemas, in: db)
            return try terms.map { try ListLinking.link($0, lang: lang, lookup: lookup) }
        }
    }

    /// The preview of an import (0130, "Import", #155), in one read: each
    /// word of `parse` linked to `lang`'s dictionaries by the rules the
    /// build links a series with (`ListLinking`), and ranked from `lang`'s
    /// `word_rank` as the build ranks: its headword's rank, else its term's
    /// or its first ranked cleaned spelling's. A language whose pack is not
    /// installed reads the stub's empty `word_rank`: its words stay unranked.
    func prepareListImport(_ parse: ListText.Result, lang: String) async throws -> ListImportPreview {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            let lookup = try Self.linkLookup(lang: lang, schemas: schemas, in: db)
            let rank = try Self.rankLookup(lang: lang, in: db)
            let words = try parse.words.map { word -> ListImportPreview.Word in
                let link = try ListLinking.link(word.term, lang: lang, lookup: lookup)
                let spellings = link.map { [$0.headword] } ?? [word.term] + ListLinking.cleanedVariants(of: word.term)
                var found: Int?
                for spelling in spellings where found == nil {
                    found = try rank(spelling)
                }
                return ListImportPreview.Word(word: word, headword: link?.headword, rank: found)
            }
            return ListImportPreview(lang: lang, parse: parse, words: words)
        }
    }

    /// Saves `preview` as an imported list titled `title` (0130, "Import"):
    /// its `user_list` row and its words with their links and ranks, in one
    /// write, which is not retried (0129). Returns its id, `user-` and a
    /// lowercase UUID.
    @discardableResult
    func saveUserList(_ preview: ListImportPreview, title: String) async throws -> WordListID {
        let pool = try await userPool()
        let id = WordListID(rawValue: "user-" + UUID().uuidString.lowercased())
        try await pool.write { db in
            // With milliseconds, so two imports of one second keep their order.
            try db.execute(sql: """
                INSERT INTO user_list(id, title, lang, origin, created_at)
                VALUES (?, ?, ?, ?, strftime('%Y-%m-%d %H:%M:%f', 'now'))
                """, arguments: [id.rawValue, title, preview.lang, preview.parse.origin.rawValue])
            let insert = try db.makeStatement(sql: """
                INSERT INTO user_list_item(list_id, term, headword, translation, endings, pos, tags, level, level_ord,
                                           rank, seq, sort_key)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for item in preview.words {
                let word = item.word
                try insert.execute(arguments: [id.rawValue, word.term, item.headword, word.translation, word.endings,
                                               word.partOfSpeech, word.tags, word.level, word.levelOrder, item.rank,
                                               word.seq, WordListItem.sortKey(of: word.term)])
            }
        }
        wordListsDidChange()
        return id
    }

    /// A word's frequency rank in `lang` (`wordRankSQL`, the primary key),
    /// keyed as the build keys it: folded Greek, other words lowercased;
    /// nil when unranked. Reads only the files whose `word_rank` holds the
    /// language.
    private static func rankLookup(lang: String, in db: Database) throws -> (String) throws -> Int? {
        let statements = try DictionarySchemas.all.filter { schema in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM \(schema).word_rank WHERE lang = ?)",
                              arguments: [lang]) ?? false
        }.map { try db.cachedStatement(sql: wordRankSQL(schema: $0)) }
        return { word in
            let key = lang == "ell" ? Search.foldGreek(word) : word.lowercased()
            for statement in statements {
                if let rank = try Int.fetchOne(statement, arguments: [lang, key]) { return rank }
            }
            return nil
        }
    }

    /// The headword language of `source` (ISO 639-3), as `sourceLanguages`
    /// reads it; nil when nothing names it.
    func sourceLanguage(of source: String) async throws -> String? {
        let pool = try await userPool()
        return try await read(pool) { db in try Self.sourceLanguages(db)[source] }
    }

    /// My words as their list screen shows them (#154): `wordListItems(.myWords)`,
    /// newest first, each with the entry of the row that stands for the word,
    /// which its snippet and its Definition show; when that entry no longer
    /// resolves (its pack removed), the entry of the word's next row. A word
    /// none of whose entries resolves waits for its pack with no entry when
    /// one of its rows is a pack's that is not installed (#245, as
    /// `fetchMyWordRows`); otherwise it stays stored and is skipped, as in
    /// `fetchMyWords` (#138). The Learn home counts these.
    func myWordsEntries() async throws -> [MyWordsEntry] {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            try Self.myWordsRows(db).compactMap { row in
                for key in row.entries {
                    if let entry = try Self.entry(for: key, in: db, schemas: schemas) {
                        return MyWordsEntry(item: row.item, key: key, entry: entry)
                    }
                }
                return row.entries.first { schemas.schema(ofSource: $0.source) == nil }
                    .map { MyWordsEntry(item: row.item, key: $0, entry: nil) }
            }
        }
    }

    /// Deletes the imported list `id` and its words (the Lists screen's
    /// swipe, #154). Built-in lists and My words are not in `user_list`.
    func deleteUserList(_ id: WordListID) async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM user_list WHERE id = ?", arguments: [id.rawValue])
        }
        wordListsDidChange()
    }

    /// Deletes every imported list and its words (`-resetData`). The shuffle
    /// seed stays.
    func clearUserLists() async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM user_list")
        }
        wordListsDidChange()
    }

    #if DEBUG
    /// `-wordListFixture <name>` (#154): imported lists for the UI tests
    /// until #155's import exists, next to the built-in lists of the packs.
    /// `lists`: "Greek fixture" (σπίτι, γράφω and έχει αέρα at A1,
    /// αγάπη η at A2, βιβλίο without a translation or a level) and the newer
    /// "English fixture" (house, water; no translations). Returns false for a
    /// name this build does not know.
    func writeWordListFixture(_ name: String) async throws -> Bool {
        guard name == "lists" else { return false }
        typealias Word = (term: String, headword: String?, translation: String, endings: String, pos: String,
                          level: String, levelOrd: Int)
        let lists: [(id: String, title: String, lang: String, createdAt: String, words: [Word])] = [
            ("user-fixture-greek", "Greek fixture", "ell", "2026-01-01 10:00:00", [
                ("σπίτι", "σπίτι", "house", "το", "noun", "A1", 1),
                ("γράφω", "γράφω", "write", "", "verb", "A1", 1),
                ("έχει αέρα", nil, "it is windy", "", "", "A1", 1),
                ("αγάπη", "αγάπη", "love", "η", "noun", "A2", 2),
                ("βιβλίο", "βιβλίο", "", "", "noun", "", 0),
            ]),
            ("user-fixture-english", "English fixture", "eng", "2026-01-02 10:00:00", [
                ("house", "house", "", "", "noun, verb", "", 0),
                ("water", "water", "", "", "noun, verb", "", 0),
            ]),
        ]
        let pool = try await userPool()
        try await pool.write { db in
            for list in lists {
                try db.execute(sql: "DELETE FROM user_list WHERE id = ?", arguments: [list.id])
                try db.execute(sql: "INSERT INTO user_list(id, title, lang, origin, created_at) VALUES (?, ?, ?, 'file', ?)",
                               arguments: [list.id, list.title, list.lang, list.createdAt])
                for (seq, word) in list.words.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO user_list_item(list_id, term, headword, translation, endings, pos, level, level_ord,
                                                   seq, sort_key)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [list.id, word.term, word.headword, word.translation, word.endings, word.pos,
                                         word.level, word.levelOrd, seq, WordListItem.sortKey(of: word.term)])
                }
            }
        }
        wordListsDidChange()
        return true
    }
    #endif

    /// Drops the cached arrangements: a list changed, or the service reopened.
    private func wordListsDidChange() {
        arrangements = [:]
        listGeneration += 1
    }

    /// The install's shuffle seed, written on first use.
    private func wordListSeed(_ pool: DatabasePool) async throws -> UInt64 {
        let key = Self.wordListSeedKey
        let stored = try await read(pool) { db in
            try String.fetchOne(db, sql: "SELECT value FROM user_meta WHERE key = ?", arguments: [key])
        }
        if let seed = stored.flatMap(UInt64.init) { return seed }
        return try await pool.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO user_meta(key, value) VALUES (?, ?)",
                           arguments: [key, String(UInt64.random(in: 0...UInt64.max))])
            let value = try String.fetchOne(db, sql: "SELECT value FROM user_meta WHERE key = ?", arguments: [key])
            return value.flatMap(UInt64.init) ?? 0
        }
    }

    /// The built-in lists of every file: a pack that is not installed reads
    /// as empty (0237, "For E3 and E4").
    private static let builtInListsSQL = DictionarySchemas.union(
        "wordlist", columns: "id, lang, level, level_ord, word_count")

    /// Each source's headword language: the bundle's and the catalog's
    /// dictionaries (`DictionarySchemas.sourceLanguageSQL`, so a source whose
    /// pack is not installed keeps its language), else an import's
    /// `imported_sources.from_lang` once imports record it (#208). An import
    /// under a dictionary's ID has that dictionary's language.
    private static func sourceLanguages(_ db: Database) throws -> [String: String] {
        var languages: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT source, from_lang FROM imported_sources WHERE from_lang IS NOT NULL") {
            languages[row["source"] as String] = row["from_lang"] as String
        }
        for row in try Row.fetchAll(db, sql: "SELECT source, from_lang FROM (\(DictionarySchemas.sourceLanguageSQL))") {
            languages[row["source"] as String] = row["from_lang"] as String
        }
        return languages
    }

    /// One row of `wordlist_item` or `user_list_item`, a word of list `list`
    /// in language `lang`, whose translations are in `translationLang`.
    private static func listItem(_ row: Row, list: WordListID, lang: String, translationLang: String = "") -> WordListItem {
        let term: String = row["term"]
        return WordListItem(
            listID: list, key: WordKey(lang: lang, word: term), term: term, headword: row["headword"],
            translation: row["translation"], translationLang: translationLang, endings: row["endings"],
            partOfSpeech: row["pos"], tags: row["tags"], level: row["level"], levelOrder: row["level_ord"],
            rank: row["rank"], seq: row["seq"], sortKey: row["sort_key"])
    }

    /// The words of list `id` in `order` (SQL on the item columns), My words
    /// newest first; none for an unknown id.
    private static func listItems(_ id: WordListID, order: String, in db: Database) throws -> [WordListItem] {
        switch id.kind {
        case .myWords:
            return try myWordsItems(db)
        case .user:
            guard let lang = try String.fetchOne(db, sql: "SELECT lang FROM user_list WHERE id = ?",
                                                 arguments: [id.rawValue]) else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT \(listItemColumns) FROM user_list_item WHERE list_id = ? ORDER BY \(order)
                """, arguments: [id.rawValue]).map { listItem($0, list: id, lang: lang) }
        case .builtIn:
            for schema in DictionarySchemas.all {
                let sql = "SELECT lang, series, level_ord, translation_lang FROM \(schema).wordlist WHERE id = ?"
                guard let list = try Row.fetchOne(db, sql: sql, arguments: [id.rawValue]) else { continue }
                let lang: String = list["lang"]
                let translationLang: String = list["translation_lang"]
                return try Row.fetchAll(db, sql: wordListItemsSQL(schema: schema, order: order),
                                        arguments: [list["series"] as String, list["level_ord"] as Int])
                    .map { listItem($0, list: id, lang: lang, translationLang: translationLang) }
            }
            return []
        }
    }

    /// My words, one item per `WordKey` (0130): when rows of two
    /// dictionaries share a key (γράφω from El–En · FD and El–En · WN), the
    /// row added first, then by source, stands for the word. Newest first.
    private static func myWordsItems(_ db: Database) throws -> [WordListItem] {
        try myWordsRows(db).map(\.item)
    }

    /// `myWordsItems` with the entry keys of each word's rows, the row that
    /// stands for it first, then the others in the same order.
    private static func myWordsRows(_ db: Database) throws -> [(item: WordListItem, entries: [EntryKey])] {
        let languages = try sourceLanguages(db)
        var index: [WordKey: Int] = [:]
        var rows: [(item: WordListItem, entries: [EntryKey])] = []
        for row in try Row.fetchAll(db, sql: "SELECT source, word FROM my_words ORDER BY added_at, source, word") {
            let word: String = row["word"], source: String = row["source"]
            let key = WordKey(lang: languages[source] ?? "und", word: word)
            if let existing = index[key] {
                rows[existing].entries.append(EntryKey(source: source, word: word))
                continue
            }
            index[key] = rows.count
            rows.append((WordListItem(
                listID: .myWords, key: key, term: word, headword: word, translation: "", endings: "",
                partOfSpeech: "", tags: "", level: "", levelOrder: 0, rank: nil, seq: rows.count,
                sortKey: WordListItem.sortKey(of: word)), [EntryKey(source: source, word: word)]))
        }
        return rows.reversed()
    }

    /// The lists of `ids` in language `lang`, in Lists screen order (a set
    /// has none): built-in lists by level, then imported lists newest first.
    /// My words and ids of lists that no longer exist drop out.
    private static func listsInScreenOrder(_ ids: Set<WordListID>, lang: String, in db: Database) throws -> [WordListID] {
        var builtIn: [(id: WordListID, level: Int)] = []
        for row in try Row.fetchAll(db, sql: DictionarySchemas.union("wordlist", columns: "id, level_ord", where: "lang = ?1"),
                                    arguments: [lang]) {
            let id = WordListID(rawValue: row["id"])
            if ids.contains(id) { builtIn.append((id, row["level_ord"])) }
        }
        let imported = try String.fetchAll(db, sql: "SELECT id FROM user_list WHERE lang = ? ORDER BY created_at DESC, id",
                                           arguments: [lang])
            .map(WordListID.init(rawValue:))
            .filter(ids.contains)
        return builtIn.sorted { ($0.level, $0.id.rawValue) < ($1.level, $1.id.rawValue) }.map(\.id) + imported
    }

    /// The dictionary reads `ListLinking` needs for a list in `lang`, over
    /// every dictionary with headwords in that language: the files that hold
    /// them (`schemas`) and the imported ones. Greek forms come from the
    /// Greek pack, English exceptions from the bundle (0237).
    private static func linkLookup(lang: String, schemas: DictionarySchemas, in db: Database) throws -> ListLinking.Lookup {
        let sources = try sourceLanguages(db).filter { $0.value == lang }.map(\.key).sorted()
        let files = schemas.files(holding: sources)
        let inSources = "source IN (" + sources.map { _ in "?" }.joined(separator: ", ") + ")"
        // Each store's entries and its FTS index, whose hidden column is
        // named after the table.
        let stores = files.map { (fts: "\($0).entries_fts", match: "entries_fts", entries: "\($0).entries") }
            + [(fts: "imported_fts", match: "imported_fts", entries: "imported_entries")]
        return ListLinking.Lookup(
            headwords: { spelling in
                guard !sources.isEmpty else { return [] }
                return try stores.flatMap { store in
                    try String.fetchAll(db, sql: "SELECT word FROM \(store.entries) WHERE word = ? COLLATE NOCASE AND \(inSources)",
                                        arguments: StatementArguments([spelling] + sources))
                }
            },
            nearCandidates: { spelling in
                guard !sources.isEmpty else { return [] }
                // The FTS index finds the rows that fold alike; a near
                // spelling has as many scalars.
                var arguments: StatementArguments = [
                    "word_normalized : " + Search.ftsString(Search.foldGreek(spelling)),
                    spelling.precomposedStringWithCanonicalMapping.unicodeScalars.count,
                ]
                arguments += StatementArguments(sources)
                return try stores.flatMap { store in
                    try String.fetchAll(db, sql: """
                        SELECT e.word FROM \(store.fts) fts JOIN \(store.entries) e ON e.id = fts.rowid
                        WHERE \(store.match) MATCH ? AND length(e.word) = ? AND e.\(inSources)
                        """, arguments: arguments)
                }
            },
            formLemmas: { spelling in
                switch lang {
                case "ell":
                    let form = spelling.precomposedStringWithCanonicalMapping
                    return try String.fetchAll(db, sql: greekFormLemmasSQL(schema: PackID.ell.schema),
                                               arguments: [Search.foldGreek(form), form])
                case "eng":
                    let exceptions = try Row.fetchAll(db, sql: morphyExceptionSQL, arguments: [spelling.lowercased()])
                        .compactMap { row in
                            Morphy.PartOfSpeech(rawValue: row["pos"]).map { Morphy.Exception(pos: $0, base: row["base"]) }
                        }
                    // Morphy's order: verb, noun, adjective, adverb.
                    return Morphy.PartOfSpeech.allCases.flatMap { pos in
                        exceptions.filter { $0.pos == pos }.map(\.base).sorted()
                    }
                default:
                    return []
                }
            })
    }

    // MARK: - Learning (0131, #157)
    //
    // Words, cards and the answer log, in the user database, keyed by
    // `WordKey`, never by row ids. Every method takes `today` from the
    // caller, so the store reads no clock. Reads go through `read`. Writes
    // are user-database writes, never retried, except the three that read
    // the sources' languages from the dictionary file (`learnWord`,
    // `stopLearning`, `enrolMyWords`): they run through `dictionaryWrite`,
    // like the import (#213). Word-level logic (started, paused, mistakes,
    // a word's state) reads and writes word cards only
    // (`LearningSQL.wordKinds`), never E5's conjugation cards.

    /// The pairs the dictionaries offer (0131, "Languages and pairs"), each
    /// with its sources in order: the catalog's (0237, `PackCatalog`): the
    /// directions of the bundle's `dict_metadata` and of its packs,
    /// installed or not, then imports with both languages (#208), and the
    /// limited pairs of `catalog_pair`.
    func learningPairs() async throws -> [LearningPair: [String]] {
        let pool = try await userPool()
        return try await read(pool) { db in
            let catalog = try PackCatalog.read(db)
            let imports = try Row.fetchAll(db, sql: """
                SELECT source, from_lang, to_lang FROM imported_sources
                WHERE source NOT IN (SELECT source FROM (\(DictionarySchemas.sourceLanguageSQL)))
                ORDER BY rowid
                """).map { row -> (source: String, from: String?, to: String?) in
                    (row["source"], row["from_lang"], row["to_lang"])
                }
            return LearningPairs.offered(catalog.directions.map { ($0.source, $0.fromLang, $0.toLang) } + imports,
                                         limited: catalog.limitedPairs.map {
                                             LearningPair(lang: $0.lang, via: $0.via, meaningsLang: $0.meaningsLang)
                                         })
        }
    }

    /// Learn on a word of a learned language. In one transaction: the My
    /// words row, the word under `wordKey(for: key)` and its two new cards,
    /// or its paused word cards resumed with their progress.
    func learnWord(_ key: EntryKey, today: LearnDay) async throws {
        let pool = try await userPool()
        try await dictionaryWrite(pool) { db in
            let word = WordKey(lang: try Self.sourceLanguages(db)[key.source] ?? "und", word: key.word)
            try db.execute(sql: "INSERT OR IGNORE INTO my_words(source, word) VALUES (?, ?)",
                           arguments: [key.source, key.word])
            try db.execute(sql: """
                INSERT OR IGNORE INTO learn_word(lang, word, term, source, headword) VALUES (?, ?, ?, ?, ?)
                """, arguments: [word.lang, word.word, key.word, key.source, key.word])
            try db.execute(sql: LearningSQL.createWordCards, arguments: [word.lang, word.word, today.rawValue])
            try db.execute(sql: """
                UPDATE learn_card SET suspended = 0
                WHERE lang = ? AND word = ? AND suspended = 1 AND kind IN \(LearningSQL.wordKinds)
                """, arguments: [word.lang, word.word])
        }
    }

    /// A language was chosen: its My words not in learning yet are enrolled,
    /// in one transaction. Choosing it again adds nothing.
    func enrolMyWords(lang: String, today: LearnDay) async throws {
        let pool = try await userPool()
        try await dictionaryWrite(pool) { db in
            try db.execute(sql: LearningSQL.enrolMyWords, arguments: [lang])
            try db.execute(sql: LearningSQL.createLanguageCards, arguments: [lang, today.rawValue])
        }
    }

    /// Stop learning, the My words swipe and "Remove from My words". In one
    /// transaction: every My words row of the word's key, whatever its
    /// source, deleted, and every word card of the key paused with its
    /// progress.
    func stopLearning(_ key: EntryKey) async throws {
        let pool = try await userPool()
        try await dictionaryWrite(pool) { db in
            let word = WordKey(lang: try Self.sourceLanguages(db)[key.source] ?? "und", word: key.word)
            try db.execute(sql: LearningSQL.deleteMyWordsOfKey, arguments: [word.lang, word.word])
            try db.execute(sql: """
                UPDATE learn_card SET suspended = 1 WHERE lang = ? AND word = ? AND kind IN \(LearningSQL.wordKinds)
                """, arguments: [word.lang, word.word])
        }
    }

    /// The word and its word cards, paused ones included; nil when it was
    /// never enrolled.
    func learningState(of key: WordKey) async throws -> WordLearningState? {
        let pool = try await userPool()
        return try await read(pool) { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM learn_word WHERE lang = ? AND word = ?",
                                             arguments: [key.lang, key.word]) else { return nil }
            let cards = try Row.fetchAll(db, sql: """
                SELECT * FROM learn_card WHERE lang = ? AND word = ? AND kind IN \(LearningSQL.wordKinds)
                ORDER BY kind DESC, facet
                """, arguments: [key.lang, key.word]).map(Self.cardState)
            return WordLearningState(word: try Self.learnWord(row), cards: cards)
        }
    }

    /// List picks (#157, for #161's session): each item's word with the
    /// list's content (`translation_lang` and `list_id` included) and its
    /// entry, resolved once now through `sourceOrder` (the language's pair
    /// first, `LearningPairs.sourceOrder`), and its two new cards, in one
    /// transaction. Retry-safe: the word and each card are `INSERT OR
    /// IGNORE`, so a repeated call keeps the content and progress already
    /// stored and only adds a missing card. It reads entries from the
    /// dictionary file, so it retries after an I/O error, like `learnWord`.
    func introduce(_ items: [WordListItem], sourceOrder: [String], today: LearnDay) async throws {
        guard !items.isEmpty else { return }
        let pool = try await userPool()
        let schemas = schemas
        try await dictionaryWrite(pool) { db in
            for item in items {
                let entry = try Self.entry(for: item, sourceOrder: sourceOrder, in: db, schemas: schemas).map(EntryKey.init)
                try db.execute(sql: """
                    INSERT OR IGNORE INTO learn_word(lang, word, term, endings, pos, translation, translation_lang,
                                                     source, headword, list_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [item.key.lang, item.key.word, item.term, item.endings, item.partOfSpeech,
                                      item.translation, item.translationLang, entry?.source, entry?.word,
                                      item.listID.rawValue])
                try db.execute(sql: LearningSQL.createWordCards,
                               arguments: [item.key.lang, item.key.word, today.rawValue])
            }
        }
    }

    /// Every word in learning, paused ones included: the exclusion set for
    /// E3's `nextNewWords`, so a stopped word never comes back as new.
    func enrolledKeys() async throws -> Set<WordKey> {
        let pool = try await userPool()
        return try await read(pool) { db in
            Set(try Row.fetchAll(db, sql: "SELECT lang, word FROM learn_word").map {
                WordKey(lang: $0["lang"], word: $0["word"])
            })
        }
    }

    /// Grades one answer. In one transaction: the card read, scheduled and
    /// updated, the word's `introduced_day` set on the first answer to one
    /// of its word cards, the log row inserted, and today's `learn_day` row
    /// with `goal`, the current daily goal, unless the day has one (0166).
    /// A conjugation card (E5, 0132) starts on its first answer: it is
    /// inserted new, due today, when missing. A word card must exist.
    @discardableResult
    func recordAnswer(_ answer: AnswerRecord, today: LearnDay, goal: Int,
                      scheduler: any Scheduler = FixedLadder()) async throws -> CardState {
        let pool = try await userPool()
        return try await pool.write { db in
            let key = answer.card
            let keyArguments: StatementArguments = [key.word.lang, key.word.word, key.kind.rawValue, key.facet]
            if key.kind == .conjugation {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO learn_card(lang, word, kind, facet, due_day) VALUES (?, ?, ?, ?, ?)
                    """, arguments: keyArguments + [today.rawValue])
            }
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM learn_card WHERE lang = ? AND word = ? AND kind = ? AND facet = ?
                """, arguments: keyArguments) else { throw DBError.cardMissing }
            let card = try Self.cardState(row)
            let next = scheduler.next(card, outcome: answer.outcome, today: today)
            try db.execute(sql: """
                UPDATE learn_card SET step = ?, due_day = ?, last_day = ?
                WHERE lang = ? AND word = ? AND kind = ? AND facet = ?
                """, arguments: [next.step, next.dueDay.rawValue, next.lastDay?.rawValue] + keyArguments)
            var introduced = false
            if CardKind.wordKinds.contains(key.kind) {
                try db.execute(sql: """
                    UPDATE learn_word SET introduced_day = ? WHERE lang = ? AND word = ? AND introduced_day IS NULL
                    """, arguments: [today.rawValue, key.word.lang, key.word.word])
                introduced = db.changesCount > 0
            }
            try db.execute(sql: """
                INSERT INTO learn_review(day, lang, word, kind, facet, exercise, mode, run_id, outcome,
                                         step_before, step_after, introduced, duration_ms, detail)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    today.rawValue, key.word.lang, key.word.word, key.kind.rawValue, key.facet,
                    answer.exercise.rawValue, answer.mode.rawValue, answer.runID.uuidString, answer.outcome.rawValue,
                    card.step, next.step, introduced, answer.durationMs, answer.detail,
                ])
            try db.execute(sql: "INSERT OR IGNORE INTO learn_day(day, goal) VALUES (?, ?)",
                           arguments: [today.rawValue, goal])
            return next
        }
    }

    /// Unpaused cards of `lang` and `kinds` due by `today`, answered or the
    /// unanswered word card of a started word (a session closed between a
    /// word's two cards), the most overdue first, then the lowest rung. A
    /// `limit` below zero gives none (SQLite reads a negative `LIMIT` as no
    /// limit).
    func dueCards(lang: String, today: LearnDay, kinds: [CardKind] = CardKind.wordKinds,
                  limit: Int? = nil) async throws -> [CardState] {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM learn_card
                WHERE lang = ? AND due_day <= ? AND suspended = 0
                  AND (last_day IS NOT NULL
                       OR (kind IN \(LearningSQL.wordKinds) AND EXISTS (
                           SELECT 1 FROM learn_word w
                           WHERE w.lang = learn_card.lang AND w.word = learn_card.word
                             AND w.introduced_day IS NOT NULL)))
                  AND kind IN (\(kinds.map { _ in "?" }.joined(separator: ", ")))
                ORDER BY due_day, step, word, kind, facet
                LIMIT ?
                """, arguments: [lang, today.rawValue] + StatementArguments(kinds.map(\.rawValue)) + [limit.map { max($0, 0) } ?? -1])
                .map(Self.cardState)
        }
    }

    /// Every card of `lang` and `kinds`, paused ones included, by word, kind
    /// and facet: the drill's planner reads Greek's conjugation cards
    /// (0132, #169). One query on the `learn_card` primary key.
    func cards(lang: String, kinds: [CardKind]) async throws -> [CardState] {
        guard !kinds.isEmpty else { return [] }
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: Self.cardsSQL(kindCount: kinds.count),
                             arguments: [lang] + StatementArguments(kinds.map(\.rawValue))).map(Self.cardState)
        }
    }

    /// `cards(lang:kinds:)`'s query: the language, then `kindCount` kinds.
    /// `+kind` keeps the kinds a filter, so the rows come in key order with
    /// no sort, one kind or several.
    static func cardsSQL(kindCount: Int) -> String {
        "SELECT * FROM learn_card WHERE lang = ? AND +kind IN (\(placeholders(kindCount))) ORDER BY word, kind, facet"
    }

    /// The new pool's first part: words of `lang` in learning, never
    /// answered and not paused, oldest `added_at` first. A `limit` below
    /// zero (more words started today than the daily limit) gives none.
    func newPool(lang: String, limit: Int) async throws -> [LearnWord] {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM learn_word w
                WHERE w.lang = ? AND w.introduced_day IS NULL
                  AND NOT EXISTS (SELECT 1 FROM learn_card c
                                  WHERE c.lang = w.lang AND c.word = w.word AND c.suspended = 1
                                    AND c.kind IN \(LearningSQL.wordKinds))
                ORDER BY w.added_at, w.word
                LIMIT ?
                """, arguments: [lang, max(limit, 0)]).map(Self.learnWord)
        }
    }

    /// Words of `lang` started on `day`: the daily limit is per language.
    func startedCount(on day: LearnDay, lang: String) async throws -> Int {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM learn_word WHERE lang = ? AND introduced_day = ?",
                             arguments: [lang, day.rawValue]) ?? 0
        }
    }

    /// Answers on `day` in every language: the goal is shared.
    func answeredCount(on day: LearnDay) async throws -> Int {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM learn_review WHERE day = ?", arguments: [day.rawValue]) ?? 0
        }
    }

    /// Unpaused word cards of `lang` whose last answer was wrong, on `since`
    /// or later: a wrong answer since the day and no right one after it.
    /// The latest mistake first.
    func mistakeCards(since: LearnDay, lang: String) async throws -> [CardState] {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: """
                SELECT c.* FROM learn_card c
                JOIN learn_review r ON r.id = (
                    SELECT MAX(x.id) FROM learn_review x
                    WHERE x.lang = c.lang AND x.word = c.word AND x.kind = c.kind AND x.facet = c.facet)
                WHERE c.lang = ? AND c.suspended = 0 AND c.kind IN \(LearningSQL.wordKinds)
                  AND r.outcome = 'wrong' AND r.day >= ?
                ORDER BY r.id DESC
                """, arguments: [lang, since.rawValue]).map(Self.cardState)
        }
    }

    /// Words of `lang` in learning, paused ones left out: none gives the
    /// Learn home's empty state (#158).
    func learningWordCount(lang: String) async throws -> Int {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM learn_word w
                WHERE w.lang = ? AND EXISTS (SELECT 1 FROM learn_card c
                                             WHERE c.lang = w.lang AND c.word = w.word AND c.suspended = 0
                                               AND c.kind IN \(LearningSQL.wordKinds))
                """, arguments: [lang]) ?? 0
        }
    }

    /// Practice for a trainer of `kind` (#159): the unpaused cards of `lang`
    /// and `kind` of words already started, the lowest rung first, then the
    /// oldest answer; a card never answered (its word was started by the
    /// other card) counts as the oldest.
    func practiceCards(lang: String, kind: CardKind, limit: Int) async throws -> [CardState] {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: """
                SELECT c.* FROM learn_card c
                JOIN learn_word w ON w.lang = c.lang AND w.word = c.word
                WHERE c.lang = ? AND c.kind = ? AND c.facet = '' AND c.suspended = 0
                  AND w.introduced_day IS NOT NULL
                ORDER BY c.step, c.last_day, c.word
                LIMIT ?
                """, arguments: [lang, kind.rawValue, max(limit, 0)]).map(Self.cardState)
        }
    }

    /// The meaning of each word in the pair's meanings language (0131,
    /// "Meanings"), chosen now, never stored: rule 1, the list translation
    /// in that language (or an import's), in Swift; else rule 2, `Gloss.short`
    /// of its `lookup` in the first of the pair's dictionaries (`lang` →
    /// `meaningsLang`) in `sourceOrder` that has it, one read per file that
    /// holds one (#237: the bundle or the dictionary's pack, through
    /// `DictionarySchemas`; a pack that is not installed gives none).
    /// `meaningsLang` nil (Other, no pair): rule 3, the translation, else
    /// its own entry's first sense. A word with none is left out: the
    /// planners skip it in this pair (rule 4).
    func meanings(of words: [MeaningQuery], lang: String, meaningsLang: String?,
                  sourceOrder: [String]) async throws -> [WordKey: String] {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            try Self.meanings(of: words, lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder,
                              schemas: schemas, in: db)
                .mapValues(\.text)
        }
    }

    /// The words among `keys`, in learning in `lang`, that have a meaning
    /// in the pair, as `wordChoices` gives it to the runs: the words a run
    /// asks (rule 4). For the Learn home's due and mistakes counts (#161).
    func wordsWithMeaning(_ keys: Set<WordKey>, lang: String, meaningsLang: String?,
                          sourceOrder: [String]) async throws -> Set<WordKey> {
        let words = keys.filter { $0.lang == lang }.map(\.word)
        guard !words.isEmpty else { return [] }
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            var learnWords: [LearnWord] = []
            for start in stride(from: 0, to: words.count, by: 500) {
                let chunk = Array(words[start..<min(start + 500, words.count)])
                learnWords += try Row.fetchAll(db, sql: """
                    SELECT * FROM learn_word WHERE lang = ? AND word IN (\(chunk.map { _ in "?" }.joined(separator: ", ")))
                    """, arguments: StatementArguments([lang] + chunk)).map(Self.learnWord)
            }
            let meanings = try Self.meanings(of: learnWords.map(MeaningQuery.init), lang: lang, meaningsLang: meaningsLang,
                                             sourceOrder: sourceOrder, schemas: schemas, in: db)
            return Set(meanings.filter { !$0.value.text.isEmpty }.keys)
        }
    }

    /// The words of `lang` in learning, paused ones included, as questions
    /// ask them and as options (#159): each with its meaning in
    /// `meaningsLang` (`meanings(of:)`, with the dictionary that gave it)
    /// and its part of speech (the list's, else its entry's).
    func wordChoices(lang: String, meaningsLang: String?, sourceOrder: [String]) async throws -> [WordChoice] {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            let rows = try Row.fetchAll(db, sql: Self.wordChoicesSQL, arguments: [lang])
            let words = try rows.map(Self.learnWord)
            let meanings = try Self.meanings(of: words.map(MeaningQuery.init), lang: lang, meaningsLang: meaningsLang,
                                             sourceOrder: sourceOrder, schemas: schemas, in: db)
            return zip(rows, words).map { row, word in
                let entryPOS: String = row["entry_pos"]
                return WordChoice(key: word.key, term: word.term, endings: word.endings,
                                  meaning: meanings[word.key]?.text ?? "",
                                  partOfSpeech: word.partOfSpeech.isEmpty ? entryPOS : word.partOfSpeech,
                                  listID: word.listID, entry: word.entry, meaningSource: meanings[word.key]?.source)
            }
        }
    }

    /// `wordChoices`' words of a language, each with its entry's part of
    /// speech: from the dictionary file of its source (#237: every file is
    /// joined on the entries' word index, and only the source's own file
    /// has the row; a pack that is not installed is the stub, with none),
    /// else from the imports.
    private static let wordChoicesSQL: String = {
        let files = Array(DictionarySchemas.all.enumerated())
        let joins = files.map { index, schema in
            "LEFT JOIN \(schema).entries e\(index) ON e\(index).word = w.headword COLLATE NOCASE AND e\(index).source = w.source"
        }
        return """
            SELECT w.*, COALESCE(\(files.map { "e\($0.offset).pos" }.joined(separator: ", ")), i.pos, '') AS entry_pos
            FROM learn_word w
            \(joins.joined(separator: "\n"))
            LEFT JOIN imported_entries i ON i.word = w.headword COLLATE NOCASE AND i.source = w.source
            WHERE w.lang = ?
            ORDER BY w.word
            """
    }()

    /// About `count` headwords of `lang` with the primary part of speech of
    /// `pos` (any, when `pos` is empty) and a meaning: the distractors' last
    /// resort (#159). With a pair, they come from `source`, the pair
    /// dictionary that gave the word's meaning, else from the pair's first
    /// dictionary (`lang` → `meaningsLang`) in `sourceOrder`, so their
    /// meanings are in the meanings language; none when the pair has no
    /// dictionary. Without (`meaningsLang` nil, Other), from `source`, the
    /// word's own, else the first dictionary of `lang` in `sourceOrder`.
    /// The headwords are random rows, drawn by `seed`, around `near` (the
    /// word's headword or term): a shipped dictionary's rows are contiguous
    /// in its file (the bundle or its pack, #237), so within its
    /// `word_count` of the anchor about half of the draws are its own. A
    /// dictionary whose pack is not installed gives none.
    func distractorSample(lang: String, meaningsLang: String?, source: String?, sourceOrder: [String], pos: String,
                          near: String, seed: UInt64, count: Int = 30) async throws -> [WordChoice] {
        let pool = try await userPool()
        let schemas = schemas
        return try await read(pool) { db in
            let chosen: String?
            if let meaningsLang {
                let pairSources = try Self.pairSources(lang: lang, meaningsLang: meaningsLang, order: sourceOrder, in: db)
                chosen = source.flatMap { pairSources.contains($0) ? $0 : nil } ?? pairSources.first
            } else {
                chosen = try source ?? Self.firstSource(of: lang, order: sourceOrder, in: db)
            }
            guard let source = chosen else { return [] }
            let isImported = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM imported_sources WHERE source = ?)",
                                               arguments: [source]) ?? false
            // #237: a dictionary's rows are in the file of its source; an
            // imported source a pack also has, in both (0237, step 7).
            var files: [String?] = []
            if let schema = isImported ? schemas.claimedSchema(ofSource: source) : schemas.schema(ofSource: source) {
                files.append(schema)
            }
            if isImported {
                files.append(nil)
            }
            var rng = SplitMix64(seed: seed)
            let wanted = DistractorPicker.primaryPOS(pos)
            var sample: [WordChoice] = []
            var taken = Set<String>()
            for file in files where sample.count < count {
                let table = file.map { "\($0).entries" } ?? "imported_entries"
                guard let anchor = try Int64.fetchOne(db, sql: """
                        SELECT id FROM \(table) WHERE word >= ? COLLATE NOCASE AND source = ?
                        ORDER BY word COLLATE NOCASE LIMIT 1
                        """, arguments: [near, source])
                        ?? Int64.fetchOne(db, sql: """
                        SELECT id FROM \(table) WHERE word < ? COLLATE NOCASE AND source = ?
                        ORDER BY word COLLATE NOCASE DESC LIMIT 1
                        """, arguments: [near, source]) else { continue }
                let range: ClosedRange<Int64>
                if let file {
                    let size = try Int64.fetchOne(db, sql: "SELECT word_count FROM \(file).dict_metadata WHERE source = ?",
                                                  arguments: [source]) ?? 0
                    let half = max(size, 1_000)
                    range = max(1, anchor - half)...(anchor + half)
                } else {
                    let bounds = try Row.fetchOne(db, sql: "SELECT MIN(id) AS lo, MAX(id) AS hi FROM imported_entries WHERE source = ?",
                                                  arguments: [source])
                    let lo: Int64? = bounds?["lo"], hi: Int64? = bounds?["hi"]
                    range = (lo ?? anchor)...max(hi ?? anchor, lo ?? anchor)
                }
                var ids: [Int64] = []
                var drawn = Set<Int64>()
                for _ in 0..<(count * 20) {
                    let id = Int64.random(in: range, using: &rng)
                    if drawn.insert(id).inserted { ids.append(id) }
                }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, word, pos, definition FROM \(table)
                    WHERE source = ? AND id IN (\(ids.map { _ in "?" }.joined(separator: ", ")))
                    """, arguments: [source] + StatementArguments(ids))
                let byID = Dictionary(rows.map { row -> (Int64, Row) in (row["id"], row) }, uniquingKeysWith: { a, _ in a })
                for id in ids {
                    guard sample.count < count, let row = byID[id] else { continue }
                    let word: String = row["word"], rowPOS: String = row["pos"]
                    guard wanted.isEmpty || DistractorPicker.primaryPOS(rowPOS) == wanted,
                          taken.insert(Self.foldedWord(word)).inserted else { continue }
                    let meaning = Gloss.short(definition: row["definition"])
                    guard !meaning.isEmpty else { continue }
                    sample.append(WordChoice(key: WordKey(lang: lang, word: word), term: word, meaning: meaning,
                                             partOfSpeech: rowPOS, entry: EntryKey(source: source, word: word),
                                             isEnrolled: false, meaningSource: source))
                }
            }
            return sample
        }
    }

    /// The first dictionary of `lang` in `order`, else the first of `lang`
    /// by source ID; nil when the app has none. Installed dictionaries only:
    /// the `dict_metadata` of the bundle and of every pack (#237; a pack
    /// that is not installed is the stub, with none), and the imports.
    private static func firstSource(of lang: String, order: [String], in db: Database) throws -> String? {
        let sources = Set(try String.fetchAll(db, sql: """
            \(DictionarySchemas.union("dict_metadata", columns: "source", where: "from_lang = ?1"))
            UNION
            SELECT source FROM imported_sources WHERE from_lang = ?1
            """, arguments: [lang]))
        return order.first(where: sources.contains) ?? sources.sorted().first
    }

    /// The pair's installed dictionaries, from `lang` into `meaningsLang`:
    /// in the bundle or an installed pack (#237: the `dict_metadata` of
    /// every file; a pack that is not installed is the stub, with none), or
    /// imported with both languages (#208). Those in `order` first, in its
    /// order, then the others by source ID.
    private static func pairSources(lang: String, meaningsLang: String, order: [String],
                                    in db: Database) throws -> [String] {
        let sources = Set(try String.fetchAll(db, sql: """
            \(DictionarySchemas.union("dict_metadata", columns: "source", where: "from_lang = ?1 AND to_lang = ?2"))
            UNION
            SELECT source FROM imported_sources WHERE from_lang = ?1 AND to_lang = ?2
            """, arguments: [lang, meaningsLang]))
        return order.filter(sources.contains) + sources.subtracting(order).sorted()
    }

    /// `meanings(of:)` in one read: each word's meaning with the dictionary
    /// that gave it (nil for a translation).
    private static func meanings(of words: [MeaningQuery], lang: String, meaningsLang: String?, sourceOrder: [String],
                                 schemas: DictionarySchemas, in db: Database) throws -> [WordKey: (text: String, source: String?)] {
        var found: [WordKey: (text: String, source: String?)] = [:]
        var rest: [MeaningQuery] = []
        for word in words {
            if let translation = Gloss.listMeaning(translation: word.translation, translationLang: word.translationLang,
                                                   meaningsLang: meaningsLang) {
                found[word.key] = (translation, nil)
            } else {
                rest.append(word)
            }
        }
        func first(_ definitions: [String: String], in sources: [String],
                   partOfSpeech: String = "") -> (text: String, source: String?)? {
            for source in sources where Gloss.gives(source, partOfSpeech: partOfSpeech) {
                if let definition = definitions[source] {
                    let text = Gloss.short(definition: definition)
                    if !text.isEmpty { return (text, source) }
                }
            }
            return nil
        }
        if let meaningsLang {
            let sources = try pairSources(lang: lang, meaningsLang: meaningsLang, order: sourceOrder, in: db)
            let byWord = try Self.definitions(of: Set(rest.map(\.lookup)), in: sources, schemas: schemas, db: db)
            for word in rest {
                found[word.key] = first(byWord[foldedWord(word.lookup)] ?? [:], in: sources,
                                        partOfSpeech: word.partOfSpeech)
            }
        } else {
            // Other: each word's own entry.
            let owned = rest.compactMap { word in word.entry.map { (key: word.key, entry: $0) } }
            for (source, group) in Dictionary(grouping: owned, by: { $0.entry.source }) {
                let byWord = try Self.definitions(of: Set(group.map { $0.entry.word }), in: [source], schemas: schemas,
                                                  db: db)
                for word in group {
                    found[word.key] = first(byWord[foldedWord(word.entry.word)] ?? [:], in: [source])
                }
            }
        }
        return found
    }

    /// The definitions of `words` in `sources`, by headword as `NOCASE`
    /// folds it (`foldedWord`), then source: one `word IN (…)` read on the
    /// entries' word index, in chunks of 500, per file that holds one of
    /// `sources`: the bundle or a pack (#237, the file of each source
    /// through `DictionarySchemas`; a source whose pack is not installed is
    /// read nowhere), and the imports. A source both imported and a pack's
    /// is read in both; the pack's row wins.
    private static func definitions(of words: Set<String>, in sources: [String], schemas: DictionarySchemas,
                                    db: Database) throws -> [String: [String: String]] {
        var found: [String: [String: String]] = [:]
        guard !words.isEmpty, !sources.isEmpty else { return found }
        let imported = Set(try String.fetchAll(db, sql: "SELECT source FROM imported_sources"))
        var inFiles: [String: [String]] = [:]
        for source in sources {
            let schema = imported.contains(source) ? schemas.claimedSchema(ofSource: source)
                : schemas.schema(ofSource: source)
            if let schema { inFiles[schema, default: []].append(source) }
        }
        let tables = DictionarySchemas.all.compactMap { schema in inFiles[schema].map { ("\(schema).entries", $0) } }
            + [("imported_entries", sources.filter(imported.contains))].filter { !$0.1.isEmpty }
        let words = Array(words)
        for (table, tableSources) in tables {
            for start in stride(from: 0, to: words.count, by: 500) {
                let chunk = Array(words[start..<min(start + 500, words.count)])
                let rows = try Row.fetchAll(db, sql: """
                    SELECT word, source, definition FROM \(table)
                    WHERE word COLLATE NOCASE IN (\(chunk.map { _ in "?" }.joined(separator: ", ")))
                      AND source IN (\(tableSources.map { _ in "?" }.joined(separator: ", ")))
                    """, arguments: StatementArguments(chunk) + StatementArguments(tableSources))
                for row in rows {
                    let word = foldedWord(row["word"]), source: String = row["source"]
                    if found[word]?[source] == nil {
                        found[word, default: [:]][source] = row["definition"]
                    }
                }
            }
        }
        return found
    }

    /// A headword as SQLite's `NOCASE` compares it: only A–Z lowercased.
    private static func foldedWord(_ word: String) -> String {
        WordKey(lang: "", word: word).word
    }

    #if DEBUG
    /// `-learningFixture <name>` (0131, Test seams), written after the reset
    /// relative to `today`. Returns the fixture's languages, nil for a name
    /// this build does not know. #158: `myWords5` (γράφω, σπίτι, νερό,
    /// καλός, είμαι in My words, new) and `bilingual` (γράφω and σπίτι due in
    /// Greek, house and water in English, all in My words). #159: `due` (the
    /// five words of `myWords5` due today on rungs 1, 2, 3, 1, 2, and βιβλίο
    /// learned, due in 20 days). #161: `session` (`due`, and the Greek list
    /// `user-fixture-ell` of four words with English translations, to check
    /// with `-learningLists`) and `mistakes` (`myWords5` on the 7-day rung,
    /// with wrong answers: γράφω's recognition today and σπίτι's production
    /// 6 days ago, in mistakes practice; νερό's recognition 7 days ago, out
    /// of it; καλός's recognition 3 days ago, right the day after). 0166,
    /// #164: `stats` (`writeStatsFixture`). 0132, #168: `conjugation`
    /// (`writeConjugationFixture`).
    func writeLearningFixture(_ name: String, today: LearnDay) async throws -> [String]? {
        func greek(_ word: String) -> EntryKey { EntryKey(source: "freedict-ell-eng", word: word) }
        let myWords5 = ["γράφω", "σπίτι", "νερό", "καλός", "είμαι"]
        switch name {
        case "myWords5":
            for word in myWords5 {
                try await learnWord(greek(word), today: today)
            }
            return ["ell"]
        case "session":
            _ = try await writeLearningFixture("due", today: today)
            let pool = try await userPool()
            try await pool.write { db in
                try db.execute(sql: """
                    INSERT INTO user_list(id, title, lang, origin) VALUES ('user-fixture-ell', 'Fixture', 'ell', 'paste')
                    """)
                let words = [("θάλασσα", "sea"), ("ήλιος", "sun"), ("ψωμί", "bread"), ("φίλος", "friend")]
                for (seq, (term, translation)) in words.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO user_list_item(list_id, term, headword, translation, seq, sort_key)
                        VALUES ('user-fixture-ell', ?, ?, ?, ?, ?)
                        """, arguments: [term, term, translation, seq, WordListItem.sortKey(of: term)])
                }
            }
            return ["ell"]
        case "mistakes":
            for word in myWords5 {
                try await learnWord(greek(word), today: today)
            }
            let pool = try await userPool()
            try await pool.write { db in
                try db.execute(sql: "UPDATE learn_card SET step = 3, last_day = ?, due_day = ? WHERE lang = 'ell'",
                               arguments: [today.adding(days: -1).rawValue, today.adding(days: 6).rawValue])
                try db.execute(sql: "UPDATE learn_word SET introduced_day = ? WHERE lang = 'ell'",
                               arguments: [today.adding(days: -30).rawValue])
                // In the order answered: word, card, days ago, right. A wrong
                // answer leaves its card learning, due that day.
                let answers = [("νερό", CardKind.recognition, 7, false), ("σπίτι", .production, 6, false),
                               ("καλός", .recognition, 3, false), ("καλός", .recognition, 2, true),
                               ("γράφω", .recognition, 0, false)]
                var steps: [String: Int] = [:]
                for (word, kind, ago, right) in answers {
                    let day = today.adding(days: -ago)
                    let before = steps[word + kind.rawValue] ?? 3
                    let after = right ? 1 : 0
                    steps[word + kind.rawValue] = after
                    try db.execute(sql: """
                        UPDATE learn_card SET step = ?, last_day = ?, due_day = ?
                        WHERE lang = 'ell' AND word = ? AND kind = ?
                        """, arguments: [after, day.rawValue, (right ? day.adding(days: 1) : day).rawValue, word,
                                         kind.rawValue])
                    try db.execute(sql: """
                        INSERT INTO learn_review(day, lang, word, kind, exercise, mode, run_id, outcome,
                                                 step_before, step_after)
                        VALUES (?, 'ell', ?, ?, ?, 'session', 'fixture-mistakes', ?, ?, ?)
                        """, arguments: [day.rawValue, word, kind.rawValue,
                                         (kind == .recognition ? ExerciseKind.recognition : .productionChoice).rawValue,
                                         right ? "right" : "wrong", before, after])
                }
            }
            return ["ell"]
        case "due":
            for word in myWords5 + ["βιβλίο"] {
                try await learnWord(greek(word), today: today)
            }
            // Each card answered right on its rung's last review, so it is due today.
            let rungs = Array(zip(myWords5, [1, 2, 3, 1, 2])) + [("βιβλίο", 5)]
            let pool = try await userPool()
            try await pool.write { db in
                for (word, step) in rungs {
                    let interval = FixedLadder.interval(ofStep: step) ?? 1
                    let dueDay = step == 5 ? today.adding(days: 20) : today
                    let lastDay = dueDay.adding(days: -interval)
                    try db.execute(sql: "UPDATE learn_card SET step = ?, last_day = ?, due_day = ? WHERE lang = 'ell' AND word = ?",
                                   arguments: [step, lastDay.rawValue, dueDay.rawValue, word])
                    try db.execute(sql: "UPDATE learn_word SET introduced_day = ? WHERE lang = 'ell' AND word = ?",
                                   arguments: [today.adding(days: -60).rawValue, word])
                }
            }
            return ["ell"]
        case "bilingual":
            for key in [greek("γράφω"), greek("σπίτι"), EntryKey(source: "wordnet", word: "house"),
                        EntryKey(source: "wordnet", word: "water")] {
                try await learnWord(key, today: today)
            }
            // Started yesterday, both cards on the 1-day rung: due today.
            let yesterday = today.adding(days: -1).rawValue
            let pool = try await userPool()
            try await pool.write { db in
                try db.execute(sql: "UPDATE learn_card SET step = 1, last_day = ?, due_day = ?",
                               arguments: [yesterday, today.rawValue])
                try db.execute(sql: "UPDATE learn_word SET introduced_day = ?", arguments: [yesterday])
            }
            return ["ell", "eng"]
        case "stats":
            try await writeStatsFixture(today: today)
            return ["ell", "eng"]
        case "conjugation":
            // 0132, Test seams (#168): with the default daily goal; the
            // caller checks `ky-ell-a1`.
            return try await writeConjugationFixture(today: today, goal: 20)
        default:
            return nil
        }
    }

    /// The `stats` fixture's words answered on the streak's days; ψωμί is
    /// started today and μήλο enrolled, never answered.
    static let statsFixtureWords = ["γράφω", "σπίτι", "νερό", "καλός", "είμαι", "βιβλίο", "θάλασσα"]

    /// The `stats` fixture's days missed between its 12-day streak and its
    /// current 9-day one: the first gap, 3 to 9 days, after which two
    /// missed days are frozen and the next one resets, whatever today's
    /// weekday (freezes come on Mondays).
    nonisolated static func statsFixtureGap(today: LearnDay) -> Int {
        for gap in 3...9 {
            let days = statsFixtureDays(today: today, gap: gap)
            let state = Streak.compute(counts: Dictionary(uniqueKeysWithValues: days.map { ($0, 20) }), goals: [:],
                                       currentGoal: 20, today: today)
            let marks = Array(state.marks.values)
            if state.current == 9, state.best == 12, marks.filter({ $0 == .frozen }).count == 2,
               marks.contains(.missed) {
                return gap
            }
        }
        return 4
    }

    /// The days whose goal the `stats` fixture meets, oldest first: 12 days,
    /// `gap` days missed, then the 9 days through today.
    nonisolated static func statsFixtureDays(today: LearnDay, gap: Int) -> [LearnDay] {
        let start = today.adding(days: -(20 + gap))
        return (0..<12).map { start.adding(days: $0) } + (0..<9).reversed().map { today.adding(days: -$0) }
    }

    /// `-learningFixture stats` (0166, Test plan), relative to `today`, with
    /// the default goal of 20 (`learn_day` rows of 20):
    /// - Greek: the 7 `statsFixtureWords` answered 20 times a day (28
    ///   yesterday, the best day: 30 with English) on `statsFixtureDays`:
    ///   the streak is 9, the best 12, with two frozen days and a reset in
    ///   the gap; 434 exercises on 21 days in the last 30;
    /// - γράφω, σπίτι and νερό with 5, 3 and 2 mistakes; βιβλίο learned;
    ///   ψωμί started today (Greek: 1 new word today); μήλο in My words, new;
    /// - 40 drill rows on the first 8 days: aorist 8 of 12, present 12 of
    ///   16 (both voices), future 7 of 12; γράφω and είμαι the hardest verbs;
    /// - English: house and water, started 2 days ago and answered once a
    ///   day through today, on days the Greek answers already meet;
    /// - the Greek list `user-fixture-stats` (θάλασσα, ψωμί, ήλιος), not
    ///   checked.
    private func writeStatsFixture(today: LearnDay) async throws {
        func greek(_ word: String) -> EntryKey { EntryKey(source: "freedict-ell-eng", word: word) }
        for word in Self.statsFixtureWords + ["ψωμί", "μήλο"] {
            try await learnWord(greek(word), today: today)
        }
        for word in ["house", "water"] {
            try await learnWord(EntryKey(source: "wordnet", word: word), today: today)
        }
        let days = Self.statsFixtureDays(today: today, gap: Self.statsFixtureGap(today: today))
        // Index in `days` → the words answered wrong once that day.
        let wrong: [Int: Set<String>] = [0: ["γράφω"], 1: ["σπίτι"], 2: ["γράφω"], 3: ["σπίτι"], 4: ["γράφω"],
                                         5: ["νερό"], 14: ["γράφω"], 15: ["σπίτι"], 16: ["γράφω"], 17: ["νερό"]]
        // (verb, facet, right answers, answers): 40 drill rows.
        let drill = [("γράφω", "aorist.active", 8, 12), ("είμαι", "present.active", 9, 10),
                     ("γράφω", "present.passive", 3, 6), ("γράφω", "future.active", 3, 6),
                     ("είμαι", "future.active", 4, 6)]
        let drillRows = drill.flatMap { word, facet, right, count in
            (0..<count).map { (word: word, facet: facet, right: $0 < right) }
        }
        let first = days[0]
        let pool = try await userPool()
        try await pool.write { db in
            func insert(_ day: LearnDay, lang: String, word: String, kind: CardKind, facet: String = "",
                        right: Bool, introduced: Bool = false) throws {
                let exercise: ExerciseKind = kind == .conjugation ? .conjugation
                    : kind == .recognition ? .recognition : .productionChoice
                try db.execute(sql: """
                    INSERT INTO learn_review(day, lang, word, kind, facet, exercise, mode, run_id, outcome,
                                             step_before, step_after, introduced, duration_ms, detail)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 6000, ?)
                    """, arguments: [day.rawValue, lang, word, kind.rawValue, facet, exercise.rawValue,
                                     kind == .conjugation ? "drill" : "session", "fixture-stats-\(day.rawValue)",
                                     right ? "right" : "wrong", right ? 1 : 0, introduced,
                                     kind == .conjugation ? "1sg" : nil])
            }
            for (index, day) in days.enumerated() {
                var count = day == today.adding(days: -1) ? 28 : 20
                if index < 8 {
                    for row in drillRows[(index * 5)..<(index * 5 + 5)] {
                        try insert(day, lang: "ell", word: row.word, kind: .conjugation, facet: row.facet, right: row.right)
                    }
                    count -= 5
                }
                let words = (day == today ? ["ψωμί"] : []) + Self.statsFixtureWords
                var seen = Set<String>()
                for row in 0..<count {
                    let word = words[row % words.count]
                    let isFirst = seen.insert(word).inserted
                    try insert(day, lang: "ell", word: word, kind: row % 2 == 0 ? .recognition : .production,
                               right: !(isFirst && wrong[index]?.contains(word) == true),
                               introduced: isFirst && (word == "ψωμί" || day == first))
                }
                try db.execute(sql: "INSERT OR IGNORE INTO learn_day(day, goal) VALUES (?, 20)", arguments: [day.rawValue])
            }
            for ago in [2, 1, 0] {
                for word in ["house", "water"] {
                    try insert(today.adding(days: -ago), lang: "eng", word: word, kind: .recognition, right: true,
                               introduced: ago == 2)
                }
            }
            // The cards after those answers: βιβλίο learned, γράφω back to
            // learning, the others on their way; μήλο untouched, new.
            func card(_ lang: String, _ word: String, step: Int, last: LearnDay, due: LearnDay,
                      started: LearnDay) throws {
                try db.execute(sql: "UPDATE learn_card SET step = ?, last_day = ?, due_day = ? WHERE lang = ? AND word = ?",
                               arguments: [step, last.rawValue, due.rawValue, lang, word])
                try db.execute(sql: "UPDATE learn_word SET introduced_day = ? WHERE lang = ? AND word = ?",
                               arguments: [started.rawValue, lang, word])
            }
            for word in Self.statsFixtureWords {
                switch word {
                case "βιβλίο":
                    try card("ell", word, step: 5, last: today.adding(days: -1), due: today.adding(days: 29), started: first)
                case "γράφω":
                    try card("ell", word, step: 0, last: today, due: today, started: first)
                default:
                    try card("ell", word, step: 2, last: today, due: today.adding(days: 3), started: first)
                }
            }
            try card("ell", "ψωμί", step: 1, last: today, due: today.adding(days: 1), started: today)
            for word in ["house", "water"] {
                try card("eng", word, step: 1, last: today, due: today.adding(days: 1), started: today.adding(days: -2))
            }
            try db.execute(sql: """
                INSERT INTO user_list(id, title, lang, origin) VALUES ('user-fixture-stats', 'Fixture stats', 'ell', 'paste')
                """)
            for (seq, (term, translation)) in [("θάλασσα", "sea"), ("ψωμί", "bread"), ("ήλιος", "sun")].enumerated() {
                try db.execute(sql: """
                    INSERT INTO user_list_item(list_id, term, headword, translation, seq, sort_key)
                    VALUES ('user-fixture-stats', ?, ?, ?, ?, ?)
                    """, arguments: [term, term, translation, seq, WordListItem.sortKey(of: term)])
            }
        }
    }
    #endif

    #if DEBUG
    /// The `conjugation` learning fixture (0132, Test seams), relative to
    /// `today`, through `recordAnswer`: 30 days of drill answers, the aorist
    /// 4 of 10 right (γράφω) and the present 9 of 10 (έχω), which leave
    /// γράφω's `aorist.active` due today on rung 2 and έχω's
    /// `present.active` in learning; and πρέπει's `future.active` learned.
    /// Each answer's day gets a `learn_day` row with `goal` (0166). Returns
    /// its languages. The caller also checks `ky-ell-a1` (0131's
    /// `-learningFixture`, #158).
    func writeConjugationFixture(today: LearnDay, goal: Int) async throws -> [String] {
        let wrong = Outcome.wrong, right = Outcome.right
        let series: [(word: String, facet: String, answers: [(daysAgo: Int, outcome: Outcome)])] = [
            ("γράφω", "aorist.active", Array(zip([29, 26, 23, 20, 17, 14, 11, 8, 5, 3],
                                                 [wrong, wrong, right, wrong, wrong, right, wrong, wrong, right, right]))),
            ("έχω", "present.active", Array(zip([28, 25, 22, 19, 16, 13, 10, 7, 4, 1],
                                                Array(repeating: right, count: 9) + [wrong]))),
        ]
        let persons = ParadigmLayout.Person.allCases.filter { $0 != .firstSingular }
        for (word, facet, answers) in series {
            for (index, answer) in answers.enumerated() {
                let card = CardKey(word: WordKey(lang: "ell", word: word), kind: .conjugation, facet: facet)
                try await recordAnswer(AnswerRecord(card: card, exercise: .conjugation, mode: .drill, runID: UUID(),
                                                    outcome: answer.outcome, durationMs: 4_000,
                                                    detail: persons[index % persons.count].rawValue),
                                       today: today.adding(days: -answer.daysAgo), goal: goal)
            }
        }
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO learn_card(lang, word, kind, facet, step, due_day, last_day)
                VALUES ('ell', 'πρέπει', 'conjugation', 'future.active', 5, ?, ?)
                """, arguments: [today.adding(days: 20).rawValue, today.adding(days: -10).rawValue])
        }
        return ["ell"]
    }
    #endif

    /// `-resetData` (DEBUG): every learning row.
    func clearLearning() async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: """
                DELETE FROM learn_review; DELETE FROM learn_card; DELETE FROM learn_word; DELETE FROM learn_day
                """)
        }
    }

    // MARK: - Learning statistics (0166, #163)
    //
    // The queries behind the aggregates in `Models/Learning.swift`. Reads go
    // through `read`; `setGoal` is a plain user-database write, never
    // retried. The goal, the streak, the chart, a run and a word read every
    // language; the other numbers take the chosen `lang`. Each query uses an
    // index or reads a small table.

    /// Today's goal changed in Settings: today's `learn_day` row takes it,
    /// so a day keeps the last goal set before it ended.
    func setGoal(_ goal: Int, today: LearnDay) async throws {
        let pool = try await userPool()
        try await pool.write { db in
            try db.execute(sql: """
                INSERT INTO learn_day(day, goal) VALUES (?, ?)
                ON CONFLICT(day) DO UPDATE SET goal = excluded.goal
                """, arguments: [today.rawValue, goal])
        }
    }

    /// The goal in force when each day ended. A day with answers and no row
    /// (before #163) uses the current goal.
    func learnDayGoals() async throws -> [LearnDay: Int] {
        let pool = try await userPool()
        return try await read(pool) { db in
            var goals: [LearnDay: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT day, goal FROM learn_day") {
                goals[try Self.learnDay(row["day"])] = row["goal"]
            }
            return goals
        }
    }

    /// One `DayCount` per day with answers, every language: the goal, the
    /// streak and the chart.
    func dayCounts() async throws -> [LearnDay: DayCount] {
        let pool = try await userPool()
        return try await read(pool) { db in
            var counts: [LearnDay: DayCount] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT day, COUNT(*) AS exercises, SUM(outcome <> 'wrong') AS "right",
                       SUM(MIN(MAX(duration_ms, 0), \(ReviewSummary.durationCapMs))) AS time_ms,
                       SUM(introduced) AS new_words
                FROM learn_review GROUP BY day
                """) {
                counts[try Self.learnDay(row["day"])] = DayCount(exercises: row["exercises"], right: row["right"],
                                                                 timeMs: row["time_ms"], newWords: row["new_words"])
            }
            return counts
        }
    }

    /// The answers of `lang` on `day`: Today's numbers through
    /// `ReviewSummary`.
    func reviewRows(day: LearnDay, lang: String) async throws -> [ReviewRow] {
        try await reviewRows(where: "day = ? AND lang = ?", [day.rawValue, lang])
    }

    /// The answers of one run, whatever its language and days: 0131's run
    /// summary through `ReviewSummary`, on the `learn_review_run` index.
    func reviewRows(run: UUID) async throws -> [ReviewRow] {
        try await reviewRows(where: "run_id = ?", [run.uuidString])
    }

    private func reviewRows(where condition: String, _ arguments: StatementArguments) async throws -> [ReviewRow] {
        let pool = try await userPool()
        return try await read(pool) { db in
            try Row.fetchAll(db, sql: """
                SELECT lang, word, kind, outcome, introduced, duration_ms, facet FROM learn_review
                WHERE \(condition) ORDER BY id
                """, arguments: arguments).map { row in
                guard let kind = CardKind(rawValue: row["kind"]),
                      let outcome = Outcome(rawValue: row["outcome"]) else { throw DBError.learningRowUnreadable }
                return ReviewRow(word: WordKey(lang: row["lang"], word: row["word"]), kind: kind, outcome: outcome,
                                 introduced: row["introduced"], durationMs: row["duration_ms"], facet: row["facet"])
            }
        }
    }

    /// Recognition (match the pairs included) and production answers of
    /// `lang` from `since` on.
    func directionAccuracy(since: LearnDay, lang: String) async throws -> DirectionAccuracy {
        let pool = try await userPool()
        return try await read(pool) { db in
            var tallies: [CardKind: Tally] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT kind, COUNT(*) AS answers, SUM(outcome <> 'wrong') AS "right" FROM learn_review
                WHERE day >= ? AND lang = ? AND kind IN \(LearningSQL.wordKinds)
                GROUP BY kind
                """, arguments: [since.rawValue, lang]) {
                guard let kind = CardKind(rawValue: row["kind"]) else { throw DBError.learningRowUnreadable }
                tallies[kind] = Tally(answers: row["answers"], right: row["right"])
            }
            return Accuracy.byDirection(tallies)
        }
    }

    /// The words of `lang` with the most mistakes on word cards from
    /// `since` on (`HardestWords.rank`), with their text, its language
    /// (`translation_lang`) and entry. The via filters nothing here.
    func hardestWords(since: LearnDay, lang: String,
                      limit: Int = HardestWords.wordLimit) async throws -> [HardWord] {
        try await hardWords(kinds: LearningSQL.wordKinds, since: since, lang: lang, limit: limit)
    }

    /// The verbs of `lang` with the most mistakes in E5's drill from
    /// `since` on.
    func hardestVerbs(since: LearnDay, lang: String,
                      limit: Int = HardestWords.verbLimit) async throws -> [HardWord] {
        try await hardWords(kinds: "('\(CardKind.conjugation.rawValue)')", since: since, lang: lang, limit: limit)
    }

    /// Words of `lang` with a wrong answer on cards of `kinds` (an SQL list)
    /// from `since` on, each with every answer of those cards in the window.
    private func hardWords(kinds: String, since: LearnDay, lang: String, limit: Int) async throws -> [HardWord] {
        let pool = try await userPool()
        let words = try await read(pool) { db in
            try Row.fetchAll(db, sql: """
                SELECT r.lang, r.word, COUNT(*) AS answers, SUM(r.outcome <> 'wrong') AS "right",
                       MAX(CASE WHEN r.outcome = 'wrong' THEN r.id END) AS latest_mistake,
                       w.term, w.translation, w.translation_lang, w.source, w.headword
                FROM learn_review r
                LEFT JOIN learn_word w ON w.lang = r.lang AND w.word = r.word
                WHERE r.day >= ? AND r.lang = ? AND r.kind IN \(kinds)
                GROUP BY r.lang, r.word
                HAVING SUM(r.outcome = 'wrong') > 0
                """, arguments: [since.rawValue, lang]).map { row -> HardWord in
                let word: String = row["word"]
                let term: String? = row["term"], translation: String? = row["translation"]
                let translationLang: String? = row["translation_lang"]
                let source: String? = row["source"], headword: String? = row["headword"]
                return HardWord(key: WordKey(lang: row["lang"], word: word), term: term ?? word,
                                translation: translation ?? "", translationLang: translationLang ?? "",
                                entry: source.flatMap { source in headword.map { EntryKey(source: source, word: $0) } },
                                tally: Tally(answers: row["answers"], right: row["right"]),
                                latestMistake: row["latest_mistake"])
            }
        }
        return HardestWords.rank(words, limit: limit)
    }

    /// E5's drill answers of `lang` from `since` on, by tense: both voices
    /// of a tense together (`Accuracy.byTense`).
    func tenseAccuracy(since: LearnDay, lang: String) async throws -> [String: Tally] {
        let pool = try await userPool()
        return try await read(pool) { db in
            var facets: [String: Tally] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT facet, COUNT(*) AS answers, SUM(outcome <> 'wrong') AS "right" FROM learn_review
                WHERE day >= ? AND lang = ? AND kind = '\(CardKind.conjugation.rawValue)'
                GROUP BY facet
                """, arguments: [since.rawValue, lang]) {
                facets[row["facet"]] = Tally(answers: row["answers"], right: row["right"])
            }
            return Accuracy.byTense(facets)
        }
    }

    /// Every word of `lang` in learning with its word cards, paused ones
    /// included: list progress (`ListProgress.of`) and the forecast.
    func wordStates(lang: String) async throws -> [WordKey: WordLearningState] {
        let pool = try await userPool()
        return try await read(pool) { db in
            var cards: [WordKey: [CardState]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT * FROM learn_card WHERE lang = ? AND kind IN \(LearningSQL.wordKinds)
                ORDER BY word, kind DESC, facet
                """, arguments: [lang]) {
                let card = try Self.cardState(row)
                cards[card.key.word, default: []].append(card)
            }
            var states: [WordKey: WordLearningState] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM learn_word WHERE lang = ?", arguments: [lang]) {
                let word = try Self.learnWord(row)
                states[word.key] = WordLearningState(word: word, cards: cards[word.key] ?? [])
            }
            return states
        }
    }

    /// Every wrong answer on the word's two cards, ever (#165).
    func errorCount(lang: String, word: String) async throws -> Int {
        let key = WordKey(lang: lang, word: word)
        let pool = try await userPool()
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM learn_review
                WHERE lang = ? AND word = ? AND kind IN \(LearningSQL.wordKinds) AND outcome = 'wrong'
                """, arguments: [key.lang, key.word]) ?? 0
        }
    }

    private static func learnDay(_ text: String) throws -> LearnDay {
        guard let day = LearnDay(rawValue: text) else { throw DBError.learningRowUnreadable }
        return day
    }

    private static func cardState(_ row: Row) throws -> CardState {
        guard let kind = CardKind(rawValue: row["kind"]) else { throw DBError.learningRowUnreadable }
        let lastDay: String? = row["last_day"]
        return CardState(key: CardKey(word: WordKey(lang: row["lang"], word: row["word"]), kind: kind, facet: row["facet"]),
                         step: row["step"], dueDay: try learnDay(row["due_day"]),
                         lastDay: try lastDay.map(learnDay), isSuspended: row["suspended"])
    }

    private static func learnWord(_ row: Row) throws -> LearnWord {
        let source: String? = row["source"], headword: String? = row["headword"]
        let introducedDay: String? = row["introduced_day"]
        return LearnWord(key: WordKey(lang: row["lang"], word: row["word"]), term: row["term"],
                         endings: row["endings"], partOfSpeech: row["pos"], translation: row["translation"],
                         translationLang: row["translation_lang"],
                         entry: source.flatMap { source in headword.map { EntryKey(source: source, word: $0) } },
                         listID: row["list_id"], introducedDay: try introducedDay.map(learnDay))
    }

    // MARK: - Metadata & Statistics

    /// The `dict_metadata` rows of the bundle and every installed pack, in
    /// file order (`DictionarySchemas.all`), each file in its own order
    /// (#237). A pack that is not installed reads as empty.
    static let metadataSQL: String = {
        DictionarySchemas.all.enumerated().map { index, schema in
            "SELECT source, display_name, version, license, url, word_count, description, from_lang, to_lang, "
                + "\(index) AS file_order, rowid AS row_order FROM \(schema).dict_metadata"
        }.joined(separator: " UNION ALL ")
    }()

    /// Metadata of every installed dictionary: the bundle's, then each
    /// installed pack's.
    func fetchMetadata() async throws -> [DictMetadata] {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await read(pool) { db in
            try DictMetadata.fetchAll(db, sql: "SELECT * FROM (\(Self.metadataSQL)) ORDER BY file_order, row_order")
        }
    }

    /// Fetch metadata for a single dictionary source.
    func fetchMetadata(source: String) async throws -> DictMetadata? {
        guard let pool = dbPool else { throw DBError.notConnected }
        return try await read(pool) { db in
            try DictMetadata.fetchOne(db, sql: """
                SELECT * FROM (\(Self.metadataSQL)) WHERE source = ? ORDER BY file_order, row_order LIMIT 1
                """, arguments: [source])
        }
    }

    /// Per-source entry counts, count-desc, with display name / license /
    /// version from the metadata (Issue #92, for the #91 detail). Issue #138:
    /// a bundled source counts its `word_count` plus any rows imported under
    /// its ID; an imported source counts its rows (indexed) and shows its ID
    /// with an empty license and version. No scan of the bundled rows.
    /// Equal counts keep the file order, then each file's own (#237), and
    /// imported-only sources come after them by ID, so the Dictionary Order
    /// default built from this list is stable (#245).
    func fetchSourceStats() async throws -> [SourceStat] {
        let pool = try await userPool()
        return try await read(pool) { db in
            // #237: the metadata of the bundle and every installed pack.
            let sql = """
                WITH i AS MATERIALIZED (SELECT source, COUNT(*) AS cnt FROM imported_entries GROUP BY source),
                     m AS MATERIALIZED (\(Self.metadataSQL))
                SELECT m.source AS source, m.display_name AS display_name, m.license AS license,
                       m.version AS version, m.word_count + COALESCE(i.cnt, 0) AS cnt,
                       m.file_order AS file_order, m.row_order AS row_order
                FROM m
                LEFT JOIN i ON i.source = m.source
                UNION ALL
                SELECT i.source, i.source, '', '', i.cnt, \(DictionarySchemas.all.count), 0
                FROM i
                WHERE i.source NOT IN (SELECT source FROM m)
                ORDER BY cnt DESC, file_order, row_order, source
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
    // 1.4.0 for a file named like a bundled source. Since #237 that is the
    // file of the import's source; for a pack that is not installed nothing
    // is skipped (its install removes the rows it has, #242).

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
        let keyCheck = schemas.schema(ofSource: source).map { schema in
            "WHERE NOT EXISTS (SELECT 1 FROM \(schema).entries WHERE word = ?1 COLLATE NOCASE AND source = ?5)"
        } ?? ""
        return try await dictionaryWrite(pool) { db in
            // Custom imports are not run through the Arabic or Greek
            // normalizers (single source of truth stays in the Python build),
            // so the search key is the word verbatim. Consequence: imported
            // Arabic is searched diacritic-sensitively — a documented v1.3.0
            // limitation, not a regression.
            let insert = try db.makeStatement(sql: """
                INSERT OR IGNORE INTO imported_entries(word, word_normalized, definition, phonetic, pos, source)
                SELECT ?1, ?1, ?2, ?3, ?4, ?5
                \(keyCheck)
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

    /// Rows of `source` in the dictionary files and the imports.
    func entryCount(source: String) async throws -> Int {
        let pool = try await userPool()
        let files = DictionarySchemas.all.map { "(SELECT COUNT(*) FROM \($0).entries WHERE source = ?1)" }
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: "SELECT " + (files + ["(SELECT COUNT(*) FROM imported_entries WHERE source = ?1)"])
                .joined(separator: " + "), arguments: [source]) ?? 0
        }
    }

    func entryCount() async throws -> Int {
        let pool = try await userPool()
        let files = DictionarySchemas.all.map { "(SELECT COUNT(*) FROM \($0).entries)" }
        return try await read(pool) { db in
            try Int.fetchOne(db, sql: "SELECT " + (files + ["(SELECT COUNT(*) FROM imported_entries)"])
                .joined(separator: " + ")) ?? 0
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

    /// `Application Support/DictApp`: the user database and, since #237, the
    /// installed packs (`Packs/`).
    static func appSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DictApp")
    }

    /// The bundled dictionary file, `dictionaries.sqlite`.
    static func bundledDictionaryURL() -> URL? {
        Bundle.main.url(forResource: DictionaryFile.resourceName, withExtension: DictionaryFile.resourceExtension)
    }

    /// The bundled stub, `empty-pack.sqlite`: attached for every pack that
    /// is not installed (#237).
    static func bundledStubURL() -> URL? {
        Bundle.main.url(forResource: DictionaryFile.stubResourceName, withExtension: DictionaryFile.resourceExtension)
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

    /// UI-test hook `-legacyFixture <path>` (#244): a 1.x install about to
    /// update, for the upgrade test. The user database and any 1.x database
    /// are deleted, as by `-resetDatabase`, and the 1.x fixture at `fixture`
    /// becomes `dict.sqlite`, so this launch moves it.
    static func installLegacyFixture(_ fixture: URL) throws {
        removeDatabaseFiles()
        let legacy = legacyDatabaseURL()
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: legacy)
    }

    /// Unit-test seam: runs `body` on the writer, the connection a write to
    /// `dict.*` would use, so a test can prove the attached dictionary file
    /// is read-only. The app never calls it.
    func writeForTesting<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else { throw DBError.notConnected }
        let result = try await pool.write(body)
        // The write may have changed a list (0130).
        wordListsDidChange()
        return result
    }
    #endif

    enum DBError: Error, LocalizedError {
        case notConnected
        case dictionaryMissing
        /// `recordAnswer` for a card that does not exist.
        case cardMissing
        /// A learning row with a day or a kind this build cannot read.
        case learningRowUnreadable
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Database is not connected. Call setup() first."
            case .dictionaryMissing: return "The bundled dictionary file is missing."
            case .cardMissing: return "The card is not in learning."
            case .learningRowUnreadable: return "A learning row could not be read."
            }
        }
    }
}

// MARK: - Grammar (0133, #172)
//
// A taught language's topics, from the file of its lists
// (`DictionarySchemas.listsSchema(for:)`: Greek in the Greek pack). A pack
// that is not installed reads as the stub, whose tables are empty; a
// language without lists has no grammar and runs no query.

extension DatabaseService {
    /// The topics of `lang` by level and order, each titled in
    /// `explainLang` when it has that text, else in English (never in a
    /// third language). The view models pass the via of `lang`.
    func grammarTopics(lang: String, explainLang: String) async throws -> [GrammarTopicSummary] {
        guard let schema = DictionarySchemas.listsSchema(for: lang) else { return [] }
        let pool = try await userPool()
        return try await read(pool) { db in
            try Self.grammarSummaries(db, schema: schema, explainLang: explainLang,
                                      condition: "t.lang = ?2", argument: lang)
        }
    }

    /// One topic: its summary, its body in the same language as the title,
    /// its links and its related topics' summaries. Nil for an unknown id
    /// or a pack that is gone.
    func grammarTopic(id: String, explainLang: String) async throws -> GrammarTopic? {
        let lang = String(id.prefix { $0 != "-" })
        guard let schema = DictionarySchemas.listsSchema(for: lang) else { return nil }
        let pool = try await userPool()
        return try await read(pool) { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT body FROM \(schema).grammar_text
                WHERE topic_id = ?1 AND explain_lang IN (?2, 'eng')
                ORDER BY explain_lang = ?2 DESC LIMIT 1
                """, arguments: [id, explainLang]),
                  let summary = try Self.grammarSummaries(db, schema: schema, explainLang: explainLang,
                                                          condition: "t.id = ?2", argument: id).first
            else { return nil }
            let links = try Self.grammarLinks(db, schema: schema, condition: "l.topic_id = ?", argument: id)
            let relatedIDs = links.filter { $0.kind == .topic }.sorted { $0.ord < $1.ord }.map(\.key)
            let topics = Dictionary(
                try Self.grammarSummaries(db, schema: schema, explainLang: explainLang, condition: "t.lang = ?2",
                                          argument: summary.lang).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first })
            return GrammarTopic(summary: summary, body: row["body"], links: links,
                                related: relatedIDs.compactMap { topics[$0] })
        }
    }

    /// Every link of `lang`'s topics, for the Definition and Rule lookups
    /// (#174): about 200 rows, read on each use.
    func grammarLinks(lang: String) async throws -> [GrammarLink] {
        guard let schema = DictionarySchemas.listsSchema(for: lang) else { return [] }
        let pool = try await userPool()
        return try await read(pool) { db in
            try Self.grammarLinks(db, schema: schema, condition: "t.lang = ?", argument: lang)
        }
    }

    /// The topics matching `condition` on `t` (`grammar_topic`, its
    /// `argument` is `?2`), with the text in `explainLang` or else `eng`,
    /// by level and order.
    private static func grammarSummaries(_ db: Database, schema: String, explainLang: String, condition: String,
                                         argument: String) throws -> [GrammarTopicSummary] {
        try Row.fetchAll(db, sql: """
            SELECT t.id, t.lang, t.level, t.ord, x.title, x.explain_lang
            FROM \(schema).grammar_topic t
            JOIN \(schema).grammar_text x ON x.topic_id = t.id AND x.explain_lang = (
                SELECT explain_lang FROM \(schema).grammar_text
                WHERE topic_id = t.id AND explain_lang IN (?1, 'eng')
                ORDER BY explain_lang = ?1 DESC LIMIT 1)
            WHERE \(condition)
            ORDER BY t.level, t.ord
            """, arguments: [explainLang, argument]).map { row in
                GrammarTopicSummary(id: row["id"], lang: row["lang"], level: row["level"], ord: row["ord"],
                                    title: row["title"], explainLang: row["explain_lang"])
            }
    }

    /// The links matching `condition` on `l` (`grammar_link`) and `t` (its
    /// topic), by topic, kind and order; unknown kinds are skipped.
    private static func grammarLinks(_ db: Database, schema: String, condition: String,
                                     argument: String) throws -> [GrammarLink] {
        try Row.fetchAll(db, sql: """
            SELECT l.topic_id, l.kind, l.key, l.ord
            FROM \(schema).grammar_link l JOIN \(schema).grammar_topic t ON t.id = l.topic_id
            WHERE \(condition)
            ORDER BY l.topic_id, l.kind, l.ord
            """, arguments: [argument]).compactMap { row in
                guard let kind = GrammarLink.Kind(rawValue: row["kind"]) else { return nil }
                return GrammarLink(topicID: row["topic_id"], kind: kind, key: row["key"], ord: row["ord"])
            }
    }
}

// MARK: - Learning SQL (0131, #157)

/// The learning statements that work on keys, so the My words key exists
/// once in SQL (0130, "For E4 and E10", item 2).
enum LearningSQL {
    /// The word cards' kinds as an SQL list: `('recognition', 'production')`.
    static let wordKinds = "(" + CardKind.wordKinds.map { "'\($0.rawValue)'" }.joined(separator: ", ") + ")"

    /// Every My words row with its `WordKey` (`lang`, `word`), its
    /// `source`, its word as `term` and its `added_at`.
    static let myWordsKeys = """
        SELECT COALESCE(d.from_lang, s.from_lang, 'und') AS lang, lower(m.word) AS word,
               m.source AS source, m.word AS term, m.added_at AS added_at
        FROM my_words m
        LEFT JOIN (\(DictionarySchemas.sourceLanguageSQL)) d ON d.source = m.source
        LEFT JOIN imported_sources s ON s.source = m.source
        """

    /// Enrols the My words of the language `?1` not in learning yet: one
    /// word per key, from the row added first (`added_at`, then `source`),
    /// dated by it, so the oldest come first among new words.
    static let enrolMyWords = """
        INSERT INTO learn_word(lang, word, term, source, headword, added_at)
        SELECT lang, word, term, source, term, added_at FROM (
            SELECT k.*, ROW_NUMBER() OVER (PARTITION BY k.lang, k.word ORDER BY k.added_at, k.source) AS n
            FROM (\(myWordsKeys)) k
            WHERE k.lang = ?1
        ) m
        WHERE m.n = 1 AND NOT EXISTS (SELECT 1 FROM learn_word w WHERE w.lang = m.lang AND w.word = m.word)
        """

    /// The two cards of the word (`?1`, `?2`), new and due on `?3`, unless
    /// it has them.
    static let createWordCards = """
        INSERT OR IGNORE INTO learn_card(lang, word, kind, due_day)
        VALUES (?1, ?2, 'recognition', ?3), (?1, ?2, 'production', ?3)
        """

    /// The two cards of every word of the language `?1` that lacks them,
    /// new and due on `?2`.
    static let createLanguageCards = """
        INSERT OR IGNORE INTO learn_card(lang, word, kind, due_day)
        SELECT w.lang, w.word, k.kind, ?2
        FROM learn_word w, (SELECT 'recognition' AS kind UNION ALL SELECT 'production') k
        WHERE w.lang = ?1
        """

    /// Deletes every My words row of the key (`?1`, `?2`), whatever its
    /// source.
    static let deleteMyWordsOfKey = """
        DELETE FROM my_words WHERE lower(word) = ?2 AND source IN (
            SELECT source FROM (\(myWordsKeys)) WHERE lang = ?1 AND word = ?2)
        """
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
        /// Pack dictionaries whose 1.x rows were dropped by their count (#244).
        var packDictionaries = 0
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
                      + "and \(moved.myWords) bookmarks, left the rows of \(moved.packDictionaries) pack "
                      + "dictionaries to their packs, then deleted the 1.x database, in \(ms) ms")
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
        // Issue #244, the count rule (0237, "Update from 1.x"): the 1.x rows
        // of a pack's dictionary whose pack is not installed are the pack's,
        // and are dropped, when their count is the catalog's `word_count`.
        // Every 1.x seed holds exactly today's rows of each dictionary it
        // shipped, and an import under the same ID only adds rows. Any other
        // count moves all of them below; the pack's install deletes the rows
        // it has (`removeImportsCovered`).
        let attached = DictionarySchemas.all.map { "SELECT source FROM \($0).dict_metadata" }
            .joined(separator: " UNION ALL ")
        let packRows = try String.fetchAll(db, sql: """
            WITH counts AS (SELECT source, COUNT(*) AS n FROM legacy.entries GROUP BY source)
            SELECT c.source FROM dict.catalog_source c JOIN counts ON counts.source = c.source
            WHERE counts.n = c.word_count AND c.source NOT IN (\(attached))
            """)
        moved.packDictionaries = packRows.count
        let notPackRows = packRows.isEmpty
            ? ""
            : "l.source NOT IN (\(packRows.map { _ in "?" }.joined(separator: ", ")))\n  AND "
        // Imported dictionaries: every other 1.x row whose key the dictionary
        // files lack (the bundle and every installed pack, #237: a source's
        // rows are in one file, and a pack that is not installed reads as
        // empty). This carries custom imports and imports named like a
        // bundled source, and drops the 1.x copy of the bundled rows. The
        // search key is the word, as on import; the triggers fill
        // `imported_fts`.
        let inFiles = DictionarySchemas.all.map { schema in
            "NOT EXISTS (SELECT 1 FROM \(schema).entries d WHERE d.word = l.word COLLATE NOCASE AND d.source = l.source)"
        }.joined(separator: "\n  AND ")
        try db.execute(sql: """
            INSERT OR IGNORE INTO imported_entries(word, word_normalized, definition, phonetic, pos, source, created_at)
            SELECT l.word, l.word, l.definition, COALESCE(l.phonetic, ''), COALESCE(l.pos, ''), l.source, l.created_at
            FROM legacy.entries l
            WHERE \(notPackRows)\(inFiles)
            ORDER BY l.id
            """, arguments: StatementArguments(packRows))
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
