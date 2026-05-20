// BookmarksView.swift

import SwiftUI

struct BookmarksView: View {
    @StateObject private var vm = BookmarksViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.entries.isEmpty {
                    ContentUnavailableView(
                        "bookmarks.empty.title",
                        systemImage: "bookmark",
                        description: Text("bookmarks.empty.description")
                    )
                } else {
                    List {
                        ForEach(vm.entries) { item in
                            NavigationLink(value: item.entry) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.entry.word)
                                        .font(.headline)
                                    Text(strippedSnippet(item.entry.definition))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { offsets in
                            Task {
                                for idx in offsets {
                                    let entry = vm.entries[idx]
                                    await vm.remove(entryId: entry.entry.id ?? 0)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("bookmarks_list")
                }
            }
            .navigationTitle("bookmarks.title")
            .navigationDestination(for: DictionaryEntry.self) { entry in
                DefinitionView(entry: entry)
            }
            .task {
                await vm.load()
            }
        }
    }

    private func strippedSnippet(_ text: String) -> String {
        String(text.prefix(100))
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
