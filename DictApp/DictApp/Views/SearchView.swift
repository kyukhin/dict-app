// SearchView.swift
// Main search interface with search-as-you-type.

import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        NavigationStack {
            List {
                if vm.query.isEmpty {
                    if !vm.recentWords.isEmpty {
                        Section("Recent") {
                            ForEach(vm.recentWords) { item in
                                NavigationLink(value: item.word) {
                                    Label(item.word, systemImage: "clock")
                                        .font(.body)
                                }
                            }
                        }
                    }
                } else if vm.results.isEmpty && !vm.isSearching {
                    ContentUnavailableView.search(text: vm.query)
                } else {
                    ForEach(vm.results) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Dictionary")
            .searchable(text: $vm.query, prompt: "Search words...")
            .onChange(of: vm.query) {
                vm.onQueryChanged()
            }
            .overlay {
                if vm.isSearching && !vm.query.isEmpty {
                    ProgressView()
                }
            }
            .navigationDestination(for: DictionaryEntry.self) { entry in
                DefinitionView(entry: entry)
            }
            .navigationDestination(for: String.self) { word in
                HistoryWordDestination(word: word)
            }
            .task {
                await vm.loadRecent()
            }
        }
    }
}

// MARK: - Row

/// A single search result row showing word, source badge, and definition snippet.
private struct EntryRow: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.word)
                    .font(.headline)
                Text(entry.sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            if !entry.phonetic.isEmpty {
                Text(entry.phonetic)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.pos.isEmpty {
                Text(entry.pos)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            Text(definitionSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var definitionSnippet: String {
        String(entry.definition.prefix(200))
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - History word destination

/// Looks up a word from history and shows its definition.
private struct HistoryWordDestination: View {
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
                let results = (try? await DatabaseService.shared.search(query: word, limit: 1)) ?? []
                entry = results.first
            }
            loaded = true
        }
    }
}
