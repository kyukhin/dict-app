// PackService.swift
// Language packs (Issue #237, docs/specs/0237-downloads.md): the catalog in
// the bundled dictionary file, the installed pack files in `Application
// Support/DictApp/Packs/`, the launch scan, and the install of a pack from
// its xz asset: verify, decompress, rename, attach. #241 installs from a
// local asset (the DEBUG `-installPacks` hook and the unit tests); #242 adds
// the download.

import Compression
import CryptoKit
import Foundation
import GRDB

// MARK: - Catalog

/// One `catalog_pack` row: a pack this app version knows, and its pinned
/// asset and file.
struct CatalogPack: Equatable, Sendable {
    let id: PackID
    let ord: Int
    /// ISO 639-3 of the language it serves.
    let lang: String
    /// `language` (dictionaries, maybe forms and lists) or `lists`.
    let kind: String
    /// The first 12 hex digits of `fileSHA256`.
    let version: String
    let url: URL?
    /// Of the asset.
    let sha256: String
    let size: Int64
    /// Of the installed file.
    let fileSHA256: String
    let fileSize: Int64

    /// `<id>-<version>.sqlite`, the installed file.
    var fileName: String { "\(id.rawValue)-\(version).sqlite" }
    /// `<id>-<version>.sqlite.xz`, the release asset.
    var assetName: String { fileName + ".xz" }
}

/// One `catalog_source` row: a dictionary of a pack, installed or not.
struct CatalogSource: Equatable, Sendable {
    let packID: PackID
    let source: String
    let displayName: String
    let wordCount: Int
    let fromLang: String
    let toLang: String
}

/// One `catalog_list` row: a built-in word list of a pack (E3).
struct CatalogList: Equatable, Sendable {
    let packID: PackID
    let id: String
    let lang: String
    let level: String
    let wordCount: Int
}

/// A dictionary's languages, as `DictionarySchemas.sourceLanguageSQL` reads
/// them: the bundle's dictionaries and the catalog's, installed or not.
struct CatalogDirection: Equatable, Sendable {
    let source: String
    let fromLang: String
    let toLang: String
}

/// One `catalog_pair` row: a limited pair the catalog declares (Kirill,
/// 2026-11-04), offered with no dictionary from `lang` into `via`.
struct LimitedPair: Equatable, Sendable {
    let lang: String
    let via: String
    /// The language of its meanings: a dictionary goes from `lang` into it.
    let meaningsLang: String
}

/// A language pair to learn (0237, "Learning a pair"; E4): `lang` learned
/// through `via`, its explanations in `via` and its meanings in
/// `meaningsLang`. It exists when a dictionary goes from `lang` into `via`
/// (meanings in `via`), or as a limited pair the catalog declares (Greek
/// via Russian, meanings in English) until such a dictionary comes.
struct CatalogPair: Equatable, Sendable {
    /// ISO 639-3 of the language learned.
    let lang: String
    /// ISO 639-3 of the language it is learned through.
    let via: String
    /// ISO 639-3 of its meanings: `via`, or the declared one of a limited pair.
    let meaningsLang: String
    /// Declared in the catalog, with no dictionary from `lang` into `via`.
    let limited: Bool
    /// The dictionaries of its meanings, from `lang` into `meaningsLang`, in
    /// catalog order.
    let sources: [String]
    /// What learning it needs, in install order: the lists pack of `lang`
    /// when it has one, then the packs of `sources`; each once, never the
    /// bundle.
    let packs: [PackID]
    /// The asset size of each of `packs`, in bytes.
    let assetSizes: [PackID: Int64]

    /// The bytes choosing the pair downloads: the assets of its packs not in
    /// `installed` (the packs with a usable file).
    func downloadSize(installed: Set<PackID>) -> Int64 {
        packs.filter { !installed.contains($0) }.reduce(0) { $0 + (assetSizes[$1] ?? 0) }
    }
}

/// A language the app offers (0237, "For E3 and E4"): English is in the
/// bundle; every other language comes with its pack.
struct CatalogLanguage: Equatable, Sendable {
    let lang: String
    let isBundled: Bool
    /// The pack with the language's dictionaries; nil for English.
    let dictionaryPack: PackID?
    /// The pack with its built-in word lists: `ell` for Greek, `eng-lists`
    /// for English, nil for the others.
    let listsPack: PackID?
    let hasBuiltInLists: Bool
    /// The assets to download and the files installed, in bytes, of every
    /// pack of the language.
    let downloadSize: Int64
    let installedSize: Int64
}

/// The packs this app version knows, read from the bundled dictionary file
/// (0237, "The catalog"): no server is asked, and an app update brings the
/// new list with it.
struct PackCatalog: Equatable, Sendable {
    var packs: [CatalogPack] = []
    var sources: [CatalogSource] = []
    var lists: [CatalogList] = []
    /// Every dictionary's languages, in catalog order: the bundle's first.
    var directions: [CatalogDirection] = []
    /// The limited pairs the catalog declares (`catalog_pair`).
    var limitedPairs: [LimitedPair] = []

    static let empty = PackCatalog()

    /// Reads the catalog on `db`, a connection with the bundled file
    /// attached as `dict`: the pool's, through `DatabaseService.packCatalog`
    /// (0237, "Launch"), so no connection is opened on the bundle (#111).
    static func read(_ db: Database) throws -> PackCatalog {
        let packs = try Row.fetchAll(db, sql: """
            SELECT id, ord, lang, kind, version, url, sha256, size, file_sha256, file_size
            FROM dict.catalog_pack ORDER BY ord
            """).map { row in
                CatalogPack(id: PackID(row["id"] as String), ord: row["ord"], lang: row["lang"],
                            kind: row["kind"], version: row["version"], url: URL(string: row["url"]),
                            sha256: row["sha256"], size: row["size"], fileSHA256: row["file_sha256"],
                            fileSize: row["file_size"])
            }
        let sources = try Row.fetchAll(db, sql: """
            SELECT pack_id, source, display_name, word_count, from_lang, to_lang
            FROM dict.catalog_source ORDER BY rowid
            """).map { row in
                CatalogSource(packID: PackID(row["pack_id"] as String), source: row["source"],
                              displayName: row["display_name"], wordCount: row["word_count"],
                              fromLang: row["from_lang"], toLang: row["to_lang"])
            }
        let lists = try Row.fetchAll(db, sql: """
            SELECT pack_id, id, lang, level, word_count FROM dict.catalog_list ORDER BY rowid
            """).map { row in
                CatalogList(packID: PackID(row["pack_id"] as String), id: row["id"], lang: row["lang"],
                            level: row["level"], wordCount: row["word_count"])
            }
        let directions = try Row.fetchAll(db, sql: """
            SELECT l.source, l.from_lang, l.to_lang FROM (\(DictionarySchemas.sourceLanguageSQL)) AS l
            LEFT JOIN dict.dict_metadata AS m ON m.source = l.source
            LEFT JOIN dict.catalog_source AS c ON c.source = l.source
            ORDER BY m.rowid IS NULL, m.rowid, c.rowid
            """).map { row in
                CatalogDirection(source: row["source"], fromLang: row["from_lang"], toLang: row["to_lang"])
            }
        let limitedPairs = try Row.fetchAll(db, sql: """
            SELECT lang, via, meanings_lang FROM dict.catalog_pair ORDER BY rowid
            """).map { row in
                LimitedPair(lang: row["lang"], via: row["via"], meaningsLang: row["meanings_lang"])
            }
        return PackCatalog(packs: packs, sources: sources, lists: lists, directions: directions,
                           limitedPairs: limitedPairs)
    }

    func pack(_ id: PackID) -> CatalogPack? {
        packs.first { $0.id == id }
    }

    /// The dictionaries of `id`, in catalog order.
    func sources(of id: PackID) -> [CatalogSource] {
        sources.filter { $0.packID == id }
    }

    /// English first, then every language with a pack, in catalog order.
    var languages: [CatalogLanguage] {
        var langs = ["eng"]
        for pack in packs where !langs.contains(pack.lang) {
            langs.append(pack.lang)
        }
        return langs.map { lang in
            let ofLang = packs.filter { $0.lang == lang }
            let dictionaryPack = ofLang.first { $0.kind == "language" }?.id
            let listsPack = self.listsPack(for: lang)
            return CatalogLanguage(
                lang: lang, isBundled: lang == "eng", dictionaryPack: dictionaryPack, listsPack: listsPack,
                hasBuiltInLists: listsPack.map { id in lists.contains { $0.packID == id } } ?? false,
                downloadSize: ofLang.reduce(0) { $0 + $1.size },
                installedSize: ofLang.reduce(0) { $0 + $1.fileSize })
        }
    }

    /// The pack of a language's built-in word lists, when the catalog has
    /// it: `ell` for Greek, `eng-lists` for English (`listsSchema(for:)`).
    func listsPack(for lang: String) -> PackID? {
        DictionarySchemas.listsSchema(for: lang).flatMap { schema in
            packs.first { $0.id.schema == schema }?.id
        }
    }

    /// The pairs to learn (0237, "Pairs"): one per distinct (`from_lang`,
    /// `to_lang`) of `directions`, `und` left out, then each of
    /// `limitedPairs` that no dictionary makes a normal pair and one gives
    /// meanings. A pack's new dictionary adds its pair, or turns a limited
    /// one normal, through the catalog. Ordered by the language learned,
    /// then the via, as `languages`; other languages after them, in catalog
    /// order.
    var pairs: [CatalogPair] {
        struct Key: Hashable {
            let lang: String
            let via: String
        }
        var keys: [Key] = []
        var sourcesOf: [Key: [String]] = [:]
        for direction in directions where direction.fromLang != "und" && direction.toLang != "und" {
            let key = Key(lang: direction.fromLang, via: direction.toLang)
            if sourcesOf[key] == nil {
                keys.append(key)
            }
            sourcesOf[key, default: []].append(direction.source)
        }
        var meaningsOf: [Key: String] = [:]
        for limited in limitedPairs where limited.via != "und" {
            let key = Key(lang: limited.lang, via: limited.via)
            guard sourcesOf[key] == nil, meaningsOf[key] == nil,
                  sourcesOf[Key(lang: limited.lang, via: limited.meaningsLang)] != nil else { continue }
            keys.append(key)
            meaningsOf[key] = limited.meaningsLang
        }
        let order = languages.map(\.lang)
        func rank(_ lang: String) -> Int { order.firstIndex(of: lang) ?? order.count }
        let packOfSource = Dictionary(sources.map { ($0.source, $0.packID) }) { first, _ in first }
        return keys.enumerated()
            .sorted { (rank($0.element.lang), rank($0.element.via), $0.offset)
                < (rank($1.element.lang), rank($1.element.via), $1.offset) }
            .map(\.element)
            .map { key in
                let meaningsLang = meaningsOf[key] ?? key.via
                let sources = sourcesOf[Key(lang: key.lang, via: meaningsLang)] ?? []
                var packIDs = listsPack(for: key.lang).map { [$0] } ?? []
                for id in sources.compactMap({ packOfSource[$0] }) where !packIDs.contains(id) {
                    packIDs.append(id)
                }
                let sizes = packIDs.map { ($0, pack($0)?.size ?? 0) }
                return CatalogPair(lang: key.lang, via: key.via, meaningsLang: meaningsLang,
                                   limited: meaningsOf[key] != nil, sources: sources, packs: packIDs,
                                   assetSizes: Dictionary(uniqueKeysWithValues: sizes))
            }
    }

    // The catalog of the running app, which launch loads once (#237).
    private static let lock = NSLock()
    private static var loaded = PackCatalog.empty

    /// The catalog of the bundled file, once launch has read it.
    static var shared: PackCatalog {
        get {
            lock.lock()
            defer { lock.unlock() }
            return loaded
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            loaded = newValue
        }
    }

    /// The languages of `shared` (E3, E4).
    static var languages: [CatalogLanguage] { shared.languages }

    /// The pairs of `shared` (E4).
    static var pairs: [CatalogPair] { shared.pairs }
}

/// An installed pack, as the launch scan or an install found it.
struct InstalledPack: Equatable, Sendable {
    let id: PackID
    let lang: String
    let version: String
    /// Its file has the app's format and is attached; false for a file of
    /// another format, which the stub replaces until an update.
    let usable: Bool
}

/// Why a pack was not installed (0237, "Offline and errors").
enum PackError: Error, Equatable {
    case offline
    case unavailable
    case damaged
    case noSpace
    case cancelled
}

// MARK: - Files

/// The pack files on disk (0237, "Files"). File operations only: no
/// database, no network.
enum PackFiles {
    /// `Application Support/DictApp/Packs/`: the installed packs, excluded
    /// from backup. Not in Caches: iOS purges Caches under storage pressure.
    static func folder() -> URL {
        DatabaseService.appSupportDirectory().appendingPathComponent("Packs", isDirectory: true)
    }

    /// `Caches/DictApp/Downloads/`: downloads in progress (#242).
    static func downloadsFolder() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DictApp/Downloads", isDirectory: true)
    }

    /// What the launch scan found.
    struct Scan: Equatable, Sendable {
        /// The file to attach for each pack that has a usable one.
        var files: [PackID: URL] = [:]
        /// Every pack with a file, usable or not.
        var installed: [InstalledPack] = []
    }

    /// The launch scan (0237, "Launch", step 2): deletes partial files, the
    /// downloads folder, files of packs the catalog does not know and files
    /// superseded by the catalog's version of the same pack. Each catalog
    /// pack then gets its current file, else an older one of the app's
    /// format (usable until an update), else none (the stub). A file of
    /// another format stays, unusable, until an update replaces it.
    static func scan(folder: URL, catalog: PackCatalog, downloads: URL? = nil) -> Scan {
        let fileManager = FileManager.default
        if let downloads {
            try? fileManager.removeItem(at: downloads)
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return Scan() }
        var byPack: [PackID: [String: URL]] = [:]
        for name in names {
            let url = folder.appendingPathComponent(name)
            if name.hasSuffix(".partial") {
                try? fileManager.removeItem(at: url)
                continue
            }
            guard let (id, version) = parse(name) else { continue }
            guard catalog.pack(id) != nil else {
                try? fileManager.removeItem(at: url)
                continue
            }
            byPack[id, default: [:]][version] = url
        }
        var scan = Scan()
        for pack in catalog.packs {
            guard var versions = byPack[pack.id] else { continue }
            if let current = versions[pack.version] {
                for (_, old) in versions where old != current {
                    try? fileManager.removeItem(at: old)
                }
                versions = [pack.version: current]
            }
            // The current file, else an older one of the app's format, the
            // newest first; else a file of another format, unusable.
            let usable = versions.filter { DictionaryFile.headerFormat(of: $0.value) == DictionaryFile.formatVersion }
            let chosen = usable[pack.version].map { (pack.version, $0) }
                ?? usable.max { modified($0.value) < modified($1.value) }.map { ($0.key, $0.value) }
            if let (version, url) = chosen {
                scan.files[pack.id] = url
                scan.installed.append(InstalledPack(id: pack.id, lang: pack.lang, version: version, usable: true))
            } else if let (version, _) = versions.first {
                scan.installed.append(InstalledPack(id: pack.id, lang: pack.lang, version: version, usable: false))
            }
        }
        return scan
    }

    /// `<id>-<version>.sqlite` → (id, version); the version is 12 hex digits.
    static func parse(_ name: String) -> (PackID, String)? {
        guard name.hasSuffix(".sqlite") else { return nil }
        let stem = name.dropLast(".sqlite".count)
        guard let dash = stem.lastIndex(of: "-") else { return nil }
        let version = String(stem[stem.index(after: dash)...])
        guard version.count == 12, version.allSatisfy(\.isHexDigit) else { return nil }
        return (PackID(String(stem[..<dash])), version)
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Installs `pack` from its xz asset at `asset` into `folder` (0237,
    /// "Download and install", steps 3 to 5) and returns the installed file:
    /// 1. the asset's SHA-256 and size must be the catalog's, before any byte
    ///    reaches the decompressor or SQLite;
    /// 2. it is decompressed, streamed, into `<id>-<version>.sqlite.partial`,
    ///    hashed as it is written; the result must be the catalog's file;
    /// 3. the folder and the file are excluded from backup, and `rename(2)`
    ///    commits the install: the folder is the registry.
    /// Throws `PackError.damaged` on a mismatch and `.noSpace` when the disk
    /// is full; either way no partial file stays.
    static func install(asset: URL, pack: CatalogPack, into folder: URL) throws -> URL {
        let (assetSHA, assetSize) = try sha256(of: asset)
        guard assetSHA == pack.sha256, assetSize == pack.size else { throw PackError.damaged }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try excludeFromBackup(folder)
        let final = folder.appendingPathComponent(pack.fileName)
        let partial = folder.appendingPathComponent(pack.fileName + ".partial")
        try? fileManager.removeItem(at: partial)
        do {
            guard fileManager.createFile(atPath: partial.path, contents: nil) else { throw PackError.noSpace }
            let output = try FileHandle(forWritingTo: partial)
            var hasher = SHA256()
            var written: Int64 = 0
            do {
                let filter = try OutputFilter(.decompress, using: .lzma) { data in
                    guard let data else { return }
                    try output.write(contentsOf: data)
                    hasher.update(data: data)
                    written += Int64(data.count)
                }
                let input = try FileHandle(forReadingFrom: asset)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                    try filter.write(chunk)
                }
                try filter.finalize()
                try output.synchronize()
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
            let fileSHA = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard fileSHA == pack.fileSHA256, written == pack.fileSize else { throw PackError.damaged }
            var partialURL = partial
            try excludeFromBackup(&partialURL)
            guard rename(partial.path, final.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return final
        } catch {
            try? fileManager.removeItem(at: partial)
            if let packError = error as? PackError { throw packError }
            if isOutOfSpace(error) { throw PackError.noSpace }
            // A stream the decompressor cannot read is a damaged download.
            if error is FilterError { throw PackError.damaged }
            throw error
        }
    }

    /// The SHA-256 (hex) and size of the file at `url`, read in 1 MB chunks.
    static func sha256(of url: URL) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += Int64(chunk.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        try excludeFromBackup(&url)
    }

    private static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError { return true }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOutOfSpace(underlying)
        }
        return false
    }

    #if DEBUG
    /// The DEBUG hook `-resetPacks`: deletes every installed pack and every
    /// download in progress.
    static func removeAll() {
        try? FileManager.default.removeItem(at: folder())
        try? FileManager.default.removeItem(at: downloadsFolder())
    }
    #endif
}

// MARK: - Service

/// Owns the installed packs: the launch scan, the installs and what is
/// installed (0237, "Download and install"). #242 adds the network.
actor PackService {
    static let shared = PackService()

    private let folder: URL
    private let database: DatabaseService
    private(set) var catalog = PackCatalog.empty
    private var installed: [PackID: InstalledPack] = [:]

    init(folder: URL = PackFiles.folder(), database: DatabaseService = .shared) {
        self.folder = folder
        self.database = database
    }

    /// Launch, after `DatabaseService.setup` has attached every pack name on
    /// the stub (0237, "Launch", step 3): reads the catalog through the
    /// pool, scans the packs folder, then points each catalog pack at its
    /// chosen file (or the stub) in one re-attach, before any reader is
    /// busy. Returns the files attached.
    @discardableResult
    func prepare() async throws -> [PackID: URL] {
        catalog = try await database.packCatalog()
        PackCatalog.shared = catalog
        let scan = PackFiles.scan(folder: folder, catalog: catalog, downloads: PackFiles.downloadsFolder())
        installed = Dictionary(uniqueKeysWithValues: scan.installed.map { ($0.id, $0) })
        var changes: [PackID: URL?] = [:]
        for pack in catalog.packs {
            changes[pack.id] = scan.files[pack.id]
        }
        try await database.attachPacks(changes)
        return scan.files
    }

    /// Every pack with a file, in catalog order (0237, "For E3 and E4").
    func installedPacks() -> [InstalledPack] {
        catalog.packs.compactMap { installed[$0.id] }
    }

    /// Installs each pack of `ids` from its asset in `assets`, skipping a
    /// pack already installed at the catalog's version, then attaches the
    /// new files on every connection at once. A pack that replaces an older
    /// version deletes the old file after the attach. When one install
    /// fails, the packs installed before it are attached, then it throws.
    func install(_ ids: [PackID], fromAssetsIn assets: URL) async throws {
        var changes: [PackID: URL?] = [:]
        var superseded: [URL] = []
        var failure: Error?
        for id in ids {
            guard let pack = catalog.pack(id) else { continue }
            if let current = installed[id], current.usable, current.version == pack.version { continue }
            let file: URL
            do {
                file = try PackFiles.install(asset: assets.appendingPathComponent(pack.assetName), pack: pack,
                                             into: folder)
            } catch {
                failure = error
                break
            }
            if let old = installed[id], old.version != pack.version {
                superseded.append(folder.appendingPathComponent("\(id.rawValue)-\(old.version).sqlite"))
            }
            installed[id] = InstalledPack(id: id, lang: pack.lang, version: pack.version, usable: true)
            changes[id] = file
        }
        if !changes.isEmpty {
            try await database.attachPacks(changes)
            for url in superseded {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if let failure { throw failure }
    }

    #if DEBUG
    /// The DEBUG hook `-installPacks <all|id,…>` with `-packFixtures <path>`
    /// (0237, "Launch"): installs the packs from the committed assets through
    /// the install path, with no network.
    func installFixtures(_ argument: String, from assets: URL) async throws {
        let ids = argument == "all"
            ? catalog.packs.map(\.id)
            : argument.split(separator: ",").map { PackID(String($0)) }
        try await install(ids, fromAssetsIn: assets)
    }
    #endif
}
