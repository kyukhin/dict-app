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
/// there is no lookup in other sources.
struct HistoryDestination: View {
    let item: HistoryItem
    @State private var entry: DictionaryEntry?
    @State private var loaded = false

    var body: some View {
        Group {
            if let entry {
                DefinitionView(entry: entry)
            } else if loaded {
                ContentUnavailableView(
                    "search.notFound.title",
                    systemImage: "magnifyingglass",
                    description: Text("search.notFound.description \(item.word)")
                )
            } else {
                ProgressView()
            }
        }
        .task {
            entry = await Self.entry(for: item)
            loaded = true
        }
    }

    /// The entry `item` opens, or `nil` for "not found". The enabled
    /// sources are not consulted. Static so unit tests run the same lookup.
    static func entry(for item: HistoryItem, db: DatabaseService = .shared) async -> DictionaryEntry? {
        try? await db.entry(for: EntryKey(source: item.source, word: item.word))
    }
}
