// HistoryView.swift

import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()
    @Environment(\.locale) private var locale

    /// In-app language on the device's region and 24-hour setting (#114).
    private var timestampLocale: Locale {
        HistoryTimestamp.formattingLocale(language: locale)
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
                    ContentUnavailableView(
                        "history.empty.title",
                        systemImage: "clock",
                        description: Text("history.empty.description")
                    )
                } else {
                    List {
                        ForEach(vm.items) { item in
                            NavigationLink {
                                HistoryDestination(item: item)
                            } label: {
                                SourceStripeRow(source: item.source) {
                                    VStack(alignment: .leading) {
                                        Text(item.word)
                                            .font(.body)
                                        if let time = HistoryTimestamp.text(item.lookedAt, locale: timestampLocale) {
                                            Text(verbatim: time)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .accessibilityIdentifier("history_item_\(item.word)")
                            .listRowInsets(EdgeInsets())   // stripe reaches the leading edge (#6 §5)
                        }
                    }
                    .accessibilityIdentifier("history_list")
                }
            }
            .navigationTitle("history.title")
            .toolbar {
                if !vm.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("history.clear") {
                            Task { await vm.clear() }
                        }
                    }
                }
            }
            .task {
                await vm.load()
            }
        }
    }
}

/// Opens a History row or a Search Recent word (Issue #138): the entry of
/// the stored `(source, word)`, also when that source is disabled. A missing
/// entry (a row from before 1.3.0 with no source, a headword a dictionary
/// update dropped, an imported dictionary that is gone) shows "not found";
/// there is no lookup in other sources. #245: a word of a pack that is not
/// installed shows the "not downloaded" view (`EntryDestination`).
struct HistoryDestination: View {
    let item: HistoryItem

    var body: some View {
        EntryDestination(key: EntryKey(source: item.source, word: item.word))
    }

    /// The entry `item` opens, or `nil` for "not found". The enabled
    /// sources are not consulted. Static so unit tests run the same lookup.
    static func entry(for item: HistoryItem, db: DatabaseService = .shared) async -> DictionaryEntry? {
        try? await db.entry(for: EntryKey(source: item.source, word: item.word))
    }
}

/// Opens a stored key (History, Recent words, My words): its entry; while
/// its dictionary's pack is not installed, the "not downloaded" view (0237,
/// "Update from 1.x"; #245), which turns into the entry once the pack
/// installs; otherwise "not found".
struct EntryDestination: View {
    let key: EntryKey
    @State private var lookup: Lookup?

    /// What a key opens.
    enum Lookup: Equatable {
        case entry(DictionaryEntry)
        /// Its dictionary's pack is not installed.
        case notDownloaded(CatalogPack)
        case notFound
    }

    var body: some View {
        Group {
            switch lookup {
            case .entry(let entry):
                DefinitionView(entry: entry)
            case .notDownloaded(let pack):
                NotDownloadedView(word: key.word, pack: pack)
            case .notFound:
                ContentUnavailableView(
                    "search.notFound.title",
                    systemImage: "magnifyingglass",
                    description: Text("search.notFound.description \(key.word)")
                )
            case nil:
                ProgressView()
            }
        }
        .task {
            lookup = await Self.lookup(key)
        }
        // A pack installed meanwhile (the view's own Download, or Settings).
        .onReceive(NotificationCenter.default.publisher(for: PackService.didChange, object: PackService.shared)) { _ in
            Task { lookup = await Self.lookup(key) }
        }
    }

    /// The entry of `key`; else the pack its source needs while that pack
    /// is not installed; else not found. Static so unit tests run it.
    static func lookup(_ key: EntryKey, db: DatabaseService = .shared,
                       catalog: PackCatalog = .shared) async -> Lookup {
        if let entry = try? await db.entry(for: key) {
            return .entry(entry)
        }
        if await db.needsPack(source: key.source), let pack = NotDownloaded.pack(ofSource: key.source, catalog: catalog) {
            return .notDownloaded(pack)
        }
        return .notFound
    }
}
