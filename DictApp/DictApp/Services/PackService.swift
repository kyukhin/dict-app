// PackService.swift
// Language packs (Issue #237, docs/specs/0237-downloads.md): the catalog in
// the bundled dictionary file, the installed pack files in `Application
// Support/DictApp/Packs/`, the launch scan, and the install of a pack from
// its xz asset: verify, decompress, rename, attach. #241 installs from a
// local asset (the DEBUG `-installPacks` hook and the unit tests); #242
// downloads it from GitHub Releases, only when the user starts it. This file
// holds the app's only network code (`NetworkAuditTests`).

import Compression
import CryptoKit
import Foundation
import GRDB
import UIKit

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
enum PackError: Error, Equatable, Sendable {
    /// No network when the download started.
    case offline
    /// The connection dropped mid-download, or the app's background time ran
    /// out. Try again continues where it stopped when it can.
    case stopped
    /// HTTP 4xx or 5xx, or the asset is missing.
    case unavailable
    /// The asset or its file does not match the catalog's sha256 and size.
    case damaged
    /// The disk is full; partial files are deleted.
    case noSpace
    /// The user cancelled.
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
        /// Packs whose removal a crash cut off (0237, "Crash safety"): their
        /// files are deleted; their `<id>.removing` marker stays until
        /// `packs_installed` has lost the id.
        var removing: [PackID] = []
    }

    /// `<id>.removing`: a removal in progress (0237, "Files").
    static func removalMarker(of id: PackID, in folder: URL) -> URL {
        folder.appendingPathComponent(id.rawValue + ".removing")
    }

    /// The launch scan (0237, "Launch", step 3): deletes partial files, the
    /// downloads folder, files of packs the catalog does not know and files
    /// superseded by the catalog's version of the same pack, and every file
    /// of a pack with a `<id>.removing` marker. Each other catalog pack then
    /// gets its current file, else an older one of the app's format (usable
    /// until an update), else none (the stub). A file of another format
    /// stays, unusable, until an update replaces it.
    static func scan(folder: URL, catalog: PackCatalog, downloads: URL? = nil) -> Scan {
        let fileManager = FileManager.default
        if let downloads {
            try? fileManager.removeItem(at: downloads)
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return Scan() }
        var byPack: [PackID: [String: URL]] = [:]
        var removing: Set<PackID> = []
        for name in names {
            let url = folder.appendingPathComponent(name)
            if name.hasSuffix(".partial") {
                try? fileManager.removeItem(at: url)
                continue
            }
            if name.hasSuffix(".removing") {
                let id = PackID(String(name.dropLast(".removing".count)))
                if catalog.pack(id) != nil {
                    removing.insert(id)
                } else {
                    try? fileManager.removeItem(at: url)
                }
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
            if removing.contains(pack.id) {
                for url in byPack[pack.id, default: [:]].values {
                    try? fileManager.removeItem(at: url)
                }
                scan.removing.append(pack.id)
                continue
            }
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
    /// is full; either way no partial file stays. A cancelled task (#242)
    /// stops between chunks and before the rename, with `CancellationError`.
    /// `fault`, a test seam (the DEBUG `noSpace` mode), is thrown by the
    /// first write.
    static func install(asset: URL, pack: CatalogPack, into folder: URL, fault: (any Error)? = nil) throws -> URL {
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
                    if let fault { throw fault }
                    try output.write(contentsOf: data)
                    hasher.update(data: data)
                    written += Int64(data.count)
                }
                let input = try FileHandle(forReadingFrom: asset)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                    try Task.checkCancellation()
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
            try Task.checkCancellation()
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

    /// `NSFileWriteOutOfSpaceError` or `ENOSPC`, also underlying.
    static func isOutOfSpace(_ error: Error) -> Bool {
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

// MARK: - Status

/// Each pack's `PackState` for the views (0237, "Download and install"):
/// the Languages screen, the first-launch sheet and E4's progress row read
/// `state(of:)`, in every window. Only `PackService` sets it.
@MainActor
final class PackStatusModel: ObservableObject {
    static let shared = PackStatusModel()

    @Published private(set) var states: [PackID: PackState] = [:]

    /// A pack nobody has set yet is not installed.
    func state(of id: PackID) -> PackState {
        states[id] ?? .notInstalled
    }

    func set(_ state: PackState, for id: PackID) {
        if states[id] != state {
            states[id] = state
        }
    }

    /// A download's progress, while the pack is downloading only, so a late
    /// callback never overwrites a later state; in 100 kB steps, the
    /// precision of "3.1 of 6.9 MB".
    func progress(_ id: PackID, received: Int64) {
        guard case .downloading(let shown, let total) = states[id] else { return }
        let received = min(received, total)
        guard received / 100_000 != shown / 100_000 || received == total else { return }
        states[id] = .downloading(received: received, total: total)
    }
}

// MARK: - Network

/// The network path (0237, "Download and install", step 1): one session
/// with the ephemeral configuration, one download task per pack, progress,
/// cancel and resume data. It starts a request only when `download` is
/// called, and `PackService` calls it only for an install the user started.
final class PackDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// A failed download, with the resume data the session gave, if any.
    struct Failure: Error {
        let error: PackError
        let resumeData: Data?
    }

    /// No cookies, no URL cache, no credentials; no network fails at once
    /// (`waitsForConnectivity` off). Cellular, expensive and constrained
    /// networks are allowed: the user started the download and saw its size.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    private enum Ending {
        case success
        case failure(Error)
    }

    /// A download in flight, by task identifier.
    private struct Download {
        let task: URLSessionDownloadTask
        let destination: URL
        let progress: @Sendable (Int64) -> Void
        let continuation: CheckedContinuation<URL, Error>
        /// The asset at `destination`, or why it is not there.
        var file: URL?
        var failure: PackError?
        /// `stopAll` asked for resume data, which comes separately.
        var stopped = false
        var stopDataArrived = false
        var stopData: Data?
        var ending: Ending?
    }

    private let lock = NSLock()
    private var downloads: [Int: Download] = [:]
    private var session: URLSession!

    init(configuration: URLSessionConfiguration = PackDownloader.configuration()) {
        super.init()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// Cancels every task and releases the session, which holds its delegate.
    func invalidate() {
        session.invalidateAndCancel()
    }

    /// Downloads `url`, or resumes from `resumeData`, into `destination` and
    /// returns it. `progress` gets the bytes received so far. Throws a
    /// `Failure`; a cancelled task throws `.cancelled`.
    func download(_ url: URL, resumeData: Data?, to destination: URL,
                  progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let handle = Handle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
                lock.withLock {
                    downloads[task.taskIdentifier] = Download(task: task, destination: destination, progress: progress,
                                                              continuation: continuation)
                }
                if !handle.start(task) {
                    lock.withLock { _ = downloads.removeValue(forKey: task.taskIdentifier) }
                    task.cancel()
                    continuation.resume(throwing: Failure(error: .cancelled, resumeData: nil))
                }
            }
        } onCancel: {
            handle.cancel()
        }
    }

    /// Stops every download and keeps its resume data: the app's background
    /// time ran out (0237, "Offline and errors"). Each fails with `.stopped`.
    func stopAll() {
        let tasks = lock.withLock { () -> [(Int, URLSessionDownloadTask)] in
            for key in downloads.keys {
                downloads[key]?.stopped = true
            }
            return downloads.map { ($0.key, $0.value.task) }
        }
        for (identifier, task) in tasks {
            task.cancel(byProducingResumeData: { [weak self] data in
                guard let self else { return }
                lock.withLock {
                    self.downloads[identifier]?.stopData = data
                    self.downloads[identifier]?.stopDataArrived = true
                }
                finish(identifier)
            })
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = lock.withLock { downloads[downloadTask.taskIdentifier]?.progress }
        progress?(totalBytesWritten)
    }

    /// The session deletes `location` when this returns: an asset is moved
    /// to its destination now; a server error's page is dropped.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination = lock.withLock({ downloads[downloadTask.taskIdentifier]?.destination }) else { return }
        var file: URL?
        var failure: PackError?
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            failure = .unavailable
        } else {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: location, to: destination)
                file = destination
            } catch {
                failure = PackFiles.isOutOfSpace(error) ? .noSpace : .stopped
            }
        }
        lock.withLock {
            downloads[downloadTask.taskIdentifier]?.file = file
            downloads[downloadTask.taskIdentifier]?.failure = failure
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.withLock {
            downloads[task.taskIdentifier]?.ending = error.map(Ending.failure) ?? .success
        }
        finish(task.taskIdentifier)
    }

    /// Resumes the caller once the task has ended and, after `stopAll`, once
    /// its resume data has come too.
    private func finish(_ identifier: Int) {
        let ended = lock.withLock { () -> Download? in
            guard let download = downloads[identifier], let ending = download.ending else { return nil }
            if download.stopped, case .failure = ending, !download.stopDataArrived { return nil }
            downloads[identifier] = nil
            return download
        }
        guard let download = ended, let ending = download.ending else { return }
        switch ending {
        case .failure(let error):
            let urlError = error as? URLError
            let packError = download.stopped && urlError?.code == .cancelled ? .stopped : Self.packError(for: error)
            let resumeData = download.stopData ?? urlError?.downloadTaskResumeData
            download.continuation.resume(throwing: Failure(error: packError,
                                                           resumeData: packError == .cancelled ? nil : resumeData))
        case .success:
            if let file = download.file {
                download.continuation.resume(returning: file)
            } else {
                download.continuation.resume(throwing: Failure(error: download.failure ?? .unavailable,
                                                               resumeData: nil))
            }
        }
    }

    /// What the user sees for a session error (0237, "Offline and errors").
    static func packError(for error: Error) -> PackError {
        guard let error = error as? URLError else { return PackFiles.isOutOfSpace(error) ? .noSpace : .stopped }
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .offline
        case .cancelled:
            return .cancelled
        case .cannotWriteToFile:
            return .noSpace
        case .badURL, .unsupportedURL, .fileDoesNotExist, .badServerResponse, .zeroByteResource,
             .resourceUnavailable, .redirectToNonExistentLocation, .httpTooManyRedirects,
             .userAuthenticationRequired, .noPermissionsToReadFile:
            return .unavailable
        default:
            return .stopped
        }
    }

    /// A task, once it exists, and whether its caller was cancelled first.
    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false

        /// Resumes `task`; false when the caller was cancelled before.
        func start(_ task: URLSessionTask) -> Bool {
            lock.withLock {
                guard !cancelled else { return false }
                self.task = task
                task.resume()
                return true
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                task?.cancel()
            }
        }
    }
}

// MARK: - Service

/// Owns the installed packs (0237, "Download and install"): the launch scan,
/// the install queue, the downloads, removals and updates, and what is
/// installed. Publishes each pack's state to `PackStatusModel` and posts
/// `didChange` after every change.
actor PackService {
    static let shared = PackService()

    /// Posted on the main thread, with the service as its object, after
    /// packs were installed, updated or removed (step 9). `userInfo["packs"]`
    /// is their `[PackID]`. Search re-runs its query, `DictionarySelection`
    /// reloads, E3 and E4 reload their lists.
    static let didChange = Notification.Name("PackService.didChange")

    private let folder: URL
    private let downloads: URL
    private let database: DatabaseService
    private let settings: SettingsService
    /// `nil`: `PackStatusModel.shared` and `LocalizationManager.shared`,
    /// resolved on the main actor.
    private let status: PackStatusModel?
    private let localization: LocalizationManager?
    private var downloader = PackDownloader()
    private let background = BackgroundActivity()
    private(set) var catalog = PackCatalog.empty
    private var installed: [PackID: InstalledPack] = [:]

    // The queue (step 2): one install at a time, in the order chosen; the
    // others wait. Each caller of `install` waits for its pack's end.
    private var queue: [PackID] = []
    /// The running install; `cancelled` once `cancel` has answered its
    /// callers, so another install of the pack can queue at once.
    private var current: (id: PackID, task: Task<Void, Error>, cancelled: Bool)?
    private var worker: Task<Void, Never>?
    private var waiters: [PackID: [CheckedContinuation<Void, Error>]] = [:]
    /// What a stopped download leaves for Try again.
    private var resumeData: [PackID: Data] = [:]
    /// Test seam (the DEBUG `noSpace` mode): the first write of a decompress
    /// throws it.
    private var writeFault: (any Error)?

    init(folder: URL = PackFiles.folder(), downloads: URL = PackFiles.downloadsFolder(),
         database: DatabaseService = .shared, settings: SettingsService = .shared,
         status: PackStatusModel? = nil, localization: LocalizationManager? = nil) {
        self.folder = folder
        self.downloads = downloads
        self.database = database
        self.settings = settings
        self.status = status
        self.localization = localization
    }

    deinit {
        downloader.invalidate()
    }

    /// Launch, after `DatabaseService.setup` has attached every pack name on
    /// the stub (0237, "Launch", step 3): reads the catalog through the
    /// pool, scans the packs folder, then points each catalog pack at its
    /// chosen file (or the stub) in one re-attach, before any reader is
    /// busy. Last it finishes an install or a removal that a crash cut off
    /// ("Crash safety") and publishes each pack's state. Returns the files
    /// attached.
    @discardableResult
    func prepare() async throws -> [PackID: URL] {
        catalog = try await database.packCatalog()
        PackCatalog.shared = catalog
        let scan = PackFiles.scan(folder: folder, catalog: catalog, downloads: downloads)
        installed = Dictionary(uniqueKeysWithValues: scan.installed.map { ($0.id, $0) })
        var changes: [PackID: URL?] = [:]
        for pack in catalog.packs {
            changes[pack.id] = scan.files[pack.id]
        }
        try await database.attachPacks(changes)
        try await finishInterrupted(scan)
        for pack in catalog.packs {
            publish(pack.id, restingState(pack.id))
        }
        return scan.files
    }

    /// 0237, "Crash safety", after the launch's re-attach. A removal cut off
    /// (its marker): the scan has deleted its files and attached the stub;
    /// `packs_installed` drops the id, then the marker goes. A usable pack
    /// that `packs_installed` lacks, an install cut off after its commit:
    /// steps 7 and 8 run again (both idempotent) and add the id last.
    private func finishInterrupted(_ scan: PackFiles.Scan) async throws {
        let settings = settings
        for id in scan.removing {
            await MainActor.run { settings.recordRemoval(of: id) }
            try? FileManager.default.removeItem(at: PackFiles.removalMarker(of: id, in: folder))
        }
        let recorded = await MainActor.run { settings.packsInstalled }
        try await recordInstalls(scan.installed.filter { $0.usable && !recorded.contains($0.id) }
            .compactMap { catalog.pack($0.id) })
    }

    /// Every pack with a file, in catalog order (0237, "For E3 and E4").
    func installedPacks() -> [InstalledPack] {
        catalog.packs.compactMap { installed[$0.id] }
    }

    // MARK: Install, cancel, remove

    /// Downloads, verifies and installs `id` (0237, "Download and install"),
    /// or updates it to the catalog's version, and returns once it is
    /// searchable; at once when it already is. Queued behind the installs
    /// asked for earlier. Throws `PackError`. The only way the app goes
    /// online: a download the user started. The caller's cancellation does
    /// not stop it ("Done" closes the sheet, the downloads go on); `cancel`
    /// does. Try again is another call: it resumes a stopped download when
    /// the session left resume data.
    func install(_ id: PackID) async throws {
        guard catalog.pack(id) != nil else { throw PackError.unavailable }
        if isCurrent(id) { return }
        if (current?.id != id || current?.cancelled == true) && !queue.contains(id) {
            queue.append(id)
            publish(id, .waiting)
            startWorker()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiters[id, default: []].append(continuation)
        }
    }

    /// Installs what learning `lang` via `via` needs (0237, "Learning a
    /// pair"; E4): the packs of the catalog's pair (`PackCatalog.pairs`, a
    /// limited one's too) that have no usable file, in the pair's order, one
    /// after the other. Returns them: empty, with no request, when nothing is
    /// missing or the catalog has no such pair (a pair of imports, #208,
    /// needs no pack). Throws the first `PackError`; the packs after it stay
    /// missing until Try again.
    @discardableResult
    func installPair(lang: String, via: String) async throws -> [PackID] {
        guard let pair = catalog.pairs.first(where: { $0.lang == lang && $0.via == via }) else { return [] }
        let missing = pair.packs.filter { installed[$0]?.usable != true }
        for id in missing {
            try await install(id)
        }
        return missing
    }

    /// Cancels a waiting or running install of `id` (0237, "Cancel"): its
    /// callers get `.cancelled` and the state goes back to what is installed
    /// at once; a running one deletes its temporary files as it stops.
    /// No-op otherwise.
    func cancel(_ id: PackID) {
        resumeData[id] = nil
        if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
            finish(id, .failure(PackError.cancelled))
        } else if let running = current, running.id == id, !running.cancelled {
            running.task.cancel()
            current?.cancelled = true
            finish(id, .failure(PackError.cancelled))
        }
    }

    /// Removes `id` (0237, "Remove"): the `<id>.removing` marker first, then
    /// the stub is attached under its name, then its files are deleted once
    /// the writer has re-attached; a reader still busy on a file finishes on
    /// it. `packs_installed` loses the id, then the marker goes, so the next
    /// launch finishes a removal a crash cut off. Its dictionaries keep their
    /// place and switch for when it returns. Cancels an install of it first.
    func remove(_ id: PackID) async throws {
        let running = current?.id == id ? current?.task : nil
        cancel(id)
        _ = await running?.result
        guard installed[id] != nil else { return }
        let marker = PackFiles.removalMarker(of: id, in: folder)
        try Data().write(to: marker)
        try checkpoint(.afterMarker)
        installed[id] = nil
        try await database.attachPacks([id: nil])
        try checkpoint(.afterReattach)
        let fileManager = FileManager.default
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where PackFiles.parse(name)?.0 == id {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
        let settings = settings
        await MainActor.run { settings.recordRemoval(of: id) }
        try? fileManager.removeItem(at: marker)
        publish(id, .notInstalled)
        postDidChange([id])
    }

    // MARK: The queue

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Runs the queue to its end, holding background time while it works.
    private func drain() async {
        repeat {
            await background.begin {
                Task { await self.stopAll() }
            }
            while !queue.isEmpty {
                let id = queue.removeFirst()
                let task = Task { try await perform(id) }
                current = (id, task, false)
                let result = await task.result
                let cancelled = current?.cancelled ?? false
                current = nil
                if !cancelled {
                    finish(id, result)
                }
            }
            await background.end()
        } while !queue.isEmpty
        worker = nil
    }

    /// The background time ran out: the running download stops with resume
    /// data, and every waiting install fails with `.stopped`.
    private func stopAll() {
        let waiting = queue
        queue.removeAll()
        for id in waiting {
            finish(id, .failure(PackError.stopped))
        }
        downloader.stopAll()
    }

    /// Ends the install of `id`: publishes a failure (a cancel shows what
    /// is installed) and resumes its callers.
    private func finish(_ id: PackID, _ result: Result<Void, Error>) {
        let callers = waiters.removeValue(forKey: id) ?? []
        switch result {
        case .success:
            for caller in callers { caller.resume() }
        case .failure(let error):
            let packError: PackError
            switch error {
            case let error as PackError: packError = error
            case is CancellationError: packError = .cancelled
            default: packError = PackFiles.isOutOfSpace(error) ? .noSpace : .unavailable
            }
            publish(id, packError == .cancelled ? restingState(id) : .failed(packError))
            for caller in callers { caller.resume(throwing: packError) }
        }
    }

    /// One install (steps 1 to 9): download, verify and decompress off the
    /// actor, then commit.
    private func perform(_ id: PackID) async throws {
        guard let pack = catalog.pack(id), let url = pack.url else { throw PackError.unavailable }
        // Installed meanwhile (a cancel that came too late, a second queue entry).
        guard !isCurrent(id) else { return publish(id, .installed) }
        publish(id, .downloading(received: 0, total: pack.size))
        let asset = try await download(pack, from: url)
        defer { try? FileManager.default.removeItem(at: asset) }
        publish(id, .installing)
        let file = try await Self.installDetached(asset: asset, pack: pack, folder: folder, fault: writeFault)
        // The rename has committed the file: a cancel from here on must not
        // leave it on disk but unattached, so the attach runs to its end.
        try await Task { try await commit([(pack, file)]) }.value
    }

    /// Step 1: downloads the asset of `pack` from `url` into `Downloads/`,
    /// continuing from a stopped download's resume data when there is some
    /// (Try again). When that resumed request is refused (the CDN's signed
    /// URL expired, or the server rejects the range), the resume data goes
    /// and one fresh request starts from the first byte; no other retry. A
    /// failure keeps the session's new resume data for the next Try again.
    private func download(_ pack: CatalogPack, from url: URL) async throws -> URL {
        let id = pack.id
        let status = status
        let progress: @Sendable (Int64) -> Void = { received in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { (status ?? .shared).progress(id, received: received) }
            }
        }
        var resume = resumeData.removeValue(forKey: id)
        while true {
            do {
                return try await downloader.download(url, resumeData: resume,
                                                     to: downloads.appendingPathComponent(pack.assetName),
                                                     progress: progress)
            } catch let failure as PackDownloader.Failure {
                if resume != nil && failure.error == .unavailable {
                    resume = nil
                    continue
                }
                if let data = failure.resumeData {
                    resumeData[id] = data
                }
                throw failure.error
            }
        }
    }

    /// Verifies, decompresses and renames off the actor (the Greek pack
    /// takes about a second); a cancel reaches it between chunks.
    private static func installDetached(asset: URL, pack: CatalogPack, folder: URL,
                                        fault: (any Error)?) async throws -> URL {
        let task = Task.detached(priority: .userInitiated) {
            try PackFiles.install(asset: asset, pack: pack, into: folder, fault: fault)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Steps 6 to 9 for files the rename has committed (step 5): one
    /// re-attach for all of them, the older versions they replace deleted,
    /// the imports they cover, their preferences, their states and
    /// `didChange`. A removal marker left by a failed removal of one of them
    /// goes first, so the next launch does not delete the new file.
    private func commit(_ files: [(pack: CatalogPack, file: URL)]) async throws {
        guard !files.isEmpty else { return }
        try checkpoint(.afterCommit)
        var changes: [PackID: URL?] = [:]
        var superseded: [URL] = []
        for (pack, file) in files {
            try? FileManager.default.removeItem(at: PackFiles.removalMarker(of: pack.id, in: folder))
            if let old = installed[pack.id], old.version != pack.version {
                superseded.append(folder.appendingPathComponent("\(pack.id.rawValue)-\(old.version).sqlite"))
            }
            installed[pack.id] = InstalledPack(id: pack.id, lang: pack.lang, version: pack.version, usable: true)
            changes[pack.id] = file
        }
        try await database.attachPacks(changes)
        try checkpoint(.afterAttach)
        for url in superseded {
            try? FileManager.default.removeItem(at: url)
        }
        try await recordInstalls(files.map(\.pack))
        for (pack, _) in files {
            publish(pack.id, .installed)
        }
        postDidChange(files.map(\.pack.id))
    }

    /// Steps 7 and 8 for attached packs; the launch runs them again for an
    /// install a crash cut off after its commit. Both are idempotent, and
    /// `packs_installed` gains each id last: the install's final write.
    private func recordInstalls(_ packs: [CatalogPack]) async throws {
        guard !packs.isEmpty else { return }
        // Step 7. A failure leaves imported rows next to the pack's own: no
        // reason to fail an install that is attached.
        try? await database.removeImportsCovered(by: packs.flatMap { catalog.sources(of: $0.id).map(\.source) })
        try checkpoint(.afterImports)
        // Step 8, on the main actor, where the Settings screens write the
        // same keys.
        let sources = packs.map { ($0.id, catalog.sources(of: $0.id).map(\.source)) }
        let settings = settings
        let localization = localization
        await MainActor.run {
            let code = (localization ?? .shared).currentLanguage.code
            for (id, ids) in sources {
                settings.recordInstall(of: id, sources: ids, uiLanguageCode: code)
            }
        }
    }

    // MARK: Crash points

    /// Where an install or a removal can be cut off (0237, "Crash safety").
    enum CrashPoint: Sendable {
        /// Install: after the rename (step 5).
        case afterCommit
        /// Install: after the re-attach (step 6).
        case afterAttach
        /// Install: after the imports it covers (step 7).
        case afterImports
        /// Removal: after the marker.
        case afterMarker
        /// Removal: after the stub's re-attach.
        case afterReattach
    }

    /// What a crash point throws: the operation stops there, as if the app
    /// were killed, and the next launch finishes it.
    struct SimulatedCrash: Error {}

    #if DEBUG
    /// Unit-test seam: the crash point the next install or removal stops at.
    private var crashPoint: CrashPoint?

    func crash(at point: CrashPoint?) {
        crashPoint = point
    }
    #endif

    /// Throws `SimulatedCrash` at the test seam's point; nothing in release.
    private func checkpoint(_ point: CrashPoint) throws {
        #if DEBUG
        if crashPoint == point {
            throw SimulatedCrash()
        }
        #endif
    }

    // MARK: States

    /// The catalog's version is attached.
    private func isCurrent(_ id: PackID) -> Bool {
        guard let current = installed[id], let pack = catalog.pack(id) else { return false }
        return current.usable && current.version == pack.version
    }

    /// The state of `id` when nothing runs: from its file, if any.
    private func restingState(_ id: PackID) -> PackState {
        guard let current = installed[id] else { return .notInstalled }
        guard current.usable else { return .updateRequired }
        return current.version == catalog.pack(id)?.version ? .installed : .updateAvailable
    }

    /// Sets a state on the main queue, in the order of the calls, after any
    /// progress callback queued before it.
    private nonisolated func publish(_ id: PackID, _ state: PackState) {
        let status = status
        DispatchQueue.main.async {
            MainActor.assumeIsolated { (status ?? .shared).set(state, for: id) }
        }
    }

    private nonisolated func postDidChange(_ ids: [PackID]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["packs": ids])
        }
    }

    // MARK: Install from the committed assets (#241)

    /// Installs each pack of `ids` from its asset in `assets`, skipping a
    /// pack already installed at the catalog's version, then commits them as
    /// a download does, with one re-attach. No network. When one install
    /// fails, the packs installed before it are committed, then it throws.
    func install(_ ids: [PackID], fromAssetsIn assets: URL) async throws {
        var files: [(pack: CatalogPack, file: URL)] = []
        var failure: Error?
        for id in ids {
            guard let pack = catalog.pack(id), !isCurrent(id) else { continue }
            do {
                files.append((pack, try PackFiles.install(asset: assets.appendingPathComponent(pack.assetName),
                                                          pack: pack, into: folder)))
            } catch {
                failure = error
                break
            }
        }
        try await commit(files)
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

    /// The DEBUG hook `-packDownloads <mode>` (0237, "Launch") and the unit
    /// tests' seam: every download goes through `PackFixtureURLProtocol` in
    /// `mode`, from the assets at `assets` (default: `Packs/` of the source
    /// tree), never the network. `noSpace` also fails the first write of the
    /// decompress with ENOSPC.
    func useFixtureDownloads(_ mode: PackFixtureURLProtocol.Mode, assets: URL? = nil) {
        PackFixtureURLProtocol.configure(mode: mode, assets: assets)
        let configuration = PackDownloader.configuration()
        configuration.protocolClasses = [PackFixtureURLProtocol.self]
        downloader.invalidate()
        downloader = PackDownloader(configuration: configuration)
        writeFault = mode == .noSpace ? POSIXError(.ENOSPC) : nil
    }

    /// Unit-test seam: the background time runs out.
    func expireBackgroundTime() {
        stopAll()
    }
    #endif
}

// MARK: - The first-launch offer (#244)

extension PackOffer {
    /// The sheet this launch offers, as `isReady` turns true (0237,
    /// "Launch", step 7). `ContentView` shows it; `record` answers it.
    @MainActor static var launchSheet: Sheet?

    /// Gathers the signals and decides (0237, "Launch"). Runs after the
    /// launch scan and the DEBUG hooks and before the 1.x move starts, so
    /// the user database is read without waiting for it and before any
    /// screen stores a dictionary order. `legacyDatabaseFound`: a 1.x
    /// `dict.sqlite` is there to move.
    @MainActor
    static func atLaunch(legacyDatabaseFound: Bool, settings: SettingsService = .shared,
                         database: DatabaseService = .shared, packs: PackService = .shared,
                         localization: LocalizationManager? = nil) async throws -> Sheet? {
        let signs = try await database.earlierInstallSigns()
        let installed = await packs.installedPacks()
        let signals = Signals(
            packsOffered: settings.packsOffered, packsInstalled: settings.packsInstalled,
            usable: Set(installed.filter(\.usable).map(\.id)), legacyDatabaseFound: legacyDatabaseFound,
            legacyMarker: signs.legacyMarker, storedOrder: settings.dictionaryOrder, userRows: signs.userRows,
            enabledSources: settings.enabledSources,
            uiLanguageCode: (localization ?? .shared).currentLanguage.code,
            preferredLanguages: Locale.preferredLanguages)
        return decide(signals, catalog: await packs.catalog)
    }
}

// MARK: - Background time

/// The app's background time while packs install (0237, "Offline and
/// errors"): a download goes on while iOS allows, then stops, and Try again
/// shows on return.
@MainActor
private final class BackgroundActivity {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    nonisolated init() {}

    func begin(onExpire: @escaping @Sendable () -> Void) {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Language download") { [weak self] in
            onExpire()
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

// MARK: - Fixture downloads (DEBUG)

#if DEBUG
/// Answers every download from the committed pack assets, never the
/// network, and fails on purpose (0237, "Launch", `-packDownloads <mode>`,
/// and "Test plan"). `PackService.useFixtureDownloads` puts it in the
/// session's `protocolClasses`; the UI tests reach it through the launch
/// argument, the unit tests through that method.
final class PackFixtureURLProtocol: URLProtocol {
    enum Mode: String, Sendable {
        /// The asset, at once.
        case ok
        /// The asset in 64 kB steps every 0.1 s, for Cancel.
        case slow
        /// `NSURLErrorNotConnectedToInternet` at once.
        case offline
        /// The first request of each asset stops halfway with
        /// `NSURLErrorNetworkConnectionLost`; the next one is served.
        case failOnce
        /// HTTP 404, as for a missing release asset.
        case http404
        /// The asset with one byte flipped: its sha256 does not match.
        case corrupt
        /// The asset; the install's first write fails with ENOSPC.
        case noSpace
        /// As `failOnce`, but a resumed request (one with `Range`) gets HTTP
        /// 403, as when the CDN's signed URL has expired; a request from the
        /// first byte is served.
        case expiredResume
    }

    /// `Packs/` of the source tree, through `#filePath`: the simulator
    /// shares the Mac's file system.
    static let sourceTreeAssets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Packs", isDirectory: true)

    private static let lock = NSLock()
    private static var mode = Mode.ok
    private static var assets = sourceTreeAssets
    private static var failedOnce: Set<String> = []
    private static var seen: [URL] = []
    private static var seenRanges: [String?] = []

    /// Sets the mode and the assets folder, and forgets earlier requests.
    static func configure(mode: Mode, assets: URL? = nil) {
        lock.withLock {
            self.mode = mode
            self.assets = assets ?? sourceTreeAssets
            failedOnce = []
            seen = []
            seenRanges = []
        }
    }

    /// Every URL requested since `configure`.
    static var requests: [URL] {
        lock.withLock { seen }
    }

    /// The `Range` header of every request since `configure`, nil for none:
    /// a download resumed from its resume data asks for the rest.
    static var ranges: [String?] {
        lock.withLock { seenRanges }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var timer: Timer?
    private var body = Data()
    private var offset = 0
    private var end = 0
    private var failsAtEnd = false

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (mode, assets, failsNow) = Self.lock.withLock { () -> (Mode, URL, Bool) in
            Self.seen.append(url)
            Self.seenRanges.append(request.value(forHTTPHeaderField: "Range"))
            let first = [.failOnce, .expiredResume].contains(Self.mode)
                && Self.failedOnce.insert(url.lastPathComponent).inserted
            return (Self.mode, Self.assets, first)
        }
        if mode == .offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if mode == .expiredResume, request.value(forHTTPHeaderField: "Range") != nil {
            respond(url, status: 403, headers: ["Content-Type": "text/html"])
            client?.urlProtocol(self, didLoad: Data("<html>expired</html>".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard mode != .http404, var asset = try? Data(contentsOf: assets.appendingPathComponent(url.lastPathComponent)) else {
            respond(url, status: 404, headers: [:])
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if mode == .corrupt {
            asset[asset.count / 2] ^= 0xFF
        }
        // A resumed download asks for the rest.
        var status = 200
        var headers = ["Content-Type": "application/octet-stream", "Accept-Ranges": "bytes",
                       "ETag": "\"\(url.lastPathComponent)\""]
        if let range = request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="),
           let start = Int(range.dropFirst("bytes=".count).prefix { $0.isNumber }), start > 0, start < asset.count {
            headers["Content-Range"] = "bytes \(start)-\(asset.count - 1)/\(asset.count)"
            asset = asset.subdata(in: start..<asset.count)
            status = 206
        }
        headers["Content-Length"] = String(asset.count)
        respond(url, status: status, headers: headers)

        body = asset
        end = failsNow ? asset.count / 2 : asset.count
        failsAtEnd = failsNow
        guard mode == .slow else {
            while offset < end {
                send(256 * 1024)
            }
            complete()
            return
        }
        // Slow: on this thread's run loop, the thread the session called
        // `startLoading` and will call `stopLoading` on.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            send(64 * 1024)
            if offset >= end {
                timer.invalidate()
                complete()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    override func stopLoading() {
        timer?.invalidate()
        timer = nil
    }

    private func respond(_ url: URL, status: Int, headers: [String: String]) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    private func send(_ chunk: Int) {
        let next = min(offset + chunk, end)
        client?.urlProtocol(self, didLoad: body.subdata(in: offset..<next))
        offset = next
    }

    private func complete() {
        if failsAtEnd {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
#endif
