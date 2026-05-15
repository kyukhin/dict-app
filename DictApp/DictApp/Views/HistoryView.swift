// HistoryView.swift

import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Words you look up will appear here.")
                    )
                } else {
                    List {
                        ForEach(vm.items) { item in
                            NavigationLink {
                                HistoryDestination(word: item.word)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.word)
                                        .font(.body)
                                    if let time = item.lookedAt {
                                        Text(time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("history_item_\(item.word)")
                        }
                    }
                    .accessibilityIdentifier("history_list")
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !vm.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
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

/// Looks up the word and shows its definition, or an error if not found.
private struct HistoryDestination: View {
    let word: String
    @State private var entry: DictionaryEntry?
    @State private var loaded = false

    var body: some View {
        Group {
            if let entry {
                DefinitionView(entry: entry)
            } else if loaded {
                ContentUnavailableView(
                    "Not Found",
                    systemImage: "magnifyingglass",
                    description: Text("'\(word)' was not found in any dictionary.")
                )
            } else {
                ProgressView()
            }
        }
        .task {
            entry = try? await DatabaseService.shared.lookup(word: word)
            if entry == nil {
                // Try FTS search as fallback (handles case differences, etc.)
                let results = (try? await DatabaseService.shared.search(query: word, limit: 1)) ?? []
                entry = results.first
            }
            loaded = true
        }
    }
}
